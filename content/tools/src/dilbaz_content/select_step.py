"""S2 select: the target items of a pack (docs/10-content-pipeline.md §4.2).

Word senses are picked from the lexicon by rule and adjusted by a curation
file; chunks and grammar points are curated in full. Curation files are
committed under `content/curation/<l2>/`; the items go to
`content/packs/<l2>/items/`.
"""

from __future__ import annotations

from collections import Counter
from collections.abc import Iterable
from pathlib import Path

import yaml
from pydantic import BaseModel, ConfigDict, Field, TypeAdapter

from dilbaz_content.items import (
    POS_CODES,
    Chunk,
    GrammarPoint,
    Level,
    Provenance,
    WordSense,
    level_index,
    slug,
)
from dilbaz_content.lexicon import LexiconEntry

# Function words are taught through grammar points and chunks, not word cards.
CONTENT_POS = ("NOUN", "VERB", "ADJ", "ADV")
MAX_SENSES_PER_LEMMA = 2
# docs/02 §2: A0 learners know fewer than 300 words, so the A1 senses of the
# 300 most frequent families are A0.
A0_MAX_RANK = 300

WORD_SENSES_FILE = "word_senses.yaml"
CHUNKS_FILE = "chunks.yaml"
GRAMMAR_FILE = "grammar_points.yaml"

_AUTO = Provenance(source="cefrj+octanove levels, wiktionary gloss", license="CC BY-SA 4.0")
_CURATED = Provenance(source="dilbaz curation", license="own")


class SenseChoice(BaseModel):
    """A sense chosen by hand: an own gloss, or a Wiktionary sense by index."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    pos: str
    sense: str | None = None
    wiktionary: int | None = Field(default=None, ge=0)
    level: Level | None = None


class WordSenseCuration(BaseModel):
    """`curation/<l2>/word_senses.yaml`: decisions on top of the rule."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    # Everyday lemmas taken first, even outside NGSL-Spoken ("breakfast").
    include: tuple[str, ...] = ()
    # Lemmas not taught as word-sense cards (grammar words, chunks, titles).
    exclude: tuple[str, ...] = ()
    # lemma → senses replacing the automatic ones.
    senses: dict[str, tuple[SenseChoice, ...]] = Field(default_factory=dict)


class ChunkEntry(BaseModel):
    """One line of `curation/<l2>/chunks.yaml`."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    text: str = Field(min_length=1)
    level: Level
    function: str = Field(min_length=1)
    note: str | None = None


class GrammarEntry(BaseModel):
    """One line of `curation/<l2>/grammar_points.yaml`."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    code: str
    level: Level
    name: str
    description: str
    examples: tuple[str, ...]


class Selection(BaseModel):
    """What S2 selected."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    word_senses: tuple[WordSense, ...]
    chunks: tuple[Chunk, ...]
    grammar_points: tuple[GrammarPoint, ...]


class SelectionError(ValueError):
    """The curation files contradict each other or the lexicon."""


def _sense_level(entry: LexiconEntry, pos: str) -> Level | None:
    tag = next((t for t in entry.levels if t.pos == pos), None)
    if tag is None:
        return None
    if tag.cefr == "A1" and entry.rank is not None and entry.rank <= A0_MAX_RANK:
        return "A0"
    return tag.cefr


def _wiktionary_gloss(entry: LexiconEntry, pos: str, index: int = 0) -> str | None:
    glosses = [sense.gloss for sense in entry.senses if sense.pos == pos]
    return glosses[index] if index < len(glosses) else None


def _choices(entry: LexiconEntry, max_level: Level) -> list[tuple[str, str, Level, Provenance]]:
    """(pos, gloss, level, provenance) chosen by the rule."""
    chosen: list[tuple[str, str, Level, Provenance]] = []
    for tag in entry.levels:
        level = _sense_level(entry, tag.pos)
        if tag.pos not in CONTENT_POS or level is None:
            continue
        if level_index(level) > level_index(max_level):
            continue
        gloss = _wiktionary_gloss(entry, tag.pos)
        if gloss is not None:
            chosen.append((tag.pos, gloss, level, _AUTO))
    return chosen[:MAX_SENSES_PER_LEMMA]


def _curated_choices(
    entry: LexiconEntry, picks: Iterable[SenseChoice], max_level: Level
) -> list[tuple[str, str, Level, Provenance]]:
    chosen: list[tuple[str, str, Level, Provenance]] = []
    for pick in picks:
        if pick.sense is not None:
            gloss, provenance = pick.sense, _CURATED
        else:
            found = _wiktionary_gloss(entry, pick.pos, pick.wiktionary or 0)
            if found is None:
                message = f"{entry.lemma}: no Wiktionary {pick.pos} sense {pick.wiktionary}"
                raise SelectionError(message)
            gloss, provenance = found, _AUTO
        level = pick.level or _sense_level(entry, pick.pos) or entry.cefr
        if level is None:
            raise SelectionError(f"{entry.lemma}: {pick.pos} has no level, give one")
        if level_index(level) <= level_index(max_level):
            chosen.append((pick.pos, gloss, level, provenance))
    return chosen


def _order(by_lemma: dict[str, LexiconEntry], include: tuple[str, ...]) -> list[LexiconEntry]:
    """Curated lemmas first, then NGSL-Spoken members, then the rest; by rank within."""
    spoken = sorted(
        (e for e in by_lemma.values() if e.rank is not None and "ngsl_spoken" in e.sources),
        key=lambda entry: entry.rank or 0,
    )
    others = sorted(
        (e for e in by_lemma.values() if e.rank is not None and "ngsl_spoken" not in e.sources),
        key=lambda entry: entry.rank or 0,
    )
    first = [by_lemma[lemma] for lemma in include]
    chosen = set(include)
    return [*first, *(e for e in (*spoken, *others) if e.lemma not in chosen)]


def select_word_senses(
    lexicon: Iterable[LexiconEntry],
    curation: WordSenseCuration,
    *,
    l2: str,
    max_level: Level,
    limit: int,
) -> tuple[WordSense, ...]:
    """Senses of content lemmas up to [max_level], for everyday conversation.

    Order: the curated `include` list, then NGSL-Spoken members, then the other
    lemmas, each by frequency rank. Lemmas are taken until [limit] senses are
    reached (the last lemma is kept whole).
    """
    by_lemma = {entry.lemma: entry for entry in lexicon}
    named = set(curation.senses) | set(curation.exclude) | set(curation.include)
    unknown = sorted(named - set(by_lemma))
    if unknown:
        raise SelectionError(f"curation names lemmas missing from the lexicon: {unknown}")
    both = sorted(set(curation.include) & set(curation.exclude))
    if both:
        raise SelectionError(f"lemmas both included and excluded: {both}")
    excluded = set(curation.exclude)
    senses: list[WordSense] = []
    for entry in _order(by_lemma, curation.include):
        if len(senses) >= limit:
            break
        if entry.lemma in excluded:
            continue
        picks = curation.senses.get(entry.lemma)
        chosen = (
            _curated_choices(entry, picks, max_level)
            if picks is not None
            else _choices(entry, max_level)
        )
        per_pos: Counter[str] = Counter()
        for pos, gloss, level, provenance in chosen:
            per_pos[pos] += 1
            senses.append(
                WordSense(
                    key=f"{l2}.ws.{slug(entry.lemma)}.{POS_CODES[pos]}.{per_pos[pos]}",
                    lemma=entry.lemma,
                    pos=pos,
                    sense=gloss,
                    level=level,
                    rank=entry.rank,
                    ipa_us=entry.ipa_us,
                    ipa_uk=entry.ipa_uk,
                    provenance=provenance,
                )
            )
    return tuple(senses)


def build_chunks(entries: Iterable[ChunkEntry], *, l2: str) -> tuple[Chunk, ...]:
    """Chunks with keys from their text; duplicate keys are an error."""
    chunks: list[Chunk] = []
    seen: dict[str, str] = {}
    for entry in entries:
        key = f"{l2}.chunk.{slug(entry.text)}"
        if key in seen:
            raise SelectionError(f"chunks {seen[key]!r} and {entry.text!r} share the key {key}")
        seen[key] = entry.text
        chunks.append(
            Chunk(
                key=key,
                text=entry.text,
                level=entry.level,
                function=entry.function,
                note=entry.note,
                provenance=_CURATED,
            )
        )
    return tuple(chunks)


def build_grammar_points(entries: Iterable[GrammarEntry], *, l2: str) -> tuple[GrammarPoint, ...]:
    """Grammar points keyed by their code; duplicate codes are an error."""
    points: list[GrammarPoint] = []
    codes: set[str] = set()
    for entry in entries:
        if entry.code in codes:
            raise SelectionError(f"grammar code {entry.code} appears twice")
        codes.add(entry.code)
        points.append(
            GrammarPoint(
                key=f"{l2}.{entry.code}",
                code=entry.code,
                level=entry.level,
                name=entry.name,
                description=entry.description,
                examples=entry.examples,
                provenance=_CURATED,
            )
        )
    return tuple(points)


_CHUNKS = TypeAdapter(tuple[ChunkEntry, ...])
_GRAMMAR = TypeAdapter(tuple[GrammarEntry, ...])


def _yaml(path: Path, empty: object) -> object:
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    return empty if data is None else data


def load_curation(
    directory: Path,
) -> tuple[WordSenseCuration, tuple[ChunkEntry, ...], tuple[GrammarEntry, ...]]:
    """Reads the three curation files of one language."""
    senses = WordSenseCuration.model_validate(_yaml(directory / WORD_SENSES_FILE, {}))
    chunks = _CHUNKS.validate_python(_yaml(directory / CHUNKS_FILE, []))
    grammar = _GRAMMAR.validate_python(_yaml(directory / GRAMMAR_FILE, []))
    return senses, chunks, grammar


def write_items(selection: Selection, items_dir: Path) -> None:
    """Writes `word_senses.jsonl`, `chunks.jsonl` and `grammar_points.jsonl`."""
    items_dir.mkdir(parents=True, exist_ok=True)
    files: dict[str, Iterable[BaseModel]] = {
        "word_senses.jsonl": selection.word_senses,
        "chunks.jsonl": selection.chunks,
        "grammar_points.jsonl": selection.grammar_points,
    }
    for name, items in files.items():
        with (items_dir / name).open("w", encoding="utf-8", newline="\n") as sink:
            for item in items:
                sink.write(item.model_dump_json(exclude_defaults=True) + "\n")


def read_lexicon(path: Path) -> tuple[LexiconEntry, ...]:
    """Entries of `work/lexicon.<l2>.jsonl`."""
    with path.open(encoding="utf-8") as stream:
        return tuple(LexiconEntry.model_validate_json(line) for line in stream if line.strip())


def run_select(content_dir: Path, *, l2: str, max_level: Level, limit: int) -> Selection:
    """Selects from `work/lexicon.<l2>.jsonl` and the curation files; writes the items."""
    lexicon_path = content_dir / "work" / f"lexicon.{l2}.jsonl"
    if not lexicon_path.is_file():
        raise FileNotFoundError(f"{lexicon_path} is missing, run `dilbaz-content lexicon`")
    senses, chunk_entries, grammar_entries = load_curation(content_dir / "curation" / l2)
    selection = Selection(
        word_senses=select_word_senses(
            read_lexicon(lexicon_path), senses, l2=l2, max_level=max_level, limit=limit
        ),
        chunks=build_chunks(chunk_entries, l2=l2),
        grammar_points=build_grammar_points(grammar_entries, l2=l2),
    )
    write_items(selection, content_dir / "packs" / l2 / "items")
    return selection

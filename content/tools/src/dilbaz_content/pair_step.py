"""S5: the pair pack of a learner language and a target language (docs/10 §6, docs/11 §2).

Turkish meanings and notes, sentence prompts, accepted English variants, rule
notes, contrast notes and the error catalogue are written in Claude Code
sessions into `curation/<l1>-<l2>/` and checked here before they become
`packs/<l1>-<l2>/*.jsonl`:

- every item of the target pack has a gloss;
- a sentence's prompt is its curated translation, else the validated Tatoeba
  translation, or the validation's fix when that translation was wrong;
- variants are normalized as answers are (docs/03 §0.5), deduplicated, and
  still contain the word of every sense the sentence is a carrier of;
- alternatives are correct answers without a target word ("gift" for
  "present"): not an error, but the learner is asked again (docs/03 §0.2);
- cards with the same prompt accept each other's answer, or the learner
  cannot know which one is meant;
- a grammar point's rule note (the H3 hint) holds no answer of a sentence that
  uses the point, nor the result of one of its "a → b" examples (I-02);
- contrast notes and error tags name existing items and grammar codes.
"""

from __future__ import annotations

import json
import re
from collections import Counter
from collections.abc import Callable, Iterable
from pathlib import Path
from typing import Literal, NamedTuple

import yaml
from pydantic import BaseModel, ConfigDict, Field, TypeAdapter

from dilbaz_content.analysis import Analyzer, Translation
from dilbaz_content.carriers import SenseMatcher, hyphenated
from dilbaz_content.carriers_step import read_word_senses
from dilbaz_content.grammar_tags import grammar_codes
from dilbaz_content.items import Chunk, GrammarPoint, Provenance, Sentence
from dilbaz_content.normalize import NORMALIZATION_FILE, Normalizer
from dilbaz_content.select_step import read_lexicon
from dilbaz_content.sentences_step import TURKISH_FILE, VALIDATION_FILE, read_validation

REPORT_FILE = "pair.{pair}.report.json"
_TATOEBA_LICENSE = "CC BY 2.0 FR"
_OWN = Provenance(source="dilbaz curation", license="own")
_VALIDATION_FIX = Provenance(source="dilbaz validation", license="own")


class SenseEntry(BaseModel):
    """`word_senses.yaml`: the learner-language meaning of one sense."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    # Equivalents, the usual one first ("izlemek, seyretmek").
    meaning: str = Field(min_length=1)
    note: str | None = None


class ChunkEntry(BaseModel):
    """`chunks.yaml`: a chunk's meaning, which is also its card prompt."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    meaning: str = Field(min_length=1)
    note: str | None = None
    # Shown with the prompt ("to a friend", "formal").
    context: str | None = None
    # The chunk's own words with small changes ("Thank you so much.").
    variants: tuple[str, ...] = ()
    # The same function in other words ("My pleasure." for "You're welcome."):
    # not an error, but asked again for the chunk (docs/03 §0.2).
    alternatives: tuple[str, ...] = ()


class SentenceEntry(BaseModel):
    """`sentences.yaml`: a sentence's prompt and accepted answers."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    # Replaces the Tatoeba translation; required for own sentences.
    turkish: str | None = Field(default=None, min_length=1)
    context: str | None = None
    variants: tuple[str, ...] = ()
    # Correct answers without a target word ("Here's a gift for you." on the
    # "present" card): not an error, but asked again for the target.
    alternatives: tuple[str, ...] = ()


class GrammarEntry(BaseModel):
    """`grammar.yaml`: a grammar point in the learner's language."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    name: str = Field(min_length=1)
    explanation: str = Field(min_length=1)
    # The H3 hint: the rule, never the answer.
    rule: str = Field(min_length=1)


class ContrastEntry(BaseModel):
    """`contrasts.yaml`: items learners confuse, and how they differ."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    items: tuple[str, ...] = Field(min_length=2)
    note: str = Field(min_length=1)


ErrorCategory = Literal["grammar", "vocabulary", "pronunciation", "perception", "pragmatics"]


class ErrorTagEntry(BaseModel):
    """`error_tags.yaml`: one tag of the closed error catalogue (docs/10 §6)."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    code: str = Field(pattern=r"^[a-z]+(\.[a-z0-9_]+)+$")
    category: ErrorCategory
    severity: float = Field(gt=0, le=1)
    description: str = Field(min_length=1)
    # "wrong → right" pairs.
    examples: tuple[str, ...] = Field(min_length=3)
    grammar_codes: tuple[str, ...] = ()
    # Pronunciation tags: expected IPA sound → the sound said instead (θ → t).
    pron_map: dict[str, str] = Field(default_factory=dict)


class Gloss(BaseModel):
    """`glosses.jsonl`: an item in the learner's language."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    key: str
    meaning: str
    explanation: str | None = None
    usage_note: str | None = None
    context: str | None = None
    provenance: Provenance


class Variants(BaseModel):
    """`variants.jsonl`: other correct answers of an item's card (I-17)."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    key: str
    variants: tuple[str, ...] = ()
    # Correct, but without a target word: asked again for it (docs/03 §0.2).
    alternatives: tuple[str, ...] = ()
    # Grammar codes of each listed answer of a sentence (S4's tagger): on a
    # grammar card, an answer says the target when it uses the card's
    # structure (docs/03 §0.5); "I'll call you" is not a going-to answer.
    grammar: dict[str, tuple[str, ...]] = Field(default_factory=dict)
    provenance: Provenance


class RuleNote(BaseModel):
    """`rule_notes.jsonl`: the H3 hint of a grammar point."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    code: str
    note: str
    provenance: Provenance


class ContrastNote(BaseModel):
    """`contrast_notes.jsonl`."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    items: tuple[str, ...]
    note: str
    provenance: Provenance


class ErrorTag(ErrorTagEntry):
    """`error_tags.jsonl`."""

    provenance: Provenance


IssueKind = Literal[
    "missing_gloss",
    "unknown_key",
    "missing_prompt",
    "variant_missing_target",
    "alternative_has_target",
    "prompt_clash",
    "rule_note_leak",
    "unknown_grammar_code",
    "duplicate_variant",
]
# Duplicate variants are dropped with a warning; everything else stops the build.
BLOCKING: frozenset[str] = frozenset(
    {
        "missing_gloss",
        "unknown_key",
        "missing_prompt",
        "variant_missing_target",
        "alternative_has_target",
        "prompt_clash",
        "rule_note_leak",
        "unknown_grammar_code",
    }
)


class Issue(BaseModel):
    """A problem with one entry."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    key: str
    kind: IssueKind
    detail: str


class PairReport(BaseModel):
    """`work/pair.<l1>-<l2>.report.json`."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    glosses: dict[str, int]
    variants: int
    alternatives: int
    rule_notes: int
    contrast_notes: int
    error_tags: int
    prompts: dict[str, int]
    issues: tuple[Issue, ...]

    @property
    def blocking(self) -> tuple[Issue, ...]:
        """Issues that must be fixed before the pack is built."""
        return tuple(issue for issue in self.issues if issue.kind in BLOCKING)


def _load[T](path: Path, adapter: TypeAdapter[T], empty: T) -> T:
    if not path.is_file():
        return empty
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    return adapter.validate_python(data) if data else empty


def _jsonl[T: BaseModel](path: Path, model: type[T]) -> tuple[T, ...]:
    if not path.is_file():
        raise FileNotFoundError(f"{path} is missing")
    with path.open(encoding="utf-8") as stream:
        return tuple(model.model_validate_json(line) for line in stream if line.strip())


def lemmas_of_forms(path: Path) -> dict[str, set[str]]:
    """Inflected form → lemmas from S1's lexicon, as the runtime's forms table (docs/11 §6)."""
    if not path.is_file():
        return {}
    found: dict[str, set[str]] = {}
    for entry in read_lexicon(path):
        for form in entry.forms:
            found.setdefault(form.lower(), set()).add(entry.lemma)
    return found


def read_translations(path: Path) -> dict[str, tuple[Translation, ...]]:
    """S4's Tatoeba translations by sentence key."""
    if not path.is_file():
        return {}
    found: dict[str, tuple[Translation, ...]] = {}
    with path.open(encoding="utf-8") as stream:
        for line in stream:
            if line.strip():
                row = json.loads(line)
                found[row["key"]] = tuple(Translation.model_validate(t) for t in row["turkish"])
    return found


def _write(path: Path, models: Iterable[BaseModel]) -> int:
    count = 0
    with path.open("w", encoding="utf-8", newline="\n") as sink:
        for model in models:
            sink.write(model.model_dump_json(exclude_defaults=True) + "\n")
            count += 1
    return count


class _Curation(BaseModel):
    model_config = ConfigDict(arbitrary_types_allowed=True, frozen=True)

    senses: dict[str, SenseEntry]
    chunks: dict[str, ChunkEntry]
    sentences: dict[str, SentenceEntry]
    grammar: dict[str, GrammarEntry]
    contrasts: tuple[ContrastEntry, ...]
    error_tags: tuple[ErrorTagEntry, ...]


def load_pair_curation(directory: Path) -> _Curation:
    """The curation files of a pair; missing files mean no entries."""
    return _Curation(
        senses=_load(directory / "word_senses.yaml", TypeAdapter(dict[str, SenseEntry]), {}),
        chunks=_load(directory / "chunks.yaml", TypeAdapter(dict[str, ChunkEntry]), {}),
        sentences=_load(directory / "sentences.yaml", TypeAdapter(dict[str, SentenceEntry]), {}),
        grammar=_load(directory / "grammar.yaml", TypeAdapter(dict[str, GrammarEntry]), {}),
        contrasts=_load(directory / "contrasts.yaml", TypeAdapter(tuple[ContrastEntry, ...]), ()),
        error_tags=_load(directory / "error_tags.yaml", TypeAdapter(tuple[ErrorTagEntry, ...]), ()),
    )


def _unknown(kind: str, named: Iterable[str], known: set[str]) -> list[Issue]:
    return [
        Issue(key=key, kind="unknown_key", detail=f"no {kind} with this key")
        for key in sorted(set(named) - known)
    ]


def _missing(keys: Iterable[str], glossed: set[str]) -> list[Issue]:
    return [
        Issue(key=key, kind="missing_gloss", detail="no gloss in the curation")
        for key in keys
        if key not in glossed
    ]


def _variants(
    key: str,
    reference: str,
    given: Iterable[str],
    normalize: Normalizer,
    taken: Iterable[str] = (),
) -> tuple[tuple[str, ...], list[Issue]]:
    """Answers without duplicates (after normalization) of each other, the reference and [taken]."""
    seen = {normalize(reference), *map(normalize, taken)}
    kept: list[str] = []
    issues: list[Issue] = []
    for variant in given:
        normal = normalize(variant)
        if normal in seen:
            issues.append(Issue(key=key, kind="duplicate_variant", detail=variant))
            continue
        seen.add(normal)
        kept.append(variant)
    return tuple(kept), issues


class _Check(NamedTuple):
    key: str
    text: str
    targets: tuple[str, ...]
    alternative: bool


class _Card(NamedTuple):
    key: str
    reference: str
    # Every accepted answer: variants and alternatives.
    variants: tuple[str, ...]
    # As the learner reads it: case and punctuation do not tell cards apart.
    prompt: tuple[str, str]


_EXAMPLE = re.compile(r"→\s*([^,;:.()→]+)")


def _shown_forms(rule: str) -> list[str]:
    """What the rule's "a → b" examples show: "go → went" shows "went"."""
    return [form.strip() for form in _EXAMPLE.findall(rule) if form.strip()]


def _prompt_key(meaning: str, context: str | None) -> tuple[str, str]:
    lowered = meaning.replace("İ", "i").replace("I", "ı").lower()
    return " ".join(re.sub(r"[^\w\s]", " ", lowered).split()), context or ""


def _clashes(cards: Iterable[_Card], normalize: Normalizer) -> list[Issue]:
    """Cards with the same prompt that do not accept each other's answer."""
    by_prompt: dict[tuple[str, str], list[_Card]] = {}
    for card in cards:
        by_prompt.setdefault(card.prompt, []).append(card)
    issues: list[Issue] = []
    for same in by_prompt.values():
        answers = [{normalize(c.reference), *map(normalize, c.variants)} for c in same]
        for index, later in enumerate(same):
            for earlier_index, earlier in enumerate(same[:index]):
                if (
                    normalize(earlier.reference) in answers[index]
                    and normalize(later.reference) in answers[earlier_index]
                ):
                    continue
                detail = f"same prompt as {earlier.key}; each must accept the other's answer"
                issues.append(Issue(key=later.key, kind="prompt_clash", detail=detail))
    return issues


def run_pair(
    content_dir: Path,
    *,
    l1: str,
    l2: str,
    analyzer: Callable[[], Analyzer],
) -> PairReport:
    """Builds `packs/<l1>-<l2>/` from the target pack and the pair's curation."""
    pair = f"{l1}-{l2}"
    target = content_dir / "packs" / l2
    items = target / "items"
    senses = read_word_senses(items / "word_senses.jsonl")
    chunks = _jsonl(items / "chunks.jsonl", Chunk)
    sentences = _jsonl(items / "sentences.jsonl", Sentence)
    points = _jsonl(items / "grammar_points.jsonl", GrammarPoint)
    normalize = Normalizer.from_file(target / NORMALIZATION_FILE)
    curation = load_pair_curation(content_dir / "curation" / pair)
    decisions = read_validation(content_dir / "curation" / l2 / VALIDATION_FILE)
    translations = read_translations(content_dir / "work" / TURKISH_FILE.format(l2=l2))

    issues: list[Issue] = []
    sense_keys = {s.key for s in senses}
    chunk_keys = {c.key for c in chunks}
    sentence_keys = {s.key for s in sentences}
    codes = {p.code for p in points}
    issues += _unknown("word sense", curation.senses, sense_keys)
    issues += _unknown("chunk", curation.chunks, chunk_keys)
    issues += _unknown("sentence", curation.sentences, sentence_keys)
    issues += _unknown("grammar point", curation.grammar, codes)
    issues += _missing((s.key for s in senses), set(curation.senses))
    issues += _missing((c.key for c in chunks), set(curation.chunks))
    issues += _missing((p.code for p in points), set(curation.grammar))

    glosses: list[Gloss] = []
    variants: list[Variants] = []
    counts: Counter[str] = Counter()
    cards: list[_Card] = []
    alternatives = 0
    for sense in senses:
        entry = curation.senses.get(sense.key)
        if entry is not None:
            glosses.append(
                Gloss(key=sense.key, meaning=entry.meaning, usage_note=entry.note, provenance=_OWN)
            )
            counts["word_senses"] += 1
    for chunk in chunks:
        chunk_entry = curation.chunks.get(chunk.key)
        if chunk_entry is None:
            continue
        glosses.append(
            Gloss(
                key=chunk.key,
                meaning=chunk_entry.meaning,
                usage_note=chunk_entry.note,
                context=chunk_entry.context,
                provenance=_OWN,
            )
        )
        counts["chunks"] += 1
        kept, found = _variants(chunk.key, chunk.text, chunk_entry.variants, normalize)
        issues += found
        others, found = _variants(
            chunk.key, chunk.text, chunk_entry.alternatives, normalize, taken=kept
        )
        issues += found
        if kept or others:
            variants.append(
                Variants(key=chunk.key, variants=kept, alternatives=others, provenance=_OWN)
            )
            alternatives += len(others)
        prompt = _prompt_key(chunk_entry.meaning, chunk_entry.context)
        cards.append(_Card(chunk.key, chunk.text, (*kept, *others), prompt))

    carriers_of: dict[str, list[str]] = {}
    for sense in senses:
        for sentence_key in sense.carriers:
            carriers_of.setdefault(sentence_key, []).append(sense.key)
    prompts: Counter[str] = Counter()
    checks: list[_Check] = []
    listed: list[tuple[str, tuple[str, ...], tuple[str, ...]]] = []
    for sentence in sentences:
        sentence_entry = curation.sentences.get(sentence.key) or SentenceEntry()
        decision = decisions.get(sentence.key)
        found_translations = translations.get(sentence.key, ())
        if sentence_entry.turkish is not None:
            meaning, provenance, source = sentence_entry.turkish, _OWN, "curated"
        elif decision is not None and decision.turkish_ok is False and decision.turkish_fix:
            meaning, provenance, source = decision.turkish_fix, _VALIDATION_FIX, "validation_fix"
        elif found_translations:
            first = found_translations[0]
            meaning, source = first.text, "tatoeba"
            provenance = Provenance(
                source=f"tatoeba:{first.id}", license=_TATOEBA_LICENSE, attribution=first.author
            )
        else:
            issues.append(Issue(key=sentence.key, kind="missing_prompt", detail=sentence.text))
            continue
        prompts[source] += 1
        glosses.append(
            Gloss(
                key=sentence.key,
                meaning=meaning,
                context=sentence_entry.context,
                provenance=provenance,
            )
        )
        counts["sentences"] += 1
        kept, found = _variants(sentence.key, sentence.text, sentence_entry.variants, normalize)
        issues += found
        others, found = _variants(
            sentence.key, sentence.text, sentence_entry.alternatives, normalize, taken=kept
        )
        issues += found
        prompt = _prompt_key(meaning, sentence_entry.context)
        cards.append(_Card(sentence.key, sentence.text, (*kept, *others), prompt))
        if kept or others:
            listed.append((sentence.key, kept, others))
            alternatives += len(others)
        targets = tuple(carriers_of.get(sentence.key, ()))
        if targets:
            checks += [_Check(sentence.key, text, targets, alternative=False) for text in kept]
            checks += [_Check(sentence.key, text, targets, alternative=True) for text in others]
    issues += _clashes(cards, normalize)

    answers = list(dict.fromkeys(text for _, kept, others in listed for text in (*kept, *others)))
    tagger = analyzer() if checks or answers else None
    grammar_of = (
        dict(
            zip(answers, (grammar_codes(tokens) for tokens in tagger.analyze(answers)), strict=True)
        )
        if tagger is not None
        else {}
    )
    for key, kept, others in listed:
        variants.append(
            Variants(
                key=key,
                variants=kept,
                alternatives=others,
                grammar={text: grammar_of[text] for text in (*kept, *others)},
                provenance=_OWN,
            )
        )

    # A variant must still say every target's word, in any form and also where
    # the tagger reads it as another part of speech ("I don't feel well", "good
    # at singing"); an alternative must lack one of them, or the learner is
    # asked again for a word already said.
    if checks and tagger is not None:
        matcher = SenseMatcher(senses)
        lemma_of = {s.key: s.lemma for s in senses}
        forms = lemmas_of_forms(content_dir / "work" / f"lexicon.{l2}.jsonl")
        analyzed = tagger.analyze(check.text for check in checks)
        for check, tokens in zip(checks, analyzed, strict=True):
            hits = matcher.hits(tokens)
            words = {
                word
                for index, (text, lemma, _, _) in enumerate(tokens)
                if not hyphenated(tokens, index)
                for word in (text.lower(), lemma, *forms.get(text.lower(), ()))
            }
            said = {k for k in check.targets if k in hits or lemma_of[k] in words}
            if check.alternative and said == set(check.targets):
                detail = f"{check.text} (has {', '.join(sorted(said))})"
                issues.append(Issue(key=check.key, kind="alternative_has_target", detail=detail))
            elif not check.alternative and said != set(check.targets):
                detail = f"{check.text} (lacks {', '.join(sorted(set(check.targets) - said))})"
                issues.append(Issue(key=check.key, kind="variant_missing_target", detail=detail))

    rule_notes: list[RuleNote] = []
    for point in points:
        grammar_entry = curation.grammar.get(point.code)
        if grammar_entry is None:
            continue
        glosses.append(
            Gloss(
                key=point.key,
                meaning=grammar_entry.name,
                explanation=grammar_entry.explanation,
                provenance=_OWN,
            )
        )
        counts["grammar_points"] += 1
        rule_notes.append(RuleNote(code=point.code, note=grammar_entry.rule, provenance=_OWN))
        padded = f" {normalize(grammar_entry.rule)} "
        shown = [(form, f" {normalize(form)} ") for form in _shown_forms(grammar_entry.rule)]
        for sentence in sentences:
            if point.code not in sentence.grammar:
                continue
            answer = f" {normalize(sentence.text)} "
            if answer in padded:
                detail = f"the note contains the answer {sentence.text!r}"
                issues.append(Issue(key=point.code, kind="rule_note_leak", detail=detail))
            # "go → went" gives away the verb of "I went to see a show today."
            for form, normal in shown:
                if normal in answer:
                    detail = f"the example form {form!r} is in the answer {sentence.text!r}"
                    issues.append(Issue(key=point.code, kind="rule_note_leak", detail=detail))

    item_keys = sense_keys | chunk_keys | sentence_keys | {p.key for p in points}
    contrast_notes: list[ContrastNote] = []
    for contrast in curation.contrasts:
        unknown = [key for key in contrast.items if key not in item_keys]
        issues += _unknown("item", unknown, set())
        contrast_notes.append(
            ContrastNote(items=contrast.items, note=contrast.note, provenance=_OWN)
        )
    error_tags: list[ErrorTag] = []
    for tag in curation.error_tags:
        for code in tag.grammar_codes:
            if code not in codes:
                issues.append(Issue(key=tag.code, kind="unknown_grammar_code", detail=code))
        error_tags.append(ErrorTag(**tag.model_dump(), provenance=_OWN))

    out = content_dir / "packs" / pair
    out.mkdir(parents=True, exist_ok=True)
    report = PairReport(
        glosses=dict(counts),
        variants=_write(out / "variants.jsonl", variants),
        alternatives=alternatives,
        rule_notes=_write(out / "rule_notes.jsonl", rule_notes),
        contrast_notes=_write(out / "contrast_notes.jsonl", contrast_notes),
        error_tags=_write(out / "error_tags.jsonl", error_tags),
        prompts=dict(prompts),
        issues=tuple(issues),
    )
    _write(out / "glosses.jsonl", glosses)
    work = content_dir / "work"
    work.mkdir(parents=True, exist_ok=True)
    (work / REPORT_FILE.format(pair=pair)).write_text(
        report.model_dump_json(indent=2) + "\n", encoding="utf-8"
    )
    return report

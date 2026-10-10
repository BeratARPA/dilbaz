"""S4: the carrier sentences of a pack, built and checked (docs/10-content-pipeline.md §4.4, §5).

Each word sense gets its best S3 candidate unless `curation/<l2>/sentences.yaml`
rejects it or names other carriers: a Tatoeba sentence by id, or an own
sentence. A sense that shares its lemma and part of speech with another selected
sense ("right": correct / not left) has no automatic choice: the tagger cannot
tell the two apart, so the curation names its carriers. Every sentence is
analysed, levelled, linked to the selected senses it contains, tagged with
grammar codes and checked. The chosen sentences become the `carriers` of their
senses in `word_senses.jsonl` (docs/11 §4). Turkish translations of the Tatoeba
sentences are kept in `work/` for S5. The independent validation pass (docs/10
§5.2) keeps its decisions in `curation/<l2>/sentences.validation.jsonl`; a
sentence without an accepted decision for its current text is reported.
"""

from __future__ import annotations

import json
from collections import Counter
from collections.abc import Callable, Iterable, Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import Literal

import yaml
from pydantic import BaseModel, ConfigDict, Field, model_validator

from dilbaz_content.analysis import Analyzer, Token, Translation, read_analysis
from dilbaz_content.carriers import (
    MAX_WORDS,
    UNLEVELLED_POS,
    Candidate,
    SenseMatcher,
    WordLevels,
    allowed_level,
    carrier_level,
    is_well_formed,
    pack_levels,
    token_levels,
    word_levels,
)
from dilbaz_content.carriers_step import (
    ANALYSIS_FILE,
    TargetCandidates,
    read_grammar_levels,
    read_word_senses,
)
from dilbaz_content.grammar_tags import grammar_codes, outside_levels
from dilbaz_content.items import Level, Provenance, Sentence, WordSense, level_index, slug
from dilbaz_content.select_step import read_lexicon

CURATION_FILE = "sentences.yaml"
VALIDATION_FILE = "sentences.validation.jsonl"
REPORT_FILE = "sentences.{l2}.report.json"
TURKISH_FILE = "sentences.{l2}.turkish.jsonl"
# Near duplicates: sentences whose lemma sets overlap this much (docs/10 §5.1).
DUPLICATE_JACCARD = 0.8
# Words no carrier may contain (docs/10 §5.1, "uygunsuz içerik").
BLOCKED_WORDS = frozenset(
    {"fuck", "fucking", "shit", "bitch", "bastard", "damn", "crap", "dick", "piss", "sex", "sexy"}
)
_TATOEBA_LICENSE = "CC BY 2.0 FR"
_OWN = Provenance(source="dilbaz curation", license="own")


class CarrierChoice(BaseModel):
    """A chosen carrier: a Tatoeba sentence by id, or an own sentence."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    tatoeba: int | None = None
    text: str | None = None

    @model_validator(mode="after")
    def _exactly_one(self) -> CarrierChoice:
        if (self.tatoeba is None) == (self.text is None):
            raise ValueError("give either tatoeba or text")
        return self


class SentenceCuration(BaseModel):
    """`curation/<l2>/sentences.yaml`."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    # Tatoeba sentences that are not good carriers (wrong sense, odd topic).
    reject: tuple[int, ...] = ()
    # sense key → carriers replacing the automatic choice.
    carriers: dict[str, tuple[CarrierChoice, ...]] = Field(default_factory=dict)


IssueKind = Literal[
    "unknown_word",
    "above_pack_level",
    "above_target_level",
    "too_long",
    "target_missing",
    "blocked_word",
    "malformed",
    "near_duplicate",
    "ambiguous_sense",
    "unvalidated",
]
# Issues that stop the build. Near duplicates are warnings for review;
# unvalidated sentences wait for the next validation pass.
BLOCKING: frozenset[str] = frozenset(
    {
        "unknown_word",
        "above_pack_level",
        "above_target_level",
        "too_long",
        "target_missing",
        "blocked_word",
        "malformed",
        "ambiguous_sense",
    }
)


class Validation(BaseModel):
    """One decision of the independent validation pass (docs/10 §5.2).

    The pass judges the English sentence; a wrong Turkish translation does not
    reject it but gives `turkish_fix` to S5.
    """

    model_config = ConfigDict(extra="forbid", frozen=True)

    key: str
    text: str
    round: int = Field(ge=1)
    naturalness: int = Field(ge=1, le=5)
    grammatical: bool
    ambiguous: bool
    sense_ok: bool
    suitable: bool
    turkish_ok: bool | None = None
    turkish_fix: str | None = None
    notes: str = ""
    accepted: bool
    # Why the sentence is kept although a check failed.
    override: str | None = None


def read_validation(path: Path) -> dict[str, Validation]:
    """The latest decision per sentence key; empty before the first pass."""
    if not path.is_file():
        return {}
    with path.open(encoding="utf-8") as stream:
        records = [Validation.model_validate_json(line) for line in stream if line.strip()]
    return {record.key: record for record in records}


class Issue(BaseModel):
    """A problem with one sentence."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    key: str
    kind: IssueKind
    detail: str


class SentencesReport(BaseModel):
    """`work/sentences.<l2>.report.json`."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    sentences: int
    tatoeba: int
    own: int
    validated: int = 0
    by_level: dict[str, int]
    grammar: dict[str, int]
    senses_without_carrier: tuple[str, ...]
    issues: tuple[Issue, ...]

    @property
    def blocking(self) -> tuple[Issue, ...]:
        """Issues that must be fixed before the pack is built."""
        return tuple(issue for issue in self.issues if issue.kind in BLOCKING)


@dataclass(frozen=True)
class _Draft:
    text: str
    tokens: tuple[Token, ...]
    provenance: Provenance
    turkish: tuple[Translation, ...]
    chosen_for: tuple[str, ...]


def load_curation(path: Path) -> SentenceCuration:
    """The curation file, or no decisions when it does not exist yet."""
    if not path.is_file():
        return SentenceCuration()
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    return SentenceCuration.model_validate(data or {})


def read_candidates(path: Path) -> dict[str, TargetCandidates]:
    """Lines of `work/carriers.<l2>.candidates.jsonl` by target key."""
    if not path.is_file():
        raise FileNotFoundError(f"{path} is missing, run `dilbaz-content carriers`")
    with path.open(encoding="utf-8") as stream:
        lines = [TargetCandidates.model_validate_json(line) for line in stream if line.strip()]
    return {line.target: line for line in lines}


def _tatoeba_provenance(candidate: Candidate) -> Provenance:
    return Provenance(
        source=f"tatoeba:{candidate.sentence_id}",
        license=_TATOEBA_LICENSE,
        attribution=candidate.author,
    )


def ambiguous_senses(senses: Iterable[WordSense]) -> dict[str, tuple[str, ...]]:
    """sense key → the other selected senses with the same lemma and part of speech."""
    groups: dict[tuple[str, str], list[str]] = {}
    for sense in senses:
        groups.setdefault((sense.lemma, sense.pos), []).append(sense.key)
    return {
        key: tuple(other for other in keys if other != key)
        for keys in groups.values()
        if len(keys) > 1
        for key in keys
    }


def _choose(
    senses: Iterable[WordSense],
    candidates: dict[str, TargetCandidates],
    curation: SentenceCuration,
    ambiguous: Mapping[str, tuple[str, ...]],
) -> tuple[dict[str, list[CarrierChoice]], list[str], list[Issue]]:
    """sense key → choices, the senses that have none, and ambiguous senses left open."""
    rejected = set(curation.reject)
    chosen: dict[str, list[CarrierChoice]] = {}
    missing: list[str] = []
    issues: list[Issue] = []
    for sense in senses:
        picks = curation.carriers.get(sense.key)
        if picks is not None:
            chosen[sense.key] = list(picks)
            continue
        if sense.key in ambiguous:
            detail = "choose its carriers; same lemma as " + ", ".join(ambiguous[sense.key])
            issues.append(Issue(key=sense.key, kind="ambiguous_sense", detail=detail))
            continue
        line = candidates.get(sense.key)
        best = (
            next((c for c in line.candidates if c.sentence_id not in rejected), None)
            if line
            else None
        )
        if best is None:
            missing.append(sense.key)
        else:
            chosen[sense.key] = [CarrierChoice(tatoeba=best.sentence_id)]
    return chosen, missing, issues


def _drafts(
    chosen: dict[str, list[CarrierChoice]],
    candidates: dict[str, TargetCandidates],
    cache: Path,
    analyzer: Callable[[], Analyzer],
) -> tuple[list[_Draft], dict[str, list[str]]]:
    """One draft per distinct text, remembering which senses chose it, and the
    normalized texts each sense chose, in order."""
    by_id: dict[int, Candidate] = {
        c.sentence_id: c for line in candidates.values() for c in line.candidates
    }
    wanted_ids = {c.tatoeba for picks in chosen.values() for c in picks if c.tatoeba is not None}
    tokens_by_id: dict[int, tuple[Token, ...]] = {}
    turkish_by_id: dict[int, tuple[Translation, ...]] = {}
    extra: dict[int, Candidate] = {}
    for record in read_analysis(cache):
        if record.id in wanted_ids:
            tokens_by_id[record.id] = record.tokens
            turkish_by_id[record.id] = record.turkish
            if record.id not in by_id:
                extra[record.id] = Candidate(
                    target="",
                    sentence_id=record.id,
                    text=record.text,
                    author=record.author,
                    level="A0",
                    words=len(record.text.split()),
                    native=record.native,
                    names=0,
                    score=0.0,
                    turkish=tuple(t.text for t in record.turkish),
                )
    unknown = sorted(wanted_ids - set(tokens_by_id))
    if unknown:
        raise ValueError(f"Tatoeba ids not in the analysis cache: {unknown}")
    own_texts = sorted({c.text for picks in chosen.values() for c in picks if c.text is not None})
    own_tokens = (
        dict(zip(own_texts, analyzer().analyze(own_texts), strict=True)) if own_texts else {}
    )

    drafts: dict[str, _Draft] = {}
    texts_by_sense: dict[str, list[str]] = {}
    for sense_key, picks in chosen.items():
        for pick in picks:
            if pick.tatoeba is not None:
                candidate = by_id.get(pick.tatoeba) or extra[pick.tatoeba]
                text, tokens = candidate.text, tokens_by_id[pick.tatoeba]
                provenance = _tatoeba_provenance(candidate)
                turkish = turkish_by_id[pick.tatoeba]
            else:
                text = pick.text or ""
                tokens, provenance, turkish = own_tokens[text], _OWN, ()
            normal = _normalized(text)
            previous = drafts.get(normal)
            chosen_for = (*previous.chosen_for, sense_key) if previous else (sense_key,)
            drafts[normal] = _Draft(text, tokens, provenance, turkish, chosen_for)
            texts_by_sense.setdefault(sense_key, []).append(normal)
    return list(drafts.values()), texts_by_sense


def _normalized(text: str) -> str:
    return " ".join(text.lower().split())


def _lemmas(tokens: tuple[Token, ...]) -> tuple[str, ...]:
    return tuple(dict.fromkeys(lemma for _, lemma, pos, _ in tokens if pos not in UNLEVELLED_POS))


def _check(
    draft: _Draft,
    key: str,
    senses: dict[str, WordSense],
    ambiguous: Mapping[str, tuple[str, ...]],
    matcher: SenseMatcher,
    levels: WordLevels,
    grammar_levels: dict[str, Level],
    max_level: Level,
) -> tuple[Sentence | None, list[Issue]]:
    issues: list[Issue] = []
    words = [w.strip(".,!?").lower() for w in draft.text.split()]
    blocked = sorted(BLOCKED_WORDS.intersection(words))
    if blocked:
        issues.append(Issue(key=key, kind="blocked_word", detail=", ".join(blocked)))
    if not is_well_formed(draft.text):
        issues.append(Issue(key=key, kind="malformed", detail="quotes, brackets or two sentences"))
    found = token_levels(draft.tokens, levels)
    if found is None:
        unknown = [
            text
            for text, lemma, pos, _ in draft.tokens
            if pos not in UNLEVELLED_POS
            and levels.of(lemma, pos) is None
            and levels.of(text.lower(), pos) is None
        ]
        issues.append(Issue(key=key, kind="unknown_word", detail=", ".join(unknown)))
        return None, issues
    codes = grammar_codes(draft.tokens)
    outside = outside_levels(draft.tokens)
    hits = matcher.hits(draft.tokens)
    found = pack_levels(found, hits)
    for sense_key in draft.chosen_for:
        if sense_key not in hits:
            issues.append(Issue(key=key, kind="target_missing", detail=sense_key))
            continue
        index, sense = hits[sense_key]
        as_carrier = carrier_level(sense, index, found, codes, grammar_levels, outside)
        if level_index(as_carrier) > level_index(allowed_level(sense.level)):
            issues.append(
                Issue(key=key, kind="above_target_level", detail=f"{sense_key}: {as_carrier}")
            )
    word_levels_found: list[Level] = [lv for lv in found if lv is not None]
    grammar_found: list[Level] = [grammar_levels[c] for c in codes if c in grammar_levels]
    level: Level = max(("A0", *word_levels_found, *grammar_found, *outside), key=level_index)
    if level_index(level) > level_index(max_level):
        issues.append(Issue(key=key, kind="above_pack_level", detail=level))
    if len(draft.text.split()) > MAX_WORDS[level]:
        issues.append(Issue(key=key, kind="too_long", detail=f"{len(words)} words at {level}"))
    # An ambiguous word stands only for the sense the curation chose it for.
    linked = {hit for hit in hits if hit not in ambiguous or hit in draft.chosen_for}
    targets = tuple(sorted(linked | (set(draft.chosen_for) & set(senses))))
    sentence = Sentence(
        key=key,
        text=draft.text,
        level=level,
        lemmas=_lemmas(draft.tokens),
        targets=targets or draft.chosen_for,
        grammar=codes,
        provenance=draft.provenance,
    )
    return sentence, issues


def _near_duplicates(sentences: list[Sentence]) -> list[Issue]:
    issues: list[Issue] = []
    sets = [(s.key, set(s.lemmas)) for s in sentences]
    for i, (key, lemmas) in enumerate(sets):
        for other_key, other in sets[i + 1 :]:
            union = lemmas | other
            if union and len(lemmas & other) / len(union) > DUPLICATE_JACCARD:
                issues.append(Issue(key=key, kind="near_duplicate", detail=other_key))
    return issues


def run_sentences(
    content_dir: Path,
    *,
    l2: str,
    analyzer: Callable[[], Analyzer],
    max_level: Level = "A2",
) -> SentencesReport:
    """Builds `packs/<l2>/items/sentences.jsonl` and the S4 report."""
    work = content_dir / "work"
    items = content_dir / "packs" / l2 / "items"
    senses = read_word_senses(items / "word_senses.jsonl")
    candidates = read_candidates(work / f"carriers.{l2}.candidates.jsonl")
    curation = load_curation(content_dir / "curation" / l2 / CURATION_FILE)
    ambiguous = ambiguous_senses(senses)
    chosen, missing, issues = _choose(senses, candidates, curation, ambiguous)
    drafts, texts_by_sense = _drafts(chosen, candidates, work / ANALYSIS_FILE, analyzer)

    levels = word_levels(read_lexicon(work / f"lexicon.{l2}.jsonl"))
    grammar_levels = read_grammar_levels(items / "grammar_points.jsonl")
    by_key = {sense.key: sense for sense in senses}
    matcher = SenseMatcher(senses)
    sentences: list[Sentence] = []
    seen_keys: dict[str, str] = {}
    for draft in drafts:
        key = f"{l2}.sent.{slug(draft.text)}"
        if key in seen_keys:
            issues.append(Issue(key=key, kind="near_duplicate", detail=seen_keys[key]))
            continue
        seen_keys[key] = draft.text
        sentence, found = _check(
            draft, key, by_key, ambiguous, matcher, levels, grammar_levels, max_level
        )
        issues.extend(found)
        if sentence is not None:
            sentences.append(sentence)
    issues.extend(_near_duplicates(sentences))
    decisions = read_validation(content_dir / "curation" / l2 / VALIDATION_FILE)
    validated = 0
    for sentence in sentences:
        decision = decisions.get(sentence.key)
        if decision is not None and decision.text == sentence.text and decision.accepted:
            validated += 1
        else:
            issues.append(
                Issue(key=sentence.key, kind="unvalidated", detail="no accepted validation")
            )

    with (items / "sentences.jsonl").open("w", encoding="utf-8", newline="\n") as sink:
        for sentence in sentences:
            sink.write(sentence.model_dump_json(exclude_defaults=True) + "\n")
    key_by_text = {_normalized(sentence.text): sentence.key for sentence in sentences}
    with (items / "word_senses.jsonl").open("w", encoding="utf-8", newline="\n") as sink:
        for sense in senses:
            chosen_keys = (key_by_text.get(t) for t in texts_by_sense.get(sense.key, ()))
            carriers = tuple(dict.fromkeys(k for k in chosen_keys if k is not None))
            with_carriers = sense.model_copy(update={"carriers": carriers})
            sink.write(with_carriers.model_dump_json(exclude_defaults=True) + "\n")
    # The translations keep their Tatoeba id and author for S5's provenance.
    turkish = {
        f"{l2}.sent.{slug(d.text)}": [t.model_dump(exclude_defaults=True) for t in d.turkish]
        for d in drafts
        if d.turkish
    }
    with (work / TURKISH_FILE.format(l2=l2)).open("w", encoding="utf-8", newline="\n") as sink:
        for key, translations in turkish.items():
            line = {"key": key, "turkish": translations}
            sink.write(json.dumps(line, ensure_ascii=False) + "\n")
    grammar = Counter(code for sentence in sentences for code in sentence.grammar)
    report = SentencesReport(
        sentences=len(sentences),
        tatoeba=sum(s.provenance.source.startswith("tatoeba:") for s in sentences),
        own=sum(s.provenance.license == "own" for s in sentences),
        validated=validated,
        by_level=dict(sorted(Counter(s.level for s in sentences).items())),
        grammar=dict(sorted(grammar.items())),
        senses_without_carrier=tuple(missing),
        issues=tuple(issues),
    )
    (work / REPORT_FILE.format(l2=l2)).write_text(
        report.model_dump_json(indent=2) + "\n", encoding="utf-8"
    )
    return report

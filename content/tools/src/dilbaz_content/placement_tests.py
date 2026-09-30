"""S8: the grammar bank and the dictation set of the placement test
(docs/06-assessment.md §2 parts 2 and 3, docs/10-content-pipeline.md §5.3).

Grammar bank. `curation/<l2>/placement_grammar.yaml` holds hand-written
items: a sentence with one gap, the answer and two distractors. An item
enters the bank only when an independent check, made without the key, found
the answer to be the one correct choice, the sentence natural and the
structure at its level (`placement_grammar.validation.jsonl`, I-16). The
check is recorded as it was made; whether it agrees with the key is decided
here, so a changed item needs a new check of its exact text.

Dictation set. Each version of the test gets sentences of the pack with a
clip, of rising level and length. A sentence with a contraction, a digit or
a name is left out: the set measures hearing, and how to write "don't", "2"
or "Tom" is a question of spelling.
"""

from __future__ import annotations

import json
import random
from collections import Counter
from collections.abc import Iterable, Mapping, Sequence
from pathlib import Path
from typing import Literal

import yaml
from pydantic import BaseModel, ConfigDict, Field

from dilbaz_content.audio_step import AUDIO_FILE, Clip
from dilbaz_content.items import GrammarPoint, Level, Provenance, Sentence, level_index
from dilbaz_content.lexicon import LexiconEntry
from dilbaz_content.normalize import NORMALIZATION_FILE, Normalizer
from dilbaz_content.select_step import read_lexicon

GAP = "___"
GRAMMAR_FILE = Path("placement") / "grammar.jsonl"
DICTATION_FILE = Path("placement") / "dictation.jsonl"
GRAMMAR_CURATION = "placement_grammar.yaml"
GRAMMAR_VALIDATION = "placement_grammar.validation.jsonl"
DICTATION_CURATION = "placement_dictation.yaml"
REPORT_FILE = "placement_tests.{l2}.report.json"
_SENTENCE_END = ".!?"
_PROVENANCE = Provenance(source="dilbaz curation", license="own")
# Fewest and most words of a dictation sentence, by level.
_DICTATION_WORDS: dict[Level, tuple[int, int]] = {"A1": (5, 7), "A2": (7, 9)}

IssueKind = Literal[
    "duplicate",
    "gap",
    "options",
    "unknown_grammar",
    "grammar_above_level",
    "unvalidated",
    "disputed",
    "unnatural",
    "off_level",
]


class PlacementTestsError(Exception):
    """The pack cannot fill the placement test."""


class GrammarDraft(BaseModel):
    """One item of `curation/<l2>/placement_grammar.yaml`."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    id: str = Field(pattern=r"^[a-z0-9]+\.[a-z0-9_]+$")
    level: Level
    # The pack's grammar point the item tests; None above the pack's levels.
    grammar: str | None = None
    focus: str = Field(min_length=1)
    stem: str = Field(min_length=1)
    answer: str = Field(min_length=1)
    distractors: tuple[str, str]

    @property
    def options(self) -> tuple[str, ...]:
        """The answer and the distractors."""
        return (self.answer, *self.distractors)

    @property
    def sentence(self) -> str:
        """The stem with the answer in the gap."""
        return self.stem.replace(GAP, self.answer)


class GrammarCuration(BaseModel):
    """`curation/<l2>/placement_grammar.yaml`."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    items: tuple[GrammarDraft, ...] = Field(min_length=1)


class GrammarCheck(BaseModel):
    """`placement_grammar.validation.jsonl`: what a check without the key found."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    id: str
    stem: str
    # The choices as they were shown, in any order.
    options: tuple[str, ...]
    round: int = Field(ge=1)
    # The choices the check found to be correct standard language.
    acceptable: tuple[str, ...]
    natural: bool
    level_ok: bool
    tests: str | None = None
    note: str | None = None
    # A reasoned exception: the item stands although the check disagrees.
    override: str | None = None


class GrammarItem(BaseModel):
    """`placement/grammar.jsonl`: one validated item."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    key: str = Field(pattern=r"^[a-z]{2,3}\.pgram\.[a-z0-9_.]+$")
    level: Level
    grammar: str | None = None
    focus: str
    stem: str
    answer: str
    distractors: tuple[str, ...]
    provenance: Provenance


class DictationCuration(BaseModel):
    """`curation/<l2>/placement_dictation.yaml`."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    seed: int = 2026
    versions: tuple[str, ...] = ("A", "B", "C")
    # Level of each sentence of a version.
    levels: tuple[Level, ...] = ("A1", "A1", "A2", "A2", "A2")
    # Fewest and most words of a sentence of each level.
    words: dict[Level, tuple[int, int]] = Field(default_factory=lambda: dict(_DICTATION_WORDS))
    # The voice of the clips, at normal speed.
    voice: str = "v1"
    # Sentences left out by hand.
    exclude: tuple[str, ...] = ()


class DictationItem(BaseModel):
    """`placement/dictation.jsonl`: one sentence of one version."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    version: str
    # Place in the version, from 1; levels and lengths rise.
    order: int = Field(ge=1)
    level: Level
    sentence: str


class Issue(BaseModel):
    """Why a grammar item cannot enter the bank."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    id: str
    kind: IssueKind
    detail: str


class PlacementTestsReport(BaseModel):
    """`work/placement_tests.<l2>.report.json`."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    grammar_by_level: dict[str, int]
    issues: tuple[Issue, ...]
    # Item → words above its level or outside the lexicon (not an issue).
    hard_words: dict[str, tuple[str, ...]]
    dictation: int
    dictation_eligible: dict[str, int]


def load_grammar_curation(path: Path) -> tuple[GrammarDraft, ...]:
    """The hand-written items."""
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    return GrammarCuration.model_validate(data).items


def read_checks(path: Path) -> dict[str, GrammarCheck]:
    """The latest check of each item; a missing file means none."""
    if not path.is_file():
        return {}
    checks: dict[str, GrammarCheck] = {}
    with path.open(encoding="utf-8") as stream:
        for line in stream:
            if line.strip():
                check = GrammarCheck.model_validate_json(line)
                checks[check.id] = check
    return checks


def _starts_sentence(stem: str) -> bool:
    before = stem.split(GAP)[0].rstrip()
    return not before or before[-1] in _SENTENCE_END


def _is_capitalised(option: str) -> bool:
    return option[:1].isupper() and not (option == "I" or option.startswith(("I ", "I'")))


def _shape_issues(draft: GrammarDraft) -> Iterable[Issue]:
    if draft.stem.count(GAP) != 1:
        yield Issue(id=draft.id, kind="gap", detail=f"the stem needs exactly one {GAP}")
        return
    options = draft.options
    if len({option.lower() for option in options}) != len(options):
        yield Issue(id=draft.id, kind="options", detail="two choices are the same")
    if any(GAP in option or option != option.strip() for option in options):
        yield Issue(id=draft.id, kind="options", detail="a choice has a gap or outer spaces")
    # A choice that opens a sentence is capitalised, any other is not; the
    # odd one out would give the answer away.
    if _starts_sentence(draft.stem):
        wrong = [option for option in options if not option[:1].isupper()]
    else:
        wrong = [option for option in options if _is_capitalised(option)]
    if wrong:
        yield Issue(id=draft.id, kind="options", detail=f"capitalisation: {', '.join(wrong)}")


def _grammar_issues(
    draft: GrammarDraft, points: Mapping[str, GrammarPoint], top: int
) -> Iterable[Issue]:
    if draft.grammar is None:
        if level_index(draft.level) <= top:
            yield Issue(
                id=draft.id, kind="unknown_grammar", detail="an item of the pack's levels needs one"
            )
        return
    point = points.get(draft.grammar)
    if point is None:
        yield Issue(id=draft.id, kind="unknown_grammar", detail=draft.grammar)
    elif level_index(point.level) > level_index(draft.level):
        yield Issue(
            id=draft.id,
            kind="grammar_above_level",
            detail=f"{draft.grammar} is {point.level}, the item {draft.level}",
        )


def check_issue(
    item: str,
    check: GrammarCheck | None,
    *,
    stem: str,
    answer: str,
    distractors: Sequence[str],
) -> Issue | None:
    """Why the independent check does not carry the item with this text, or None."""
    options = sorted((answer, *distractors))
    if check is None or check.stem != stem or sorted(check.options) != options:
        return Issue(id=item, kind="unvalidated", detail="no check of this exact text")
    if check.override:
        return None
    if tuple(check.acceptable) != (answer,):
        found = ", ".join(check.acceptable) or "none"
        return Issue(id=item, kind="disputed", detail=f"the check accepts: {found}")
    if not check.natural:
        return Issue(id=item, kind="unnatural", detail=check.note or "")
    if not check.level_ok:
        return Issue(id=item, kind="off_level", detail=check.note or "")
    return None


def grammar_issues(
    drafts: Sequence[GrammarDraft],
    points: Iterable[GrammarPoint],
    checks: Mapping[str, GrammarCheck],
) -> list[Issue]:
    """Everything that keeps items out of the bank."""
    by_code = {point.code: point for point in points}
    top = max((level_index(point.level) for point in by_code.values()), default=-1)
    issues: list[Issue] = []
    seen: set[str] = set()
    for draft in drafts:
        if draft.id in seen:
            issues.append(Issue(id=draft.id, kind="duplicate", detail="the id is used twice"))
        seen.add(draft.id)
        shape = list(_shape_issues(draft))
        issues += shape
        issues += _grammar_issues(draft, by_code, top)
        if not shape:
            issue = check_issue(
                draft.id,
                checks.get(draft.id),
                stem=draft.stem,
                answer=draft.answer,
                distractors=draft.distractors,
            )
            if issue is not None:
                issues.append(issue)
    return issues


def hard_words(
    draft: GrammarDraft, normalizer: Normalizer, levels: Mapping[str, str | None]
) -> tuple[str, ...]:
    """Words of the sentence above the item's level or outside the lexicon.

    [levels] maps a word form to the lowest level of its lemmas. The words
    around the gap should not be what makes an item hard.
    """
    limit = level_index(draft.level)
    hard = []
    for word in normalizer(draft.sentence).split():
        level = levels.get(word)
        if level is None or level_index(level) > limit:
            hard.append(word)
    return tuple(dict.fromkeys(hard))


def form_levels(lexicon: Iterable[LexiconEntry]) -> dict[str, str | None]:
    """Word form → the lowest level of the lemmas it belongs to."""
    levels: dict[str, str | None] = {}
    for entry in lexicon:
        if entry.multiword:
            continue
        for form in (entry.lemma, *entry.spellings, *entry.forms):
            known = levels.get(form.lower())
            if form.lower() not in levels or (
                entry.cefr is not None
                and (known is None or level_index(entry.cefr) < level_index(known))
            ):
                levels[form.lower()] = entry.cefr
    return levels


def grammar_bank(
    drafts: Sequence[GrammarDraft], issues: Iterable[Issue], *, l2: str
) -> list[GrammarItem]:
    """The items without issues, as they go into the pack."""
    rejected = {issue.id for issue in issues}
    return [
        GrammarItem(
            key=f"{l2}.pgram.{draft.id}",
            level=draft.level,
            grammar=draft.grammar,
            focus=draft.focus,
            stem=draft.stem,
            answer=draft.answer,
            distractors=draft.distractors,
            provenance=_PROVENANCE,
        )
        for draft in drafts
        if draft.id not in rejected
    ]


def _dictation_words(sentence: Sentence, normalizer: Normalizer) -> int | None:
    """Words of a sentence fit for dictation, or None when it is not."""
    text = sentence.text
    if "'" in text or any(mark in text for mark in normalizer.rules.apostrophes):
        return None
    if any(character.isdigit() for character in text) or "-" in text:
        return None
    if any(_is_capitalised(word) for word in text.split()[1:]):
        return None
    return len(normalizer(text).split())


def dictation_set(
    sentences: Iterable[Sentence],
    clips: Iterable[Clip],
    normalizer: Normalizer,
    curation: DictationCuration,
) -> tuple[list[DictationItem], dict[str, int]]:
    """The sentences of each version and how many were eligible per level."""
    spoken = {clip.key for clip in clips if clip.voice == curation.voice and clip.speed == 1}
    excluded = set(curation.exclude)
    pools: dict[Level, list[tuple[int, str]]] = {level: [] for level in curation.levels}
    for sentence in sorted(sentences, key=lambda s: s.key):
        if sentence.level not in pools or sentence.key not in spoken or sentence.key in excluded:
            continue
        words = _dictation_words(sentence, normalizer)
        fewest, most = curation.words[sentence.level]
        if words is not None and fewest <= words <= most:
            pools[sentence.level].append((words, sentence.key))
    eligible: dict[str, int] = {level: len(pool) for level, pool in pools.items()}
    needed = Counter(curation.levels)
    for level, pool in pools.items():
        if len(pool) < needed[level] * len(curation.versions):
            raise PlacementTestsError(
                f"{len(pool)} sentences of {level} fit for dictation, "
                f"{needed[level] * len(curation.versions)} needed"
            )
        random.Random(f"{curation.seed}:{level}").shuffle(pool)
    items: list[DictationItem] = []
    for version in curation.versions:
        picks = sorted(
            (level_index(level), *pools[level].pop(0), level) for level in curation.levels
        )
        items += [
            DictationItem(version=version, order=order, level=level, sentence=key)
            for order, (_, _, key, level) in enumerate(picks, start=1)
        ]
    return items, eligible


def load_dictation_curation(path: Path) -> DictationCuration:
    """The curation file; a missing file means the defaults."""
    if not path.is_file():
        return DictationCuration()
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    return DictationCuration.model_validate(data or {})


def _read[T: BaseModel](path: Path, model: type[T]) -> list[T]:
    with path.open(encoding="utf-8") as stream:
        return [model.model_validate_json(line) for line in stream if line.strip()]


def _write(path: Path, rows: Iterable[BaseModel]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as sink:
        for row in rows:
            sink.write(row.model_dump_json(exclude_none=True) + "\n")


def run_placement_tests(content_dir: Path, *, l2: str) -> PlacementTestsReport:
    """Builds `packs/<l2>/placement/grammar.jsonl` and `dictation.jsonl`."""
    pack = content_dir / "packs" / l2
    curation = content_dir / "curation" / l2
    normalizer = Normalizer.from_file(pack / NORMALIZATION_FILE)

    drafts = load_grammar_curation(curation / GRAMMAR_CURATION)
    points = _read(pack / "items" / "grammar_points.jsonl", GrammarPoint)
    issues = grammar_issues(drafts, points, read_checks(curation / GRAMMAR_VALIDATION))
    bank = grammar_bank(drafts, issues, l2=l2)
    _write(pack / GRAMMAR_FILE, bank)

    levels = form_levels(read_lexicon(content_dir / "work" / f"lexicon.{l2}.jsonl"))
    hard = {draft.id: hard_words(draft, normalizer, levels) for draft in drafts}

    dictation, eligible = dictation_set(
        _read(pack / "items" / "sentences.jsonl", Sentence),
        _read(pack / AUDIO_FILE, Clip),
        normalizer,
        load_dictation_curation(curation / DICTATION_CURATION),
    )
    _write(pack / DICTATION_FILE, dictation)

    report = PlacementTestsReport(
        grammar_by_level=dict(sorted(Counter(item.level for item in bank).items())),
        issues=tuple(issues),
        hard_words={item: words for item, words in hard.items() if words},
        dictation=len(dictation),
        dictation_eligible=eligible,
    )
    work = content_dir / "work"
    work.mkdir(parents=True, exist_ok=True)
    (work / REPORT_FILE.format(l2=l2)).write_text(
        json.dumps(report.model_dump(mode="json"), indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    return report

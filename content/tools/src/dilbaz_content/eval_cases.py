"""The gold set of the LLM answer check (docs/07-ai-tutor.md §8).

`evals/tutor/answer_check/cases.yaml` holds hand-written cases: a card of the
packs, a learner's answer and the verdicts that count as right. This step
fills in what the app sends with the answer (docs/07 §4.1): the prompt, the
reference, the listed answers, the target and the grammar codes. For the
engine's deterministic check, which runs the same set in CI, it adds the
forms of the case's words from the built pack (`content_forms`).

An answer that a listed one matches after normalization never reaches the
LLM (docs/03 §0.5), so such a case is refused.

Every gold answer is checked by a second rater who does not see it
(`validation.jsonl`, the latest round of a case counts). A case without a
check, or whose check disagrees (the rater's first verdict outside the
case's verdicts, or another target_ok), stays out.
"""

from __future__ import annotations

import json
import sqlite3
from collections import Counter
from collections.abc import Callable, Iterable, Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Literal

import yaml
from pydantic import BaseModel, ConfigDict, Field

from dilbaz_content.analysis import Analyzer
from dilbaz_content.grammar_tags import grammar_codes
from dilbaz_content.items import Chunk, GrammarPoint, Level, Sentence, WordSense
from dilbaz_content.normalize import NORMALIZATION_FILE, Normalizer
from dilbaz_content.pair_step import Gloss, Variants

CASES_DIR = Path("evals") / "tutor" / "answer_check"
CASES_SOURCE = "cases.yaml"
CASES_FILE = "cases.jsonl"
VALIDATION_FILE = "validation.jsonl"
DEFAULT_CONFIDENCE = 0.9
# Error categories a card answer can show (pronunciation and perception tags
# belong to speaking tasks and dictation).
CARD_CATEGORIES = frozenset({"grammar", "vocabulary", "pragmatics"})

Verdict = Literal[
    "correct",
    "acceptable_variant",
    "minor_error",
    "wrong",
    "off_target",
    "unintelligible",
    "uncertain",
]
_WITHOUT_TARGET: frozenset[str] = frozenset({"wrong", "off_target", "unintelligible"})
_TAGGED: frozenset[str] = frozenset({"minor_error", "wrong"})

IssueKind = Literal[
    "duplicate",
    "unknown_card",
    "unknown_sentence",
    "not_carried",
    "matched",
    "unknown_tag",
    "inconsistent",
    "unvalidated",
    "disputed",
]


class EvalCase(BaseModel):
    """One case of `cases.yaml`."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    id: str = Field(pattern=r"^[a-z]\d{2}$")
    card: str = Field(min_length=1)
    # The carrier sentence without "en.sent."; none for a set phrase.
    sent: str | None = None
    say: str = Field(min_length=1)
    src: Literal["asr", "typed"] = "asr"
    conf: float | None = Field(default=None, ge=0, le=1)
    expect: tuple[Verdict, ...] = Field(min_length=1)
    target_ok: bool | None = None
    tags: tuple[str, ...] = ()
    why: str | None = None


class Check(BaseModel):
    """One line of `validation.jsonl`: a blind rater's judgment of a case."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    id: str
    round: int = Field(ge=1)
    verdicts: tuple[Verdict, ...] = Field(min_length=1)
    target_ok: bool | Literal["either"]
    note: str | None = None


class Issue(BaseModel):
    model_config = ConfigDict(frozen=True)

    id: str
    kind: IssueKind
    detail: str


class EvalReport(BaseModel):
    model_config = ConfigDict(frozen=True)

    cases: int
    by_kind: dict[str, int]
    by_verdict: dict[str, int]
    issues: tuple[Issue, ...] = ()


@dataclass(frozen=True)
class Packs:
    """What the cases are built from: a target pack and its pair pack."""

    l1: str
    l2: str
    sentences: Mapping[str, Sentence]
    senses: Mapping[str, WordSense]
    chunks: Mapping[str, Chunk]
    points: Mapping[str, GrammarPoint]
    glosses: Mapping[str, Gloss]
    variants: Mapping[str, Variants]
    # Inflected form → lemmas, as the runtime's forms table.
    forms: Mapping[str, frozenset[str]]
    normalize: Normalizer
    # Error tags a card answer may carry.
    tags: frozenset[str]
    # The grammar codes a text uses (S4's tagger); None leaves a grammar
    # card's lists as the pack has them.
    grammar_of: Callable[[str], frozenset[str]] | None = None


@dataclass(frozen=True)
class _Card:
    level: Level
    prompt: Gloss
    reference: str
    listed: Variants | None
    target_lemmas: tuple[str, ...]
    grammar: tuple[str, ...]
    rule_code: str | None


def _card(case: EvalCase, packs: Packs) -> _Card | Issue:
    sentence = None
    if case.sent is not None:
        sentence = packs.sentences.get(f"{packs.l2}.sent.{case.sent}")
        if sentence is None:
            return Issue(id=case.id, kind="unknown_sentence", detail=case.sent)

    def carried(card: str) -> _Card | Issue:
        if sentence is None:
            return Issue(id=case.id, kind="unknown_sentence", detail="a carrier is needed")
        prompt = packs.glosses.get(sentence.key)
        if prompt is None:
            return Issue(id=case.id, kind="unknown_sentence", detail=f"{sentence.key}: no prompt")
        if card in packs.senses:
            if card not in sentence.targets:
                return Issue(
                    id=case.id, kind="not_carried", detail=f"{sentence.key} does not carry {card}"
                )
            lemmas = tuple(packs.senses[card].lemma.lower().split())
            code = None
        else:
            code = packs.points[card].code
            if code not in sentence.grammar:
                return Issue(
                    id=case.id, kind="not_carried", detail=f"{sentence.key} does not carry {code}"
                )
            lemmas = ()
        return _Card(
            level=sentence.level,
            prompt=prompt,
            reference=sentence.text,
            listed=packs.variants.get(sentence.key),
            target_lemmas=lemmas,
            grammar=sentence.grammar,
            rule_code=code,
        )

    if case.card in packs.senses or case.card in packs.points:
        return carried(case.card)
    chunk = packs.chunks.get(case.card)
    if chunk is None:
        return Issue(id=case.id, kind="unknown_card", detail=case.card)
    if sentence is not None:
        return Issue(id=case.id, kind="unknown_sentence", detail="a set phrase has none")
    prompt = packs.glosses.get(chunk.key)
    if prompt is None:
        return Issue(id=case.id, kind="unknown_card", detail=f"{chunk.key}: no prompt")
    return _Card(
        level=chunk.level,
        prompt=prompt,
        reference=chunk.text,
        listed=packs.variants.get(chunk.key),
        target_lemmas=(),
        grammar=(),
        rule_code=None,
    )


def _consistency(case: EvalCase, packs: Packs) -> list[Issue]:
    issues = [
        Issue(id=case.id, kind="unknown_tag", detail=tag)
        for tag in case.tags
        if tag not in packs.tags
    ]
    if case.tags and not _TAGGED & set(case.expect):
        issues.append(Issue(id=case.id, kind="inconsistent", detail="tags without an error"))
    if case.target_ok and set(case.expect) <= _WITHOUT_TARGET:
        issues.append(Issue(id=case.id, kind="inconsistent", detail="target_ok on a miss"))
    if case.target_ok is False and set(case.expect) == {"correct"}:
        issues.append(Issue(id=case.id, kind="inconsistent", detail="correct without target"))
    if case.src == "typed" and (case.conf is not None or "unintelligible" in case.expect):
        issues.append(Issue(id=case.id, kind="inconsistent", detail="typed answers are read"))
    return issues


def _by_target(
    card: _Card, packs: Packs, variants: Sequence[str], alternatives: Sequence[str]
) -> tuple[tuple[str, ...], tuple[str, ...]]:
    """The listed answers that say this card's target, and those that do not.

    A pack lists answers per sentence, for all the items it carries; what
    counts is the card's own target (docs/03 §0.5): a word card's lemmas, a
    grammar card's structure. When the reference itself does not show the
    target, the lists decide, as in the engine.
    """
    lemmas = set(card.target_lemmas)
    grammar_of = packs.grammar_of

    def says(text: str) -> bool:
        if lemmas:
            words = packs.normalize(text).split()
            return lemmas <= {lemma for w in words for lemma in packs.forms.get(w, {w})}
        code = card.rule_code
        return code is not None and grammar_of is not None and code in grammar_of(text)

    decided = bool(lemmas) or (card.rule_code is not None and grammar_of is not None)
    if not decided or not says(card.reference):
        return tuple(variants), tuple(alternatives)
    answers = (*variants, *alternatives)
    return (
        tuple(text for text in answers if says(text)),
        tuple(text for text in answers if not says(text)),
    )


def build_case(case: EvalCase, packs: Packs) -> tuple[dict[str, object] | None, list[Issue]]:
    """The case as the eval and the engine's test read it, or its issues."""
    card = _card(case, packs)
    if isinstance(card, Issue):
        return None, [card]
    issues = _consistency(case, packs)
    listed = card.listed
    variants, alternatives = _by_target(
        card,
        packs,
        listed.variants if listed else (),
        listed.alternatives if listed else (),
    )
    said = packs.normalize(case.say)
    for answer in (card.reference, *variants, *alternatives):
        if packs.normalize(answer) == said:
            issues.append(Issue(id=case.id, kind="matched", detail=answer))
    if issues:
        return None, issues

    words = packs.normalize(card.reference).split()
    target = [w for w in words if packs.forms.get(w, frozenset({w})) & set(card.target_lemmas)]
    texts = (card.reference, *variants, *alternatives, case.say)
    forms = {
        word: sorted(packs.forms[word])
        for text in texts
        for word in packs.normalize(text).split()
        if word in packs.forms
    }
    response: dict[str, object] = {"text": case.say, "source": case.src}
    if case.src == "asr":
        response["asr_confidence"] = case.conf if case.conf is not None else DEFAULT_CONFIDENCE
    item: dict[str, object] = {
        "key": case.card,
        "prompt_l1": card.prompt.meaning,
        "reference_l2": card.reference,
        "variants": list(variants),
        "alternatives": list(alternatives),
        "target_span": " ".join(target) if target else card.reference,
        "grammar_codes": list(card.grammar),
    }
    if card.prompt.context:
        item["context_note"] = card.prompt.context
    row: dict[str, object] = {
        "id": case.id,
        "kind": case.id[0],
        "input": {
            "ctx": {"l1": packs.l1, "l2": packs.l2, "level": card.level, "explain_in": "l1"},
            "item": item,
            "response": response,
            "attempt_no": 1,
            "previous_responses": [],
        },
        "expected": {
            "verdicts": list(case.expect),
            "target_ok": case.target_ok,
            "tags": list(case.tags),
        },
        "fixture": {
            "target_lemmas": list(card.target_lemmas),
            "rule_code": card.rule_code,
            "forms": dict(sorted(forms.items())),
        },
    }
    if case.why:
        row["why"] = case.why
    return row, []


def _checked(case: EvalCase, check: Check | None) -> list[Issue]:
    if check is None:
        return [Issue(id=case.id, kind="unvalidated", detail="no blind check")]
    if check.verdicts[0] not in case.expect:
        return [Issue(id=case.id, kind="disputed", detail=f"checked {check.verdicts[0]}")]
    if case.target_ok is not None and check.target_ok not in ("either", case.target_ok):
        return [Issue(id=case.id, kind="disputed", detail=f"target_ok {check.target_ok}")]
    return []


def build_cases(
    cases: Sequence[EvalCase],
    packs: Packs,
    checks: Mapping[str, Check] | None = None,
) -> tuple[list[dict[str, object]], list[Issue]]:
    """Every case in order, with the issues of those that cannot be used.

    With [checks], a case also needs a blind check that agrees with it.
    """
    rows: list[dict[str, object]] = []
    issues: list[Issue] = []
    seen_ids: set[str] = set()
    seen_answers: set[tuple[str, str | None, str]] = set()
    for case in cases:
        answer = (case.card, case.sent, packs.normalize(case.say))
        if case.id in seen_ids or answer in seen_answers:
            issues.append(Issue(id=case.id, kind="duplicate", detail=case.say))
            continue
        seen_ids.add(case.id)
        seen_answers.add(answer)
        row, found = build_case(case, packs)
        if checks is not None:
            found += _checked(case, checks.get(case.id))
            row = None if found else row
        issues += found
        if row is not None:
            rows.append(row)
    return rows, issues


def _jsonl[T: BaseModel](path: Path, model: type[T]) -> list[T]:
    if not path.is_file():
        raise FileNotFoundError(f"{path} is missing")
    with path.open(encoding="utf-8") as stream:
        return [model.model_validate_json(line) for line in stream if line.strip()]


def read_forms(database: Path) -> dict[str, frozenset[str]]:
    """`content_forms` of a built target pack."""
    if not database.is_file():
        raise FileNotFoundError(f"{database} is missing: run `dilbaz-content build` first")
    found: dict[str, set[str]] = {}
    with sqlite3.connect(database) as connection:
        for form, lemma in connection.execute("select form, lemma from content_forms"):
            found.setdefault(form, set()).add(lemma)
    return {form: frozenset(lemmas) for form, lemmas in found.items()}


def _card_tags(path: Path) -> frozenset[str]:
    rows = (json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line)
    return frozenset(row["code"] for row in rows if row["category"] in CARD_CATEGORIES)


def tagger(analyzer: Analyzer) -> Callable[[str], frozenset[str]]:
    """The grammar codes of a text, as S4 tags sentences, remembered."""
    known: dict[str, frozenset[str]] = {}

    def grammar_of(text: str) -> frozenset[str]:
        if text not in known:
            tokens = next(iter(analyzer.analyze([text])))
            known[text] = frozenset(grammar_codes(tokens))
        return known[text]

    return grammar_of


def load_packs(
    content_dir: Path,
    *,
    l1: str = "tr",
    l2: str = "en",
    grammar_of: Callable[[str], frozenset[str]] | None = None,
) -> Packs:
    """The pack sources and the built pack's forms."""
    target = content_dir / "packs" / l2
    pair = content_dir / "packs" / f"{l1}-{l2}"
    items = target / "items"

    def by_key[T: Sentence | WordSense | Chunk | GrammarPoint | Gloss | Variants](
        rows: Iterable[T],
    ) -> dict[str, T]:
        return {row.key: row for row in rows}

    return Packs(
        l1=l1,
        l2=l2,
        sentences=by_key(_jsonl(items / "sentences.jsonl", Sentence)),
        senses=by_key(_jsonl(items / "word_senses.jsonl", WordSense)),
        chunks=by_key(_jsonl(items / "chunks.jsonl", Chunk)),
        points=by_key(_jsonl(items / "grammar_points.jsonl", GrammarPoint)),
        glosses=by_key(_jsonl(pair / "glosses.jsonl", Gloss)),
        variants=by_key(_jsonl(pair / "variants.jsonl", Variants)),
        forms=read_forms(content_dir / "build" / f"{l2}@1.sqlite"),
        normalize=Normalizer.from_file(target / NORMALIZATION_FILE),
        tags=_card_tags(pair / "error_tags.jsonl"),
        grammar_of=grammar_of,
    )


def read_checks(path: Path) -> dict[str, Check]:
    """The latest check of each case."""
    found: dict[str, Check] = {}
    for check in _jsonl(path, Check):
        if check.id not in found or check.round >= found[check.id].round:
            found[check.id] = check
    return found


def read_cases(path: Path) -> list[EvalCase]:
    data = yaml.safe_load(path.read_text(encoding="utf-8")) or []
    return [EvalCase.model_validate(entry) for entry in data]


def run_eval_cases(content_dir: Path, *, analyzer: Callable[[], Analyzer]) -> EvalReport:
    """Writes `evals/tutor/answer_check/cases.jsonl` when every case is usable."""
    folder = content_dir.parent / CASES_DIR
    cases = read_cases(folder / CASES_SOURCE)
    packs = load_packs(content_dir, grammar_of=tagger(analyzer()))
    rows, issues = build_cases(cases, packs, read_checks(folder / VALIDATION_FILE))
    report = EvalReport(
        cases=len(rows),
        by_kind=dict(sorted(Counter(case.id[0] for case in cases).items())),
        by_verdict=dict(sorted(Counter(case.expect[0] for case in cases).items())),
        issues=tuple(issues),
    )
    if not issues:
        with (folder / CASES_FILE).open("w", encoding="utf-8", newline="\n") as sink:
            for row in rows:
                sink.write(json.dumps(row, ensure_ascii=False) + "\n")
    return report

"""Speaking tasks, chat cards, can-do codes and connectors of a pack (A11,
A14, A23; docs/02-curriculum.md §7-§8, docs/11-language-packs.md §2).

`curation/<l2>/tasks.yaml` holds the tasks in the target language's terms
(goal, phrases), the can-do codes and the connectors;
`curation/<l1>-<l2>/tasks.yaml` holds what the learner reads (title, prompt,
the phrases' meanings, can-do summaries). Chat cards (A14) are tasks of kind
`pair_chat`: a question to talk about with the partner, follow-up questions
and three phrases, with their meanings. Information gap tasks (A15,
ADR-0012) are tasks of kind `pair_info_gap`: each role's lines, the
options of the role that chooses, and the answer key. A task or a summary enters the
packs only when an independent check of its exact texts accepted it
(`curation/<l1>-<l2>/tasks.validation.jsonl`, I-16): a changed text needs a
new check.

Writes `packs/<l2>/tasks.jsonl`, `can_dos.jsonl` and `connectors.jsonl`, and
`packs/<l1>-<l2>/task_instructions.jsonl` and `can_do_summaries.jsonl`.
"""

from __future__ import annotations

import json
from collections.abc import Iterable, Mapping
from pathlib import Path
from typing import Literal

import yaml
from pydantic import BaseModel, ConfigDict, Field

from dilbaz_content.items import Level, Provenance, level_index

TASKS_CURATION = "tasks.yaml"
TASKS_VALIDATION = "tasks.validation.jsonl"
TASKS_FILE = "tasks.jsonl"
CAN_DOS_FILE = "can_dos.jsonl"
CONNECTORS_FILE = "connectors.jsonl"
INSTRUCTIONS_FILE = "task_instructions.jsonl"
SUMMARIES_FILE = "can_do_summaries.jsonl"
REPORT_FILE = "tasks.{l2}.report.json"
_PROVENANCE = Provenance(source="dilbaz curation", license="own")
# Phrases shown with a task (docs/02 §3: "3 kalıp"); anchors have none.
PHRASES = 3
# Follow-up questions of a chat card (A14).
FOLLOW_UPS = (2, 3)
# Lines of each role in a "differences" task, and how many differ (A15).
DIFFERENCE_LINES = 6
DIFFERENCES = 3
# Options of the role that chooses (A15).
OPTIONS = 4

IssueKind = Literal[
    "unvalidated",
    "rejected",
    "missing_instruction",
    "phrases",
    "unknown_can_do",
    "duplicate",
]


class TasksError(Exception):
    """The task curation is broken."""


class TaskDraft(BaseModel):
    """One task of `curation/<l2>/tasks.yaml`."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    id: str = Field(pattern=r"^[a-z0-9_]+$")
    # ANC-1…3: a fixed task of the monthly test (docs/06 §3.1).
    anchor: str | None = Field(default=None, pattern=r"^ANC-[0-9]+$")
    level: Level
    can_do: tuple[str, ...] = Field(min_length=1)
    goal: str = Field(min_length=1)
    phrases: tuple[str, ...] = ()


class CanDo(BaseModel):
    """A can-do code: its level and the Companion Volume scale."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    code: str = Field(pattern=r"^cd\.[a-z_]+\.[a-c][0-2]$")
    level: Level
    scale: str = Field(min_length=1)


class Connector(BaseModel):
    """A connector counted by `connector_types` (docs/06 §3.3)."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    text: str = Field(min_length=1)
    level: Level


class ChatCardDraft(BaseModel):
    """A chat card (A14): what the partners talk about, in the target language."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    id: str = Field(pattern=r"^[a-z0-9_]+$")
    level: Level
    question: str = Field(min_length=1)
    follow_ups: tuple[str, ...]
    phrases: tuple[str, ...]


class GapOption(BaseModel):
    """One option of the role that chooses."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    id: str = Field(pattern=r"^[a-z0-9_]+$")
    text: str = Field(min_length=1)


class GapRole(BaseModel):
    """What one role of an information gap task sees, in the target language."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    lines: tuple[str, ...] = ()
    options: tuple[GapOption, ...] = ()


class GapAnswer(BaseModel):
    """The answer key: the option the chooser must pick, or each role's
    lines that differ."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    chooser: Literal["a", "b"] | None = None
    option: str | None = None
    a: tuple[int, ...] = ()
    b: tuple[int, ...] = ()


class InfoGapDraft(BaseModel):
    """An information gap task (A15, ADR-0012)."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    id: str = Field(pattern=r"^[a-z0-9_]+$")
    level: Level
    # choose: one role describes, the other picks one of its options (also
    # "plan": a timetable on one side, the constraints on the other);
    # differences: each role marks its lines that differ.
    type: Literal["choose", "differences"]
    # What doing the task means, for the speaking annotation (docs/07 §4.2).
    goal: str = Field(min_length=1)
    a: GapRole
    b: GapRole
    answer: GapAnswer


class TasksCuration(BaseModel):
    """`curation/<l2>/tasks.yaml`."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    tasks: tuple[TaskDraft, ...] = Field(min_length=1)
    chat_cards: tuple[ChatCardDraft, ...] = ()
    info_gaps: tuple[InfoGapDraft, ...] = ()
    can_dos: tuple[CanDo, ...] = Field(min_length=1)
    connectors: tuple[Connector, ...] = Field(min_length=1)


class Instruction(BaseModel):
    """What the learner reads for a task."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    id: str
    title: str = Field(min_length=1)
    prompt: str = Field(min_length=1)
    phrases: tuple[str, ...] = ()


class CanDoSummary(BaseModel):
    """Our own short summary of a can-do code."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    code: str
    summary: str = Field(min_length=1)


class ChatInstruction(BaseModel):
    """What a chat card means in the learner's language."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    id: str
    title: str = Field(min_length=1)
    question: str = Field(min_length=1)
    follow_ups: tuple[str, ...]
    phrases: tuple[str, ...]


class GapInstruction(BaseModel):
    """What an information gap task says in the learner's language."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    id: str
    title: str = Field(min_length=1)
    prompt: str = Field(min_length=1)
    a: str = Field(min_length=1)
    b: str = Field(min_length=1)


class PairTasksCuration(BaseModel):
    """`curation/<l1>-<l2>/tasks.yaml`."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    instructions: tuple[Instruction, ...]
    can_do_summaries: tuple[CanDoSummary, ...]
    chat_instructions: tuple[ChatInstruction, ...] = ()
    gap_instructions: tuple[GapInstruction, ...] = ()


class TaskCheck(BaseModel):
    """`tasks.validation.jsonl`: one independent check, as it was made."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    # A task id or a can-do code.
    id: str
    round: int = Field(ge=1)
    # Exactly the texts that were checked.
    texts: dict[str, str | list[str]]
    # The learner's language reads clearly and naturally.
    clear: bool
    # Both languages say the same.
    faithful: bool
    # The target language is correct and natural.
    correct: bool
    # It fits its level.
    level_ok: bool
    notes: str = ""

    @property
    def accepted(self) -> bool:
        """Whether the check carries the texts it saw."""
        return self.clear and self.faithful and self.correct and self.level_ok


class Issue(BaseModel):
    """Why a task or a summary stays out of the packs."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    id: str
    kind: IssueKind
    detail: str


class TasksReport(BaseModel):
    """`work/tasks.<l2>.report.json`."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    tasks_by_level: dict[str, int]
    chat_cards_by_level: dict[str, int] = Field(default_factory=dict)
    info_gaps_by_level: dict[str, int] = Field(default_factory=dict)
    anchors: tuple[str, ...]
    can_dos: int
    connectors: int
    issues: tuple[Issue, ...]


def task_texts(task: TaskDraft, instruction: Instruction) -> dict[str, str | list[str]]:
    """What a check of [task] must have seen."""
    return {
        "goal": task.goal,
        "phrases": list(task.phrases),
        "title": instruction.title,
        "prompt": instruction.prompt,
        "phrase_meanings": list(instruction.phrases),
    }


def chat_texts(card: ChatCardDraft, instruction: ChatInstruction) -> dict[str, str | list[str]]:
    """What a check of a chat card must have seen."""
    return {
        "question": card.question,
        "follow_ups": list(card.follow_ups),
        "phrases": list(card.phrases),
        "title": instruction.title,
        "question_meaning": instruction.question,
        "follow_up_meanings": list(instruction.follow_ups),
        "phrase_meanings": list(instruction.phrases),
    }


def chat_issues(
    curation: TasksCuration,
    pair: PairTasksCuration,
    checks: Mapping[str, TaskCheck],
) -> list[Issue]:
    """What keeps chat cards out of the packs."""
    issues: list[Issue] = []
    ids = [task.id for task in curation.tasks] + [card.id for card in curation.chat_cards]
    instructions = {instruction.id: instruction for instruction in pair.chat_instructions}
    low, high = FOLLOW_UPS
    for card in curation.chat_cards:
        instruction = instructions.get(card.id)
        found: Issue | None = None
        if ids.count(card.id) > 1:
            found = Issue(id=card.id, kind="duplicate", detail="the id is used twice")
        elif not low <= len(card.follow_ups) <= high or len(card.phrases) != PHRASES:
            found = Issue(
                id=card.id,
                kind="phrases",
                detail=f"{len(card.follow_ups)} follow-ups and {len(card.phrases)} phrases",
            )
        elif instruction is None:
            found = Issue(id=card.id, kind="missing_instruction", detail="no instruction")
        elif len(instruction.follow_ups) != len(card.follow_ups) or len(instruction.phrases) != len(
            card.phrases
        ):
            found = Issue(id=card.id, kind="phrases", detail="the meanings do not match")
        else:
            found = _check_issue(card.id, checks.get(card.id), chat_texts(card, instruction))
        if found is not None:
            issues.append(found)
    return issues


def gap_texts(task: InfoGapDraft, instruction: GapInstruction) -> dict[str, str | list[str]]:
    """What a check of an information gap task must have seen."""

    def role(r: GapRole) -> list[str]:
        return [*r.lines, *(f"{o.id}: {o.text}" for o in r.options)]

    answer = (
        [f"{task.answer.chooser} picks {task.answer.option}"]
        if task.type == "choose"
        else [f"a: {list(task.answer.a)}", f"b: {list(task.answer.b)}"]
    )
    return {
        "type": task.type,
        "goal": task.goal,
        "a": role(task.a),
        "b": role(task.b),
        "answer": answer,
        "title": instruction.title,
        "prompt": instruction.prompt,
        "a_instruction": instruction.a,
        "b_instruction": instruction.b,
    }


def _gap_shape(task: InfoGapDraft) -> str | None:
    """Why [task]'s roles and key do not fit its type; None when they do."""
    answer = task.answer
    if task.type == "choose":
        chooser = task.a if answer.chooser == "a" else task.b if answer.chooser == "b" else None
        other = task.b if answer.chooser == "a" else task.a
        if chooser is None or len(chooser.options) != OPTIONS or other.options:
            return f"the chooser needs {OPTIONS} options, the other role none"
        if not other.lines:
            return "the role that is asked needs lines"
        if answer.option not in {o.id for o in chooser.options}:
            return "the answer is not one of the options"
        return None
    if task.a.options or task.b.options or answer.chooser or answer.option:
        return "a differences task has no options"
    for name, role, marked in (("a", task.a, answer.a), ("b", task.b, answer.b)):
        if len(role.lines) != DIFFERENCE_LINES:
            return f"role {name} needs {DIFFERENCE_LINES} lines"
        if len(set(marked)) != DIFFERENCES or any(not 0 <= i < DIFFERENCE_LINES for i in marked):
            return f"role {name} needs {DIFFERENCES} differing lines"
    return None


def gap_issues(
    curation: TasksCuration,
    pair: PairTasksCuration,
    checks: Mapping[str, TaskCheck],
) -> list[Issue]:
    """What keeps information gap tasks out of the packs."""
    issues: list[Issue] = []
    ids = (
        [task.id for task in curation.tasks]
        + [card.id for card in curation.chat_cards]
        + [task.id for task in curation.info_gaps]
    )
    instructions = {instruction.id: instruction for instruction in pair.gap_instructions}
    for task in curation.info_gaps:
        instruction = instructions.get(task.id)
        shape = _gap_shape(task)
        found: Issue | None = None
        if ids.count(task.id) > 1:
            found = Issue(id=task.id, kind="duplicate", detail="the id is used twice")
        elif shape is not None:
            found = Issue(id=task.id, kind="phrases", detail=shape)
        elif instruction is None:
            found = Issue(id=task.id, kind="missing_instruction", detail="no instruction")
        else:
            found = _check_issue(task.id, checks.get(task.id), gap_texts(task, instruction))
        if found is not None:
            issues.append(found)
    return issues


def summary_texts(can_do: CanDo, summary: CanDoSummary) -> dict[str, str | list[str]]:
    """What a check of a can-do summary must have seen."""
    return {"scale": can_do.scale, "level": can_do.level, "summary": summary.summary}


def read_checks(path: Path) -> dict[str, TaskCheck]:
    """The latest check of each id; a missing file means none."""
    if not path.is_file():
        return {}
    checks: dict[str, TaskCheck] = {}
    with path.open(encoding="utf-8") as stream:
        for line in stream:
            if line.strip():
                check = TaskCheck.model_validate_json(line)
                checks[check.id] = check
    return checks


def _check_issue(
    key: str, check: TaskCheck | None, texts: Mapping[str, str | list[str]]
) -> Issue | None:
    if check is None or check.texts != dict(texts):
        return Issue(id=key, kind="unvalidated", detail="no check of these exact texts")
    if not check.accepted:
        return Issue(id=key, kind="rejected", detail=check.notes or "the check found a problem")
    return None


def task_issues(
    curation: TasksCuration,
    pair: PairTasksCuration,
    checks: Mapping[str, TaskCheck],
) -> list[Issue]:
    """What keeps tasks and summaries out of the packs."""
    issues: list[Issue] = []
    ids = [task.id for task in curation.tasks]
    anchors = [task.anchor for task in curation.tasks if task.anchor]
    codes = {can_do.code for can_do in curation.can_dos}
    instructions = {instruction.id: instruction for instruction in pair.instructions}
    for task in curation.tasks:
        found: Issue | None = None
        unknown = [code for code in task.can_do if code not in codes]
        wanted = 0 if task.anchor else PHRASES
        instruction = instructions.get(task.id)
        if ids.count(task.id) > 1:
            found = Issue(id=task.id, kind="duplicate", detail="the id is used twice")
        elif task.anchor and anchors.count(task.anchor) > 1:
            found = Issue(id=task.id, kind="duplicate", detail=f"another task is {task.anchor}")
        elif unknown:
            found = Issue(id=task.id, kind="unknown_can_do", detail=", ".join(unknown))
        elif len(task.phrases) != wanted:
            found = Issue(
                id=task.id, kind="phrases", detail=f"{len(task.phrases)} phrases, not {wanted}"
            )
        elif instruction is None:
            found = Issue(id=task.id, kind="missing_instruction", detail="no instruction")
        elif len(instruction.phrases) != len(task.phrases):
            found = Issue(
                id=task.id, kind="phrases", detail="the meanings do not match the phrases"
            )
        else:
            found = _check_issue(task.id, checks.get(task.id), task_texts(task, instruction))
        if found is not None:
            issues.append(found)

    summaries = {summary.code: summary for summary in pair.can_do_summaries}
    for can_do in curation.can_dos:
        summary = summaries.get(can_do.code)
        if summary is None:
            issues.append(Issue(id=can_do.code, kind="missing_instruction", detail="no summary"))
            continue
        found = _check_issue(can_do.code, checks.get(can_do.code), summary_texts(can_do, summary))
        if found is not None:
            issues.append(found)
    return issues


def _write(path: Path, *groups: Iterable[Mapping[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as stream:
        for rows in groups:
            for row in rows:
                stream.write(json.dumps(row, ensure_ascii=False) + "\n")


def load_curation(path: Path) -> TasksCuration:
    """`curation/<l2>/tasks.yaml`."""
    return TasksCuration.model_validate(yaml.safe_load(path.read_text(encoding="utf-8")))


def load_pair_curation(path: Path) -> PairTasksCuration:
    """`curation/<l1>-<l2>/tasks.yaml`."""
    return PairTasksCuration.model_validate(yaml.safe_load(path.read_text(encoding="utf-8")))


def run_tasks(content_dir: Path, *, l1: str, l2: str) -> TasksReport:
    """Writes the task files of both packs from the checked curation."""
    curation = load_curation(content_dir / "curation" / l2 / TASKS_CURATION)
    pair_dir = content_dir / "curation" / f"{l1}-{l2}"
    pair = load_pair_curation(pair_dir / TASKS_CURATION)
    checks = read_checks(pair_dir / TASKS_VALIDATION)
    issues = (
        task_issues(curation, pair, checks)
        + chat_issues(curation, pair, checks)
        + gap_issues(curation, pair, checks)
    )
    out = {issue.id for issue in issues}
    tasks = [task for task in curation.tasks if task.id not in out]
    chats = [card for card in curation.chat_cards if card.id not in out]
    chatted = {card.id for card in chats}
    gaps = [task for task in curation.info_gaps if task.id not in out]
    gapped = {task.id for task in gaps}
    can_dos = [can_do for can_do in curation.can_dos if can_do.code not in out]
    kept = {task.id for task in tasks} | {can_do.code for can_do in can_dos}
    provenance = _PROVENANCE.model_dump(exclude_none=True)

    packs = content_dir / "packs"
    _write(
        packs / l2 / TASKS_FILE,
        (
            {
                "key": f"{l2}.task.{task.id}",
                "kind": "speaking",
                "level": task.level,
                "anchor": task.anchor,
                "can_do": list(task.can_do),
                "goal": task.goal,
                "phrases": list(task.phrases),
                "provenance": provenance,
            }
            for task in tasks
        ),
        (
            {
                "key": f"{l2}.chat.{card.id}",
                "kind": "pair_chat",
                "level": card.level,
                "question": card.question,
                "follow_ups": list(card.follow_ups),
                "phrases": list(card.phrases),
                "provenance": provenance,
            }
            for card in chats
        ),
        (
            {
                "key": f"{l2}.gap.{task.id}",
                "kind": "pair_info_gap",
                "level": task.level,
                "type": task.type,
                "goal": task.goal,
                "roles": {
                    "a": task.a.model_dump(mode="json"),
                    "b": task.b.model_dump(mode="json"),
                },
                "answer": task.answer.model_dump(mode="json", exclude_defaults=True),
                "provenance": provenance,
            }
            for task in gaps
        ),
    )
    _write(packs / l2 / CAN_DOS_FILE, (can_do.model_dump() for can_do in can_dos))
    _write(
        packs / l2 / CONNECTORS_FILE,
        (
            connector.model_dump()
            for connector in sorted(
                curation.connectors, key=lambda c: (level_index(c.level), c.text)
            )
        ),
    )
    _write(
        packs / f"{l1}-{l2}" / INSTRUCTIONS_FILE,
        (
            {
                "key": f"{l2}.task.{instruction.id}",
                "title": instruction.title,
                "prompt": instruction.prompt,
                "phrases": list(instruction.phrases),
                "provenance": provenance,
            }
            for instruction in pair.instructions
            if instruction.id in kept
        ),
        (
            {
                "key": f"{l2}.chat.{instruction.id}",
                "title": instruction.title,
                "prompt": instruction.question,
                "follow_ups": list(instruction.follow_ups),
                "phrases": list(instruction.phrases),
                "provenance": provenance,
            }
            for instruction in pair.chat_instructions
            if instruction.id in chatted
        ),
        (
            {
                "key": f"{l2}.gap.{instruction.id}",
                "title": instruction.title,
                "prompt": instruction.prompt,
                "roles": {"a": instruction.a, "b": instruction.b},
                "provenance": provenance,
            }
            for instruction in pair.gap_instructions
            if instruction.id in gapped
        ),
    )
    _write(
        packs / f"{l1}-{l2}" / SUMMARIES_FILE,
        (
            {"code": summary.code, "summary": summary.summary, "provenance": provenance}
            for summary in pair.can_do_summaries
            if summary.code in kept
        ),
    )

    by_level: dict[str, int] = {}
    for task in tasks:
        if not task.anchor:
            by_level[task.level] = by_level.get(task.level, 0) + 1
    chats_by_level: dict[str, int] = {}
    for card in chats:
        chats_by_level[card.level] = chats_by_level.get(card.level, 0) + 1
    gaps_by_level: dict[str, int] = {}
    for gap in gaps:
        gaps_by_level[gap.level] = gaps_by_level.get(gap.level, 0) + 1
    report = TasksReport(
        tasks_by_level=dict(sorted(by_level.items())),
        info_gaps_by_level=dict(sorted(gaps_by_level.items())),
        chat_cards_by_level=dict(sorted(chats_by_level.items())),
        anchors=tuple(sorted(task.anchor for task in tasks if task.anchor)),
        can_dos=len(can_dos),
        connectors=len(curation.connectors),
        issues=tuple(issues),
    )
    work = content_dir / "work"
    work.mkdir(parents=True, exist_ok=True)
    (work / REPORT_FILE.format(l2=l2)).write_text(
        report.model_dump_json(indent=2) + "\n", encoding="utf-8"
    )
    return report

import json
from pathlib import Path

import pytest
import yaml
from typer.testing import CliRunner

from dilbaz_content.cli import app
from dilbaz_content.tasks_step import (
    CAN_DOS_FILE,
    CONNECTORS_FILE,
    INSTRUCTIONS_FILE,
    SUMMARIES_FILE,
    TASKS_CURATION,
    TASKS_FILE,
    TASKS_VALIDATION,
    CanDo,
    CanDoSummary,
    Instruction,
    TaskCheck,
    TaskDraft,
    run_tasks,
    summary_texts,
    task_texts,
)

ANCHOR = {
    "id": "anc_1",
    "anchor": "ANC-1",
    "level": "A1",
    "can_do": ["cd.describe_experience.a1"],
    "goal": "Introduce yourself.",
    "phrases": [],
}
ROUTINE = {
    "id": "daily_routine",
    "level": "A1",
    "can_do": ["cd.describe_experience.a1"],
    "goal": "Describe a usual day.",
    "phrases": ["I usually get up at ...", "After that, I ...", "In the evening, I ..."],
}
CAN_DO = {"code": "cd.describe_experience.a1", "level": "A1", "scale": "describing_experience"}


def write_curation(
    root: Path,
    tasks: list[dict[str, object]],
    instructions: list[dict[str, object]],
    checked: list[str] | None = None,
    *,
    reject: str | None = None,
) -> None:
    en = root / "curation" / "en"
    pair = root / "curation" / "tr-en"
    en.mkdir(parents=True, exist_ok=True)
    pair.mkdir(parents=True, exist_ok=True)
    (en / TASKS_CURATION).write_text(
        yaml.safe_dump(
            {
                "tasks": tasks,
                "can_dos": [CAN_DO],
                "connectors": [
                    {"text": "because", "level": "A1"},
                    {"text": "after that", "level": "A2"},
                    {"text": "and", "level": "A1"},
                ],
            },
            allow_unicode=True,
        ),
        encoding="utf-8",
    )
    summary = {"code": CAN_DO["code"], "summary": "Kendini basit cümlelerle anlatabilirsin."}
    (pair / TASKS_CURATION).write_text(
        yaml.safe_dump(
            {"instructions": instructions, "can_do_summaries": [summary]}, allow_unicode=True
        ),
        encoding="utf-8",
    )
    by_id = {str(i["id"]): Instruction.model_validate(i) for i in instructions}
    checks = []
    for task in tasks:
        if checked is not None and task["id"] not in checked:
            continue
        draft = TaskDraft.model_validate(task)
        checks.append(
            TaskCheck(
                id=draft.id,
                round=1,
                texts=task_texts(draft, by_id[draft.id]),
                clear=True,
                faithful=draft.id != reject,
                correct=True,
                level_ok=True,
                notes="the goal asks for more" if draft.id == reject else "",
            )
        )
    checks.append(
        TaskCheck(
            id=CAN_DO["code"],
            round=1,
            texts=summary_texts(CanDo.model_validate(CAN_DO), CanDoSummary.model_validate(summary)),
            clear=True,
            faithful=True,
            correct=True,
            level_ok=True,
        )
    )
    (pair / TASKS_VALIDATION).write_text(
        "".join(check.model_dump_json() + "\n" for check in checks), encoding="utf-8"
    )


def lines(path: Path) -> list[dict]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()]


INSTRUCTIONS = [
    {"id": "anc_1", "title": "Kendini tanıt", "prompt": "Kendini tanıt.", "phrases": []},
    {
        "id": "daily_routine",
        "title": "Sıradan bir gün",
        "prompt": "Sıradan bir gününü anlat.",
        "phrases": ["Genelde saat ...'te kalkarım.", "Ondan sonra ...", "Akşamları ..."],
    },
]


def test_checked_tasks_go_to_both_packs(tmp_path: Path) -> None:
    write_curation(tmp_path, [ANCHOR, ROUTINE], INSTRUCTIONS)

    report = run_tasks(tmp_path, l1="tr", l2="en")

    assert report.issues == ()
    assert report.tasks_by_level == {"A1": 1}
    assert report.anchors == ("ANC-1",)
    tasks = lines(tmp_path / "packs" / "en" / TASKS_FILE)
    assert [t["key"] for t in tasks] == ["en.task.anc_1", "en.task.daily_routine"]
    assert tasks[1] == {
        "key": "en.task.daily_routine",
        "kind": "speaking",
        "level": "A1",
        "anchor": None,
        "can_do": ["cd.describe_experience.a1"],
        "goal": "Describe a usual day.",
        "phrases": ROUTINE["phrases"],
        "provenance": {"source": "dilbaz curation", "license": "own"},
    }
    assert lines(tmp_path / "packs" / "en" / CAN_DOS_FILE) == [CAN_DO]
    # Connectors by level, then alphabetically.
    assert [c["text"] for c in lines(tmp_path / "packs" / "en" / CONNECTORS_FILE)] == [
        "and",
        "because",
        "after that",
    ]
    instructions = lines(tmp_path / "packs" / "tr-en" / INSTRUCTIONS_FILE)
    assert instructions[1]["key"] == "en.task.daily_routine"
    assert instructions[1]["phrases"][0] == "Genelde saat ...'te kalkarım."
    summaries = lines(tmp_path / "packs" / "tr-en" / SUMMARIES_FILE)
    assert summaries[0]["code"] == "cd.describe_experience.a1"
    assert (tmp_path / "work" / "tasks.en.report.json").is_file()


def test_a_task_without_an_accepted_check_of_its_texts_stays_out(tmp_path: Path) -> None:
    changed = INSTRUCTIONS[1] | {"prompt": "Bir gününü anlat."}
    write_curation(tmp_path, [ANCHOR, ROUTINE], INSTRUCTIONS, reject="anc_1")
    # The prompt changes after the check.
    pair = tmp_path / "curation" / "tr-en" / TASKS_CURATION
    data = yaml.safe_load(pair.read_text(encoding="utf-8"))
    data["instructions"][1] = changed
    pair.write_text(yaml.safe_dump(data, allow_unicode=True), encoding="utf-8")

    report = run_tasks(tmp_path, l1="tr", l2="en")

    assert {(i.id, i.kind) for i in report.issues} == {
        ("anc_1", "rejected"),
        ("daily_routine", "unvalidated"),
    }
    assert lines(tmp_path / "packs" / "en" / TASKS_FILE) == []
    assert lines(tmp_path / "packs" / "tr-en" / INSTRUCTIONS_FILE) == []


@pytest.mark.parametrize(
    ("task", "instructions", "kind"),
    [
        (ROUTINE | {"phrases": ROUTINE["phrases"][:2]}, INSTRUCTIONS, "phrases"),
        (ANCHOR | {"phrases": ["Hello."]}, INSTRUCTIONS, "phrases"),
        (ROUTINE | {"can_do": ["cd.unknown.a1"]}, INSTRUCTIONS, "unknown_can_do"),
        (ROUTINE, INSTRUCTIONS[:1], "missing_instruction"),
        (
            ROUTINE,
            [INSTRUCTIONS[0], INSTRUCTIONS[1] | {"phrases": ["Ondan sonra ..."]}],
            "phrases",
        ),
    ],
)
def test_broken_tasks_are_reported(
    tmp_path: Path,
    task: dict[str, object],
    instructions: list[dict[str, object]],
    kind: str,
) -> None:
    write_curation(tmp_path, [task], instructions, checked=[])

    report = run_tasks(tmp_path, l1="tr", l2="en")

    assert [i.kind for i in report.issues] == [kind]


def test_ids_and_anchors_are_used_once(tmp_path: Path) -> None:
    other = ANCHOR | {"id": "anc_other"}
    write_curation(
        tmp_path,
        [ANCHOR, ANCHOR, other],
        [*INSTRUCTIONS, INSTRUCTIONS[0] | {"id": "anc_other"}],
    )

    report = run_tasks(tmp_path, l1="tr", l2="en")

    assert {(i.id, i.kind) for i in report.issues} == {
        ("anc_1", "duplicate"),
        ("anc_other", "duplicate"),
    }
    assert lines(tmp_path / "packs" / "en" / TASKS_FILE) == []


def test_the_tasks_command_reports_and_fails_on_issues(tmp_path: Path) -> None:
    write_curation(tmp_path, [ANCHOR, ROUTINE], INSTRUCTIONS)
    runner = CliRunner()

    done = runner.invoke(app, ["tasks", "--content-dir", str(tmp_path)])
    assert done.exit_code == 0, done.output
    assert "anchors ANC-1" in done.output

    write_curation(tmp_path, [ANCHOR, ROUTINE], INSTRUCTIONS, checked=["anc_1"])
    failed = runner.invoke(app, ["tasks", "--content-dir", str(tmp_path)])
    assert failed.exit_code == 1
    assert "unvalidated" in failed.output

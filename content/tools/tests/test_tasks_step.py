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
    ChatCardDraft,
    ChatInstruction,
    GapInstruction,
    InfoGapDraft,
    Instruction,
    TaskCheck,
    TaskDraft,
    chat_texts,
    gap_texts,
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


# --- Chat cards (A14) ---------------------------------------------------------

FOOD = {
    "id": "chat_food",
    "level": "A1",
    "question": "What is your favorite food?",
    "follow_ups": ["Who cooks it best?", "When do you eat it?"],
    "phrases": ["My favorite food is ...", "I eat it when ...", "I don't like ..."],
}
FOOD_TR = {
    "id": "chat_food",
    "title": "En sevdiğin yemek",
    "question": "En sevdiğin yemek ne?",
    "follow_ups": ["Onu en iyi kim yapar?", "Onu ne zaman yersin?"],
    "phrases": ["En sevdiğim yemek ...", "Onu ... zaman yerim.", "... sevmem."],
}


def add_chats(
    root: Path,
    cards: list[dict[str, object]],
    meanings: list[dict[str, object]],
    checked: list[str],
) -> None:
    """Adds chat cards to a curation made by `write_curation`."""
    en = root / "curation" / "en" / TASKS_CURATION
    data = yaml.safe_load(en.read_text(encoding="utf-8"))
    data["chat_cards"] = cards
    en.write_text(yaml.safe_dump(data, allow_unicode=True), encoding="utf-8")
    pair = root / "curation" / "tr-en" / TASKS_CURATION
    data = yaml.safe_load(pair.read_text(encoding="utf-8"))
    data["chat_instructions"] = meanings
    pair.write_text(yaml.safe_dump(data, allow_unicode=True), encoding="utf-8")
    by_id = {str(m["id"]): ChatInstruction.model_validate(m) for m in meanings}
    validation = root / "curation" / "tr-en" / TASKS_VALIDATION
    with validation.open("a", encoding="utf-8") as stream:
        for card in cards:
            draft = ChatCardDraft.model_validate(card)
            if draft.id not in checked or draft.id not in by_id:
                continue
            check = TaskCheck(
                id=draft.id,
                round=1,
                texts=chat_texts(draft, by_id[draft.id]),
                clear=True,
                faithful=True,
                correct=True,
                level_ok=True,
            )
            stream.write(check.model_dump_json() + "\n")


def test_checked_chat_cards_go_to_both_packs(tmp_path: Path) -> None:
    write_curation(tmp_path, [ANCHOR, ROUTINE], INSTRUCTIONS)
    add_chats(tmp_path, [FOOD], [FOOD_TR], ["chat_food"])

    report = run_tasks(tmp_path, l1="tr", l2="en")

    assert report.issues == ()
    assert report.chat_cards_by_level == {"A1": 1}
    tasks = lines(tmp_path / "packs" / "en" / TASKS_FILE)
    assert tasks[-1] == {
        "key": "en.chat.chat_food",
        "kind": "pair_chat",
        "level": "A1",
        "question": FOOD["question"],
        "follow_ups": FOOD["follow_ups"],
        "phrases": FOOD["phrases"],
        "provenance": {"source": "dilbaz curation", "license": "own"},
    }
    instruction = lines(tmp_path / "packs" / "tr-en" / INSTRUCTIONS_FILE)[-1]
    assert instruction == {
        "key": "en.chat.chat_food",
        "title": FOOD_TR["title"],
        "prompt": FOOD_TR["question"],
        "follow_ups": FOOD_TR["follow_ups"],
        "phrases": FOOD_TR["phrases"],
        "provenance": {"source": "dilbaz curation", "license": "own"},
    }


def test_unchecked_or_broken_chat_cards_stay_out(tmp_path: Path) -> None:
    write_curation(tmp_path, [ANCHOR, ROUTINE], INSTRUCTIONS)
    one_follow_up = FOOD | {"id": "chat_one", "follow_ups": ["Why?"]}
    unchecked = FOOD | {"id": "chat_new"}
    no_meaning = FOOD | {"id": "chat_alone"}
    short = FOOD_TR | {"id": "chat_short", "phrases": ["En sevdiğim yemek ..."]}
    add_chats(
        tmp_path,
        [one_follow_up, unchecked, no_meaning, FOOD | {"id": "chat_short"}, ROUTINE_AS_CHAT],
        [
            FOOD_TR | {"id": "chat_one", "follow_ups": ["Neden?"]},
            FOOD_TR | {"id": "chat_new"},
            short,
            FOOD_TR | {"id": "daily_routine"},
        ],
        ["chat_one", "chat_short"],
    )

    report = run_tasks(tmp_path, l1="tr", l2="en")

    kinds = {issue.id: issue.kind for issue in report.issues}
    assert kinds == {
        "chat_one": "phrases",
        "chat_new": "unvalidated",
        "chat_alone": "missing_instruction",
        "chat_short": "phrases",
        "daily_routine": "duplicate",
    }
    tasks = lines(tmp_path / "packs" / "en" / TASKS_FILE)
    assert not [t for t in tasks if t["kind"] == "pair_chat"]
    assert (
        json.loads((tmp_path / "work" / "tasks.en.report.json").read_text())["chat_cards_by_level"]
        == {}
    )


# A chat card whose id is a task's.
ROUTINE_AS_CHAT = FOOD | {"id": "daily_routine"}


# --- Information gaps (A15) ----------------------------------------------------

FRIEND = {
    "id": "gap_friend",
    "level": "A1",
    "type": "choose",
    "goal": "Find the friend.",
    "a": {"lines": ["She has short hair.", "She wears glasses."]},
    "b": {
        "options": [
            {"id": "a", "text": "Long hair."},
            {"id": "b", "text": "Short hair, glasses."},
            {"id": "c", "text": "Short hair."},
            {"id": "d", "text": "Glasses."},
        ]
    },
    "answer": {"chooser": "b", "option": "b"},
}
FRIEND_TR = {
    "id": "gap_friend",
    "title": "Arkadaşımı bul",
    "prompt": "Arkadaşı bulun.",
    "a": "Arkadaşını anlat.",
    "b": "Doğru kişiyi seç.",
}
ROOM_LINES = [f"Line {i}." for i in range(6)]
DIFF = {
    "id": "gap_room",
    "level": "A1",
    "type": "differences",
    "goal": "Find the differences.",
    "a": {"lines": ROOM_LINES},
    "b": {"lines": [*ROOM_LINES[:3], "Other 3.", "Other 4.", "Other 5."]},
    "answer": {"a": [3, 4, 5], "b": [3, 4, 5]},
}
DIFF_TR = FRIEND_TR | {"id": "gap_room", "title": "Farklar"}


def add_gaps(
    root: Path,
    gaps: list[dict[str, object]],
    meanings: list[dict[str, object]],
    checked: list[str],
) -> None:
    """Adds information gap tasks to a curation made by `write_curation`."""
    en = root / "curation" / "en" / TASKS_CURATION
    data = yaml.safe_load(en.read_text(encoding="utf-8"))
    data["info_gaps"] = gaps
    en.write_text(yaml.safe_dump(data, allow_unicode=True), encoding="utf-8")
    pair = root / "curation" / "tr-en" / TASKS_CURATION
    data = yaml.safe_load(pair.read_text(encoding="utf-8"))
    data["gap_instructions"] = meanings
    pair.write_text(yaml.safe_dump(data, allow_unicode=True), encoding="utf-8")
    by_id = {str(m["id"]): GapInstruction.model_validate(m) for m in meanings}
    with (root / "curation" / "tr-en" / TASKS_VALIDATION).open("a", encoding="utf-8") as stream:
        for gap in gaps:
            draft = InfoGapDraft.model_validate(gap)
            if draft.id not in checked or draft.id not in by_id:
                continue
            check = TaskCheck(
                id=draft.id,
                round=1,
                texts=gap_texts(draft, by_id[draft.id]),
                clear=True,
                faithful=True,
                correct=True,
                level_ok=True,
            )
            stream.write(check.model_dump_json() + "\n")


def test_checked_information_gaps_go_to_both_packs(tmp_path: Path) -> None:
    write_curation(tmp_path, [ANCHOR, ROUTINE], INSTRUCTIONS)
    add_gaps(tmp_path, [FRIEND, DIFF], [FRIEND_TR, DIFF_TR], ["gap_friend", "gap_room"])

    report = run_tasks(tmp_path, l1="tr", l2="en")

    assert report.issues == ()
    assert report.info_gaps_by_level == {"A1": 2}
    tasks = {t["key"]: t for t in lines(tmp_path / "packs" / "en" / TASKS_FILE)}
    friend = tasks["en.gap.gap_friend"]
    assert friend["kind"] == "pair_info_gap"
    assert friend["type"] == "choose"
    assert friend["roles"]["a"] == {"lines": FRIEND["a"]["lines"], "options": []}
    assert friend["answer"] == {"chooser": "b", "option": "b"}
    assert tasks["en.gap.gap_room"]["answer"] == {"a": [3, 4, 5], "b": [3, 4, 5]}
    instruction = lines(tmp_path / "packs" / "tr-en" / INSTRUCTIONS_FILE)[-2]
    assert instruction["key"] == "en.gap.gap_friend"
    assert instruction["roles"] == {"a": "Arkadaşını anlat.", "b": "Doğru kişiyi seç."}


def test_misshaped_information_gaps_stay_out(tmp_path: Path) -> None:
    write_curation(tmp_path, [ANCHOR, ROUTINE], INSTRUCTIONS)
    wrong_option = FRIEND | {"id": "gap_x", "answer": {"chooser": "b", "option": "z"}}
    both_choose = FRIEND | {"id": "gap_y", "a": FRIEND["b"]}
    two_differ = DIFF | {"id": "gap_z", "answer": {"a": [4, 5], "b": [4, 5]}}
    add_gaps(
        tmp_path,
        [wrong_option, both_choose, two_differ, FRIEND],
        [FRIEND_TR | {"id": i} for i in ("gap_x", "gap_y", "gap_z")],
        ["gap_x", "gap_y", "gap_z"],
    )

    report = run_tasks(tmp_path, l1="tr", l2="en")

    assert {issue.id: issue.kind for issue in report.issues} == {
        "gap_x": "phrases",
        "gap_y": "phrases",
        "gap_z": "phrases",
        "gap_friend": "missing_instruction",
    }
    assert report.info_gaps_by_level == {}

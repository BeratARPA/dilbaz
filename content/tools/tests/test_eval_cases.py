import json
import sqlite3
from dataclasses import replace
from pathlib import Path

import pytest
from typer.testing import CliRunner

from dilbaz_content.cli import app
from dilbaz_content.eval_cases import (
    CASES_DIR,
    CASES_FILE,
    CASES_SOURCE,
    VALIDATION_FILE,
    Check,
    EvalCase,
    Packs,
    build_case,
    build_cases,
    read_forms,
    run_eval_cases,
)
from dilbaz_content.items import Chunk, GrammarPoint, Provenance, Sentence, WordSense
from dilbaz_content.normalize import NORMALIZATION_FILE, Normalizer
from dilbaz_content.pair_step import Gloss, Variants

EN_RULES = Path(__file__).resolve().parents[2] / "packs" / "en" / NORMALIZATION_FILE
OWN = Provenance(source="test", license="own")

SENTENCE = Sentence(
    key="en.sent.he_works_every_day",
    text="He works every day.",
    level="A1",
    lemmas=("he", "work", "every", "day"),
    targets=("en.ws.work.v.1", "en.ws.day.n.1"),
    grammar=("gp.present_simple.affirmative",),
    provenance=OWN,
)
PACKS = Packs(
    l1="tr",
    l2="en",
    sentences={SENTENCE.key: SENTENCE},
    senses={
        key: WordSense(key=key, lemma=lemma, pos=pos, sense="s", level="A1", provenance=OWN)
        for key, lemma, pos in [
            ("en.ws.work.v.1", "work", "VERB"),
            ("en.ws.day.n.1", "day", "NOUN"),
            ("en.ws.cat.n.1", "cat", "NOUN"),
        ]
    },
    chunks={
        "en.chunk.i_agree": Chunk(
            key="en.chunk.i_agree", text="I agree.", level="A1", function="f", provenance=OWN
        )
    },
    points={
        "en.gp.present_simple.affirmative": GrammarPoint(
            key="en.gp.present_simple.affirmative",
            code="gp.present_simple.affirmative",
            level="A1",
            name="n",
            description="d",
            examples=("a", "b"),
            provenance=OWN,
        )
    },
    glosses={
        SENTENCE.key: Gloss(key=SENTENCE.key, meaning="O her gün çalışır.", provenance=OWN),
        "en.chunk.i_agree": Gloss(
            key="en.chunk.i_agree", meaning="Katılıyorum.", context="bir toplantıda", provenance=OWN
        ),
    },
    variants={
        SENTENCE.key: Variants(
            key=SENTENCE.key,
            variants=("She works every day.",),
            alternatives=("He has a job every day.",),
            provenance=OWN,
        )
    },
    forms={
        "works": frozenset({"work"}),
        "work": frozenset({"work"}),
        "day": frozenset({"day"}),
        "every": frozenset({"every"}),
        "he": frozenset({"he"}),
    },
    normalize=Normalizer.from_file(EN_RULES),
    tags=frozenset({"agr.3sg_s", "be.extra"}),
)


def case(**fields: object) -> EvalCase:
    base: dict[str, object] = {
        "id": "f01",
        "card": "en.ws.work.v.1",
        "sent": "he_works_every_day",
        "say": "he work every day",
        "expect": ["minor_error"],
    }
    return EvalCase.model_validate(base | fields)


def test_a_word_card_carries_what_the_app_sends() -> None:
    row, issues = build_case(case(conf=0.8, target_ok=False, tags=["agr.3sg_s"]), PACKS)

    assert issues == []
    assert row is not None
    assert row["input"] == {
        "ctx": {"l1": "tr", "l2": "en", "level": "A1", "explain_in": "l1"},
        "item": {
            "key": "en.ws.work.v.1",
            "prompt_l1": "O her gün çalışır.",
            "reference_l2": "He works every day.",
            "variants": ["She works every day."],
            "alternatives": ["He has a job every day."],
            "target_span": "works",
            "grammar_codes": ["gp.present_simple.affirmative"],
        },
        "response": {"text": "he work every day", "source": "asr", "asr_confidence": 0.8},
        "attempt_no": 1,
        "previous_responses": [],
    }
    assert row["expected"] == {
        "verdicts": ["minor_error"],
        "target_ok": False,
        "tags": ["agr.3sg_s"],
    }
    fixture = row["fixture"]
    assert isinstance(fixture, dict)
    assert fixture["target_lemmas"] == ["work"]
    assert fixture["rule_code"] is None
    # Only the words the pack knows; "she", "has", "a", "job" are not in it.
    assert fixture["forms"] == {
        "day": ["day"],
        "every": ["every"],
        "he": ["he"],
        "work": ["work"],
        "works": ["work"],
    }


def test_a_grammar_card_targets_the_whole_sentence_and_names_its_rule() -> None:
    row, _ = build_case(
        case(card="en.gp.present_simple.affirmative", say="He work every day.", src="typed"),
        PACKS,
    )

    assert row is not None
    item = row["input"]["item"]  # type: ignore[index]
    assert item["target_span"] == "He works every day."
    assert row["input"]["response"] == {  # type: ignore[index]
        "text": "He work every day.",
        "source": "typed",
    }
    assert row["fixture"]["rule_code"] == "gp.present_simple.affirmative"  # type: ignore[index]


def test_a_set_phrase_has_no_carrier_and_keeps_its_context() -> None:
    row, _ = build_case(case(id="c01", card="en.chunk.i_agree", sent=None, say="i am agree"), PACKS)

    assert row is not None
    item = row["input"]["item"]  # type: ignore[index]
    assert item["reference_l2"] == "I agree."
    assert item["prompt_l1"] == "Katılıyorum."
    assert item["context_note"] == "bir toplantıda"
    assert item["variants"] == []
    assert item["target_span"] == "I agree."


def test_an_answer_the_lists_accept_never_reaches_the_llm() -> None:
    for said in ["He works every day!", "she works every day", "He has a job every day"]:
        row, issues = build_case(case(say=said, expect=["correct"]), PACKS)
        assert row is None
        assert [issue.kind for issue in issues] == ["matched"], said


@pytest.mark.parametrize(
    ("fields", "kind"),
    [
        ({"card": "en.ws.dog.n.1"}, "unknown_card"),
        ({"sent": "no_such_sentence"}, "unknown_sentence"),
        ({"card": "en.ws.cat.n.1"}, "not_carried"),
        ({"card": "en.chunk.i_agree"}, "unknown_sentence"),
        ({"sent": None}, "unknown_sentence"),
        ({"tags": ["phon.th"]}, "unknown_tag"),
        ({"tags": ["agr.3sg_s"], "expect": ["correct"]}, "inconsistent"),
        ({"expect": ["wrong"], "target_ok": True}, "inconsistent"),
        ({"expect": ["correct"], "target_ok": False}, "inconsistent"),
        ({"src": "typed", "conf": 0.5}, "inconsistent"),
        ({"src": "typed", "expect": ["unintelligible"]}, "inconsistent"),
    ],
)
def test_a_case_that_cannot_be_used_is_named(fields: dict[str, object], kind: str) -> None:
    row, issues = build_case(case(**fields), PACKS)
    assert row is None
    assert kind in [issue.kind for issue in issues]


def test_ids_and_answers_are_used_once() -> None:
    rows, issues = build_cases(
        [case(), case(), case(id="f02", say="He  work every day.")],
        PACKS,
    )
    assert len(rows) == 1
    assert [issue.kind for issue in issues] == ["duplicate", "duplicate"]


def test_forms_come_from_the_built_pack(tmp_path: Path) -> None:
    database = tmp_path / "en@1.sqlite"
    with sqlite3.connect(database) as connection:
        connection.execute("create table content_forms (form text, lemma text, pack_id text)")
        connection.executemany(
            "insert into content_forms values (?, ?, 'en@1')",
            [("left", "leave"), ("left", "left"), ("works", "work")],
        )
    assert read_forms(database) == {
        "left": frozenset({"leave", "left"}),
        "works": frozenset({"work"}),
    }
    with pytest.raises(FileNotFoundError, match="build"):
        read_forms(tmp_path / "missing.sqlite")


def _content(tmp_path: Path, cases: str, checks: str = "") -> Path:
    root = tmp_path / "content"
    items = root / "packs" / "en" / "items"
    pair = root / "packs" / "tr-en"
    items.mkdir(parents=True)
    pair.mkdir(parents=True)
    (root / "packs" / "en" / NORMALIZATION_FILE).write_text(
        EN_RULES.read_text(encoding="utf-8"), encoding="utf-8"
    )

    def write(path: Path, rows: list[object]) -> None:
        path.write_text(
            "".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf-8"
        )

    write(items / "sentences.jsonl", [SENTENCE.model_dump()])
    write(items / "word_senses.jsonl", [s.model_dump() for s in PACKS.senses.values()])
    write(items / "chunks.jsonl", [c.model_dump() for c in PACKS.chunks.values()])
    write(items / "grammar_points.jsonl", [p.model_dump() for p in PACKS.points.values()])
    write(pair / "glosses.jsonl", [g.model_dump() for g in PACKS.glosses.values()])
    write(pair / "variants.jsonl", [v.model_dump() for v in PACKS.variants.values()])
    write(
        pair / "error_tags.jsonl",
        [
            {"code": "agr.3sg_s", "category": "grammar"},
            {"code": "phon.th", "category": "pronunciation"},
        ],
    )
    build = root / "build"
    build.mkdir()
    with sqlite3.connect(build / "en@1.sqlite") as connection:
        connection.execute("create table content_forms (form text, lemma text, pack_id text)")
        connection.executemany(
            "insert into content_forms values (?, ?, 'en@1')",
            [(form, lemma) for form, lemmas in PACKS.forms.items() for lemma in lemmas],
        )
    folder = tmp_path / CASES_DIR
    folder.mkdir(parents=True)
    (folder / CASES_SOURCE).write_text(cases, encoding="utf-8")
    (folder / VALIDATION_FILE).write_text(checks, encoding="utf-8")
    return root


def test_the_step_writes_the_set_in_the_order_of_its_source(tmp_path: Path) -> None:
    root = _content(
        tmp_path,
        "- {id: f01, card: en.ws.work.v.1, sent: he_works_every_day, say: he work every day,"
        " expect: [minor_error], tags: [agr.3sg_s]}\n"
        "- {id: c01, card: en.chunk.i_agree, say: i am agree, expect: [wrong]}\n",
        '{"id": "f01", "round": 1, "verdicts": ["wrong"], "target_ok": false}\n'
        '{"id": "f01", "round": 2, "verdicts": ["minor_error"], "target_ok": false}\n'
        '{"id": "c01", "round": 1, "verdicts": ["wrong"], "target_ok": "either"}\n',
    )

    report = run_eval_cases(root)

    assert report.cases == 2
    assert report.by_kind == {"c": 1, "f": 1}
    assert report.by_verdict == {"minor_error": 1, "wrong": 1}
    lines = (tmp_path / CASES_DIR / CASES_FILE).read_text(encoding="utf-8").splitlines()
    assert [json.loads(line)["id"] for line in lines] == ["f01", "c01"]


def test_the_command_fails_and_writes_nothing_while_a_case_is_unusable(tmp_path: Path) -> None:
    root = _content(
        tmp_path,
        "- {id: f01, card: en.ws.work.v.1, sent: he_works_every_day, say: He works every day.,"
        " expect: [correct]}\n",
    )

    result = CliRunner().invoke(app, ["eval-cases", "--content-dir", str(root)])

    assert result.exit_code == 1
    assert "matched" in result.output
    assert not (tmp_path / CASES_DIR / CASES_FILE).exists()


def test_the_lists_are_split_by_the_cards_own_target() -> None:
    work, _ = build_case(case(), PACKS)
    day, _ = build_case(case(card="en.ws.day.n.1", say="he work every day"), PACKS)
    assert work is not None
    assert day is not None
    # "He has a job every day." lacks "work" but says "day".
    assert work["input"]["item"]["variants"] == ["She works every day."]  # type: ignore[index]
    assert work["input"]["item"]["alternatives"] == ["He has a job every day."]  # type: ignore[index]
    assert day["input"]["item"]["variants"] == [  # type: ignore[index]
        "She works every day.",
        "He has a job every day.",
    ]
    assert day["input"]["item"]["alternatives"] == []  # type: ignore[index]


def test_a_grammar_card_keeps_the_answers_that_use_its_structure() -> None:
    listed = PACKS.variants[SENTENCE.key]
    coded = listed.model_copy(
        update={
            "grammar": {
                "She works every day.": ("gp.present_simple.affirmative",),
                "He has a job every day.": ("gp.present_simple.affirmative",),
            }
        }
    )
    tagged = replace(PACKS, variants={SENTENCE.key: coded})
    card = "en.gp.present_simple.affirmative"
    row, _ = build_case(case(card=card, say="He work every day."), tagged)
    assert row is not None
    # "He has a job every day." lacks the word but uses the structure.
    assert row["input"]["item"]["variants"] == [  # type: ignore[index]
        "She works every day.",
        "He has a job every day.",
    ]
    assert row["input"]["item"]["alternatives"] == []  # type: ignore[index]

    # Without the codes the pack's lists stand, as the engine reads them.
    row, _ = build_case(case(card=card, say="He work every day."), PACKS)
    assert row is not None
    assert row["input"]["item"]["alternatives"] == ["He has a job every day."]  # type: ignore[index]


def test_a_case_needs_a_blind_check_that_agrees() -> None:
    def check(verdict: str, target_ok: bool | str = False) -> Check:
        return Check.model_validate(
            {"id": "f01", "round": 1, "verdicts": [verdict], "target_ok": target_ok}
        )

    good = case(target_ok=False)
    assert build_cases([good], PACKS, {"f01": check("minor_error")})[1] == []
    assert build_cases([good], PACKS, {"f01": check("minor_error", "either")})[1] == []
    for checks, kind, detail in [
        ({}, "unvalidated", "no blind check"),
        ({"f01": check("wrong")}, "disputed", "checked wrong"),
        ({"f01": check("minor_error", True)}, "disputed", "target_ok True"),
    ]:
        rows, issues = build_cases([good], PACKS, checks)
        assert rows == []
        assert [(i.kind, i.detail) for i in issues] == [(kind, detail)]

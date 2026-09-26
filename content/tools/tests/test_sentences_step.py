import json
from pathlib import Path

import pytest
from pydantic import ValidationError

from dilbaz_content.items import Sentence, WordSense
from dilbaz_content.sentences_step import (
    CarrierChoice,
    SentenceCuration,
    ambiguous_senses,
    load_curation,
    read_candidates,
    run_sentences,
)

from sample_sentences import SENSES, OwnAnalyzer, write_s4_inputs

# Both "right" senses need a choice: the tagger cannot tell them apart.
RIGHTS = """
carriers:
  en.ws.right.adj.1: [{tatoeba: 3}]
  en.ws.right.adj.2: [{text: "My right hand is cold."}]
"""


def sentences(root: Path) -> dict[str, Sentence]:
    path = root / "packs" / "en" / "items" / "sentences.jsonl"
    lines = path.read_text(encoding="utf-8").splitlines()
    parsed = [Sentence.model_validate_json(line) for line in lines]
    return {sentence.text: sentence for sentence in parsed}


def carriers(root: Path) -> dict[str, tuple[str, ...]]:
    path = root / "packs" / "en" / "items" / "word_senses.jsonl"
    senses = [WordSense.model_validate_json(line) for line in path.read_text().splitlines()]
    return {sense.key: sense.carriers for sense in senses}


def test_each_sense_gets_its_best_candidate_or_the_curated_carriers(tmp_path: Path) -> None:
    root = write_s4_inputs(tmp_path, RIGHTS)

    report = run_sentences(root, l2="en", analyzer=OwnAnalyzer)

    assert report.issues == ()
    assert (report.sentences, report.tatoeba, report.own) == (4, 3, 1)
    assert report.by_level == {"A0": 1, "A1": 3}
    found = sentences(root)
    we = found["We watch TV."]
    assert we.key == "en.sent.we_watch_tv"
    assert we.level == "A1"
    assert we.lemmas == ("we", "watch", "tv")
    assert we.grammar == ("gp.present_simple.affirmative", "gp.pronouns.subject")
    assert we.provenance.source == "tatoeba:2"
    assert we.provenance.license == "CC BY 2.0 FR"
    assert we.provenance.attribution == "CK"
    # A sentence carries every selected sense in it, not only the one that chose it.
    assert found["I watch TV every evening."].targets == ("en.ws.evening.n.1", "en.ws.watch.v.1")
    own = found["My right hand is cold."]
    assert own.provenance.license == "own"
    assert carriers(root) == {
        "en.ws.watch.v.1": ("en.sent.we_watch_tv",),
        "en.ws.evening.n.1": ("en.sent.i_watch_tv_every_evening",),
        "en.ws.right.adj.1": ("en.sent.you_are_right",),
        "en.ws.right.adj.2": ("en.sent.my_right_hand_is_cold",),
    }
    turkish = [
        json.loads(line)
        for line in (root / "work" / "sentences.en.turkish.jsonl").read_text("utf-8").splitlines()
    ]
    assert {"key": "en.sent.you_are_right", "turkish": ["Haklısın."]} in turkish
    assert len(turkish) == 3
    saved = json.loads((root / "work" / "sentences.en.report.json").read_text(encoding="utf-8"))
    assert saved["sentences"] == 4


def test_an_ambiguous_word_stands_only_for_the_chosen_sense(tmp_path: Path) -> None:
    root = write_s4_inputs(tmp_path, RIGHTS)
    run_sentences(root, l2="en", analyzer=OwnAnalyzer)
    found = sentences(root)
    assert found["You are right."].targets == ("en.ws.right.adj.1",)
    assert found["My right hand is cold."].targets == ("en.ws.right.adj.2",)


def test_ambiguous_senses_have_no_automatic_carrier(tmp_path: Path) -> None:
    root = write_s4_inputs(tmp_path)

    report = run_sentences(root, l2="en", analyzer=OwnAnalyzer)

    assert [(i.key, i.kind) for i in report.blocking] == [
        ("en.ws.right.adj.1", "ambiguous_sense"),
        ("en.ws.right.adj.2", "ambiguous_sense"),
    ]
    assert "en.ws.right.adj.2" in report.blocking[0].detail
    assert set(sentences(root)) == {"We watch TV.", "I watch TV every evening."}
    assert carriers(root)["en.ws.right.adj.1"] == ()


def test_ambiguous_senses_group_by_lemma_and_part_of_speech() -> None:
    assert ambiguous_senses(SENSES) == {
        "en.ws.right.adj.1": ("en.ws.right.adj.2",),
        "en.ws.right.adj.2": ("en.ws.right.adj.1",),
    }


def test_rejected_sentences_are_skipped(tmp_path: Path) -> None:
    root = write_s4_inputs(tmp_path, "reject: [2]\n" + RIGHTS)

    run_sentences(root, l2="en", analyzer=OwnAnalyzer)

    assert "We watch TV." not in sentences(root)
    assert carriers(root)["en.ws.watch.v.1"] == ("en.sent.i_watch_tv_every_evening",)


def test_a_curated_id_may_come_from_outside_the_candidates(tmp_path: Path) -> None:
    root = write_s4_inputs(tmp_path, RIGHTS + "  en.ws.watch.v.1: [{tatoeba: 7}]\n")
    analyzer = OwnAnalyzer()

    run_sentences(root, l2="en", analyzer=lambda: analyzer)

    they = sentences(root)["They watch TV."]
    assert they.provenance.source == "tatoeba:7"
    assert analyzer.calls == 1


def test_unknown_ids_stop_the_step(tmp_path: Path) -> None:
    root = write_s4_inputs(tmp_path, RIGHTS + "  en.ws.watch.v.1: [{tatoeba: 999}]\n")
    with pytest.raises(ValueError, match=r"not in the analysis cache: \[999\]"):
        run_sentences(root, l2="en", analyzer=OwnAnalyzer)


def test_the_checks_block_bad_carriers(tmp_path: Path) -> None:
    curation = """
carriers:
  en.ws.watch.v.1: [{tatoeba: 4}]
  en.ws.evening.n.1: [{tatoeba: 5}]
  en.ws.right.adj.1: [{text: "Damn, you are right."}]
  en.ws.right.adj.2: [{text: "You are right, xyzzy."}]
"""
    root = write_s4_inputs(tmp_path, curation)

    report = run_sentences(root, l2="en", analyzer=OwnAnalyzer)

    found = {(issue.key, issue.kind, issue.detail) for issue in report.blocking}
    assert found == {
        ("en.sent.i_watch_a_documentary", "above_target_level", "en.ws.watch.v.1: B1"),
        ("en.sent.i_watch_a_documentary", "above_pack_level", "B1"),
        ("en.sent.tom_is_here", "target_missing", "en.ws.evening.n.1"),
        ("en.sent.damn_you_are_right", "blocked_word", "damn"),
        ("en.sent.you_are_right_xyzzy", "unknown_word", "xyzzy"),
    }
    # A sentence with an unknown word cannot be levelled and is left out.
    assert "You are right, xyzzy." not in sentences(root)


def test_near_duplicates_are_warnings(tmp_path: Path) -> None:
    curation = """
carriers:
  en.ws.watch.v.1: [{tatoeba: 6}]
  en.ws.evening.n.1: [{tatoeba: 1}]
  en.ws.right.adj.1: [{tatoeba: 3}]
  en.ws.right.adj.2: [{text: "You are right!"}]
"""
    root = write_s4_inputs(tmp_path, curation)

    report = run_sentences(root, l2="en", analyzer=OwnAnalyzer)

    assert report.blocking == ()
    assert {(i.key, i.kind, i.detail) for i in report.issues} == {
        # Same key: the second text is dropped.
        ("en.sent.you_are_right", "near_duplicate", "You are right."),
        # Lemma sets overlap more than 80 %.
        (
            "en.sent.do_i_watch_tv_every_evening",
            "near_duplicate",
            "en.sent.i_watch_tv_every_evening",
        ),
    }


def test_curation_defaults_and_validation(tmp_path: Path) -> None:
    assert load_curation(tmp_path / "missing.yaml") == SentenceCuration()
    empty = tmp_path / "empty.yaml"
    empty.write_text("", encoding="utf-8")
    assert load_curation(empty) == SentenceCuration()
    with pytest.raises(ValidationError, match="either tatoeba or text"):
        CarrierChoice()
    with pytest.raises(ValidationError, match="either tatoeba or text"):
        CarrierChoice(tatoeba=1, text="Hi.")


def test_the_candidates_come_from_s3(tmp_path: Path) -> None:
    with pytest.raises(FileNotFoundError, match="dilbaz-content carriers"):
        read_candidates(tmp_path / "carriers.en.candidates.jsonl")

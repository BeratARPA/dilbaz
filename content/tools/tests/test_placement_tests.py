import json
from pathlib import Path

import pytest
from typer.testing import CliRunner

from dilbaz_content.audio_step import Clip
from dilbaz_content.cli import app
from dilbaz_content.items import GrammarPoint, Provenance, Sentence
from dilbaz_content.lexicon import LevelTag, LexiconEntry
from dilbaz_content.normalize import NormalizationRules, Normalizer
from dilbaz_content.placement_tests import (
    DICTATION_CURATION,
    DICTATION_FILE,
    GRAMMAR_CURATION,
    GRAMMAR_FILE,
    GRAMMAR_VALIDATION,
    DictationCuration,
    GrammarCheck,
    GrammarDraft,
    PlacementTestsError,
    dictation_set,
    form_levels,
    grammar_bank,
    grammar_issues,
    hard_words,
    read_checks,
    run_placement_tests,
)

from test_build_step import ready

OWN = Provenance(source="dilbaz curation", license="own")
NORMALIZER = Normalizer(
    NormalizationRules(version=1, apostrophes=("’",), punctuation=".,!?", words={"i'm": "i am"})
)


def draft(**changes: object) -> GrammarDraft:
    fields: dict[str, object] = {
        "id": "a1.be_present",
        "level": "A1",
        "grammar": "gp.be.present",
        "focus": "be: am / is / are",
        "stem": "My parents ___ at home now.",
        "answer": "are",
        "distractors": ("is", "am"),
    }
    return GrammarDraft.model_validate(fields | changes)


def point(code: str = "gp.be.present", level: str = "A0") -> GrammarPoint:
    return GrammarPoint(
        key=f"en.{code}",
        code=code,
        level=level,  # type: ignore[arg-type]
        name=code,
        description="A structure.",
        examples=("One.", "Two."),
        provenance=OWN,
    )


def check(item: GrammarDraft, **changes: object) -> GrammarCheck:
    fields: dict[str, object] = {
        "id": item.id,
        "stem": item.stem,
        "options": tuple(reversed(item.options)),
        "round": 1,
        "acceptable": (item.answer,),
        "natural": True,
        "level_ok": True,
    }
    return GrammarCheck.model_validate(fields | changes)


def issues(item: GrammarDraft, *checks: GrammarCheck) -> list[tuple[str, str]]:
    found = grammar_issues([item], [point()], {c.id: c for c in checks})
    return [(issue.kind, issue.detail) for issue in found]


def test_a_checked_item_enters_the_bank() -> None:
    item = draft()

    assert issues(item, check(item)) == []
    (banked,) = grammar_bank([item], [], l2="en")
    assert banked.key == "en.pgram.a1.be_present"
    assert banked.stem == "My parents ___ at home now."
    assert (banked.answer, banked.distractors) == ("are", ("is", "am"))
    assert banked.provenance == OWN


def test_an_item_needs_one_gap_and_three_different_choices() -> None:
    assert issues(draft(stem="My parents are at home now.")) == [
        ("gap", "the stem needs exactly one ___")
    ]
    assert issues(draft(stem="My ___ are ___ now."))[0][0] == "gap"
    twice = draft(distractors=("is", "Are"))
    assert ("options", "two choices are the same") in issues(twice, check(twice))
    spaced = draft(distractors=("is ", "am"))
    assert ("options", "a choice has a gap or outer spaces") in issues(spaced, check(spaced))


def test_a_choice_is_capitalised_only_where_it_opens_a_sentence() -> None:
    opener = draft(stem="___ your father speak English?", answer="Does", distractors=("Do", "is"))
    assert ("options", "capitalisation: is") in issues(opener, check(opener))
    second = draft(
        stem="My mother is a teacher. ___ works in a school.",
        answer="She",
        distractors=("He", "Her"),
    )
    assert issues(second, check(second)) == []
    inside = draft(distractors=("Is", "am"))
    assert ("options", "capitalisation: Is") in issues(inside, check(inside))
    # The pronoun is written with a capital everywhere.
    pronoun = draft(
        stem="She asked me where ___.",
        answer="I lived",
        distractors=("did I live", "do I live"),
    )
    assert issues(pronoun, check(pronoun)) == []


def test_an_item_of_the_packs_levels_names_one_of_its_grammar_points() -> None:
    unknown = draft(grammar="gp.nothing")
    assert ("unknown_grammar", "gp.nothing") in issues(unknown, check(unknown))
    nameless = draft(grammar=None, level="A0")
    assert issues(nameless, check(nameless)) == [
        ("unknown_grammar", "an item of the pack's levels needs one")
    ]
    # Above the pack's grammar points there is no code to name yet.
    above = draft(id="b1.since", grammar=None, level="B1")
    assert issues(above, check(above)) == []


def test_a_grammar_point_above_the_items_level_is_refused() -> None:
    item = draft(level="A0")
    found = grammar_issues([item], [point(level="A1")], {item.id: check(item)})

    assert [(i.kind, i.detail) for i in found] == [
        ("grammar_above_level", "gp.be.present is A1, the item A0")
    ]


def test_an_item_without_a_check_of_its_exact_text_stays_out() -> None:
    item = draft()
    unvalidated = [("unvalidated", "no check of this exact text")]

    assert issues(item) == unvalidated
    assert issues(item, check(item, stem="My parents ___ at home.")) == unvalidated
    assert issues(item, check(item, options=("are", "is", "be"))) == unvalidated
    assert grammar_bank([item], grammar_issues([item], [point()], {}), l2="en") == []


def test_the_check_must_find_the_answer_and_nothing_else() -> None:
    item = draft()

    assert issues(item, check(item, acceptable=("are", "is"))) == [
        ("disputed", "the check accepts: are, is")
    ]
    assert issues(item, check(item, acceptable=("is",))) == [("disputed", "the check accepts: is")]
    assert issues(item, check(item, acceptable=())) == [("disputed", "the check accepts: none")]
    assert issues(item, check(item, natural=False, note="stilted")) == [("unnatural", "stilted")]
    assert issues(item, check(item, level_ok=False)) == [("off_level", "")]


def test_a_reasoned_exception_carries_an_item() -> None:
    item = draft()
    overridden = check(item, acceptable=("are", "is"), override="dialectal only; see note")

    assert issues(item, overridden) == []


def test_an_id_is_used_once() -> None:
    item = draft()
    found = grammar_issues([item, item], [point()], {item.id: check(item)})

    assert [i.kind for i in found] == ["duplicate"]


def test_the_latest_check_of_an_item_counts(tmp_path: Path) -> None:
    item = draft()
    path = tmp_path / GRAMMAR_VALIDATION
    first = check(item, acceptable=("are", "is"))
    second = check(item, round=2)
    path.write_text(
        first.model_dump_json() + "\n\n" + second.model_dump_json() + "\n", encoding="utf-8"
    )

    assert read_checks(path) == {item.id: second}
    assert read_checks(tmp_path / "missing.jsonl") == {}


def entry(lemma: str, cefr: str | None, *forms: str, multiword: bool = False) -> LexiconEntry:
    return LexiconEntry(
        lemma=lemma,
        display=lemma,
        multiword=multiword,
        cefr=cefr,  # type: ignore[arg-type]
        levels=(LevelTag(pos="NOUN", cefr=cefr or "A1", source="cefrj"),),  # type: ignore[arg-type]
        rank=1,
        zipf=5.0,
        family_zipf=5.0,
        forms=forms,
        sources=("cefrj",),
    )


def test_words_above_the_level_of_an_item_are_named() -> None:
    levels = form_levels(
        [
            entry("my", "A1"),
            entry("parent", "A1", "parents"),
            entry("be", "A1", "are", "is"),
            entry("at", "A1"),
            entry("home", "B1"),
            # The easier of two lemmas with one form decides.
            entry("home", "A2"),
            entry("nowadays", None),
            entry("at home", "A1", multiword=True),
        ]
    )

    assert levels["parents"] == "A1"
    assert levels["home"] == "A2"
    assert levels["nowadays"] is None
    assert "at home" not in levels
    assert hard_words(draft(), NORMALIZER, levels) == ("home", "now")
    assert hard_words(draft(level="A2"), NORMALIZER, levels) == ("now",)


def sentence(text: str, level: str = "A1") -> Sentence:
    key = "en.sent." + "_".join(NORMALIZER(text).split())
    return Sentence(
        key=key,
        text=text,
        level=level,  # type: ignore[arg-type]
        lemmas=tuple(NORMALIZER(text).split()),
        targets=("en.ws.thing.n.1",),
        provenance=OWN,
    )


def clips(sentences: list[Sentence], voice: str = "v1", speed: float = 1.0) -> list[Clip]:
    return [
        Clip(key=s.key, voice=voice, speed=speed, file=f"{voice}/{i}.mp3", duration_ms=900)
        for i, s in enumerate(sentences)
    ]


EASY = [
    sentence("The cat is on the chair."),
    sentence("My sister has a small dog."),
    sentence("We go to school by bus."),
    sentence("They live in a big house."),
]
HARDER = [
    sentence("She works in the local flower shop.", "A2"),
    sentence("What are you going to do next?", "A2"),
]
ONE_VERSION = DictationCuration(
    versions=("A",), levels=("A1", "A2", "A1"), words={"A1": (5, 7), "A2": (7, 9)}
)


def test_a_version_plays_sentences_of_rising_level_and_length() -> None:
    pool = [*EASY, *HARDER]

    items, eligible = dictation_set(pool, clips(pool), NORMALIZER, ONE_VERSION)

    assert eligible == {"A1": 4, "A2": 2}
    assert [(item.version, item.order, item.level) for item in items] == [
        ("A", 1, "A1"),
        ("A", 2, "A1"),
        ("A", 3, "A2"),
    ]
    lengths = [len(NORMALIZER(s.text).split()) for i in items for s in pool if s.key == i.sentence]
    assert lengths[:2] == sorted(lengths[:2])
    assert len({item.sentence for item in items}) == 3


def test_versions_share_no_sentence_and_the_seed_fixes_the_draw() -> None:
    curation = DictationCuration(versions=("A", "B"), levels=("A1", "A1"), words={"A1": (5, 7)})

    items, _ = dictation_set(EASY, clips(EASY), NORMALIZER, curation)
    again, _ = dictation_set(list(reversed(EASY)), clips(EASY), NORMALIZER, curation)
    other, _ = dictation_set(EASY, clips(EASY), NORMALIZER, curation.model_copy(update={"seed": 7}))

    assert len({item.sentence for item in items}) == 4
    assert items == again
    assert [i.sentence for i in items] != [i.sentence for i in other]


def test_sentences_that_ask_for_spelling_are_left_out() -> None:
    unfit = [
        sentence("I don't like the cold weather."),
        sentence("I don’t like the cold weather much."),
        sentence("There are 12 people in the room."),
        sentence("My friend lives in a well-known town."),
        sentence("We met Tom at the old station."),
    ]
    fit = [sentence("Then I went to the market."), *EASY[:1]]
    curation = DictationCuration(versions=("A",), levels=("A1", "A1"), words={"A1": (5, 7)})

    items, eligible = dictation_set([*unfit, *fit], clips([*unfit, *fit]), NORMALIZER, curation)

    assert eligible == {"A1": 2}
    assert {item.sentence for item in items} == {s.key for s in fit}


def test_length_voice_and_the_curation_decide_who_is_eligible() -> None:
    curation = DictationCuration(versions=("A",), levels=("A1",), words={"A1": (5, 7)})
    short = sentence("You are right.")
    long = sentence("I usually go to the old market with my little brother.")
    slow = sentence("They live in a big house.")
    other_voice = sentence("We go to school by bus.")
    rejected = sentence("My sister has a small dog.")
    good = sentence("The cat is on the chair.")
    pool = [short, long, slow, other_voice, rejected, good]
    spoken = [
        *clips([short, long, rejected, good]),
        *clips([slow], speed=0.8),
        *clips([other_voice], voice="v3"),
    ]

    items, eligible = dictation_set(
        pool, spoken, NORMALIZER, curation.model_copy(update={"exclude": (rejected.key,)})
    )

    assert eligible == {"A1": 1}
    assert [item.sentence for item in items] == [good.key]


def test_too_few_sentences_stop_the_step() -> None:
    curation = DictationCuration(
        versions=("A", "B", "C"), levels=("A1", "A1"), words={"A1": (5, 7)}
    )

    with pytest.raises(PlacementTestsError, match="4 sentences of A1 fit for dictation, 6 needed"):
        dictation_set(EASY, clips(EASY), NORMALIZER, curation)


GRAMMAR_YAML = """
items:
  - id: a1.be_present
    level: A1
    grammar: gp.be.present
    focus: "be"
    stem: "You ___ right."
    answer: "are"
    distractors: ["is", "am"]
  - id: a1.pronoun
    level: A1
    grammar: gp.pronouns.subject
    focus: "subject pronouns"
    stem: "___ watch TV every evening."
    answer: "We"
    distractors: ["Us", "Our"]
  - id: b1.documentary
    level: B1
    focus: "passive"
    stem: "The documentary ___ every evening."
    answer: "is watched"
    distractors: ["watches", "is watching"]
"""
DICTATION_YAML = """
versions: [A]
levels: [A1]
words: {A1: [5, 5]}
"""


def with_curation(tmp_path: Path, *, checked: tuple[str, ...]) -> Path:
    root = ready(tmp_path)
    curation = root / "curation" / "en"
    (curation / GRAMMAR_CURATION).write_text(GRAMMAR_YAML, encoding="utf-8")
    (curation / DICTATION_CURATION).write_text(DICTATION_YAML, encoding="utf-8")
    verdicts = {
        "a1.be_present": ("You ___ right.", ["am", "is", "are"], ["are"]),
        "a1.pronoun": ("___ watch TV every evening.", ["We", "Us", "Our"], ["We"]),
        "b1.documentary": (
            "The documentary ___ every evening.",
            ["is watched", "watches", "is watching"],
            ["is watched"],
        ),
    }
    (curation / GRAMMAR_VALIDATION).write_text(
        "".join(
            json.dumps(
                {
                    "id": item,
                    "stem": stem,
                    "options": options,
                    "round": 1,
                    "acceptable": acceptable,
                    "natural": True,
                    "level_ok": True,
                }
            )
            + "\n"
            for item, (stem, options, acceptable) in verdicts.items()
            if item in checked
        ),
        encoding="utf-8",
    )
    return root


def lines(path: Path) -> list[dict]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()]


def test_the_step_writes_the_bank_and_the_set(tmp_path: Path) -> None:
    root = with_curation(tmp_path, checked=("a1.be_present", "a1.pronoun", "b1.documentary"))

    report = run_placement_tests(root, l2="en")

    assert report.issues == ()
    assert report.grammar_by_level == {"A1": 2, "B1": 1}
    # The miniature lexicon has few words and no inflections. "documentary"
    # is B1 there, which a B1 item may use.
    assert report.hard_words == {
        "a1.be_present": ("are",),
        "b1.documentary": ("the", "is", "watched"),
    }
    en = root / "packs" / "en"
    bank = lines(en / GRAMMAR_FILE)
    assert [item["key"] for item in bank] == [
        "en.pgram.a1.be_present",
        "en.pgram.a1.pronoun",
        "en.pgram.b1.documentary",
    ]
    assert bank[0]["grammar"] == "gp.be.present"
    assert "grammar" not in bank[2]
    assert bank[0]["provenance"] == {"source": "dilbaz curation", "license": "own"}
    # "We watch TV." and its longer sister hold a name; the A0 sentence is no A1.
    assert report.dictation_eligible == {"A1": 1}
    assert lines(en / DICTATION_FILE) == [
        {"version": "A", "order": 1, "level": "A1", "sentence": "en.sent.my_right_hand_is_cold"}
    ]
    saved = json.loads((root / "work" / "placement_tests.en.report.json").read_text("utf-8"))
    assert saved["dictation"] == 1


def test_the_command_fails_while_an_item_lacks_its_check(tmp_path: Path) -> None:
    runner = CliRunner()
    good = with_curation(
        tmp_path / "good", checked=("a1.be_present", "a1.pronoun", "b1.documentary")
    )
    result = runner.invoke(app, ["placement-tests", "--content-dir", str(good)])
    assert result.exit_code == 0, result.output
    assert "{'A1': 2, 'B1': 1}" in result.output

    bad = with_curation(tmp_path / "bad", checked=("a1.be_present",))
    result = runner.invoke(app, ["placement-tests", "--content-dir", str(bad)])
    assert result.exit_code == 1
    assert "unvalidated" in result.output
    # The checked item is in the bank all the same.
    assert [i["key"] for i in lines(bad / "packs" / "en" / GRAMMAR_FILE)] == [
        "en.pgram.a1.be_present"
    ]

    (bad / "curation" / "en" / DICTATION_CURATION).write_text("levels: [A2]\n", encoding="utf-8")
    result = runner.invoke(app, ["placement-tests", "--content-dir", str(bad)])
    assert result.exit_code == 1
    assert "0 sentences of A2" in result.output

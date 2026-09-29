"""The rule-based tagger against real spaCy analyses of the curated examples."""

from pathlib import Path

import pytest
import yaml

from dilbaz_content.analysis import SpacyAnalyzer, Token
from dilbaz_content.grammar_tags import (
    OUTSIDE_LEVELS,
    grammar_codes,
    outside_levels,
    outside_structures,
)

GRAMMAR = Path(__file__).resolve().parents[2] / "curation" / "en" / "grammar_points.yaml"


@pytest.fixture(scope="module")
def analyzer() -> SpacyAnalyzer:
    return SpacyAnalyzer()


def codes(analyzer: SpacyAnalyzer, text: str) -> tuple[str, ...]:
    tokens: tuple[Token, ...] = next(analyzer.analyze([text]))
    return grammar_codes(tokens)


def test_every_grammar_point_is_found_in_one_of_its_examples(analyzer: SpacyAnalyzer) -> None:
    points = yaml.safe_load(GRAMMAR.read_text(encoding="utf-8"))
    missed = [
        point["code"]
        for point in points
        if not any(point["code"] in codes(analyzer, text) for text in point["examples"])
    ]
    assert missed == []


@pytest.mark.parametrize(
    ("text", "present", "absent"),
    [
        ("I'm going to visit my parents.", "gp.future.going_to", "gp.present_continuous.now"),
        ("I'm cooking dinner.", "gp.present_continuous.now", "gp.be.present"),
        ("The window was opened.", "gp.past_simple.be", "gp.past_simple.regular"),
        ("Where do you work?", "gp.questions.wh", "gp.present_simple.questions"),
        ("That is my car.", "gp.demonstratives", "gp.questions.wh"),
        ("I was tired, so I went to bed.", "gp.past_simple.irregular", "gp.conjunctions.basic"),
        ("I like tea and coffee.", "gp.conjunctions.basic", "gp.like_ing"),
        ("I've got to go now.", "gp.modals.obligation", "gp.have_got"),
        ("I've got a car.", "gp.have_got", "gp.modals.obligation"),
        ("It's been too long.", "gp.present_perfect.experience", "gp.be.present"),
        ("Would you like some tea?", "gp.would_like", "gp.questions.wh"),
        ("Don't forget the party tonight.", "gp.imperative", "gp.present_simple.negative"),
        ("Don't you want to learn to drive?", "gp.present_simple.negative", "gp.imperative"),
        ("I have lessons in the afternoon.", "gp.prepositions.time", "gp.prepositions.place"),
        ("He works even on Sundays.", "gp.prepositions.time", "gp.prepositions.place"),
        ("Put it on the table.", "gp.prepositions.place", "gp.prepositions.time"),
    ],
)
def test_rules_do_not_overreach(
    analyzer: SpacyAnalyzer, text: str, present: str, absent: str
) -> None:
    found = codes(analyzer, text)
    assert present in found
    assert absent not in found


def test_empty_input_has_no_codes() -> None:
    assert grammar_codes(()) == ()
    assert grammar_codes(((".", ".", "PUNCT", "."),)) == ()


@pytest.mark.parametrize(
    ("text", "structure"),
    [
        ("The changes were not made.", "passive"),
        ("I'm used to working late.", "passive"),
        ("You used to teach, right?", "used_to"),
        ("I was going to call you.", "past_continuous"),
        ("It's been raining all day.", "perfect_continuous"),
        ("I had finished my work.", "past_perfect"),
        ("You'd have done the same.", "modal_perfect"),
        ("You'd have done the same.", "would"),
        ("Could you help me?", "modal_possibility"),
        ("If it rains, we stay at home.", "conditional"),
        ("Tell me what you want.", "wh_clause"),
        ("The man who lives here is nice.", "wh_clause"),
        ("Call me when you get home.", "when_clause"),
        ("I was tired, so I went to bed.", "so_result"),
    ],
)
def test_structures_outside_the_pack_are_found(
    analyzer: SpacyAnalyzer, text: str, structure: str
) -> None:
    tokens: tuple[Token, ...] = next(analyzer.analyze([text]))
    assert structure in outside_structures(tokens)


@pytest.mark.parametrize(
    "text",
    [
        "Come on, what's his name?",
        "Where do you work?",
        "When does the game start?",
        "Would you like some tea?",
        "I'd like a coffee, please.",
        "I'm tired.",
        "I've got a car.",
        "It's been too long.",
        "What a nice day!",
    ],
)
def test_pack_sentences_have_no_outside_structures(analyzer: SpacyAnalyzer, text: str) -> None:
    tokens: tuple[Token, ...] = next(analyzer.analyze([text]))
    assert outside_structures(tokens) == ()


def test_outside_structures_have_levels(analyzer: SpacyAnalyzer) -> None:
    tokens: tuple[Token, ...] = next(analyzer.analyze(["Call me when you get home."]))
    assert outside_levels(tokens) == ("A2",)
    assert set(OUTSIDE_LEVELS.values()) <= {"A2", "B1", "B2"}

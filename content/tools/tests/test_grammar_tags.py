"""The rule-based tagger against real spaCy analyses of the curated examples."""

from pathlib import Path

import pytest
import yaml

from dilbaz_content.analysis import SpacyAnalyzer, Token
from dilbaz_content.grammar_tags import grammar_codes

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
        ("I was tired, so I went to bed.", "gp.conjunctions.basic", "gp.be.present"),
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

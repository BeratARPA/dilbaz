from pathlib import Path

import pytest

from dilbaz_content.normalize import NORMALIZATION_FILE, NormalizationRules, Normalizer

EN_RULES = Path(__file__).resolve().parents[2] / "packs" / "en" / NORMALIZATION_FILE
NORMALIZE = Normalizer.from_file(EN_RULES)


@pytest.mark.parametrize(("text", "expected"), NORMALIZE.rules.tests)
def test_the_pack_examples_hold(text: str, expected: str) -> None:
    # The engine runs the same examples (F1-07), so both sides agree.
    assert NORMALIZE(text) == expected


def test_numbers_are_written_in_words_up_to_999() -> None:
    assert NORMALIZE("0 7 19 20 40 99 100 110 999") == (
        "zero seven nineteen twenty forty ninety nine one hundred "
        "one hundred ten nine hundred ninety nine"
    )
    assert NORMALIZE("1000 cats") == "1000 cats"


def test_fillers_drop_and_repeats_count_once() -> None:
    assert NORMALIZE("Uh, I I have um a a car.") == "i have a car"
    assert NORMALIZE("I have a car, a car.") == "i have a car a car"
    plain = Normalizer(NormalizationRules(version=1, fillers=("uh",)))
    assert plain("uh the the cat") == "the the cat"


def test_rules_without_numbers_leave_digits() -> None:
    plain = Normalizer(NormalizationRules(version=1, punctuation=".", words={"i'm": "i am"}))
    assert plain("I'm 20.") == "i am 20"


def test_an_ending_alone_is_not_expanded() -> None:
    assert NORMALIZE("'d") == "d"

import pytest

from dilbaz_content.arpabet import to_ipa


@pytest.mark.parametrize(
    ("arpabet", "ipa"),
    [
        ("W AA1 CH", "/ˈwɑt͡ʃ/"),
        ("DH AH0", "/ðə/"),
        ("Y UW1", "/ˈju/"),
        ("AH0 B AW1 T", "/əˈbaʊt/"),
        ("AE1 P AH0 L", "/ˈæpəl/"),
        ("HH AE1 P IY0", "/ˈhæpi/"),
        # Maximal onset: "str" starts the stressed syllable.
        ("R IH0 S T R IH1 K T", "/ɹɪˈstɹɪkt/"),
        # "nd" cannot start a syllable, so only "d" moves.
        ("AH0 N D ER1", "/ənˈdɝ/"),
        # Secondary stress and the reduced r-coloured vowel.
        ("T EH2 L AH0 V IH1 ZH AH0 N", "/ˌtɛləˈvɪʒən/"),
        ("W AO1 T ER0", "/ˈwɔtɚ/"),
        # "ng" never starts a syllable.
        ("S IH1 NG ER0", "/ˈsɪŋɚ/"),
        ("IH0 N G L IH1 SH", "/ɪnˈɡlɪʃ/"),
        # Initialisms have two primaries in CMUdict; the first becomes secondary.
        ("T IY1 V IY1", "/ˌtiˈvi/"),
        ("OW1 K EY1", "/ˌoʊˈkeɪ/"),
    ],
)
def test_to_ipa(arpabet: str, ipa: str) -> None:
    assert to_ipa(arpabet) == ipa


def test_unknown_symbols_raise() -> None:
    with pytest.raises(KeyError):
        to_ipa("QQ1")

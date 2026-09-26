"""ARPAbet (CMUdict) to IPA for General American (docs/10-content-pipeline.md §4.1).

CMUdict gives the citation form with stress digits, so its first
pronunciation is a steadier US transcription than Wiktionary's accent tags.
Stress marks go before the syllable onset, found by the maximal onset
principle over English onsets.
"""

from __future__ import annotations

_VOWELS = {
    "AA": "ɑ",
    "AE": "æ",
    "AH": "ʌ",
    "AO": "ɔ",
    "AW": "aʊ",
    "AY": "aɪ",
    "EH": "ɛ",
    "ER": "ɝ",
    "EY": "eɪ",
    "IH": "ɪ",
    "IY": "i",
    "OW": "oʊ",
    "OY": "ɔɪ",
    "UH": "ʊ",
    "UW": "u",
}
# Unstressed AH and ER are the reduced vowels.
_REDUCED = {"AH": "ə", "ER": "ɚ"}

_CONSONANTS = {
    "B": "b",
    "CH": "t͡ʃ",
    "D": "d",
    "DH": "ð",
    "F": "f",
    "G": "ɡ",
    "HH": "h",
    "JH": "d͡ʒ",
    "K": "k",
    "L": "l",
    "M": "m",
    "N": "n",
    "NG": "ŋ",
    "P": "p",
    "R": "ɹ",
    "S": "s",
    "SH": "ʃ",
    "T": "t",
    "TH": "θ",
    "V": "v",
    "W": "w",
    "Y": "j",
    "Z": "z",
    "ZH": "ʒ",
}

# Consonant clusters that can begin an English syllable (besides single ones).
# fmt: off
_ONSETS = frozenset(
    {
        ("P", "R"), ("P", "L"), ("B", "R"), ("B", "L"), ("T", "R"), ("D", "R"),
        ("K", "R"), ("K", "L"), ("G", "R"), ("G", "L"), ("F", "R"), ("F", "L"),
        ("TH", "R"), ("SH", "R"), ("S", "P"), ("S", "T"), ("S", "K"), ("S", "M"),
        ("S", "N"), ("S", "L"), ("S", "W"), ("S", "F"), ("T", "W"), ("D", "W"),
        ("K", "W"), ("G", "W"), ("TH", "W"), ("P", "Y"), ("B", "Y"), ("F", "Y"),
        ("V", "Y"), ("K", "Y"), ("G", "Y"), ("M", "Y"), ("HH", "Y"),
        ("S", "P", "R"), ("S", "P", "L"), ("S", "T", "R"), ("S", "K", "R"),
        ("S", "K", "W"), ("S", "K", "Y"), ("S", "P", "Y"),
    }
)
# fmt: on
_NO_ONSET = frozenset({"NG"})


def _phone(symbol: str) -> tuple[str, int | None]:
    """(phone, stress) for 'AH0' → ('AH', 0); consonants have no stress."""
    if symbol[-1].isdigit():
        return symbol[:-1], int(symbol[-1])
    return symbol, None


def _onset_length(cluster: list[str]) -> int:
    """How many consonants at the end of [cluster] start the next syllable."""
    for size in range(min(3, len(cluster)), 1, -1):
        if tuple(cluster[-size:]) in _ONSETS:
            return size
    return 1 if cluster and cluster[-1] not in _NO_ONSET else 0


def to_ipa(pronunciation: str) -> str:
    """'W AA1 CH' → '/ˈwɑt͡ʃ/'; raises KeyError on an unknown symbol.

    CMUdict marks initialisms with two primary stresses ("T IY1 V IY1"); all
    but the last become secondary, as in /ˌtiˈvi/.
    """
    phones = [_phone(symbol) for symbol in pronunciation.split()]
    primaries = [index for index, (_, stress) in enumerate(phones) if stress == 1]
    for index in primaries[:-1]:
        phones[index] = (phones[index][0], 2)
    marks: dict[int, str] = {}
    cluster_start = 0
    for index, (_, stress) in enumerate(phones):
        if stress is None:
            continue
        if stress in (1, 2):
            cluster = [p for p, _ in phones[cluster_start:index]]
            onset = len(cluster) if cluster_start == 0 else _onset_length(cluster)
            marks[index - onset] = "ˈ" if stress == 1 else "ˌ"
        cluster_start = index + 1
    out: list[str] = []
    for index, (phone, stress) in enumerate(phones):
        out.append(marks.get(index, ""))
        if stress is None:
            out.append(_CONSONANTS[phone])
        elif stress == 0 and phone in _REDUCED:
            out.append(_REDUCED[phone])
        else:
            out.append(_VOWELS[phone])
    return "/" + "".join(out) + "/"

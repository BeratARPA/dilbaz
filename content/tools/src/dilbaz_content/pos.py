"""Part-of-speech tags of the lexicon (docs/11-language-packs.md §4).

Sources name parts of speech differently. The lexicon uses Universal
Dependencies style tags ("VERB"); conjunctions stay `CONJ` because the level
lists do not tell coordinating from subordinating ones.
"""

from __future__ import annotations

UNKNOWN = "X"
PHRASE = "PHRASE"

_LEVEL_LIST = {
    "noun": "NOUN",
    "verb": "VERB",
    "vern": "VERB",  # typo in Octanove 1.0
    "be-verb": "VERB",
    "do-verb": "VERB",
    "have-verb": "VERB",
    "modal auxiliary": "AUX",
    "adjective": "ADJ",
    "adverb": "ADV",
    "pronoun": "PRON",
    "preposition": "ADP",
    "determiner": "DET",
    "conjunction": "CONJ",
    "number": "NUM",
    "interjection": "INTJ",
    "infinitive-to": "PART",
}

_WIKTIONARY = {
    "noun": "NOUN",
    "verb": "VERB",
    "adj": "ADJ",
    "adv": "ADV",
    "pron": "PRON",
    "prep": "ADP",
    "postp": "ADP",
    "det": "DET",
    "article": "DET",
    "conj": "CONJ",
    "num": "NUM",
    "intj": "INTJ",
    "particle": "PART",
    "phrase": PHRASE,
    "prep_phrase": PHRASE,
    "adv_phrase": PHRASE,
}


def level_list_pos(raw: str) -> str:
    """Tag of a CEFR-J or Octanove part of speech; unknown ones become X."""
    return _LEVEL_LIST.get(raw.strip().lower(), UNKNOWN)


def wiktionary_pos(raw: str) -> str | None:
    """Tag of a Wiktextract part of speech; None for names, affixes and symbols."""
    return _WIKTIONARY.get(raw)

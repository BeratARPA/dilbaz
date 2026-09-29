"""S3 carrier candidates for word senses (docs/10-content-pipeline.md §4.3).

A carrier sentence contains the target sense (lemma and part of speech) and,
apart from it, only words and grammar at or below the target's level (docs/02
§4.4). A0 targets may use A1 words: A0 has too few words for natural sentences.
The best few candidates per target are kept for review.
"""

from __future__ import annotations

import heapq
import math
import re
from collections.abc import Iterable, Mapping
from dataclasses import dataclass

from pydantic import BaseModel, ConfigDict

from dilbaz_content.analysis import AnalyzedSentence, Token
from dilbaz_content.grammar_tags import LEXICAL_TRIGGERS, grammar_codes, outside_levels
from dilbaz_content.items import Level, WordSense, level_index
from dilbaz_content.lexicon import LexiconEntry
from dilbaz_content.select_step import A0_MAX_RANK

# Longest carrier per level, in words (docs/10 §5.1).
MAX_WORDS: dict[str, int] = {"A0": 6, "A1": 8, "A2": 12, "B1": 16, "B2": 22, "C1": 30, "C2": 30}
IDEAL_WORDS: dict[str, int] = {"A0": 4, "A1": 5, "A2": 7, "B1": 9, "B2": 11, "C1": 13, "C2": 13}
# Not levelled: names, numbers, punctuation.
UNLEVELLED_POS = frozenset({"PUNCT", "NUM", "PROPN", "SYM", "SPACE", "X"})
# spaCy tags be/have/do as AUX and days as proper nouns.
_POS_MATCH: dict[str, frozenset[str]] = {
    "VERB": frozenset({"VERB", "AUX"}),
    "NOUN": frozenset({"NOUN", "PROPN"}),
    "ADJ": frozenset({"ADJ"}),
    "ADV": frozenset({"ADV"}),
}
# spaCy calls "today" and "tomorrow" nouns while the level lists call them
# adverbs; a lemma with a single selected sense may cross between the two.
_CROSSING = frozenset({"NOUN", "PROPN", "ADV"})
# Quotes, brackets and the like make poor carriers.
_ODD_CHARACTERS = frozenset('"“”()[];:…/*_')
# A second sentence inside the text ("He looks tired. Probably …").
_INNER_BOUNDARY = re.compile(r"[.!?]\s+\S")
# Bonus per other selected sense a sentence carries, for at most three.
_REUSE_BONUS = 0.15
_REUSE_CAP = 3
# Penalty per level a carrier is above its target: the simplest context first.
_LEVEL_GAP_PENALTY = 0.25


@dataclass(frozen=True)
class WordLevels:
    """The level of each lemma, on the A0-C2 scale."""

    by_lemma: Mapping[str, Level]
    by_lemma_pos: Mapping[tuple[str, str], Level]
    rank: Mapping[str, int]

    def of(self, lemma: str, pos: str) -> Level | None:
        """Level of a token; None if the lemma is not in the lexicon.

        The level of the same part of speech wins; auxiliaries fall back to the
        verb (be, have, do), then any part of speech.
        """
        found = self.by_lemma_pos.get((lemma, pos))
        if found is None and pos == "AUX":
            found = self.by_lemma_pos.get((lemma, "VERB"))
        return found if found is not None else self.by_lemma.get(lemma)


def word_levels(lexicon: Iterable[LexiconEntry]) -> WordLevels:
    """Levels from the lexicon; A1 words among the 300 most frequent are A0 (docs/02 §2)."""

    def scale(cefr: str, rank: int | None) -> Level:
        if cefr == "A1" and rank is not None and rank <= A0_MAX_RANK:
            return "A0"
        return cefr  # type: ignore[return-value]

    by_lemma: dict[str, Level] = {}
    by_pos: dict[tuple[str, str], Level] = {}
    ranks: dict[str, int] = {}
    for entry in lexicon:
        forms = (entry.lemma, *entry.forms)
        if entry.rank is not None:
            ranks[entry.lemma] = entry.rank
        if entry.cefr is not None:
            by_lemma.setdefault(entry.lemma, scale(entry.cefr, entry.rank))
        for tag in entry.levels:
            by_pos.setdefault((entry.lemma, tag.pos), scale(tag.cefr, entry.rank))
        # Inflected forms that spaCy may leave as lemmas ("people") share the level.
        for form in forms[1:]:
            if entry.cefr is not None:
                by_lemma.setdefault(form, scale(entry.cefr, entry.rank))
    return WordLevels(by_lemma=by_lemma, by_lemma_pos=by_pos, rank=ranks)


class Candidate(BaseModel):
    """A possible carrier of one target, with the facts reviewers need."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    target: str
    sentence_id: int
    text: str
    author: str | None = None
    level: Level
    words: int
    native: bool
    names: int
    score: float
    grammar: tuple[str, ...] = ()
    turkish: tuple[str, ...]
    also_carries: tuple[str, ...] = ()


def allowed_level(target: Level) -> Level:
    """Highest level of the other words in a carrier of a [target]-level item."""
    return "A1" if target == "A0" else target


def token_levels(tokens: tuple[Token, ...], levels: WordLevels) -> list[Level | None] | None:
    """Level of each token (None for unlevelled ones); None if a word is unknown.

    The surface form is tried when the lemma is unknown: spaCy lemmatizes
    "clothes" to "clothe".
    """
    found: list[Level | None] = []
    for text, lemma, pos, _ in tokens:
        if pos in UNLEVELLED_POS:
            found.append(None)
            continue
        level = levels.of(lemma, pos) or levels.of(text.lower(), pos)
        if level is None:
            return None
        found.append(level)
    return found


def is_well_formed(text: str) -> bool:
    """One sentence, without quotes, brackets and similar marks."""
    return not _ODD_CHARACTERS.intersection(text) and not _INNER_BOUNDARY.search(text)


def hyphenated(tokens: tuple[Token, ...], index: int) -> bool:
    """The token is part of a hyphenated word ("well-known", "open-minded")."""
    before = index > 0 and tokens[index - 1][0] == "-"
    after = index + 1 < len(tokens) and tokens[index + 1][0] == "-"
    return before or after


class SenseMatcher:
    """Finds the selected senses a token stands for."""

    def __init__(self, senses: Iterable[WordSense]) -> None:
        self._by_lemma: dict[str, list[WordSense]] = {}
        for sense in senses:
            self._by_lemma.setdefault(sense.lemma, []).append(sense)

    def __call__(self, text: str, lemma: str, pos: str) -> list[WordSense]:
        found = self._by_lemma.get(lemma) or self._by_lemma.get(text.lower()) or []
        if not found and pos == "PROPN" and lemma.endswith("s"):
            # spaCy keeps plural proper nouns whole: "Mondays" has the lemma "mondays".
            found = self._by_lemma.get(lemma[:-1], [])
        same = [s for s in found if pos in _POS_MATCH.get(s.pos, frozenset({s.pos}))]
        if same or len(found) != 1:
            return same
        only = found[0]
        return [only] if only.pos in _CROSSING and pos in _CROSSING else []

    def hits(self, tokens: tuple[Token, ...]) -> dict[str, tuple[int, WordSense]]:
        """Sense key → (first token index, sense) of every sense in the sentence.

        A part of a hyphenated word ("well-known", "ten-year-old") does not
        stand for its own sense.
        """
        found: dict[str, tuple[int, WordSense]] = {}
        for index, (text, lemma, pos, _) in enumerate(tokens):
            if hyphenated(tokens, index):
                continue
            for sense in self(text, lemma, pos):
                found.setdefault(sense.key, (index, sense))
        return found


def pack_levels(
    levels: list[Level | None], hits: Mapping[str, tuple[int, WordSense]]
) -> list[Level | None]:
    """Levels where a word that is a selected sense counts at the sense's level.

    The pack teaches "hope" (a verb at B1 in CEFR-J) at A1; a sentence using it
    is as hard as the pack says.
    """
    adjusted = list(levels)
    for index, sense in hits.values():
        current = adjusted[index]
        if current is None or level_index(sense.level) < level_index(current):
            adjusted[index] = sense.level
    return adjusted


def carrier_level(
    sense: WordSense,
    index: int,
    levels: list[Level | None],
    codes: Iterable[str],
    grammar_levels: Mapping[str, Level],
    outside: Iterable[Level] = (),
) -> Level:
    """Level of a sentence as a carrier of [sense] at token [index].

    The other words, the grammar and the structures outside the pack
    ([outside]) count; a grammar point that the target itself triggers
    ("always": adverbs of frequency) does not.
    """
    others = [lv for i, lv in enumerate(levels) if i != index and lv is not None]
    others.extend(
        grammar_levels[code]
        for code in codes
        if code in grammar_levels and sense.lemma not in LEXICAL_TRIGGERS.get(code, frozenset())
    )
    others.extend(outside)
    return max((sense.level, *others), key=level_index)


def _score(
    sentence: AnalyzedSentence,
    target: Level,
    level: Level,
    words: int,
    others: int,
    names: int,
    levels: WordLevels,
) -> float:
    """Higher is better: native author, no names, ideal length, common words, reuse,
    and no more above the target's level than needed."""
    ranks = [
        levels.rank.get(lemma) for _, lemma, pos, _ in sentence.tokens if pos not in UNLEVELLED_POS
    ]
    known = [rank for rank in ranks if rank is not None]
    commonness = sum(math.log10(rank) for rank in known) / len(known) if known else 3.0
    return (
        (2.0 if sentence.native else 0.0)
        - 1.5 * names
        - 0.3 * abs(words - IDEAL_WORDS[level])
        - 0.4 * commonness
        + _REUSE_BONUS * min(others, _REUSE_CAP)
        - _LEVEL_GAP_PENALTY * max(0, level_index(level) - level_index(target))
    )


def find_candidates(
    sentences: Iterable[AnalyzedSentence],
    senses: Iterable[WordSense],
    levels: WordLevels,
    *,
    grammar_levels: Mapping[str, Level] | None = None,
    per_target: int = 3,
) -> dict[str, list[Candidate]]:
    """The best [per_target] carriers of each sense, best first.

    [grammar_levels] maps grammar codes to levels; a sentence whose grammar is
    above the target's level is not a candidate.
    """
    match = SenseMatcher(senses)
    grammar_map: Mapping[str, Level] = grammar_levels or {}
    heaps: dict[str, list[tuple[float, int, Candidate]]] = {}
    seen_texts: set[str] = set()
    for sentence in sentences:
        normalized = " ".join(sentence.text.lower().split())
        if normalized in seen_texts or not is_well_formed(sentence.text):
            continue
        seen_texts.add(normalized)
        levels_found = token_levels(sentence.tokens, levels)
        if levels_found is None:
            continue
        # First occurrence of each sense: "I watch you watch TV" is one candidate.
        hits = match.hits(sentence.tokens)
        if not hits:
            continue
        levels_found = pack_levels(levels_found, hits)
        codes = grammar_codes(sentence.tokens)
        outside = outside_levels(sentence.tokens)
        # Names are hard to say and translate; a selected sense ("Monday") is not one.
        hit_indexes = {index for index, _ in hits.values()}
        names = sum(
            pos == "PROPN" and i not in hit_indexes
            for i, (_, _, pos, _) in enumerate(sentence.tokens)
        )
        words = len(sentence.text.split())
        carried = sorted(hits)
        for index, sense in hits.values():
            allowed = allowed_level(sense.level)
            level = carrier_level(sense, index, levels_found, codes, grammar_map, outside)
            if level_index(level) > level_index(allowed) or words > MAX_WORDS[allowed]:
                continue
            candidate = Candidate(
                target=sense.key,
                sentence_id=sentence.id,
                text=sentence.text,
                author=sentence.author,
                level=level,
                words=words,
                native=sentence.native,
                names=names,
                score=round(
                    _score(sentence, sense.level, level, words, len(carried) - 1, names, levels),
                    3,
                ),
                grammar=codes,
                turkish=tuple(t.text for t in sentence.turkish),
                also_carries=tuple(key for key in carried if key != sense.key),
            )
            heap = heaps.setdefault(sense.key, [])
            entry = (candidate.score, -candidate.sentence_id, candidate)
            if len(heap) < per_target:
                heapq.heappush(heap, entry)
            elif entry[:2] > heap[0][:2]:
                heapq.heapreplace(heap, entry)
    return {
        key: [candidate for _, _, candidate in sorted(heap, key=lambda e: e[:2], reverse=True)]
        for key, heap in heaps.items()
    }

"""Rule-based grammar codes of an English sentence (docs/10-content-pipeline.md §4.4).

The rules read spaCy's Penn Treebank tags and lemmas and cover the grammar
points of en@1 that can be recognised reliably from them. A sentence gets a
code only when the rule is sure. Structures that en@1 does not teach (the
passive, conditionals, relative clauses…) are recognised separately: they are
not pack codes, but they make a sentence as hard as docs/02 §5 says they are.
"""

from __future__ import annotations

from itertools import pairwise

from dilbaz_content.analysis import Token
from dilbaz_content.items import Level

_BE_PRESENT = frozenset({"am", "is", "are", "'m", "'s", "'re"})
_BE_PAST = frozenset({"was", "were"})
_SUBJECT_PRONOUNS = frozenset({"i", "he", "she", "we", "they"})
_OBJECT_PRONOUNS = frozenset({"me", "him", "us", "them"})
_FREQUENCY = frozenset({"always", "usually", "often", "sometimes", "never"})
_QUANTIFIERS = frozenset({"some", "any", "much", "many"})
_DEMONSTRATIVES = frozenset({"this", "that", "these", "those"})
_CONJUNCTIONS = frozenset({"and", "but", "because"})
_LIKE_VERBS = frozenset({"like", "love", "hate", "enjoy"})
_TO_VERBS = frozenset({"want", "need", "decide", "hope", "try", "plan", "learn"})
_ING_VERBS = frozenset({"finish", "stop", "mind"})
_TIME_WORDS = frozenset(
    {
        "morning",
        "afternoon",
        "evening",
        "night",
        "weekend",
        "monday",
        "tuesday",
        "wednesday",
        "thursday",
        "friday",
        "saturday",
        "sunday",
        "o'clock",
        "january",
        "february",
        "march",
        "april",
        "may",
        "june",
        "july",
        "august",
        "september",
        "october",
        "november",
        "december",
        "summer",
        "winter",
        "spring",
        "autumn",
        "birthday",
    }
)
_PLACE_PREPOSITIONS = frozenset({"in", "on", "at", "under", "between", "behind"})
# Words that open a noun phrase after a preposition of place ("on the table").
_NOUN_STARTS = frozenset({"the", "a", "an", "my", "your", "his", "her", "our", "their"})


def _is_time(word: str) -> bool:
    return word in _TIME_WORDS or word.removesuffix("s") in _TIME_WORDS


def _words(tokens: tuple[Token, ...]) -> list[tuple[str, str, str]]:
    """(lowercased text, lemma, tag) of the tokens that are not punctuation."""
    return [(text.lower(), lemma, tag) for text, lemma, pos, tag in tokens if pos != "PUNCT"]


def _followed_by(
    words: list[tuple[str, str, str]], index: int, tags: set[str], within: int
) -> bool:
    return any(tag in tags for _, _, tag in words[index + 1 : index + 1 + within])


def _verb_codes(words: list[tuple[str, str, str]], question: bool) -> set[str]:
    codes: set[str] = set()
    for i, (text, lemma, tag) in enumerate(words):
        nxt = words[i + 1][0] if i + 1 < len(words) else ""
        if text in _BE_PRESENT and lemma == "be":
            going_to = nxt == "going" and i + 2 < len(words) and words[i + 2][0] == "to"
            if _followed_by(words, i, {"VBG"}, 3) and not going_to:
                codes.add("gp.present_continuous.now")
            elif not going_to and not _followed_by(words, i, {"VBN"}, 2):
                codes.add("gp.be.present")
                if nxt in {"not", "n't"}:
                    codes.add("gp.be.negative")
                if i == 0 and question:
                    codes.add("gp.be.questions")
        if text in _BE_PAST and lemma == "be":
            codes.add("gp.past_simple.be")
        if lemma == "do" and tag in {"VBZ", "VBP"} and _followed_by(words, i, {"VB"}, 3):
            # "Don't forget!" opens an imperative; "Don't you know?" is a question.
            if nxt in {"not", "n't"} and (i > 0 or question):
                codes.add("gp.present_simple.negative")
            elif i == 0 and question:
                codes.add("gp.present_simple.questions")
        if lemma == "do" and tag == "VBD" and _followed_by(words, i, {"VB"}, 3):
            codes.add("gp.past_simple.negative_questions")
        if tag in {"VBZ", "VBP"} and lemma not in {"be", "do", "have"}:
            codes.add("gp.present_simple.affirmative")
        if tag == "VBD" and lemma not in {"be", "do"}:
            regular = text.endswith("ed")
            codes.add("gp.past_simple.regular" if regular else "gp.past_simple.irregular")
        if text == "going" and nxt == "to" and _followed_by(words, i + 1, {"VB"}, 1):
            codes.add("gp.future.going_to")
        if text in {"will", "'ll"} and tag == "MD":
            codes.add("gp.future.will")
        if lemma == "can" and tag == "MD":
            codes.add("gp.can.ability")
        if text in {"would", "'d"} and "like" in (w[0] for w in words[i + 1 : i + 3]):
            codes.add("gp.would_like")
        if text in {"must", "should"} or (lemma == "have" and nxt == "to"):
            codes.add("gp.modals.obligation")
        if lemma == "have" and tag in {"VBZ", "VBP"} and nxt == "got":
            # "I've got to go" is obligation, like have to.
            got_to = i + 2 < len(words) and words[i + 2][0] == "to"
            codes.add("gp.modals.obligation" if got_to else "gp.have_got")
        elif (lemma == "have" and tag in {"VBZ", "VBP"} and _followed_by(words, i, {"VBN"}, 3)) or (
            text == "'s" and nxt == "been"
        ):
            codes.add("gp.present_perfect.experience")
        if lemma in _LIKE_VERBS and _followed_by(words, i, {"VBG"}, 1):
            codes.add("gp.like_ing")
        if (lemma in _TO_VERBS and nxt == "to") or (
            lemma in _ING_VERBS and _followed_by(words, i, {"VBG"}, 1)
        ):
            codes.add("gp.verb_patterns.to_ing")
    _, first_lemma, first_tag = words[0]
    negative = first_lemma == "do" and len(words) > 1 and words[1][0] == "n't"
    if not question and (first_tag == "VB" or negative):
        codes.add("gp.imperative")
    return codes


def _noun_phrase_codes(words: list[tuple[str, str, str]]) -> set[str]:
    codes: set[str] = set()
    texts = [text for text, _, _ in words]
    for i, (text, _, tag) in enumerate(words):
        nxt = texts[i + 1] if i + 1 < len(texts) else ""
        if text in {"a", "an"} and tag == "DT":
            codes.add("gp.articles.a_an")
        if text == "the":
            codes.add("gp.articles.the")
        if tag == "NNS":
            codes.add("gp.nouns.plural")
        if text in _DEMONSTRATIVES and tag == "DT":
            codes.add("gp.demonstratives")
        if tag == "PRP$":
            codes.add("gp.possessive.adjectives")
        if tag == "POS":
            codes.add("gp.possessive.s")
        if text in _SUBJECT_PRONOUNS and tag == "PRP":
            codes.add("gp.pronouns.subject")
        if text in _OBJECT_PRONOUNS and tag == "PRP":
            codes.add("gp.pronouns.object")
        if tag in {"JJR", "RBR"} or (text == "more" and "than" in texts[i + 1 :]):
            codes.add("gp.comparatives")
        if tag in {"JJS", "RBS"}:
            codes.add("gp.superlatives")
        if text in _FREQUENCY:
            codes.add("gp.adverbs.frequency")
        if text in _QUANTIFIERS or (text == "lot" and nxt == "of"):
            codes.add("gp.countable_uncountable")
        if text in _CONJUNCTIONS and tag in {"CC", "IN"}:
            codes.add("gp.conjunctions.basic")
        if text == "there" and tag == "EX":
            codes.add("gp.there_is_are")
        if (text == "years" and nxt == "old") or (text == "how" and nxt == "old"):
            codes.add("gp.age")
        next_tag = words[i + 1][2] if i + 1 < len(words) else ""
        # The head of "in the afternoon", "on Sundays".
        head = texts[i + 2] if nxt in _NOUN_STARTS and i + 2 < len(texts) else nxt
        if text in {"in", "on", "at"} and (_is_time(head) or (text == "at" and next_tag == "CD")):
            codes.add("gp.prepositions.time")
        elif text in _PLACE_PREPOSITIONS and tag == "IN" and nxt in _NOUN_STARTS:
            codes.add("gp.prepositions.place")
    if words[0][2] in {"WDT", "WP", "WRB"}:
        codes.add("gp.questions.wh")
    return codes


def grammar_codes(tokens: tuple[Token, ...]) -> tuple[str, ...]:
    """Sorted codes of the grammar points the sentence uses."""
    words = _words(tokens)
    if not words:
        return ()
    question = bool(tokens) and tokens[-1][0] == "?"
    codes = _verb_codes(words, question) | _noun_phrase_codes(words)
    if not question:
        codes.discard("gp.questions.wh")
    simple = {"gp.present_simple.affirmative", "gp.present_simple.negative"}
    if simple & codes and "gp.present_continuous.now" in codes:
        codes.add("gp.present_simple_vs_continuous")
    return tuple(sorted(codes))


# Structures outside en@1 and their level in docs/02 §5.
OUTSIDE_LEVELS: dict[str, Level] = {
    "passive": "B1",
    "used_to": "B1",
    "past_continuous": "B1",
    "modal_possibility": "B1",
    "would": "B1",
    "conditional": "B1",
    "wh_clause": "B1",
    "perfect_continuous": "B2",
    "past_perfect": "B2",
    "modal_perfect": "B2",
    "when_clause": "A2",
    "so_result": "A2",
}
# Words before a question word that still leave it at the start of its clause.
_LEADERS = frozenset({"and", "but", "so", "oh", "well", "now", "ok", "okay", "then", "hey"})
_WH_TAGS = frozenset({"WDT", "WP", "WP$", "WRB"})


def _clause_starts(tokens: tuple[Token, ...]) -> set[int]:
    """Indexes of the tokens that open a clause: the first one and those after a comma."""
    starts: set[int] = set()
    opening = True
    for index, (text, _, pos, _) in enumerate(tokens):
        if pos == "PUNCT":
            opening = opening or text == ","
            continue
        if opening:
            starts.add(index)
        opening = text.lower() in _LEADERS and opening
    return starts


def outside_structures(tokens: tuple[Token, ...]) -> tuple[str, ...]:
    """Sorted structures of the sentence that en@1 does not teach (see OUTSIDE_LEVELS)."""
    found: set[str] = set()
    question = bool(tokens) and tokens[-1][0] == "?"
    starts = _clause_starts(tokens)
    for i, (raw, lemma, _, tag) in enumerate(tokens):
        text = raw.lower()
        after = [t for t in tokens[i + 1 : i + 5] if t[2] != "PUNCT"]
        nxt = after[0][0].lower() if after else ""
        # be or get, then a past participle other than "been": "It was made", "I got lost".
        if lemma in {"be", "get"} and any(
            t[3] == "VBN" and t[2] == "VERB" and t[1] != "be" for t in after[:2]
        ):
            found.add("passive")
        if text == "used" and nxt == "to" and len(after) > 1 and after[1][3] == "VB":
            found.add("used_to")
        if text in {"was", "were"} and any(t[3] == "VBG" for t in after[:2]):
            found.add("past_continuous")
        if text == "been" and any(t[3] == "VBG" for t in after[:2]):
            found.add("perfect_continuous")
        if lemma == "have" and tag == "VBD" and any(t[3] == "VBN" for t in after[:2]):
            found.add("past_perfect")
        if tag == "MD":
            if text in {"might", "may", "could", "shall"}:
                found.add("modal_possibility")
            elif text in {"would", "'d"} and "like" not in (t[0].lower() for t in after[:2]):
                found.add("would")
            if any(a[1] == "have" and b[3] == "VBN" for a, b in pairwise(after)):
                found.add("modal_perfect")
        if text == "if" and tag == "IN":
            found.add("conditional")
        if tag in _WH_TAGS:
            if text == "when":
                if not (i in starts and question):
                    found.add("when_clause")
            elif i not in starts:
                found.add("wh_clause")
        if text == "so" and i > 0 and tokens[i - 1][0] == ",":
            found.add("so_result")
    return tuple(sorted(found))


def outside_levels(tokens: tuple[Token, ...]) -> tuple[Level, ...]:
    """Levels of the structures of the sentence that en@1 does not teach."""
    return tuple(OUTSIDE_LEVELS[name] for name in outside_structures(tokens))


# Grammar points recognised from particular words. A carrier of one of these
# words ("always") uses the point because of its target, so the point's level
# does not count against the sentence.
LEXICAL_TRIGGERS: dict[str, frozenset[str]] = {
    "gp.adverbs.frequency": _FREQUENCY,
    "gp.countable_uncountable": _QUANTIFIERS | {"lot"},
    "gp.conjunctions.basic": _CONJUNCTIONS,
    "gp.demonstratives": _DEMONSTRATIVES,
    "gp.like_ing": _LIKE_VERBS,
    "gp.verb_patterns.to_ing": _TO_VERBS | _ING_VERBS,
    "gp.can.ability": frozenset({"can"}),
    "gp.future.will": frozenset({"will"}),
    "gp.modals.obligation": frozenset({"must", "should", "have"}),
    "gp.would_like": frozenset({"would", "like"}),
    "gp.age": frozenset({"old", "year"}),
    "gp.there_is_are": frozenset({"there"}),
}

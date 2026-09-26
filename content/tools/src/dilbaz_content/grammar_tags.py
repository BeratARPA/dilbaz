"""Rule-based grammar codes of an English sentence (docs/10-content-pipeline.md §4.4).

The rules read spaCy's Penn Treebank tags and lemmas and cover the grammar
points of en@1 that can be recognised reliably from them. A sentence gets a
code only when the rule is sure; the curation file can add missing ones.
"""

from __future__ import annotations

from itertools import pairwise

from dilbaz_content.analysis import Token

_BE_PRESENT = frozenset({"am", "is", "are", "'m", "'s", "'re"})
_BE_PAST = frozenset({"was", "were"})
_SUBJECT_PRONOUNS = frozenset({"i", "he", "she", "we", "they"})
_OBJECT_PRONOUNS = frozenset({"me", "him", "us", "them"})
_FREQUENCY = frozenset({"always", "usually", "often", "sometimes", "never"})
_QUANTIFIERS = frozenset({"some", "any", "much", "many"})
_DEMONSTRATIVES = frozenset({"this", "that", "these", "those"})
_CONJUNCTIONS = frozenset({"and", "but", "because", "so"})
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
            if nxt in {"not", "n't"}:
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
        if text in {"would", "'d"} and nxt == "like":
            codes.add("gp.would_like")
        if text in {"must", "should"} or (lemma == "have" and nxt == "to"):
            codes.add("gp.modals.obligation")
        if lemma == "have" and tag in {"VBZ", "VBP"} and nxt == "got":
            codes.add("gp.have_got")
        elif lemma == "have" and tag in {"VBZ", "VBP"} and _followed_by(words, i, {"VBN"}, 3):
            codes.add("gp.present_perfect.experience")
        if lemma in _LIKE_VERBS and _followed_by(words, i, {"VBG"}, 1):
            codes.add("gp.like_ing")
        if (lemma in _TO_VERBS and nxt == "to") or (
            lemma in _ING_VERBS and _followed_by(words, i, {"VBG"}, 1)
        ):
            codes.add("gp.verb_patterns.to_ing")
    _, first_lemma, first_tag = words[0]
    if first_tag == "VB" or (first_lemma == "do" and len(words) > 1 and words[1][0] == "n't"):
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
        if text in {"in", "on", "at"} and (
            nxt in _TIME_WORDS or (text == "at" and next_tag == "CD")
        ):
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
    # "so" after a comma joins two clauses ("I was tired, so I went to bed").
    if any(a[0] == "," and b[0].lower() == "so" for a, b in pairwise(tokens)):
        codes.add("gp.conjunctions.basic")
    simple = {"gp.present_simple.affirmative", "gp.present_simple.negative"}
    if simple & codes and "gp.present_continuous.now" in codes:
        codes.add("gp.present_simple_vs_continuous")
    return tuple(sorted(codes))


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

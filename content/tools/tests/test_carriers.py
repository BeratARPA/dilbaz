from dilbaz_content.analysis import AnalyzedSentence, Token, Translation
from dilbaz_content.carriers import find_candidates, word_levels
from dilbaz_content.items import Provenance, WordSense
from dilbaz_content.lexicon import LevelTag, LexiconEntry


def lex(lemma: str, rank: int, levels: dict[str, str], forms: tuple[str, ...] = ()) -> LexiconEntry:
    return LexiconEntry(
        lemma=lemma,
        display=lemma,
        multiword=False,
        cefr=min(levels.values()),  # type: ignore[arg-type]
        levels=tuple(LevelTag(pos=p, cefr=c, source="cefrj") for p, c in levels.items()),  # type: ignore[arg-type]
        rank=rank,
        zipf=5.0,
        family_zipf=5.0,
        forms=forms,
        sources=("cefrj",),
    )


LEXICON = [
    lex("i", 8, {"PRON": "A1"}),
    lex("we", 29, {"PRON": "A1"}),
    lex("watch", 270, {"VERB": "A1", "NOUN": "A1"}, ("watches", "watched")),
    lex("tv", 676, {"NOUN": "A1"}),
    lex("every", 250, {"DET": "A1"}),
    lex("evening", 900, {"NOUN": "A1"}),
    lex("film", 600, {"NOUN": "A2"}),
    lex("documentary", 5000, {"NOUN": "B1"}),
    lex("be", 2, {"VERB": "A1"}),
    lex("can", 40, {"AUX": "A1"}),
    lex("new", 61, {"ADJ": "A1"}),
    lex("a", 5, {"DET": "A1"}),
    lex("my", 25, {"DET": "A1"}),
]

WATCH_V = WordSense(
    key="en.ws.watch.v.1",
    lemma="watch",
    pos="VERB",
    sense="look at something for some time",
    level="A0",
    rank=270,
    provenance=Provenance(source="dilbaz curation", license="own"),
)
WATCH_N = WATCH_V.model_copy(update={"key": "en.ws.watch.n.1", "pos": "NOUN", "level": "A1"})
EVENING = WATCH_V.model_copy(
    update={"key": "en.ws.evening.n.1", "lemma": "evening", "pos": "NOUN", "level": "A1"}
)


def sentence(sid: int, text: str, tokens: list[Token], *, native: bool = True) -> AnalyzedSentence:
    return AnalyzedSentence(
        id=sid,
        text=text,
        author="CK" if native else "someone",
        native=native,
        tokens=tuple(tokens),
        turkish=(Translation(id=sid + 1000, text=f"tr {sid}"),),
    )


WE_WATCH = sentence(
    1,
    "We watch TV every evening.",
    [
        ("We", "we", "PRON", "PRP"),
        ("watch", "watch", "VERB", "VBP"),
        ("TV", "tv", "NOUN", "NN"),
        ("every", "every", "DET", "DT"),
        ("evening", "evening", "NOUN", "NN"),
        (".", ".", "PUNCT", "."),
    ],
)


def test_word_levels_use_the_a0_rule_and_forms() -> None:
    levels = word_levels(LEXICON)
    assert levels.of("watch", "VERB") == "A0"
    assert levels.of("evening", "NOUN") == "A1"
    assert levels.of("watches", "NOUN") == "A0"
    assert levels.of("documentary", "NOUN") == "B1"
    assert levels.of("unknownword", "NOUN") is None


def test_auxiliaries_fall_back_to_the_verb_level() -> None:
    levels = word_levels(LEXICON)
    assert levels.of("be", "AUX") == "A0"
    assert levels.of("can", "AUX") == "A0"


def test_a_sentence_carries_every_sense_it_contains() -> None:
    found = find_candidates([WE_WATCH], [WATCH_V, WATCH_N, EVENING], word_levels(LEXICON))
    assert set(found) == {"en.ws.watch.v.1", "en.ws.evening.n.1"}
    candidate = found["en.ws.watch.v.1"][0]
    assert candidate.text == "We watch TV every evening."
    assert candidate.level == "A1"
    assert candidate.words == 5
    assert candidate.turkish == ("tr 1",)
    assert candidate.also_carries == ("en.ws.evening.n.1",)


def test_words_above_the_target_level_reject_the_sentence() -> None:
    hard = sentence(
        2,
        "I watch a documentary.",
        [
            ("I", "i", "PRON", "PRP"),
            ("watch", "watch", "VERB", "VBP"),
            ("a", "a", "DET", "DT"),
            ("documentary", "documentary", "NOUN", "NN"),
            (".", ".", "PUNCT", "."),
        ],
    )
    assert find_candidates([hard], [WATCH_V], word_levels(LEXICON)) == {}


def test_unknown_words_reject_the_sentence_but_names_do_not() -> None:
    unknown = sentence(
        3,
        "I watch zorbs.",
        [
            ("I", "i", "PRON", "PRP"),
            ("watch", "watch", "VERB", "VBP"),
            ("zorbs", "zorb", "NOUN", "NNS"),
        ],
    )
    named = sentence(
        4,
        "Tom can watch TV.",
        [
            ("Tom", "tom", "PROPN", "NNP"),
            ("can", "can", "AUX", "MD"),
            ("watch", "watch", "VERB", "VB"),
            ("TV", "tv", "NOUN", "NN"),
        ],
    )
    found = find_candidates([unknown, named], [WATCH_V], word_levels(LEXICON))
    assert [c.sentence_id for c in found["en.ws.watch.v.1"]] == [4]
    assert found["en.ws.watch.v.1"][0].names == 1


def test_long_sentences_and_odd_characters_are_skipped() -> None:
    long_tokens: list[Token] = [("watch", "watch", "VERB", "VB")] + [
        ("my", "my", "DET", "PRP$")
    ] * 8
    too_long = sentence(5, " ".join(["watch"] + ["my"] * 8), long_tokens)
    quoted = sentence(
        6,
        'I "watch" TV.',
        [("I", "i", "PRON", "PRP"), ("watch", "watch", "VERB", "VBP"), ("TV", "tv", "NOUN", "NN")],
    )
    assert find_candidates([too_long, quoted], [WATCH_V], word_levels(LEXICON)) == {}


def test_duplicate_texts_count_once_and_native_authors_rank_first() -> None:
    plain = [
        ("I", "i", "PRON", "PRP"),
        ("watch", "watch", "VERB", "VBP"),
        ("TV", "tv", "NOUN", "NN"),
    ]
    first = sentence(7, "I watch TV.", plain, native=False)
    duplicate = sentence(8, "i watch tv.", plain)
    native = sentence(9, "We watch TV.", [("We", "we", "PRON", "PRP"), *plain[1:]])
    found = find_candidates([first, duplicate, native], [WATCH_V], word_levels(LEXICON))
    assert [c.sentence_id for c in found["en.ws.watch.v.1"]] == [9, 7]


def test_only_the_best_few_are_kept() -> None:
    sentences = [
        sentence(10 + i, f"We watch TV {i}.", list(WE_WATCH.tokens[:3]), native=i % 2 == 0)
        for i in range(6)
    ]
    found = find_candidates(sentences, [WATCH_V], word_levels(LEXICON), per_target=2)
    kept = found["en.ws.watch.v.1"]
    assert len(kept) == 2
    assert all(c.native for c in kept)
    assert kept[0].score >= kept[1].score


def test_a_sense_twice_in_one_sentence_is_one_candidate() -> None:
    twice = sentence(
        20,
        "I watch you watch TV.",
        [
            ("I", "i", "PRON", "PRP"),
            ("watch", "watch", "VERB", "VBP"),
            ("you", "i", "PRON", "PRP"),
            ("watch", "watch", "VERB", "VB"),
            ("TV", "tv", "NOUN", "NN"),
        ],
    )
    found = find_candidates(
        [twice, twice.model_copy(update={"id": 21, "text": "I watch, you watch TV."})],
        [WATCH_V],
        word_levels(LEXICON),
    )
    assert [c.sentence_id for c in found["en.ws.watch.v.1"]] == [20, 21]


TODAY = WATCH_V.model_copy(
    update={"key": "en.ws.today.adv.1", "lemma": "today", "pos": "ADV", "level": "A0"}
)
MONDAY = WATCH_V.model_copy(
    update={"key": "en.ws.monday.n.1", "lemma": "monday", "pos": "NOUN", "level": "A1"}
)
CLOTHES = WATCH_V.model_copy(
    update={"key": "en.ws.clothes.n.1", "lemma": "clothes", "pos": "NOUN", "level": "A1"}
)
EXTRA = [
    lex("today", 200, {"ADV": "A1"}),
    lex("monday", 800, {"NOUN": "A1"}),
    lex("clothes", 900, {"NOUN": "A1"}),
    lex("on", 14, {"ADP": "A1"}),
    lex("wash", 950, {"VERB": "A1"}),
]


def test_tagging_differences_do_not_hide_senses() -> None:
    levels = word_levels([*LEXICON, *EXTRA])
    today = sentence(
        30,
        "I watch TV today.",
        [
            *WE_WATCH.tokens[:1],
            ("watch", "watch", "VERB", "VBP"),
            ("TV", "tv", "NOUN", "NN"),
            ("today", "today", "NOUN", "NN"),
        ],
    )
    monday = sentence(
        31,
        "I watch TV on Monday.",
        [
            ("I", "i", "PRON", "PRP"),
            ("watch", "watch", "VERB", "VBP"),
            ("TV", "tv", "NOUN", "NN"),
            ("on", "on", "ADP", "IN"),
            ("Monday", "monday", "PROPN", "NNP"),
        ],
    )
    clothes = sentence(
        32,
        "I wash my clothes.",
        [
            ("I", "i", "PRON", "PRP"),
            ("wash", "wash", "VERB", "VBP"),
            ("my", "my", "PRON", "PRP$"),
            ("clothes", "clothe", "NOUN", "NNS"),
        ],
    )
    found = find_candidates([today, monday, clothes], [TODAY, MONDAY, CLOTHES], levels)
    assert found["en.ws.today.adv.1"][0].sentence_id == 30
    assert found["en.ws.monday.n.1"][0].sentence_id == 31
    assert found["en.ws.clothes.n.1"][0].sentence_id == 32


def test_a_lemma_with_two_senses_keeps_the_part_of_speech() -> None:
    levels = word_levels(LEXICON)
    noun_use = sentence(
        33,
        "My watch is new.",
        [
            ("My", "my", "PRON", "PRP$"),
            ("watch", "watch", "NOUN", "NN"),
            ("is", "be", "AUX", "VBZ"),
            ("new", "new", "ADJ", "JJ"),
        ],
    )
    found = find_candidates([noun_use], [WATCH_V, WATCH_N], levels)
    assert set(found) == {"en.ws.watch.n.1"}


def test_two_sentences_in_one_text_are_skipped() -> None:
    two = sentence(34, "I watch TV. We watch TV.", [*WE_WATCH.tokens[:3]])
    assert find_candidates([two], [WATCH_V], word_levels(LEXICON)) == {}


def test_grammar_above_the_target_level_rejects_the_sentence() -> None:
    perfect = sentence(
        35,
        "We have watched TV.",
        [
            ("We", "we", "PRON", "PRP"),
            ("have", "have", "AUX", "VBP"),
            ("watched", "watch", "VERB", "VBN"),
            ("TV", "tv", "NOUN", "NN"),
        ],
    )
    levels = word_levels([*LEXICON, lex("have", 11, {"VERB": "A1"})])
    grammar = {"gp.present_perfect.experience": "A2"}
    assert find_candidates([perfect], [WATCH_V], levels, grammar_levels=grammar) == {}
    kept = find_candidates([perfect], [WATCH_V], levels)
    assert kept["en.ws.watch.v.1"][0].grammar == (
        "gp.present_perfect.experience",
        "gp.pronouns.subject",
    )


def test_a_target_that_triggers_a_grammar_point_is_not_held_back_by_it() -> None:
    always = WATCH_V.model_copy(
        update={"key": "en.ws.always.adv.1", "lemma": "always", "pos": "ADV", "level": "A1"}
    )
    levels = word_levels([*LEXICON, lex("always", 165, {"ADV": "A1"})])
    text = sentence(
        36,
        "We always watch TV.",
        [
            ("We", "we", "PRON", "PRP"),
            ("always", "always", "ADV", "RB"),
            ("watch", "watch", "VERB", "VBP"),
            ("TV", "tv", "NOUN", "NN"),
        ],
    )
    grammar = {"gp.adverbs.frequency": "A2"}
    found = find_candidates([text], [always, WATCH_V], levels, grammar_levels=grammar)
    assert set(found) == {"en.ws.always.adv.1"}


def test_selected_senses_count_at_their_pack_level() -> None:
    hope = WATCH_V.model_copy(
        update={"key": "en.ws.hope.v.1", "lemma": "hope", "pos": "VERB", "level": "A1"}
    )
    levels = word_levels([*LEXICON, lex("hope", 400, {"VERB": "B1"})])
    text = sentence(
        37,
        "I hope we watch TV.",
        [
            ("I", "i", "PRON", "PRP"),
            ("hope", "hope", "VERB", "VBP"),
            ("we", "we", "PRON", "PRP"),
            ("watch", "watch", "VERB", "VBP"),
            ("TV", "tv", "NOUN", "NN"),
        ],
    )
    found = find_candidates([text], [hope, WATCH_V], levels)
    assert set(found) == {"en.ws.hope.v.1", "en.ws.watch.v.1"}
    assert found["en.ws.watch.v.1"][0].level == "A1"


def test_a_part_of_a_hyphenated_word_is_not_its_sense() -> None:
    compound = sentence(
        38,
        "We watch-proof TV.",
        [
            ("We", "we", "PRON", "PRP"),
            ("watch", "watch", "VERB", "VB"),
            ("-", "-", "PUNCT", "HYPH"),
            ("proof", "proof", "ADJ", "JJ"),
            ("TV", "tv", "NOUN", "NN"),
        ],
    )
    levels = word_levels([*LEXICON, lex("proof", 3000, {"ADJ": "A1"})])
    assert find_candidates([compound], [WATCH_V], levels) == {}


def test_a_selected_proper_noun_is_not_a_name() -> None:
    levels = word_levels([*LEXICON, *EXTRA])
    tokens = [
        ("I", "i", "PRON", "PRP"),
        ("watch", "watch", "VERB", "VBP"),
        ("TV", "tv", "NOUN", "NN"),
        ("on", "on", "ADP", "IN"),
    ]
    monday = sentence(39, "I watch TV on Monday.", [*tokens, ("Monday", "monday", "PROPN", "NNP")])
    tom = sentence(40, "I watch TV on Tom.", [*tokens, ("Tom", "tom", "PROPN", "NNP")])
    found = find_candidates([monday, tom], [WATCH_V, MONDAY], levels)
    by_id = {c.sentence_id: c for c in found["en.ws.watch.v.1"]}
    assert by_id[39].names == 0
    assert by_id[40].names == 1
    assert by_id[39].score > by_id[40].score


def test_a_carrier_at_the_target_level_ranks_first() -> None:
    # The same words; only the tag of "watch" raises the second one to A1.
    easy = sentence(
        41, "We watch.", [("We", "we", "PRON", "PRP"), ("watch", "watch", "VERB", "VB")]
    )
    harder = sentence(
        42, "We watch!", [("We", "we", "PRON", "PRP"), ("watch", "watch", "VERB", "VBP")]
    )
    grammar = {"gp.present_simple.affirmative": "A1"}
    found = find_candidates([harder, easy], [WATCH_V], word_levels(LEXICON), grammar_levels=grammar)
    ranked = found["en.ws.watch.v.1"]
    assert [(c.sentence_id, c.level) for c in ranked] == [(41, "A0"), (42, "A1")]
    # 0.25 for the level gap, 0.3 because the ideal A1 length is longer.
    assert round(ranked[0].score - ranked[1].score, 3) == 0.55


def test_structures_outside_the_pack_reject_the_sentence() -> None:
    passive = sentence(
        43,
        "TV is watched.",
        [
            ("TV", "tv", "NOUN", "NN"),
            ("is", "be", "AUX", "VBZ"),
            ("watched", "watch", "VERB", "VBN"),
        ],
    )
    assert find_candidates([passive], [WATCH_V], word_levels(LEXICON)) == {}

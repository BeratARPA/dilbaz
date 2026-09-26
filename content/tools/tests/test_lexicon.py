import pytest

from dilbaz_content.lexicon import (
    MAX_SENSES_PER_POS,
    LexiconEntry,
    LexiconInputs,
    build_lexicon,
    lexicon_words,
    zipf,
)
from dilbaz_content.readers.level_lists import LevelEntry
from dilbaz_content.readers.ngsl import RankedLemma
from dilbaz_content.readers.wiktextract import WikiEntry, WikiSense, WikiSound

from sample_sources import fake_frequency


def level(display: str, pos: str, cefr: str, source: str = "cefrj", *spellings: str) -> LevelEntry:
    return LevelEntry(
        display=display,
        spellings=(display.lower(), *spellings),
        pos=pos,
        cefr=cefr,
        source=source,
    )


def ranked(lemma: str, rank: int | None) -> RankedLemma:
    return RankedLemma(lemma=lemma, rank=rank, sfi=None, per_million=None)


def inputs(**changes: object) -> LexiconInputs:
    base: dict[str, object] = {
        "level_entries": (),
        "ngsl": (),
        "ngsl_spoken": (),
        "pronunciations": {},
        "wiki": {},
    }
    return LexiconInputs(**(base | changes))  # type: ignore[arg-type]


def by_lemma(entries: tuple[LexiconEntry, ...]) -> dict[str, LexiconEntry]:
    return {entry.lemma: entry for entry in entries}


def build(**changes: object) -> dict[str, LexiconEntry]:
    return by_lemma(build_lexicon(inputs(**changes), fake_frequency).entries)


def test_zipf_matches_the_wordfreq_scale() -> None:
    assert zipf(1e-3) == 6.0
    assert zipf(0.0) == 0.0


def test_the_lowest_level_wins_per_part_of_speech_and_overall() -> None:
    watch = build(
        level_entries=(
            level("watch", "VERB", "A1"),
            level("watch", "NOUN", "A2"),
            level("watch", "NOUN", "C1", "octanove"),
        )
    )["watch"]
    assert watch.cefr == "A1"
    assert [(t.pos, t.cefr, t.source) for t in watch.levels] == [
        ("VERB", "A1", "cefrj"),
        ("NOUN", "A2", "cefrj"),
    ]
    assert watch.pos == ("VERB", "NOUN")


def test_spelling_variants_join_the_first_spelling() -> None:
    lemmas = build(
        level_entries=(level("color", "NOUN", "A1", "cefrj", "colour"),),
        ngsl=(ranked("colour", 900),),
        wiki={"color": (WikiEntry(word="color", pos="NOUN", forms=("colors", "colour")),)},
    )
    assert set(lemmas) == {"color"}
    color = lemmas["color"]
    assert color.spellings == ("colour",)
    assert color.forms == ("colors",)
    assert color.ngsl_rank == 900
    assert "ngsl" in color.sources
    # The British spelling counts towards the family frequency.
    assert color.family_zipf == zipf(0.0001 + 0.00005)


def test_a_spelling_that_is_its_own_headword_stays_separate() -> None:
    lemmas = build(
        level_entries=(level("a.m.", "ADV", "A1", "cefrj", "am"), level("am", "VERB", "A1"))
    )
    assert set(lemmas) == {"a.m.", "am"}
    assert lemmas["a.m."].spellings == ()


def test_phrase_spellings_do_not_inflate_a_word() -> None:
    # "onto/on to": wordfreq's estimate for "on to" is huge, so it is left out.
    lemmas = build(level_entries=(level("onto", "ADP", "A2", "cefrj", "on to"),))
    assert lemmas["onto"].family_zipf == zipf(fake_frequency("onto"))
    assert lemmas["onto"].spellings == ("on to",)


def test_lemmas_only_in_ngsl_are_kept_without_a_level() -> None:
    the = build(ngsl=(ranked("the", 1),), ngsl_spoken=(ranked("the", 2),))["the"]
    assert the.cefr is None
    assert (the.ngsl_rank, the.ngsl_spoken_rank) == (1, 2)
    assert the.sources == ("ngsl", "ngsl_spoken", "wordfreq")


def test_list_members_without_a_rank_still_count_as_members() -> None:
    true = build(ngsl_spoken=(ranked("true", None),))["true"]
    assert true.ngsl_spoken_rank is None
    assert "ngsl_spoken" in true.sources


def test_rank_follows_family_frequency_with_shared_forms_split() -> None:
    wiki = {
        "see": (WikiEntry(word="see", pos="VERB", forms=("saw", "seen")),),
        "saw": (WikiEntry(word="saw", pos="NOUN"),),
    }
    entries = build_lexicon(
        inputs(
            level_entries=(level("see", "VERB", "A1"), level("saw", "NOUN", "B2")),
            ngsl=(ranked("the", 1),),
            wiki=wiki,
        ),
        fake_frequency,
    ).entries
    lemmas = by_lemma(entries)
    assert [e.lemma for e in entries] == ["the", "see", "saw"]
    assert [e.rank for e in entries] == [1, 2, 3]
    # "saw" is a headword itself, so it keeps its frequency for itself.
    assert lemmas["see"].family_zipf == zipf(0.0008 + 0.0001)
    assert lemmas["saw"].family_zipf == zipf(0.0002)
    assert lemmas["see"].forms == ("saw", "seen")


def test_a_form_shared_by_two_families_is_split() -> None:
    wiki = {
        "lie": (WikiEntry(word="lie", pos="VERB", forms=("lay", "lain")),),
        "lay": (WikiEntry(word="lay", pos="VERB", forms=("laid",)),),
        "left": (WikiEntry(word="left", pos="ADJ"),),
        "leave": (WikiEntry(word="leave", pos="VERB", forms=("left",)),),
        "go": (WikiEntry(word="go", pos="VERB", forms=("went",)),),
        "wend": (WikiEntry(word="wend", pos="VERB", forms=("went",)),),
    }
    lemmas = build(
        level_entries=(level("go", "VERB", "A1"), level("wend", "VERB", "C2")),
        wiki=wiki,
        pronunciations={},
    )
    # "went" is no headword and belongs to both families: each gets half.
    assert lemmas["go"].family_zipf == zipf(fake_frequency("go") + 0.0003 / 2)
    assert lemmas["wend"].family_zipf == zipf(0.0003 / 2)


def test_forms_come_from_the_listed_parts_of_speech() -> None:
    wiki = {
        "i": (
            WikiEntry(word="I", pos="PRON"),
            # The letter I: its plural "is" must not join the pronoun's family.
            WikiEntry(word="I", pos="NOUN", forms=("Is", "I's")),
        ),
        "watch": (
            WikiEntry(word="watch", pos="VERB", forms=("watched", "Watches")),
            WikiEntry(word="watch", pos="NOUN", forms=("watches",)),
        ),
    }
    lemmas = build(
        level_entries=(level("I", "PRON", "A1"), level("watch", "VERB", "A1")), wiki=wiki
    )
    assert lemmas["i"].forms == ()
    assert lemmas["watch"].forms == ("watched", "watches")


def test_forms_fall_back_to_all_entries_when_no_part_of_speech_matches() -> None:
    wiki = {"okay": (WikiEntry(word="okay", pos="VERB", forms=("okayed",)),)}
    lemmas = build(level_entries=(level("okay", "ADJ", "A1"),), wiki=wiki)
    assert lemmas["okay"].forms == ("okayed",)


def test_hyphenated_words_count_as_phrases() -> None:
    lemmas = build(
        level_entries=(
            level("part-time", "ADJ", "B1"),
            level("takeoff", "NOUN", "B1", "cefrj", "take-off"),
        )
    )
    assert lemmas["part-time"].multiword
    assert lemmas["part-time"].rank is None
    # A hyphenated spelling does not add wordfreq's phrase estimate either.
    assert lemmas["takeoff"].family_zipf == zipf(fake_frequency("takeoff"))


def test_phrases_have_no_rank_and_come_last() -> None:
    entries = build_lexicon(
        inputs(level_entries=(level("according to", "ADP", "A2"), level("watch", "VERB", "A1"))),
        fake_frequency,
    ).entries
    assert [e.lemma for e in entries] == ["watch", "according to"]
    phrase = entries[-1]
    assert phrase.multiword
    assert phrase.rank is None
    assert phrase.family_zipf is None
    assert phrase.zipf == zipf(0.00009)
    assert phrase.arpabet == ()


def test_us_ipa_comes_from_cmudict() -> None:
    sounds = (WikiSound(ipa="/jə/", tags=("General-American",)),)
    you = build(
        level_entries=(level("you", "PRON", "A1"),),
        pronunciations={"you": ("Y UW1", "Y UH0")},
        wiki={"you": (WikiEntry(word="you", pos="PRON", sounds=sounds),)},
    )["you"]
    assert you.ipa_us == "/ˈju/"
    assert you.arpabet == ("Y UW1", "Y UH0")


def test_without_cmudict_wiktionary_gives_the_us_ipa() -> None:
    sounds = (
        WikiSound(ipa="/wɒtʃ/", tags=("Received-Pronunciation",)),
        WikiSound(ipa="/wɒtʃ/"),
        WikiSound(ipa="/wɑtʃ/"),
    )
    watch = build(
        level_entries=(level("watch", "VERB", "A1"),),
        wiki={"watch": (WikiEntry(word="watch", pos="VERB", sounds=sounds),)},
    )["watch"]
    assert (watch.ipa_us, watch.ipa_uk) == ("/wɑtʃ/", "/wɒtʃ/")


def test_untagged_ipa_is_general_only_when_no_accent_is_tagged() -> None:
    general = (WikiSound(ipa="/ði/ [ðɪj]"), WikiSound(ipa="[ðə]"))
    the = build(
        level_entries=(level("the", "DET", "A1"),),
        wiki={"the": (WikiEntry(word="the", pos="DET", sounds=general),)},
    )["the"]
    assert the.ipa_uk == "/ði/"
    us_only = (WikiSound(ipa="/a/"), WikiSound(ipa="/b/", tags=("General-American",)))
    x = build(
        level_entries=(level("x", "NOUN", "A1"),),
        wiki={"x": (WikiEntry(word="x", pos="NOUN", sounds=us_only),)},
    )["x"]
    assert (x.ipa_us, x.ipa_uk) == ("/b/", None)


def test_exact_spelling_wins_over_other_case() -> None:
    wiki = {
        "tv": (
            WikiEntry(word="TV", pos="NOUN", senses=(WikiSense(gloss="Television."),)),
            WikiEntry(word="tv", pos="NOUN", senses=(WikiSense(gloss="Lowercase."),)),
        )
    }
    tv = build(level_entries=(level("TV", "NOUN", "A1"),), wiki=wiki)["tv"]
    assert tv.display == "TV"
    assert [s.gloss for s in tv.senses] == ["Television."]


def test_senses_of_listed_parts_of_speech_come_first_and_are_capped() -> None:
    many = tuple(WikiSense(gloss=f"noun {i}") for i in range(MAX_SENSES_PER_POS + 3))
    wiki = {
        "watch": (
            WikiEntry(word="watch", pos="NOUN", senses=many),
            WikiEntry(word="watch", pos="VERB", senses=(WikiSense(gloss="To look at."),)),
        )
    }
    watch = build(level_entries=(level("watch", "VERB", "A1"),), wiki=wiki)["watch"]
    assert watch.senses[0].gloss == "To look at."
    assert sum(s.pos == "NOUN" for s in watch.senses) == MAX_SENSES_PER_POS
    assert watch.pos == ("VERB", "NOUN")


def test_sources_record_every_contributor() -> None:
    watch = build(
        level_entries=(level("watch", "VERB", "A1"),),
        ngsl=(ranked("watch", 412),),
        pronunciations={"watch": ("W AA1 CH",)},
        wiki={"watch": (WikiEntry(word="watch", pos="VERB"),)},
    )["watch"]
    assert watch.sources == ("cefrj", "cmudict", "ngsl", "wiktextract", "wordfreq")
    assert watch.arpabet == ("W AA1 CH",)


def test_inflection_headwords_fold_into_their_lemma() -> None:
    wiki = {
        "be": (WikiEntry(word="be", pos="VERB", forms=("is", "was", "been")),),
        "is": (
            WikiEntry(word="is", pos="VERB"),
            # Other parts of speech do not matter (the plural of the letter i).
            WikiEntry(word="is", pos="NOUN", forms=("iss",)),
        ),
        "been": (WikiEntry(word="been", pos="VERB"),),
        "find": (WikiEntry(word="find", pos="VERB", forms=("found",)),),
        # "found" (to establish) has inflections of its own, so it is a lemma.
        "found": (WikiEntry(word="found", pos="VERB", forms=("founded",)),),
        "late": (WikiEntry(word="late", pos="ADV", forms=("later",)),),
        "later": (WikiEntry(word="later", pos="ADV"),),
    }
    lexicon = build_lexicon(
        inputs(
            level_entries=(
                level("be", "VERB", "A1"),
                level("is", "VERB", "A1"),
                level("been", "VERB", "A2"),
                level("find", "VERB", "A1"),
                level("found", "VERB", "B2"),
                level("late", "ADV", "A1"),
                level("later", "ADV", "A1"),
            ),
            wiki=wiki,
        ),
        fake_frequency,
    )
    lemmas = by_lemma(lexicon.entries)
    assert dict(lexicon.merged) == {"been": "be", "is": "be"}
    assert set(lemmas) == {"be", "find", "found", "late", "later"}
    be = lemmas["be"]
    assert be.forms == ("been", "is", "was")
    assert be.cefr == "A1"
    assert be.family_zipf == zipf(0.006 + 0.01 + 0.004)
    assert lemmas["found"].cefr == "B2"
    # Comparatives such as "later" are words of their own.
    assert lemmas["later"].cefr == "A1"


def test_an_inflection_of_two_lemmas_is_not_folded() -> None:
    wiki = {
        "lie": (WikiEntry(word="lie", pos="VERB", forms=("lay",)),),
        "lay": (WikiEntry(word="lay", pos="VERB"),),
        "lye": (WikiEntry(word="lye", pos="VERB", forms=("lay",)),),
    }
    lexicon = build_lexicon(
        inputs(
            level_entries=(
                level("lie", "VERB", "B1"),
                level("lay", "VERB", "B1"),
                level("lye", "VERB", "C2"),
            ),
            wiki=wiki,
        ),
        fake_frequency,
    )
    assert dict(lexicon.merged) == {}


def test_clitic_headwords_are_left_to_normalization() -> None:
    lemmas = build(level_entries=(level("'s", "VERB", "A1"), level("be", "VERB", "A1")))
    assert set(lemmas) == {"be"}


def test_lexicon_words_include_display_forms_and_spellings() -> None:
    words = lexicon_words(
        inputs(
            level_entries=(level("TV", "NOUN", "A1"), level("color", "NOUN", "A1", "c", "colour")),
            ngsl=(ranked("the", 1),),
        )
    )
    assert words == {"tv", "TV", "color", "colour", "the"}


@pytest.mark.parametrize("order", [0, 1])
def test_output_is_deterministic(order: int) -> None:
    entries = (level("b", "NOUN", "A1"), level("a", "NOUN", "A1"))
    built = build_lexicon(
        inputs(level_entries=entries if order else tuple(reversed(entries))), fake_frequency
    ).entries
    assert [e.lemma for e in built] == ["a", "b"]

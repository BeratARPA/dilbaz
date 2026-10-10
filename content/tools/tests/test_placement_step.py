import json
import random
from collections import Counter
from pathlib import Path

import pytest
from typer.testing import CliRunner

from dilbaz_content.cli import app
from dilbaz_content.lexicon import LevelTag, LexiconEntry
from dilbaz_content.placement_step import (
    PlacementError,
    PseudowordCheck,
    XlexCuration,
    dictionary_words,
    load_curation,
    one_letter_away,
    pseudoword_candidates,
    pseudowords,
    real_words,
    run_placement,
)

from sample_sources import write_wiki_dump

SMALL = {"bands": 2, "band_size": 10, "per_band": 2}


def entry(lemma: str, rank: int | None, pos: str = "NOUN", **fields: object) -> LexiconEntry:
    return LexiconEntry(
        lemma=lemma,
        display=str(fields.pop("display", lemma)),
        multiword=bool(fields.pop("multiword", False)),
        cefr="A1",
        levels=(LevelTag(pos=pos, cefr="A1", source="cefrj"),),  # type: ignore[arg-type]
        rank=rank,
        zipf=5.0,
        family_zipf=5.0,
        sources=("cefrj",),
    )


def lexicon() -> list[LexiconEntry]:
    """Two bands of ten ranks; every band has some words the bank must skip."""
    words = [entry(f"word{chr(97 + i)}", i + 1) for i in range(20)]
    words[0] = entry("monday", 1, display="Monday")
    words[1] = entry("the", 2, pos="DET")
    words[2] = entry("go", 3, pos="VERB")
    words[11] = entry("hotel", 12)
    return [*words, entry("ice cream", None, multiword=True), entry("far", 30)]


def test_real_words_fill_every_band_and_version_evenly() -> None:
    curation = XlexCuration(exclude={"hotel": "otel"})

    items, excluded, eligible = real_words(lexicon(), curation, **SMALL)

    assert excluded == Counter(
        {"name": 1, "function word": 1, "short or not a word": 1, "curated": 1}
    )
    assert eligible == {1: 7, 2: 9}
    per = Counter((item.version, item.band) for item in items)
    assert per == {(v, b): 2 for v in "ABC" for b in (1, 2)}
    words = {item.word for item in items}
    assert not words & {"monday", "the", "go", "hotel", "far", "ice cream"}


def test_versions_get_ranks_in_rotating_order() -> None:
    items, _, _ = real_words(lexicon(), XlexCuration(), **SMALL)

    band_two = [item.version for item in items if item.band == 2]
    # Sorted by rank, the six words are dealt A B C, then B C A.
    assert band_two == ["A", "B", "C", "B", "C", "A"]


def test_excluding_a_word_replaces_only_that_word() -> None:
    before, _, _ = real_words(lexicon(), XlexCuration(), **SMALL)
    dropped = next(item.word for item in before if item.band == 1)

    after, _, _ = real_words(lexicon(), XlexCuration(exclude={dropped: "test"}), **SMALL)

    assert len({i.word for i in before} - {i.word for i in after}) == 1
    assert dropped not in {item.word for item in after}


def test_a_band_without_enough_words_stops_the_build() -> None:
    with pytest.raises(PlacementError, match="band 1"):
        real_words(lexicon(), XlexCuration(), bands=2, band_size=10, per_band=3)


def test_candidates_look_like_short_english_words() -> None:
    stream = pseudoword_candidates(random.Random(1))
    candidates = [next(stream) for _ in range(200)]

    assert all(4 <= len(word) <= 9 and word.isalpha() and word.islower() for word in candidates)
    assert len(set(candidates)) > 150


def test_one_letter_away_inserts_deletes_and_substitutes() -> None:
    near = set(one_letter_away("cat"))

    assert {"cart", "at", "cut", "scat"} <= near
    assert "cat" not in near
    assert "dog" not in near


@pytest.mark.parametrize(
    ("word", "reason"),
    [
        ("house", "a word by frequency"),
        ("kalem", "a word of the learners' language"),
        ("zorbly", "in a dictionary"),
        ("hoose", "one letter from a common word"),
        ("floodous", "starts or ends with a common word"),
        ("glopen", "starts or ends with a common word"),
        ("snacock", "rude"),
        ("brastle", None),
    ],
)
def test_pseudoword_checks(word: str, reason: str | None) -> None:
    frequencies = {("house", "en"): 1e-4, ("kalem", "tr"): 1e-5}
    check = PseudowordCheck(
        l1="tr",
        l2="en",
        frequency=lambda w, lang: frequencies.get((w, lang), 0.0),
        dictionary=frozenset({"zorbly"}),
        common=frozenset({"house", "flood", "open"}),
    )

    assert check(word) == reason


def test_pseudowords_skip_rejected_candidates() -> None:
    curation = XlexCuration(seed=7)
    first, _, _ = pseudowords(lambda word: None, curation, per_version=2)
    rejected = first[0].word

    items, tried, reasons = pseudowords(
        lambda word: None, XlexCuration(seed=7, reject_pseudowords=(rejected,)), per_version=2
    )

    assert len(items) == 6
    assert all(item.is_pseudo and item.band is None for item in items)
    assert rejected not in {item.word for item in items}
    assert reasons == Counter({"rejected in the curation": 1})
    assert tried == 7


def test_pseudowords_give_up_after_too_many_candidates() -> None:
    with pytest.raises(PlacementError, match="pseudowords"):
        pseudowords(lambda word: "never", XlexCuration(), max_tries=50)


def test_dictionary_words_are_cached(tmp_path: Path) -> None:
    dump = write_wiki_dump(
        tmp_path / "2026-01-01" / "dump.jsonl.gz",
        [
            {"word": "Zorbly", "lang_code": "en"},
            {"word": "ice cream", "lang_code": "en"},
            {"word": "kalem", "lang_code": "tr"},
        ],
    )
    cmudict = tmp_path / "cmudict.dict"
    cmudict.write_text("glim G L IH1 M\n", encoding="utf-8")
    work = tmp_path / "work"

    assert dictionary_words(cmudict, dump, work, l2="en") == {"zorbly", "glim"}
    dump.unlink()
    # The second call reads the cache.
    assert dictionary_words(cmudict, dump, work, l2="en") == {"zorbly", "glim"}


def test_the_bank_is_written_from_the_lexicon_and_curation(tmp_path: Path) -> None:
    work = tmp_path / "work"
    work.mkdir()
    # 5,000 distinct lemmas "waaa", "waab" …
    names = ["w" + "".join(chr(97 + i // 26**k % 26) for k in (2, 1, 0)) for i in range(5000)]
    words = [entry(name, rank) for rank, name in enumerate(names, start=1)]
    (work / "lexicon.en.jsonl").write_text(
        "".join(w.model_dump_json() + "\n" for w in words), encoding="utf-8"
    )
    curation = tmp_path / "curation" / "en"
    curation.mkdir(parents=True)
    (curation / "xlex.yaml").write_text("seed: 3\nexclude: {waaa: test}\n", encoding="utf-8")

    report = run_placement(
        tmp_path,
        l1="tr",
        l2="en",
        frequency=lambda word, lang: 0.0,
        dictionary=frozenset,
        common=frozenset,
    )

    assert report.items == 360
    assert report.excluded == {"curated": 1}
    rows = [
        json.loads(line)
        for line in (tmp_path / "packs" / "en" / "placement" / "xlex.jsonl").open(encoding="utf-8")
    ]
    assert Counter(row["version"] for row in rows) == {"A": 120, "B": 120, "C": 120}
    assert Counter(row["band"] for row in rows if row["version"] == "A") == {
        1: 20,
        2: 20,
        3: 20,
        4: 20,
        5: 20,
        None: 20,
    }
    assert (work / "placement.en.report.json").is_file()


def test_missing_curation_means_the_defaults(tmp_path: Path) -> None:
    assert load_curation(tmp_path / "none.yaml") == XlexCuration()


def test_the_placement_command_reports_a_small_lexicon(content_dir: Path) -> None:
    runner = CliRunner()
    assert runner.invoke(app, ["ingest", "--content-dir", str(content_dir)]).exit_code == 0
    assert runner.invoke(app, ["lexicon", "--content-dir", str(content_dir)]).exit_code == 0

    result = runner.invoke(app, ["placement", "--content-dir", str(content_dir)])

    assert result.exit_code == 1
    assert "eligible words" in result.output

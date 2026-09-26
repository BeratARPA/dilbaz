import json
from pathlib import Path

import pytest

from dilbaz_content.readers.cmudict import read_cmudict
from dilbaz_content.readers.level_lists import read_level_list
from dilbaz_content.readers.ngsl import read_stats
from dilbaz_content.readers.wiktextract import extract_subset, read_subset, slim_entry

from sample_sources import (
    CEFRJ,
    CMUDICT,
    NGSL_STATS,
    OCTANOVE,
    SPOKEN_STATS,
    WIKI_LINES,
    write_wiki_dump,
)


def write(tmp_path: Path, name: str, text: str) -> Path:
    path = tmp_path / name
    path.write_bytes(text.encode("utf-8"))
    return path


def test_ngsl_stats_are_sorted_by_rank(tmp_path: Path) -> None:
    rows = read_stats(write(tmp_path, "stats.csv", NGSL_STATS))
    assert [r.lemma for r in rows] == ["the", "be", "watch", "colour"]
    assert rows[2].rank == 412
    assert rows[2].sfi == pytest.approx(70.1)


def test_spoken_stats_have_a_short_header(tmp_path: Path) -> None:
    rows = read_stats(write(tmp_path, "spoken.csv", SPOKEN_STATS))
    assert [(r.lemma, r.rank) for r in rows] == [("be", 1), ("watch", 300), ("true", None)]


def test_rows_without_statistics_keep_the_lemma(tmp_path: Path) -> None:
    rows = read_stats(write(tmp_path, "spoken.csv", SPOKEN_STATS))
    true = rows[-1]
    assert (true.lemma, true.rank, true.sfi, true.per_million) == ("true", None, None, None)


def test_stats_reject_an_unexpected_header(tmp_path: Path) -> None:
    with pytest.raises(ValueError, match="unexpected header"):
        read_stats(write(tmp_path, "bad.csv", "word,count\nthe,1\n"))


def test_level_lists_split_spellings_and_map_parts_of_speech(tmp_path: Path) -> None:
    entries = read_level_list(write(tmp_path, "cefrj.csv", CEFRJ), "cefrj")
    color = next(e for e in entries if e.display == "color")
    assert color.spellings == ("color", "colour")
    assert color.key == "color"
    assert (color.pos, color.cefr, color.source) == ("NOUN", "A1", "cefrj")
    tv = next(e for e in entries if e.display == "TV")
    assert tv.key == "tv"
    assert next(e for e in entries if e.key == "be").pos == "VERB"
    assert next(e for e in entries if e.key == "according to").pos == "ADP"


def test_octanove_typos_and_trailing_spaces_are_cleaned(tmp_path: Path) -> None:
    entries = read_level_list(write(tmp_path, "octanove.csv", OCTANOVE), "octanove")
    laud = next(e for e in entries if e.key == "laud")
    assert (laud.display, laud.pos, laud.cefr) == ("laud", "VERB", "C2")


def test_level_lists_reject_unknown_levels_and_columns(tmp_path: Path) -> None:
    with pytest.raises(ValueError, match="unknown level"):
        read_level_list(write(tmp_path, "a.csv", "headword,pos,CEFR\nwatch,verb,Z9\n"), "x")
    with pytest.raises(ValueError, match="missing columns"):
        read_level_list(write(tmp_path, "b.csv", "word,pos\nwatch,verb\n"), "x")


def test_cmudict_keeps_alternates_in_order(tmp_path: Path) -> None:
    pronunciations = read_cmudict(write(tmp_path, "cmudict.dict", CMUDICT))
    assert pronunciations["watch"] == ("W AA1 CH", "W AO1 CH")
    assert pronunciations["aalborg"] == ("AO1 L B AO0 R G",)
    assert ";;;" not in "".join(pronunciations)


def test_slim_entry_keeps_teachable_senses_ipa_and_inflections() -> None:
    noun = slim_entry(json.dumps(WIKI_LINES[0]))
    assert noun is not None
    assert noun.pos == "NOUN"
    assert [s.gloss for s in noun.senses] == ["A portable timepiece."]
    assert [s.ipa for s in noun.sounds] == ["/wɒtʃ/", "/wɑtʃ/"]
    verb = slim_entry(json.dumps(WIKI_LINES[1]))
    assert verb is not None
    assert verb.forms == ("watches", "watched")
    assert verb.senses[0].tags == ("transitive",)
    # An entry with only form-of senses keeps them, so the word still has a gloss.
    form_of = slim_entry(json.dumps(WIKI_LINES[5]))
    assert form_of is not None
    assert [s.gloss for s in form_of.senses] == ["simple past of see"]
    assert slim_entry(json.dumps(WIKI_LINES[3])) is None


def test_slim_entry_keeps_only_grammatical_inflections() -> None:
    line = {
        "word": "get",
        "pos": "verb",
        "lang_code": "en",
        "forms": [
            {"form": "gets", "tags": ["present", "singular", "third-person"]},
            {"form": "got", "tags": ["past"]},
            {"form": "gotten", "tags": ["participle", "past", "US"]},
            {"form": "gitten", "tags": ["dialectal", "participle", "past"]},
            {"form": "'s", "tags": ["contraction", "present", "third-person"]},
            {"form": "get", "tags": ["infinitive"]},
            {"form": "have got", "tags": ["present"]},
        ],
    }
    entry = slim_entry(json.dumps(line))
    assert entry is not None
    assert entry.forms == ("gets", "got", "gotten")


def test_extract_subset_keeps_only_english_entries_of_the_words(tmp_path: Path) -> None:
    dump = write_wiki_dump(tmp_path / "dump.jsonl.gz", WIKI_LINES)
    out = tmp_path / "subset.jsonl"

    kept = extract_subset(dump, frozenset({"watch", "see", "TV", "tv", "Watch"}), out)

    subset = read_subset(out)
    assert kept == 5
    assert sorted(subset) == ["see", "tv", "watch"]
    assert [e.pos for e in subset["watch"]] == ["NOUN", "VERB"]
    assert [e.word for e in subset["tv"]] == ["TV", "tv"]
    assert not out.with_name("subset.jsonl.part").exists()


def test_extract_subset_reports_progress(tmp_path: Path) -> None:
    lines = [{"word": f"w{i}", "pos": "noun", "lang_code": "en"} for i in range(200_000)]
    dump = write_wiki_dump(tmp_path / "big.jsonl.gz", lines)
    seen: list[int] = []

    extract_subset(dump, frozenset({"w5"}), tmp_path / "out.jsonl", seen.append)

    assert seen == [100_000, 200_000]

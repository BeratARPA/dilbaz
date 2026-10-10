import bz2
from collections.abc import Iterable, Iterator
from pathlib import Path

from dilbaz_content.analysis import (
    Token,
    analyze_pairs,
    cache_is_fresh,
    read_analysis,
)
from dilbaz_content.readers.tatoeba import (
    ENG_SENTENCES,
    ENG_TUR_LINKS,
    ENG_USERS,
    TUR_SENTENCES,
    native_speakers,
    read_pairs,
)

NULL = "\\N"


def write_bz2(path: Path, rows: list[list[str]]) -> None:
    with bz2.open(path, "wt", encoding="utf-8") as stream:
        for row in rows:
            stream.write("\t".join(row) + "\n")


def write_snapshot(directory: Path) -> Path:
    directory.mkdir(parents=True, exist_ok=True)
    write_bz2(
        directory / ENG_SENTENCES,
        [
            ["1", "eng", "I watch TV every evening.", "CK", NULL, "2012-01-01"],
            ["2", "eng", "Tom is here.", "someone", NULL, NULL],
            ["3", "eng", "This sentence has no Turkish translation at all.", "CK", NULL, NULL],
            [
                "4",
                "eng",
                "A very long sentence that has far too many words to be used.",
                "CK",
                "",
                "",
            ],
            ["5", "eng", "Where are you?", NULL, NULL, NULL],
        ],
    )
    write_bz2(
        directory / TUR_SENTENCES,
        [
            ["10", "tur", "Her akşam televizyon izlerim.", "turkuaz", NULL, NULL],
            ["11", "tur", "Tom burada.", "turkuaz", NULL, NULL],
            ["12", "tur", "Nerdesin?", NULL, NULL, NULL],
            ["13", "tur", "Çok uzun bir cümle.", "turkuaz", NULL, NULL],
        ],
    )
    write_bz2(directory / ENG_TUR_LINKS, [["1", "10"], ["2", "11"], ["4", "13"], ["5", "12"]])
    write_bz2(
        directory / ENG_USERS,
        [["eng", "5", "CK", ""], ["eng", "3", "someone", ""], ["eng", "5", NULL, ""]],
    )
    return directory


def test_native_speakers_skip_anonymous_rows(tmp_path: Path) -> None:
    snapshot = write_snapshot(tmp_path / "snap")
    assert native_speakers(snapshot / ENG_USERS) == {"CK"}


def test_read_pairs_keeps_short_translated_sentences(tmp_path: Path) -> None:
    snapshot = write_snapshot(tmp_path / "snap")

    pairs = list(read_pairs(snapshot, max_words=8))

    assert [p.english.id for p in pairs] == [1, 2, 5]
    first = pairs[0]
    assert first.native
    assert [t.text for t in first.turkish] == ["Her akşam televizyon izlerim."]
    assert not pairs[1].native
    assert pairs[2].english.author is None
    assert not pairs[2].native
    assert pairs[2].turkish[0].author is None


class FakeAnalyzer:
    name = "fake:1"

    def __init__(self) -> None:
        self.calls = 0

    def analyze(self, texts: Iterable[str]) -> Iterator[tuple[Token, ...]]:
        self.calls += 1
        for text in texts:
            words = text.rstrip(".?!").split()
            yield tuple(
                (w, w.lower(), "PROPN" if w[0].isupper() and i else "NOUN", "NN")
                for i, w in enumerate(words)
            )


def test_analyze_pairs_round_trips(tmp_path: Path) -> None:
    snapshot = write_snapshot(tmp_path / "snap")
    out = tmp_path / "analysis.jsonl.gz"
    analyzer = FakeAnalyzer()

    count = analyze_pairs(read_pairs(snapshot, max_words=8), analyzer, out)

    records = list(read_analysis(out))
    assert count == 3
    assert [r.id for r in records] == [1, 2, 5]
    assert records[0].tokens[0] == ("I", "i", "NOUN", "NN")
    assert records[0].native
    assert records[1].turkish[0].text == "Tom burada."
    assert not out.with_name(out.name + ".part").exists()


def test_cache_is_fresh_compares_the_whole_meta(tmp_path: Path) -> None:
    meta_path = tmp_path / "meta.json"
    assert not cache_is_fresh(meta_path, {"a": 1})
    meta_path.write_text('{"a": 1}', encoding="utf-8")
    assert cache_is_fresh(meta_path, {"a": 1})
    assert not cache_is_fresh(meta_path, {"a": 2})

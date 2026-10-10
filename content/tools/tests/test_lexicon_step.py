import json
from datetime import UTC, datetime
from pathlib import Path

import pytest

from dilbaz_content import lexicon_step
from dilbaz_content.ingest import ingest_source
from dilbaz_content.lexicon import LexiconEntry
from dilbaz_content.lexicon_step import (
    LEXICON_FILE,
    REPORT_FILE,
    SUBSET_FILE,
    run_lexicon,
)
from dilbaz_content.sources import REGISTRY_FILE, Registry, load_registry

from sample_sources import fake_frequency

NOW = datetime(2026, 9, 26, 12, 0, tzinfo=UTC)


def ingested(content_dir: Path) -> Registry:
    registry = load_registry(content_dir / REGISTRY_FILE)
    for source in registry.sources:
        ingest_source(source, content_dir / "sources", NOW)
    return registry


def read_entries(content_dir: Path) -> dict[str, LexiconEntry]:
    lines = (content_dir / "work" / LEXICON_FILE).read_text(encoding="utf-8").splitlines()
    entries = [LexiconEntry.model_validate_json(line) for line in lines]
    return {entry.lemma: entry for entry in entries}


def test_builds_the_lexicon_and_report_from_snapshots(content_dir: Path) -> None:
    registry = ingested(content_dir)

    report = run_lexicon(registry, content_dir, fake_frequency)

    entries = read_entries(content_dir)
    assert set(entries) == {
        "the",
        "be",
        "true",
        "watch",
        "color",
        "tv",
        "according to",
        "see",
        "saw",
        "laud",
    }
    watch = entries["watch"]
    assert watch.cefr == "A1"
    assert watch.ngsl_rank == 412
    assert watch.ngsl_spoken_rank == 300
    assert watch.arpabet == ("W AA1 CH", "W AO1 CH")
    assert (watch.ipa_us, watch.ipa_uk) == ("/ˈwɑt͡ʃ/", "/wɒtʃ/")
    assert watch.forms == ("watched", "watches")
    assert entries["according to"].rank is None
    assert entries["color"].spellings == ("colour",)
    assert entries["tv"].display == "TV"
    assert entries["the"].rank == 1

    assert report.entries == len(entries)
    assert report.by_level["A1"] == 5
    assert report.multiword == 1
    saved = json.loads((content_dir / "work" / REPORT_FILE).read_text(encoding="utf-8"))
    assert saved["entries"] == report.entries
    uses = {use["id"]: use for use in saved["sources"]}
    assert uses["wordfreq"]["snapshot"] == "package"
    assert uses["wiktextract"]["snapshot"] == "2026-09-26"
    assert "cmudict.dict" in uses["cmudict"]["sha256"]


def test_the_wiktionary_subset_is_reused_until_its_inputs_change(
    content_dir: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    registry = ingested(content_dir)
    run_lexicon(registry, content_dir, fake_frequency)
    subset = content_dir / "work" / SUBSET_FILE
    assert subset.is_file()

    def refuse(*_: object) -> int:
        raise AssertionError("the subset should have been reused")

    monkeypatch.setattr(lexicon_step, "extract_subset", refuse)
    run_lexicon(registry, content_dir, fake_frequency)

    cefrj = content_dir / "sources" / "cefrj" / "1" / "cefrj-vocabulary-profile-1.5.csv"
    cefrj.write_text(cefrj.read_text(encoding="utf-8") + "zebra,noun,A2,,,\n", encoding="utf-8")
    with pytest.raises(AssertionError, match="reused"):
        run_lexicon(registry, content_dir, fake_frequency)


def test_a_missing_snapshot_asks_for_ingest(content_dir: Path) -> None:
    registry = load_registry(content_dir / REGISTRY_FILE)
    with pytest.raises(FileNotFoundError, match="dilbaz-content ingest"):
        run_lexicon(registry, content_dir, fake_frequency)

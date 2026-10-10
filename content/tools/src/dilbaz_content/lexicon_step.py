"""Runs S1 on the ingested snapshots and writes `work/lexicon.en.*`.

Reads the latest snapshot of each source, refreshes the Wiktionary subset
only when the dump or the word list changed, builds the lexicon and records
which source files it came from.
"""

from __future__ import annotations

import hashlib
import json
from collections import Counter
from collections.abc import Callable, Iterable
from dataclasses import replace
from pathlib import Path

from pydantic import BaseModel, ConfigDict

from dilbaz_content.ingest import latest_snapshot, read_snapshot, verify_package
from dilbaz_content.lexicon import Lexicon, LexiconInputs, build_lexicon, lexicon_words
from dilbaz_content.readers.cmudict import read_cmudict
from dilbaz_content.readers.level_lists import read_level_list
from dilbaz_content.readers.ngsl import read_stats
from dilbaz_content.readers.wiktextract import SLIM_VERSION, extract_subset, read_subset
from dilbaz_content.sources import Registry

LEXICON_FILE = "lexicon.en.jsonl"
REPORT_FILE = "lexicon.en.report.json"
SUBSET_FILE = "wiktextract.en.subset.jsonl"
SUBSET_META_FILE = "wiktextract.en.subset.meta.json"

# The files each source contributes to S1 (names as in content/sources.yaml).
NGSL_STATS = "NGSL_1.2_stats.csv"
SPOKEN_STATS = "NGSL-Spoken_1.2_stats.csv"
CEFRJ_LIST = "cefrj-vocabulary-profile-1.5.csv"
OCTANOVE_LIST = "octanove-vocabulary-profile-c1c2-1.0.csv"
CMUDICT = "cmudict.dict"
WIKTEXTRACT_DUMP = "kaikki.org-dictionary-English.jsonl.gz"


class SourceUse(BaseModel):
    """Which snapshot of a source a build used."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    id: str
    version: str
    snapshot: str
    sha256: dict[str, str]


class LexiconReport(BaseModel):
    """`lexicon.en.report.json`: counts and provenance of one build."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    entries: int
    by_level: dict[str, int]
    multiword: int
    with_ipa_us: int
    with_ipa_uk: int
    with_arpabet: int
    with_senses: int
    ngsl: int
    ngsl_spoken: int
    top_5000_with_level: int
    # Headwords folded into their lemma, e.g. "is" → "be" (docs/10 §4.1).
    merged: dict[str, str]
    sources: tuple[SourceUse, ...]


def summarize(lexicon: Lexicon, sources: tuple[SourceUse, ...]) -> LexiconReport:
    """Counts that show how complete the lexicon is."""
    items = list(lexicon.entries)
    levels = Counter(entry.cefr or "none" for entry in items)
    return LexiconReport(
        entries=len(items),
        by_level=dict(sorted(levels.items())),
        multiword=sum(entry.multiword for entry in items),
        with_ipa_us=sum(entry.ipa_us is not None for entry in items),
        with_ipa_uk=sum(entry.ipa_uk is not None for entry in items),
        with_arpabet=sum(bool(entry.arpabet) for entry in items),
        with_senses=sum(bool(entry.senses) for entry in items),
        ngsl=sum("ngsl" in entry.sources for entry in items),
        ngsl_spoken=sum("ngsl_spoken" in entry.sources for entry in items),
        top_5000_with_level=sum(
            e.rank is not None and e.rank <= 5000 and e.cefr is not None for e in items
        ),
        merged=dict(lexicon.merged),
        sources=sources,
    )


def _source_file(registry: Registry, sources_dir: Path, source_id: str, name: str) -> Path:
    path = latest_snapshot(sources_dir, registry.get(source_id)) / name
    if not path.is_file():
        raise FileNotFoundError(f"{path} is missing, run `dilbaz-content ingest {source_id}`")
    return path


def _uses(registry: Registry, sources_dir: Path, ids: Iterable[str]) -> tuple[SourceUse, ...]:
    uses: list[SourceUse] = []
    for source_id in ids:
        source = registry.get(source_id)
        if not source.files:
            uses.append(
                SourceUse(
                    id=source.id, version=verify_package(source), snapshot="package", sha256={}
                )
            )
            continue
        directory = latest_snapshot(sources_dir, source)
        snapshot = read_snapshot(directory)
        checksums = {f.name: f.sha256 for f in snapshot.files} if snapshot else {}
        uses.append(
            SourceUse(
                id=source.id, version=source.version, snapshot=directory.name, sha256=checksums
            )
        )
    return tuple(uses)


def _subset(
    dump: Path, words: frozenset[str], work_dir: Path, progress: Callable[[int], None] | None
) -> Path:
    """The Wiktionary subset for [words]; rebuilt only if its inputs changed."""
    subset = work_dir / SUBSET_FILE
    meta_path = work_dir / SUBSET_META_FILE
    meta = {
        "dump": dump.parent.name + "/" + dump.name,
        "slim_version": SLIM_VERSION,
        "words_sha256": hashlib.sha256("\n".join(sorted(words)).encode()).hexdigest(),
    }
    if (
        subset.is_file()
        and meta_path.is_file()
        and json.loads(meta_path.read_text(encoding="utf-8")) == meta
    ):
        return subset
    extract_subset(dump, words, subset, progress)
    meta_path.write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")
    return subset


def run_lexicon(
    registry: Registry,
    content_dir: Path,
    frequency: Callable[[str], float],
    progress: Callable[[int], None] | None = None,
) -> LexiconReport:
    """Builds `work/lexicon.en.jsonl` and its report from the latest snapshots."""
    sources_dir = content_dir / "sources"
    work_dir = content_dir / "work"
    work_dir.mkdir(parents=True, exist_ok=True)

    def path(source_id: str, name: str) -> Path:
        return _source_file(registry, sources_dir, source_id, name)

    partial = LexiconInputs(
        level_entries=(
            *read_level_list(path("cefrj", CEFRJ_LIST), "cefrj"),
            *read_level_list(path("octanove", OCTANOVE_LIST), "octanove"),
        ),
        ngsl=read_stats(path("ngsl", NGSL_STATS)),
        ngsl_spoken=read_stats(path("ngsl_spoken", SPOKEN_STATS)),
        pronunciations=read_cmudict(path("cmudict", CMUDICT)),
        wiki={},
    )
    subset = _subset(
        path("wiktextract", WIKTEXTRACT_DUMP), lexicon_words(partial), work_dir, progress
    )
    lexicon = build_lexicon(replace(partial, wiki=read_subset(subset)), frequency)
    with (work_dir / LEXICON_FILE).open("w", encoding="utf-8", newline="\n") as sink:
        for entry in lexicon.entries:
            sink.write(entry.model_dump_json() + "\n")
    ids = ("ngsl", "ngsl_spoken", "cefrj", "octanove", "cmudict", "wiktextract", "wordfreq")
    report = summarize(lexicon, _uses(registry, sources_dir, ids))
    (work_dir / REPORT_FILE).write_text(report.model_dump_json(indent=2) + "\n", encoding="utf-8")
    return report

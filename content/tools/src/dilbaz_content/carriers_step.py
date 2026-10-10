"""Runs S3 on the latest Tatoeba snapshot: analysis cache and carrier candidates.

The analysis of every short English sentence with a Turkish translation is
cached in `work/`; the candidates of each selected word sense are written to
`work/carriers.<l2>.candidates.jsonl` for review.
"""

from __future__ import annotations

import json
from collections.abc import Callable
from pathlib import Path

from pydantic import BaseModel, ConfigDict

from dilbaz_content.analysis import (
    CACHE_VERSION,
    Analyzer,
    analyze_pairs,
    cache_is_fresh,
    read_analysis,
)
from dilbaz_content.carriers import MAX_WORDS, Candidate, find_candidates, word_levels
from dilbaz_content.ingest import latest_snapshot
from dilbaz_content.items import GrammarPoint, Level, WordSense
from dilbaz_content.readers.tatoeba import read_pairs
from dilbaz_content.select_step import read_lexicon
from dilbaz_content.sources import Registry

ANALYSIS_FILE = "tatoeba.en.analysis.jsonl.gz"
ANALYSIS_META_FILE = "tatoeba.en.analysis.meta.json"
# Carriers are A2 at most in en@1; longer sentences are never candidates.
MAX_CANDIDATE_WORDS = MAX_WORDS["A2"]


class TargetCandidates(BaseModel):
    """One line of the candidates file."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    target: str
    lemma: str
    pos: str
    level: str
    sense: str
    candidates: tuple[Candidate, ...]


def read_word_senses(path: Path) -> tuple[WordSense, ...]:
    """Items of `packs/<l2>/items/word_senses.jsonl`."""
    if not path.is_file():
        raise FileNotFoundError(f"{path} is missing, run `dilbaz-content select`")
    with path.open(encoding="utf-8") as stream:
        return tuple(WordSense.model_validate_json(line) for line in stream if line.strip())


def read_grammar_levels(path: Path) -> dict[str, Level]:
    """code → level of the selected grammar points; empty before S2 has any."""
    if not path.is_file():
        return {}
    with path.open(encoding="utf-8") as stream:
        points = [GrammarPoint.model_validate_json(line) for line in stream if line.strip()]
    return {point.code: point.level for point in points}


def ensure_analysis(
    registry: Registry,
    content_dir: Path,
    analyzer: Callable[[], Analyzer],
    progress: Callable[[int], None] | None = None,
) -> Path:
    """The analysis cache of the latest Tatoeba snapshot, built if stale."""
    snapshot = latest_snapshot(content_dir / "sources", registry.get("tatoeba"))
    work = content_dir / "work"
    work.mkdir(parents=True, exist_ok=True)
    cache = work / ANALYSIS_FILE
    meta_path = work / ANALYSIS_META_FILE
    built = analyzer()
    meta: dict[str, object] = {
        "snapshot": snapshot.name,
        "analyzer": built.name,
        "version": CACHE_VERSION,
        "max_words": MAX_CANDIDATE_WORDS,
    }
    if cache.is_file() and cache_is_fresh(meta_path, meta):
        return cache
    analyze_pairs(read_pairs(snapshot, max_words=MAX_CANDIDATE_WORDS), built, cache, progress)
    meta_path.write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")
    return cache


def run_carriers(
    registry: Registry,
    content_dir: Path,
    *,
    l2: str,
    analyzer: Callable[[], Analyzer],
    per_target: int = 3,
    progress: Callable[[int], None] | None = None,
) -> tuple[TargetCandidates, ...]:
    """Writes `work/carriers.<l2>.candidates.jsonl`; senses without candidates come first."""
    cache = ensure_analysis(registry, content_dir, analyzer, progress)
    lexicon = read_lexicon(content_dir / "work" / f"lexicon.{l2}.jsonl")
    senses = read_word_senses(content_dir / "packs" / l2 / "items" / "word_senses.jsonl")
    levels = word_levels(lexicon)
    grammar = read_grammar_levels(content_dir / "packs" / l2 / "items" / "grammar_points.jsonl")
    found = find_candidates(
        read_analysis(cache), senses, levels, grammar_levels=grammar, per_target=per_target
    )
    lines = tuple(
        TargetCandidates(
            target=sense.key,
            lemma=sense.lemma,
            pos=sense.pos,
            level=sense.level,
            sense=sense.sense,
            candidates=tuple(found.get(sense.key, ())),
        )
        for sense in senses
    )
    ordered = sorted(lines, key=lambda line: len(line.candidates))
    out = content_dir / "work" / f"carriers.{l2}.candidates.jsonl"
    with out.open("w", encoding="utf-8", newline="\n") as sink:
        for line in ordered:
            sink.write(line.model_dump_json() + "\n")
    return tuple(ordered)

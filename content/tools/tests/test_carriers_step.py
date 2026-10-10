import json
from datetime import UTC, datetime
from pathlib import Path

import pytest

from dilbaz_content.carriers_step import (
    ANALYSIS_FILE,
    TargetCandidates,
    ensure_analysis,
    run_carriers,
)
from dilbaz_content.ingest import ingest_source
from dilbaz_content.items import Provenance, WordSense
from dilbaz_content.lexicon import LevelTag, LexiconEntry
from dilbaz_content.sources import REGISTRY_FILE, Registry, load_registry

from test_tatoeba_analysis import FakeAnalyzer, write_snapshot

NOW = datetime(2026, 9, 27, 12, 0, tzinfo=UTC)


def tatoeba_content(tmp_path: Path) -> tuple[Path, Registry]:
    upstream = write_snapshot(tmp_path / "upstream")
    root = tmp_path / "content"
    root.mkdir()
    files = "\n".join(
        f"      - name: {path.name}\n        url: {path.as_uri()}"
        for path in sorted(upstream.iterdir())
    )
    (root / REGISTRY_FILE).write_text(
        "sources:\n"
        "  - id: tatoeba\n"
        "    name: Tatoeba\n"
        '    version: "weekly"\n'
        "    rolling: true\n"
        "    license: CC BY 2.0 FR\n"
        "    attribution: Tatoeba contributors\n"
        "    files:\n" + files + "\n",
        encoding="utf-8",
    )
    registry = load_registry(root / REGISTRY_FILE)
    ingest_source(registry.get("tatoeba"), root / "sources", NOW)
    return root, registry


def entry(lemma: str, pos: str) -> LexiconEntry:
    return LexiconEntry(
        lemma=lemma,
        display=lemma,
        multiword=False,
        cefr="A1",
        levels=(LevelTag(pos=pos, cefr="A1", source="cefrj"),),
        rank=100,
        zipf=5.0,
        family_zipf=5.0,
        sources=("cefrj",),
    )


def write_inputs(root: Path) -> None:
    work = root / "work"
    work.mkdir(exist_ok=True)
    lexicon = [
        entry(lemma, "NOUN")
        for lemma in (
            "i",
            "watch",
            "tv",
            "every",
            "evening",
            "tom",
            "is",
            "here",
            "where",
            "are",
            "you",
        )
    ]
    (work / "lexicon.en.jsonl").write_text(
        "".join(e.model_dump_json() + "\n" for e in lexicon), encoding="utf-8"
    )
    items = root / "packs" / "en" / "items"
    items.mkdir(parents=True)
    senses = [
        WordSense(
            key=f"en.ws.{lemma}.n.1",
            lemma=lemma,
            pos="NOUN",
            sense=lemma,
            level="A1",
            provenance=Provenance(source="dilbaz curation", license="own"),
        )
        for lemma in ("evening", "zebra")
    ]
    (items / "word_senses.jsonl").write_text(
        "".join(s.model_dump_json() + "\n" for s in senses), encoding="utf-8"
    )


def test_the_analysis_is_cached_per_snapshot_and_analyzer(tmp_path: Path) -> None:
    root, registry = tatoeba_content(tmp_path)
    made: list[FakeAnalyzer] = []

    def analyzer() -> FakeAnalyzer:
        made.append(FakeAnalyzer())
        return made[-1]

    cache = ensure_analysis(registry, root, analyzer)
    assert cache.name == ANALYSIS_FILE
    assert made[0].calls > 0
    ensure_analysis(registry, root, analyzer)
    assert made[1].calls == 0


def test_run_carriers_lists_senses_without_candidates_first(tmp_path: Path) -> None:
    root, registry = tatoeba_content(tmp_path)
    write_inputs(root)

    lines = run_carriers(registry, root, l2="en", analyzer=FakeAnalyzer)

    assert [line.target for line in lines] == ["en.ws.zebra.n.1", "en.ws.evening.n.1"]
    evening = lines[1].candidates[0]
    assert evening.text == "I watch TV every evening."
    assert evening.turkish == ("Her akşam televizyon izlerim.",)
    saved = [
        TargetCandidates.model_validate_json(line)
        for line in (root / "work" / "carriers.en.candidates.jsonl")
        .read_text(encoding="utf-8")
        .splitlines()
    ]
    assert saved == list(lines)
    meta = json.loads((root / "work" / "tatoeba.en.analysis.meta.json").read_text())
    assert meta["analyzer"] == "fake:1"


def test_run_carriers_needs_the_selection(tmp_path: Path) -> None:
    root, registry = tatoeba_content(tmp_path)
    (root / "work").mkdir(exist_ok=True)
    (root / "work" / "lexicon.en.jsonl").write_text("", encoding="utf-8")
    with pytest.raises(FileNotFoundError, match="dilbaz-content select"):
        run_carriers(registry, root, l2="en", analyzer=FakeAnalyzer)

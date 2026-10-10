"""A miniature `content/` tree: registry + upstream files in the real formats."""

from __future__ import annotations

from pathlib import Path

import pytest

from sample_sources import (
    CEFRJ,
    CMUDICT,
    NGSL_STATS,
    OCTANOVE,
    SPOKEN_STATS,
    WIKI_LINES,
    write_wiki_dump,
)


def _write(path: Path, text: str) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(text.encode("utf-8"))
    return path


@pytest.fixture
def content_dir(tmp_path: Path) -> Path:
    """content/ with a registry whose file:// URLs point at upstream copies."""
    upstream = tmp_path / "upstream"
    files = {
        "ngsl": [_write(upstream / "NGSL_1.2_stats.csv", NGSL_STATS)],
        "ngsl_spoken": [_write(upstream / "NGSL-Spoken_1.2_stats.csv", SPOKEN_STATS)],
        "cefrj": [_write(upstream / "cefrj-vocabulary-profile-1.5.csv", CEFRJ)],
        "octanove": [_write(upstream / "octanove-vocabulary-profile-c1c2-1.0.csv", OCTANOVE)],
        "cmudict": [_write(upstream / "cmudict.dict", CMUDICT)],
        "wiktextract": [
            write_wiki_dump(upstream / "kaikki.org-dictionary-English.jsonl.gz", WIKI_LINES)
        ],
    }
    root = tmp_path / "content"
    root.mkdir()
    lines = ["sources:"]
    for source_id, paths in files.items():
        rolling = source_id == "wiktextract"
        lines += [
            f"  - id: {source_id}",
            f"    name: {source_id}",
            f'    version: "{"weekly" if rolling else "1"}"',
            f"    rolling: {'true' if rolling else 'false'}",
            "    license: test license",
            "    attribution: test attribution",
            "    files:",
        ]
        for path in paths:
            lines += [f"      - name: {path.name}", f"        url: {path.as_uri()}"]
    lines += [
        "  - id: wordfreq",
        "    name: wordfreq",
        '    version: "3.1.1"',
        "    package: wordfreq",
        "    license: Apache-2.0 (code), CC BY-SA 4.0 (data)",
        "    attribution: Robyn Speer",
    ]
    _write(root / "sources.yaml", "\n".join(lines) + "\n")
    return root

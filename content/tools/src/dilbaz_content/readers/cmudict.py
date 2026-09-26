"""CMU Pronouncing Dictionary (docs/10-content-pipeline.md §2).

Lines are `word P R O N` with alternates as `word(2) …` and comments after
`#`. Pronunciations stay in ARPAbet; minimal pairs are found on phonemes.
"""

from __future__ import annotations

import re
from pathlib import Path

_ALTERNATE = re.compile(r"\(\d+\)$")


def read_cmudict(path: Path) -> dict[str, tuple[str, ...]]:
    """word → ARPAbet pronunciations in file order."""
    pronunciations: dict[str, list[str]] = {}
    with path.open(encoding="utf-8") as stream:
        for raw in stream:
            content = raw.split("#", 1)[0].strip()
            if not content or content.startswith(";;;"):
                continue
            word, _, phones = content.partition(" ")
            key = _ALTERNATE.sub("", word).lower()
            pronunciations.setdefault(key, []).append(" ".join(phones.split()))
    return {word: tuple(values) for word, values in pronunciations.items()}

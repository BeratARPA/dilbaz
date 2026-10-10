"""CEFR-J Wordlist 1.5 and Octanove C1/C2 1.0 (docs/10-content-pipeline.md §2).

Both are `headword,pos,CEFR,…` CSV files. A headword may carry spelling
variants separated by slashes ("center/centre"); the first spelling is the
lexicon key.
"""

from __future__ import annotations

import csv
from dataclasses import dataclass
from pathlib import Path

from dilbaz_content.pos import level_list_pos

CEFR_LEVELS = ("A1", "A2", "B1", "B2", "C1", "C2")
_REQUIRED = frozenset({"headword", "pos", "CEFR"})


@dataclass(frozen=True)
class LevelEntry:
    """One headword + part of speech with its CEFR level."""

    display: str
    spellings: tuple[str, ...]
    pos: str
    cefr: str
    source: str

    @property
    def key(self) -> str:
        """Lowercase first spelling, the lexicon key."""
        return self.spellings[0]


def read_level_list(path: Path, source: str) -> tuple[LevelEntry, ...]:
    """Reads a level list; raises on unknown levels or a changed format."""
    entries: list[LevelEntry] = []
    with path.open(encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream)
        missing = _REQUIRED.difference(reader.fieldnames or ())
        if missing:
            raise ValueError(f"{path.name}: missing columns {sorted(missing)}")
        for row in reader:
            parts = [part.strip() for part in row["headword"].split("/") if part.strip()]
            if not parts:
                continue
            cefr = row["CEFR"].strip().upper()
            if cefr not in CEFR_LEVELS:
                raise ValueError(f"{path.name}: unknown level {cefr!r} for {parts[0]!r}")
            entries.append(
                LevelEntry(
                    display=parts[0],
                    spellings=tuple(dict.fromkeys(" ".join(p.lower().split()) for p in parts)),
                    pos=level_list_pos(row["pos"]),
                    cefr=cefr,
                    source=source,
                )
            )
    return tuple(entries)

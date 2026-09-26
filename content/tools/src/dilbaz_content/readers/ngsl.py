"""NGSL and NGSL-Spoken 1.2 rank lists (docs/10-content-pipeline.md §2).

Only `*_stats.csv` is read. The lemmatized lists are not used for word forms:
even the teaching lists carry tokenizer fragments such as "isn", "aren" and
"gettin"; inflections come from Wiktionary instead.
"""

from __future__ import annotations

import csv
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class RankedLemma:
    """A lemma with its NGSL rank and frequency statistics.

    The statistics are None when the list has none for the lemma: NGSL-Spoken
    1.2 has a spreadsheet artefact row `TRUE,#N/A,#N/A,#N/A` for "true".
    """

    lemma: str
    rank: int | None
    sfi: float | None
    per_million: float | None


def _number[T: (int, float)](cell: str, kind: type[T]) -> T | None:
    try:
        return kind(cell)
    except ValueError:
        return None


def read_stats(path: Path) -> tuple[RankedLemma, ...]:
    """Reads `Lemma,Rank,SFI,U` rows, sorted by rank (rows without one last)."""
    with path.open(encoding="utf-8-sig", newline="") as stream:
        reader = csv.reader(stream)
        header = next(reader, [])
        if len(header) < 4 or header[0].strip().lower() != "lemma":
            raise ValueError(f"{path.name}: unexpected header {header}")
        rows = [
            RankedLemma(
                lemma=cells[0].strip().lower(),
                rank=_number(cells[1], int),
                sfi=_number(cells[2], float),
                per_million=_number(cells[3], float),
            )
            for cells in reader
            if cells and cells[0].strip()
        ]
    return tuple(sorted(rows, key=lambda row: (row.rank is None, row.rank or 0, row.lemma)))

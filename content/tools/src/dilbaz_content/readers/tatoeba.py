"""Tatoeba weekly exports (docs/10-content-pipeline.md §2).

`eng_sentences_detailed.tsv` rows are `id, lang, text, username, added,
modified`; `eng-tur_links.tsv` rows are `eng_id, tur_id`;
`eng_user_languages.tsv` rows are `lang, skill, username, details`, where
skill 5 means a native speaker. Missing values are `\\N`.
"""

from __future__ import annotations

import bz2
from collections.abc import Iterator
from dataclasses import dataclass
from pathlib import Path

NULL = "\\N"
NATIVE_SKILL = "5"

ENG_SENTENCES = "eng_sentences_detailed.tsv.bz2"
TUR_SENTENCES = "tur_sentences_detailed.tsv.bz2"
ENG_TUR_LINKS = "eng-tur_links.tsv.bz2"
ENG_USERS = "eng_user_languages.tsv.bz2"


@dataclass(frozen=True)
class TatoebaSentence:
    """One sentence with its author (None when the account is gone)."""

    id: int
    text: str
    author: str | None


@dataclass(frozen=True)
class TatoebaPair:
    """An English sentence, whether a native speaker wrote it, and its Turkish translations."""

    english: TatoebaSentence
    native: bool
    turkish: tuple[TatoebaSentence, ...]


def _rows(path: Path) -> Iterator[list[str]]:
    with bz2.open(path, "rt", encoding="utf-8", newline="") as stream:
        for line in stream:
            yield line.rstrip("\r\n").split("\t")


def _sentences(path: Path) -> Iterator[TatoebaSentence]:
    for cells in _rows(path):
        if len(cells) >= 4 and cells[0].isdigit():
            author = None if cells[3] == NULL else cells[3]
            yield TatoebaSentence(id=int(cells[0]), text=cells[2], author=author)


def native_speakers(path: Path) -> frozenset[str]:
    """Usernames that declare the language as their native one."""
    return frozenset(
        cells[2]
        for cells in _rows(path)
        if len(cells) >= 3 and cells[1] == NATIVE_SKILL and cells[2] != NULL
    )


def read_pairs(snapshot: Path, *, max_words: int) -> Iterator[TatoebaPair]:
    """English sentences of at most [max_words] words that have a Turkish translation."""
    links: dict[int, list[int]] = {}
    for cells in _rows(snapshot / ENG_TUR_LINKS):
        if len(cells) == 2 and cells[0].isdigit() and cells[1].isdigit():
            links.setdefault(int(cells[0]), []).append(int(cells[1]))
    wanted = {tur for turs in links.values() for tur in turs}
    turkish = {s.id: s for s in _sentences(snapshot / TUR_SENTENCES) if s.id in wanted}
    native = native_speakers(snapshot / ENG_USERS)
    for sentence in _sentences(snapshot / ENG_SENTENCES):
        translations = [turkish[t] for t in links.get(sentence.id, ()) if t in turkish]
        if not translations or len(sentence.text.split()) > max_words:
            continue
        yield TatoebaPair(
            english=sentence,
            native=sentence.author is not None and sentence.author in native,
            turkish=tuple(translations),
        )

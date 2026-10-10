"""Learnable items of a target pack (docs/11-language-packs.md §4).

Keys follow `{l2}.{kind}.{id}` and never change once published. Every item
records where it came from and under which license (I-16).
"""

from __future__ import annotations

import re
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

Level = Literal["A0", "A1", "A2", "B1", "B2", "C1", "C2"]
LEVELS: tuple[Level, ...] = ("A0", "A1", "A2", "B1", "B2", "C1", "C2")

# Short part-of-speech codes used inside word-sense keys (en.ws.watch.v.1).
POS_CODES = {
    "NOUN": "n",
    "VERB": "v",
    "ADJ": "adj",
    "ADV": "adv",
    "PRON": "pron",
    "DET": "det",
    "ADP": "prep",
    "CONJ": "conj",
    "NUM": "num",
    "INTJ": "intj",
    "AUX": "aux",
    "PART": "part",
}

_NON_SLUG = re.compile(r"[^a-z0-9]+")


def slug(text: str) -> str:
    """Key-safe id: "How are you?" → "how_are_you", "a.m." → "a_m"."""
    return _NON_SLUG.sub("_", text.lower()).strip("_")


def level_index(level: str) -> int:
    """Position of a CEFR level, A0 first."""
    return LEVELS.index(level)


class Provenance(BaseModel):
    """Where an item comes from (I-16); attribution names the author when required."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    source: str = Field(min_length=1)
    license: str = Field(min_length=1)
    attribution: str | None = None


class WordSense(BaseModel):
    """`items/word_senses.jsonl`: one sense of one lemma."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    key: str = Field(pattern=r"^[a-z]{2,3}\.ws\.[a-z0-9_]+\.[a-z]+\.\d+$")
    lemma: str = Field(min_length=1)
    pos: str = Field(min_length=1)
    sense: str = Field(min_length=1)
    level: Level
    rank: int | None = None
    ipa_us: str | None = None
    ipa_uk: str | None = None
    carriers: tuple[str, ...] = ()
    provenance: Provenance


class Chunk(BaseModel):
    """`items/chunks.jsonl`: a phrase learned as a whole ("How are you?")."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    key: str = Field(pattern=r"^[a-z]{2,3}\.chunk\.[a-z0-9_]+$")
    text: str = Field(min_length=1)
    level: Level
    function: str = Field(min_length=1)
    lemmas: tuple[str, ...] = ()
    note: str | None = None
    provenance: Provenance


class GrammarPoint(BaseModel):
    """`items/grammar_points.jsonl`; its `code` is on the closed list (docs/07 §1)."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    key: str = Field(pattern=r"^[a-z]{2,3}\.gp\.[a-z0-9_.]+$")
    code: str = Field(pattern=r"^gp\.[a-z0-9_]+(\.[a-z0-9_]+)*$")
    level: Level
    name: str = Field(min_length=1)
    description: str = Field(min_length=1)
    examples: tuple[str, ...] = Field(min_length=2)
    provenance: Provenance


class Sentence(BaseModel):
    """`items/sentences.jsonl`: a carrier sentence and the items it carries."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    key: str = Field(pattern=r"^[a-z]{2,3}\.sent\.[a-z0-9_]+$")
    text: str = Field(min_length=1)
    level: Level
    lemmas: tuple[str, ...]
    targets: tuple[str, ...] = Field(min_length=1)
    grammar: tuple[str, ...] = ()
    provenance: Provenance

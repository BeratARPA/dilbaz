"""Pack manifest schema (docs/11-language-packs.md §3).

Every pack records the sources it was built from, each with a license and an
attribution; a manifest without them cannot be loaded (I-16).
"""

from __future__ import annotations

import re
from datetime import date
from pathlib import Path
from typing import Literal

import yaml
from pydantic import BaseModel, ConfigDict, Field, model_validator

PACK_ID = re.compile(r"^[a-z]{2,3}(-[a-z]{2,3})?@\d+(\.\d+)?$")


class Source(BaseModel):
    """A data source of the pack, with its license."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    name: str = Field(min_length=1)
    version: str | None = None
    license: str = Field(min_length=1)
    attribution: str = Field(min_length=1)


class Script(BaseModel):
    """Writing direction and word separation of the target language."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    direction: Literal["ltr", "rtl"] = "ltr"
    word_separator: Literal["space", "none"] = "space"


class Tokenizer(BaseModel):
    """Build-time tokenizer and runtime lemmatization strategy."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    build_time: str = Field(min_length=1)
    runtime: Literal["forms_table", "remote"] = "forms_table"


class Manifest(BaseModel):
    """`manifest.yaml` of a target (`en@1`) or pair (`tr-en@1`) pack."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    id: str = Field(pattern=PACK_ID.pattern)
    kind: Literal["target", "pair"]
    l2: str = Field(min_length=2, max_length=3)
    l1: str | None = None
    version: float = Field(gt=0)
    min_engine_version: int = Field(ge=1)
    level_scheme: Literal["CEFR"] = "CEFR"
    script: Script = Script()
    tokenizer: Tokenizer | None = None
    fsrs_defaults: list[float] | None = Field(default=None, min_length=21, max_length=21)
    counts: dict[str, int] = Field(default_factory=dict)
    sources: list[Source] = Field(min_length=1)
    checksum: str | None = Field(default=None, pattern=r"^sha256:[0-9a-f]{64}$")
    created_at: date | None = None

    @model_validator(mode="after")
    def _pair_packs_name_both_languages(self) -> Manifest:
        if self.kind == "pair" and self.l1 is None:
            raise ValueError("a pair pack needs l1")
        if self.kind == "target" and self.l1 is not None:
            raise ValueError("a target pack has no l1")
        return self


def load_manifest(path: Path) -> Manifest:
    """Reads and validates a manifest; raises on any schema violation."""
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    return Manifest.model_validate(data)

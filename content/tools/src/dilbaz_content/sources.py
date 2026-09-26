"""Registry of the open data sources (docs/10-content-pipeline.md §2).

`content/sources.yaml` lists every source with its license and attribution
(I-16). Static files are pinned by sha256; rolling exports (weekly dumps) are
snapshotted by download date instead.
"""

from __future__ import annotations

from pathlib import Path

import yaml
from pydantic import BaseModel, ConfigDict, Field, model_validator

REGISTRY_FILE = "sources.yaml"


class SourceFile(BaseModel):
    """One downloadable file of a source."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    name: str = Field(pattern=r"^[A-Za-z0-9._-]+$")
    url: str = Field(pattern=r"^(https|file)://")
    sha256: str | None = Field(default=None, pattern=r"^[0-9a-f]{64}$")


class DataSource(BaseModel):
    """A source with its license; data comes as files or with a Python package."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    id: str = Field(pattern=r"^[a-z][a-z0-9_]*$")
    name: str = Field(min_length=1)
    version: str = Field(min_length=1)
    license: str = Field(min_length=1)
    attribution: str = Field(min_length=1)
    homepage: str | None = None
    rolling: bool = False
    package: str | None = None
    files: tuple[SourceFile, ...] = ()

    @model_validator(mode="after")
    def _check_data(self) -> DataSource:
        if not self.files and self.package is None:
            raise ValueError("a source needs files or a package")
        if self.rolling and any(file.sha256 is not None for file in self.files):
            raise ValueError("rolling sources are snapshotted, not pinned")
        names = [file.name for file in self.files]
        if len(names) != len(set(names)):
            raise ValueError("file names must be unique within a source")
        return self


class Registry(BaseModel):
    """`content/sources.yaml`."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    sources: tuple[DataSource, ...] = Field(min_length=1)

    @model_validator(mode="after")
    def _unique_ids(self) -> Registry:
        ids = [source.id for source in self.sources]
        if len(ids) != len(set(ids)):
            raise ValueError("source ids must be unique")
        return self

    def get(self, source_id: str) -> DataSource:
        """Returns the source with [source_id]; raises KeyError if unknown."""
        for source in self.sources:
            if source.id == source_id:
                return source
        raise KeyError(source_id)


def load_registry(path: Path) -> Registry:
    """Reads and validates the registry; raises on any schema violation."""
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    return Registry.model_validate(data)


def find_content_dir(start: Path) -> Path:
    """The `content/` directory: [start] or the nearest parent with a registry."""
    for directory in (start, *start.parents):
        if (directory / REGISTRY_FILE).is_file():
            return directory
    raise FileNotFoundError(f"no {REGISTRY_FILE} in {start} or its parents")

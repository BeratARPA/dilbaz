"""S0 ingest: downloads the registered sources (docs/10-content-pipeline.md §4).

Static sources land in `<sources dir>/<id>/<version>/`, rolling exports in
`<sources dir>/<id>/<YYYY-MM-DD>/`. Each snapshot directory gets a
`SNAPSHOT.json` with the URL, size and sha256 of every file, so later stages
can record exactly which data they were built from.
"""

from __future__ import annotations

import hashlib
import json
import urllib.request
from collections.abc import Callable
from datetime import date, datetime
from importlib import metadata
from pathlib import Path

from pydantic import BaseModel, ConfigDict

from dilbaz_content.sources import DataSource, SourceFile

SNAPSHOT_FILE = "SNAPSHOT.json"
USER_AGENT = "dilbaz-content/0.1"
_CHUNK = 1 << 20
_TIMEOUT_SECONDS = 60

# Called with (bytes so far, total bytes or None) while a file downloads.
OnProgress = Callable[[int, int | None], None]
# Downloads a URL into a path and returns the sha256 of the bytes written.
Fetch = Callable[[str, Path, OnProgress | None], str]


class ChecksumMismatchError(Exception):
    """A downloaded file does not match its pinned sha256."""


class PackageVersionError(Exception):
    """The installed data package differs from the registered version."""


class FileRecord(BaseModel):
    """What was downloaded, from where, and its checksum."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    name: str
    url: str
    size: int
    sha256: str
    retrieved_at: datetime


class Snapshot(BaseModel):
    """`SNAPSHOT.json` of one source directory."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    source: str
    version: str
    files: tuple[FileRecord, ...]


def sha256_of(path: Path) -> str:
    """Hex sha256 of a file, read in chunks."""
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(_CHUNK):
            digest.update(chunk)
    return digest.hexdigest()


def download(url: str, target: Path, progress: OnProgress | None = None) -> str:
    """Streams [url] into [target] through a `.part` file; returns its sha256."""
    partial = target.with_name(target.name + ".part")
    digest = hashlib.sha256()
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with (
        urllib.request.urlopen(request, timeout=_TIMEOUT_SECONDS) as response,
        partial.open("wb") as out,
    ):
        length = response.headers.get("Content-Length")
        total = int(length) if length is not None else None
        done = 0
        while chunk := response.read(_CHUNK):
            digest.update(chunk)
            out.write(chunk)
            done += len(chunk)
            if progress is not None:
                progress(done, total)
    partial.replace(target)
    return digest.hexdigest()


def snapshot_dir(sources_dir: Path, source: DataSource, today: date) -> Path:
    """Where the files of [source] go: by version, or by date if rolling."""
    label = today.isoformat() if source.rolling else source.version
    return sources_dir / source.id / label


def read_snapshot(directory: Path) -> Snapshot | None:
    """The snapshot record of [directory], if it has one."""
    path = directory / SNAPSHOT_FILE
    if not path.is_file():
        return None
    return Snapshot.model_validate_json(path.read_text(encoding="utf-8"))


def latest_snapshot(sources_dir: Path, source: DataSource) -> Path:
    """The newest complete snapshot directory of [source]."""
    root = sources_dir / source.id
    if not source.rolling:
        candidates = [root / source.version]
    elif root.is_dir():
        candidates = sorted(root.iterdir(), key=lambda path: path.name)
    else:
        candidates = []
    complete = [path for path in candidates if (path / SNAPSHOT_FILE).is_file()]
    if not complete:
        raise FileNotFoundError(f"{source.id}: no snapshot, run `dilbaz-content ingest`")
    return complete[-1]


def verify_package(source: DataSource) -> str:
    """Checks that the data package of [source] is installed at its version."""
    if source.package is None:
        raise ValueError(f"{source.id} has no package")
    installed = metadata.version(source.package)
    if installed != source.version:
        raise PackageVersionError(
            f"{source.package} {installed} installed, registry expects {source.version}"
        )
    return installed


def _fetch_file(
    file: SourceFile,
    target: Path,
    fetch: Fetch,
    progress: OnProgress | None,
) -> str:
    checksum = fetch(file.url, target, progress)
    if file.sha256 is not None and checksum != file.sha256:
        target.unlink()
        raise ChecksumMismatchError(
            f"{file.name}: sha256 {checksum} differs from the pinned {file.sha256}; "
            "the upstream file changed, review it before updating the pin"
        )
    return checksum


def ingest_source(
    source: DataSource,
    sources_dir: Path,
    now: datetime,
    *,
    fetch: Fetch = download,
    progress: Callable[[SourceFile], OnProgress | None] | None = None,
    refresh: bool = False,
) -> Snapshot | None:
    """Downloads the missing or changed files of [source]; idempotent.

    A rolling source is downloaded again only with [refresh]; otherwise its
    latest snapshot is kept. Returns the snapshot record, or None for
    package-only sources (those are checked with [verify_package]).
    """
    if not source.files:
        verify_package(source)
        return None
    if source.rolling and not refresh:
        try:
            existing = read_snapshot(latest_snapshot(sources_dir, source))
        except FileNotFoundError:
            existing = None
        if existing is not None:
            return existing
    directory = snapshot_dir(sources_dir, source, now.date())
    directory.mkdir(parents=True, exist_ok=True)
    previous = read_snapshot(directory)
    known = {record.name: record for record in previous.files} if previous else {}
    records: list[FileRecord] = []
    for file in source.files:
        target = directory / file.name
        record = known.get(file.name)
        up_to_date = (
            record is not None
            and target.is_file()
            and sha256_of(target) == record.sha256
            and (file.sha256 is None or record.sha256 == file.sha256)
        )
        if record is None or not up_to_date:
            listener = progress(file) if progress is not None else None
            checksum = _fetch_file(file, target, fetch, listener)
            record = FileRecord(
                name=file.name,
                url=file.url,
                size=target.stat().st_size,
                sha256=checksum,
                retrieved_at=now,
            )
        records.append(record)
    snapshot = Snapshot(source=source.id, version=source.version, files=tuple(records))
    (directory / SNAPSHOT_FILE).write_text(
        json.dumps(snapshot.model_dump(mode="json"), indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    return snapshot

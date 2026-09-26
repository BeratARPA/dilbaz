import hashlib
from datetime import UTC, datetime
from pathlib import Path

import pytest

from dilbaz_content.ingest import (
    SNAPSHOT_FILE,
    ChecksumMismatchError,
    PackageVersionError,
    download,
    ingest_source,
    latest_snapshot,
    read_snapshot,
    sha256_of,
    verify_package,
)
from dilbaz_content.sources import DataSource

DAY_1 = datetime(2026, 9, 26, 12, 0, tzinfo=UTC)
DAY_2 = datetime(2026, 10, 3, 12, 0, tzinfo=UTC)


def upstream_file(tmp_path: Path, name: str = "list.csv", text: str = "a,b\n") -> Path:
    path = tmp_path / "upstream" / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    return path


def make_source(path: Path, *, rolling: bool = False, sha256: str | None = None) -> DataSource:
    return DataSource.model_validate(
        {
            "id": "demo",
            "name": "Demo list",
            "version": "weekly" if rolling else "1.0",
            "rolling": rolling,
            "license": "CC BY 4.0",
            "attribution": "Demo authors",
            "files": [{"name": path.name, "url": path.as_uri(), "sha256": sha256}],
        }
    )


def refuse(url: str, target: Path, progress: object) -> str:
    raise AssertionError(f"unexpected download of {url}")


def test_downloads_into_the_version_directory_with_a_snapshot(tmp_path: Path) -> None:
    upstream = upstream_file(tmp_path)
    expected = hashlib.sha256(upstream.read_bytes()).hexdigest()
    sources_dir = tmp_path / "sources"

    snapshot = ingest_source(make_source(upstream, sha256=expected), sources_dir, DAY_1)

    target = sources_dir / "demo" / "1.0" / "list.csv"
    assert target.read_bytes() == upstream.read_bytes()
    assert snapshot is not None
    assert snapshot.files[0].sha256 == expected
    assert snapshot.files[0].size == upstream.stat().st_size
    assert read_snapshot(target.parent) == snapshot
    assert not (target.parent / "list.csv.part").exists()


def test_a_changed_upstream_file_stops_the_ingest(tmp_path: Path) -> None:
    upstream = upstream_file(tmp_path)
    source = make_source(upstream, sha256="0" * 64)

    with pytest.raises(ChecksumMismatchError, match="upstream file changed"):
        ingest_source(source, tmp_path / "sources", DAY_1)

    assert not (tmp_path / "sources" / "demo" / "1.0" / "list.csv").exists()


def test_ingest_is_idempotent(tmp_path: Path) -> None:
    upstream = upstream_file(tmp_path)
    source = make_source(upstream, sha256=sha256_of(upstream))
    first = ingest_source(source, tmp_path / "sources", DAY_1)

    again = ingest_source(source, tmp_path / "sources", DAY_2, fetch=refuse)

    assert again == first


def test_a_damaged_local_copy_is_downloaded_again(tmp_path: Path) -> None:
    upstream = upstream_file(tmp_path)
    source = make_source(upstream, sha256=sha256_of(upstream))
    ingest_source(source, tmp_path / "sources", DAY_1)
    local = tmp_path / "sources" / "demo" / "1.0" / "list.csv"
    local.write_text("damaged", encoding="utf-8")

    snapshot = ingest_source(source, tmp_path / "sources", DAY_2)

    assert local.read_bytes() == upstream.read_bytes()
    assert snapshot is not None
    assert snapshot.files[0].retrieved_at == DAY_2


def test_rolling_sources_are_snapshotted_by_date(tmp_path: Path) -> None:
    upstream = upstream_file(tmp_path, "dump.tsv", "v1\n")
    source = make_source(upstream, rolling=True)
    sources_dir = tmp_path / "sources"
    ingest_source(source, sources_dir, DAY_1)

    kept = ingest_source(source, sources_dir, DAY_2, fetch=refuse)
    assert kept is not None
    assert kept.files[0].retrieved_at == DAY_1
    assert latest_snapshot(sources_dir, source).name == "2026-09-26"

    upstream.write_text("v2\n", encoding="utf-8")
    ingest_source(source, sources_dir, DAY_2, refresh=True)
    newest = latest_snapshot(sources_dir, source)
    assert newest.name == "2026-10-03"
    assert (newest / "dump.tsv").read_text(encoding="utf-8") == "v2\n"
    assert (sources_dir / "demo" / "2026-09-26" / "dump.tsv").read_text(encoding="utf-8") == "v1\n"


def test_latest_snapshot_needs_a_completed_ingest(tmp_path: Path) -> None:
    upstream = upstream_file(tmp_path)
    source = make_source(upstream)
    (tmp_path / "sources" / "demo" / "1.0").mkdir(parents=True)

    with pytest.raises(FileNotFoundError, match="run `dilbaz-content ingest`"):
        latest_snapshot(tmp_path / "sources", source)

    ingest_source(source, tmp_path / "sources", DAY_1)
    assert (latest_snapshot(tmp_path / "sources", source) / SNAPSHOT_FILE).is_file()


def test_download_reports_progress(tmp_path: Path) -> None:
    upstream = upstream_file(tmp_path, text="x" * 5000)
    seen: list[tuple[int, int | None]] = []

    checksum = download(upstream.as_uri(), tmp_path / "copy.csv", lambda d, t: seen.append((d, t)))

    assert checksum == sha256_of(upstream)
    assert seen[-1] == (5000, 5000)


def test_package_sources_check_the_installed_version() -> None:
    wordfreq = DataSource.model_validate(
        {
            "id": "wordfreq",
            "name": "wordfreq",
            "version": "3.1.1",
            "package": "wordfreq",
            "license": "Apache-2.0",
            "attribution": "Robyn Speer",
        }
    )
    assert verify_package(wordfreq) == "3.1.1"
    assert ingest_source(wordfreq, Path("unused"), DAY_1) is None

    stale = wordfreq.model_copy(update={"version": "0.1"})
    with pytest.raises(PackageVersionError, match=r"registry expects 0\.1"):
        verify_package(stale)

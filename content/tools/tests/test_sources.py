from pathlib import Path

import pytest
from pydantic import ValidationError

from dilbaz_content.sources import (
    REGISTRY_FILE,
    DataSource,
    Registry,
    find_content_dir,
    load_registry,
)

REPO_CONTENT = Path(__file__).resolve().parents[2]


def source(**changes: object) -> dict[str, object]:
    base: dict[str, object] = {
        "id": "ngsl",
        "name": "NGSL",
        "version": "1.2",
        "license": "CC BY-SA 4.0",
        "attribution": "Browne et al.",
        "files": [{"name": "a.csv", "url": "https://example.org/a.csv"}],
    }
    return base | changes


def test_committed_registry_is_valid() -> None:
    registry = load_registry(REPO_CONTENT / REGISTRY_FILE)
    ids = {s.id for s in registry.sources}
    assert {"ngsl", "ngsl_spoken", "cefrj", "octanove", "cmudict", "tatoeba"} <= ids
    assert {"wiktextract", "wordfreq"} <= ids


def test_committed_registry_pins_static_files_over_https() -> None:
    registry = load_registry(REPO_CONTENT / REGISTRY_FILE)
    for data_source in registry.sources:
        for file in data_source.files:
            assert file.url.startswith("https://"), file.name
            if not data_source.rolling:
                assert file.sha256 is not None, f"{data_source.id}/{file.name} is not pinned"


def test_every_source_has_license_and_attribution() -> None:
    with pytest.raises(ValidationError, match="license"):
        DataSource.model_validate({k: v for k, v in source().items() if k != "license"})
    with pytest.raises(ValidationError, match="attribution"):
        DataSource.model_validate(source(attribution=""))


def test_rolling_sources_cannot_be_pinned() -> None:
    pinned = [{"name": "a.bz2", "url": "https://example.org/a.bz2", "sha256": "0" * 64}]
    with pytest.raises(ValidationError, match="rolling"):
        DataSource.model_validate(source(rolling=True, files=pinned))


def test_a_source_needs_files_or_a_package() -> None:
    with pytest.raises(ValidationError, match="files or a package"):
        DataSource.model_validate(source(files=[]))
    assert DataSource.model_validate(source(files=[], package="wordfreq")).package == "wordfreq"


def test_file_names_and_source_ids_are_unique() -> None:
    twice = [
        {"name": "a.csv", "url": "https://example.org/1"},
        {"name": "a.csv", "url": "https://example.org/2"},
    ]
    with pytest.raises(ValidationError, match="unique within a source"):
        DataSource.model_validate(source(files=twice))
    with pytest.raises(ValidationError, match="ids must be unique"):
        Registry.model_validate({"sources": [source(), source()]})


@pytest.mark.parametrize(
    "url", ["http://example.org/a.csv", "ftp://example.org/a.csv", "example.org/a.csv"]
)
def test_urls_must_be_https_or_file(url: str) -> None:
    with pytest.raises(ValidationError):
        DataSource.model_validate(source(files=[{"name": "a.csv", "url": url}]))


def test_get_unknown_source_raises_key_error() -> None:
    registry = Registry.model_validate({"sources": [source()]})
    assert registry.get("ngsl").name == "NGSL"
    with pytest.raises(KeyError):
        registry.get("missing")


def test_find_content_dir_walks_up(tmp_path: Path) -> None:
    (tmp_path / REGISTRY_FILE).write_text("sources: []\n", encoding="utf-8")
    nested = tmp_path / "tools" / "src"
    nested.mkdir(parents=True)
    assert find_content_dir(nested) == tmp_path
    with pytest.raises(FileNotFoundError):
        find_content_dir(tmp_path.parent / "elsewhere")

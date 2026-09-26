from pathlib import Path

import pytest
from typer.testing import CliRunner

from dilbaz_content import __version__
from dilbaz_content.cli import app

runner = CliRunner()

MANIFEST = """
id: tr-en@1
kind: pair
l2: en
l1: tr
version: 1
min_engine_version: 1
sources:
  - { name: Dilbaz, license: own, attribution: "Dilbaz content pipeline" }
"""


def test_help_lists_the_commands() -> None:
    result = runner.invoke(app, ["--help"])
    assert result.exit_code == 0
    assert "check-manifest" in result.output
    assert "version" in result.output


def test_version() -> None:
    result = runner.invoke(app, ["version"])
    assert result.exit_code == 0
    assert __version__ in result.output


def test_check_manifest_accepts_a_valid_manifest(tmp_path: Path) -> None:
    path = tmp_path / "manifest.yaml"
    path.write_text(MANIFEST, encoding="utf-8")
    result = runner.invoke(app, ["check-manifest", str(path)])
    assert result.exit_code == 0
    assert "tr-en@1" in result.output


def test_check_manifest_fails_without_licenses(tmp_path: Path) -> None:
    path = tmp_path / "manifest.yaml"
    path.write_text(MANIFEST.replace("license: own, ", ""), encoding="utf-8")
    result = runner.invoke(app, ["check-manifest", str(path)])
    assert result.exit_code == 1
    assert "invalid manifest" in result.output


def test_help_lists_the_pipeline_stages() -> None:
    result = runner.invoke(app, ["--help"])
    assert "ingest" in result.output
    assert "lexicon" in result.output


def test_ingest_downloads_and_lexicon_builds(content_dir: Path) -> None:
    ingest = runner.invoke(app, ["ingest", "--content-dir", str(content_dir)])
    assert ingest.exit_code == 0, ingest.output
    assert "ngsl: 1 file(s) ok" in ingest.output
    assert "unpinned" in ingest.output
    assert "wordfreq: package wordfreq 3.1.1 ok" in ingest.output

    built = runner.invoke(app, ["lexicon", "--content-dir", str(content_dir)])
    assert built.exit_code == 0, built.output
    assert "entries" in built.output
    assert (content_dir / "work" / "lexicon.en.jsonl").is_file()


def test_ingest_rejects_unknown_sources(content_dir: Path) -> None:
    result = runner.invoke(app, ["ingest", "nope", "--content-dir", str(content_dir)])
    assert result.exit_code == 2
    assert "unknown source" in result.output


def test_commands_need_a_content_dir(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.chdir(tmp_path)
    result = runner.invoke(app, ["lexicon"])
    assert result.exit_code == 2
    assert "--content-dir" in result.output

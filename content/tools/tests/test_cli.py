from pathlib import Path

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

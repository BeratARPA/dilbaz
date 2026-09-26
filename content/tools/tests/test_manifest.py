from pathlib import Path

import pytest
from pydantic import ValidationError

from dilbaz_content.manifest import Manifest, load_manifest

VALID = """
id: en@1
kind: target
l2: en
l1: null
version: 1
min_engine_version: 1
level_scheme: CEFR
script: { direction: ltr, word_separator: space }
tokenizer: { build_time: "spacy:en_core_web_md", runtime: "forms_table" }
fsrs_defaults: null
counts: { word_senses: 612, sentences: 604, chunks: 120, grammar_points: 40, tasks: 23 }
sources:
  - name: NGSL
    version: "1.2"
    license: CC BY-SA 4.0
    attribution: Browne, Culligan & Phillips
  - name: CEFR-J Wordlist
    version: "1.6"
    license: free with citation
    attribution: Tono Lab, TUFS
created_at: 2026-10-01
"""


def write(tmp_path: Path, text: str) -> Path:
    path = tmp_path / "manifest.yaml"
    path.write_text(text, encoding="utf-8")
    return path


def test_documented_manifest_is_valid(tmp_path: Path) -> None:
    manifest = load_manifest(write(tmp_path, VALID))
    assert manifest.id == "en@1"
    assert manifest.kind == "target"
    assert manifest.counts["sentences"] == 604
    assert [s.license for s in manifest.sources] == ["CC BY-SA 4.0", "free with citation"]


def test_sources_are_required(tmp_path: Path) -> None:
    text = VALID.split("sources:")[0] + "sources: []\n"
    with pytest.raises(ValidationError):
        load_manifest(write(tmp_path, text))


def test_every_source_needs_a_license(tmp_path: Path) -> None:
    text = VALID.replace("    license: CC BY-SA 4.0\n", "")
    with pytest.raises(ValidationError, match="license"):
        load_manifest(write(tmp_path, text))


def test_unknown_fields_are_rejected(tmp_path: Path) -> None:
    with pytest.raises(ValidationError):
        load_manifest(write(tmp_path, VALID + "surprise: 1\n"))


@pytest.mark.parametrize(
    ("changes", "message"),
    [
        ({"kind": "pair", "l1": None}, "pair pack needs l1"),
        ({"kind": "target", "l1": "tr"}, "target pack has no l1"),
    ],
)
def test_pair_and_target_languages(changes: dict[str, object], message: str) -> None:
    base = {
        "id": "tr-en@1",
        "l2": "en",
        "version": 1,
        "min_engine_version": 1,
        "sources": [{"name": "own", "license": "own", "attribution": "Dilbaz"}],
    }
    with pytest.raises(ValidationError, match=message):
        Manifest.model_validate(base | changes)


@pytest.mark.parametrize("pack_id", ["en", "EN@1", "en@", "english@1"])
def test_pack_ids_follow_the_key_format(pack_id: str) -> None:
    with pytest.raises(ValidationError):
        Manifest.model_validate(
            {
                "id": pack_id,
                "kind": "target",
                "l2": "en",
                "version": 1,
                "min_engine_version": 1,
                "sources": [{"name": "own", "license": "own", "attribution": "Dilbaz"}],
            }
        )

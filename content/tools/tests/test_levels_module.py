"""The word levels module for the functions (docs/07-ai-tutor.md §4.3)."""

from __future__ import annotations

import json
import sqlite3
from pathlib import Path

import pytest

from dilbaz_content.levels_module import read_levels, render, run_levels_module


def _pack(path: Path, *, kind: str = "target") -> None:
    db = sqlite3.connect(path)
    db.executescript(
        """
        CREATE TABLE pack_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE content_items (key TEXT, kind TEXT, level TEXT, lemmas TEXT);
        CREATE TABLE content_forms (form TEXT, lemma TEXT);
        """
    )
    db.execute(
        "INSERT INTO pack_meta VALUES ('manifest', ?)",
        (json.dumps({"id": "zz@1", "kind": kind, "l2": "zz"}),),
    )
    db.executemany(
        "INSERT INTO content_items VALUES (?, ?, ?, ?)",
        [
            ("zz.lemma.bada", "lemma", "A1", '["bada"]'),
            ("zz.lemma.sima", "lemma", "B2", '["sima"]'),
            # Listed twice: the lower level counts.
            ("zz.lemma.sima.2", "lemma", "A2", '["sima"]'),
            ("zz.lemma.kolu", "lemma", "C1", '["Kolu"]'),
            ("zz.lemma.dero", "lemma", "", '["dero"]'),
            ("zz.ws.bada.n.1", "word_sense", "A1", '["bada"]'),
        ],
    )
    db.executemany(
        "INSERT INTO content_forms VALUES (?, ?)",
        [
            ("bada", "bada"),
            ("badan", "bada"),
            ("sim", "sima"),
            ("sim", "bada"),
            ("deros", "dero"),
            ("Kolun", "kolu"),
        ],
    )
    db.commit()
    db.close()


def test_reads_the_lexicon_levels_and_forms(tmp_path: Path) -> None:
    _pack(tmp_path / "zz@1.sqlite")
    levels = read_levels(tmp_path / "zz@1.sqlite")
    assert levels.pack == "zz@1"
    assert levels.levels == {"bada": "A1", "sima": "A2", "kolu": "C1"}
    # Forms of lemmas without a level, and a lemma's own form, stay out.
    assert levels.forms == {
        "badan": frozenset({"bada"}),
        "sim": frozenset({"sima", "bada"}),
        "kolun": frozenset({"kolu"}),
    }


def test_renders_a_stable_module(tmp_path: Path) -> None:
    _pack(tmp_path / "zz@1.sqlite")
    text = render(read_levels(tmp_path / "zz@1.sqlite"))
    assert text == render(read_levels(tmp_path / "zz@1.sqlite"))
    assert "from zz@1; do not edit." in text
    assert "export const zzLevels: LevelData = {" in text
    assert '    A1: "bada",' in text
    assert '    A2: "sima",' in text
    assert '    C1: "kolu",' in text
    assert "B1:" not in text
    assert '  forms: "badan bada|kolun kolu|sim bada/sima",' in text


def test_refuses_a_pair_pack(tmp_path: Path) -> None:
    _pack(tmp_path / "zz@1.sqlite", kind="pair")
    with pytest.raises(ValueError, match="not a target pack"):
        read_levels(tmp_path / "zz@1.sqlite")


def test_writes_the_module_beside_the_functions(tmp_path: Path) -> None:
    root = tmp_path / "content"
    (root / "build").mkdir(parents=True)
    _pack(root / "build" / "zz@1.sqlite")
    report = run_levels_module(root, l2="zz")
    assert report.path == tmp_path / "supabase" / "functions" / "_shared" / "levels" / "zz.ts"
    assert report.lemmas == 3
    assert report.forms == 3
    assert report.path.read_text(encoding="utf-8").startswith("// deno-fmt-ignore-file")


def test_needs_a_built_pack(tmp_path: Path) -> None:
    (tmp_path / "build").mkdir()
    with pytest.raises(FileNotFoundError, match="run build first"):
        run_levels_module(tmp_path, l2="zz")

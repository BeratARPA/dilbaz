import hashlib
import json
import shutil
import sqlite3
from pathlib import Path

import pytest
from typer.testing import CliRunner

from dilbaz_content.audio_step import AUDIO_FILE, VOICES_FILE, Clip
from dilbaz_content.build_step import FORMAT_VERSION, BuildError, run_build
from dilbaz_content.cli import app
from dilbaz_content.pair_step import run_pair
from dilbaz_content.placement_step import XLEX_FILE, XlexItem
from dilbaz_content.sentences_step import VALIDATION_FILE, Validation

from sample_sentences import OwnAnalyzer
from test_pair_step import build as build_pair_inputs

PACKS = Path(__file__).resolve().parents[2] / "packs"


def lines(path: Path) -> list[dict]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()]


def ready(tmp_path: Path) -> Path:
    """content/ with everything S9 reads: items, validation, audio, X_Lex, S5, manifests."""
    root = build_pair_inputs(tmp_path)
    run_pair(root, l1="tr", l2="en", analyzer=OwnAnalyzer)
    en = root / "packs" / "en"
    shutil.copy(PACKS / "en" / "manifest.yaml", en / "manifest.yaml")
    shutil.copy(PACKS / "tr-en" / "manifest.yaml", root / "packs" / "tr-en" / "manifest.yaml")
    shutil.copy(PACKS / "en" / VOICES_FILE, en / VOICES_FILE)
    sentences = lines(en / "items" / "sentences.jsonl")
    decisions = [
        Validation(
            key=s["key"],
            text=s["text"],
            round=1,
            naturalness=5,
            grammatical=True,
            ambiguous=False,
            sense_ok=True,
            suitable=True,
            accepted=True,
        )
        for s in sentences
    ]
    (root / "curation" / "en" / VALIDATION_FILE).write_text(
        "".join(d.model_dump_json() + "\n" for d in decisions), encoding="utf-8"
    )
    keys = [s["key"] for s in sentences]
    keys += [c["key"] for c in lines(en / "items" / "chunks.jsonl")]
    keys += [w["key"] for w in lines(en / "items" / "word_senses.jsonl")]
    audio_dir = root / "build" / "audio" / "en" / "1"
    clips = []
    for index, key in enumerate(keys):
        for voice in ("v1", "v3"):
            file = f"{voice}/{index:04d}.mp3"
            (audio_dir / file).parent.mkdir(parents=True, exist_ok=True)
            (audio_dir / file).write_bytes(b"mp3")
            clips.append(Clip(key=key, voice=voice, speed=1.0, file=file, duration_ms=900))
    (en / AUDIO_FILE).write_text(
        "".join(c.model_dump_json() + "\n" for c in clips), encoding="utf-8"
    )
    xlex = [
        XlexItem(version="A", band=1, word="watch", is_pseudo=False),
        XlexItem(version="A", band=None, word="brastle", is_pseudo=True),
    ]
    (en / XLEX_FILE).parent.mkdir(parents=True, exist_ok=True)
    (en / XLEX_FILE).write_text("".join(x.model_dump_json() + "\n" for x in xlex), encoding="utf-8")
    return root


def rows(path: Path, sql: str) -> list[tuple]:
    with sqlite3.connect(path) as db:
        found = db.execute(sql).fetchall()
    db.close()
    return found


def test_the_packs_are_built_with_the_app_tables(tmp_path: Path) -> None:
    root = ready(tmp_path)

    report = run_build(root, l1="tr", l2="en")

    assert report.issues == ()
    target = root / "build" / "en@1.sqlite"
    pair = root / "build" / "tr-en@1.sqlite"
    assert rows(target, "PRAGMA user_version") == [(FORMAT_VERSION,)]
    kinds = dict(rows(target, "SELECT kind, count(*) FROM content_items GROUP BY kind"))
    assert kinds["sentence"] == 4
    assert kinds["word_sense"] == 4
    assert kinds["chunk"] == 1
    assert kinds["grammar_point"] == 6
    assert kinds["xlex"] == 2
    assert kinds["lemma"] > 10
    (data,) = rows(target, "SELECT data FROM content_items WHERE key = 'en.sent.we_watch_tv'")[0]
    assert {clip["voice"] for clip in json.loads(data)["audio"]} == {"v1", "v3"}
    links = set(rows(target, "SELECT from_key, to_key, type FROM content_links"))
    assert ("en.sent.we_watch_tv", "en.ws.watch.v.1", "contains") in links
    assert any(kind == "example_of" for _, _, kind in links)
    # Every lemma is at least its own form; inflections come from the lexicon.
    assert ("watch", "watch") in set(rows(target, "SELECT form, lemma FROM content_forms"))
    meta = dict(rows(target, "SELECT key, value FROM pack_meta"))
    assert json.loads(meta["manifest"])["id"] == "en@1"
    assert json.loads(meta["audio"]) == {"bucket": "pack-audio", "prefix": "en/1/"}
    assert "tests" in json.loads(meta["normalization"])
    entries = dict(rows(pair, "SELECT kind, count(*) FROM content_pair_entries GROUP BY kind"))
    assert entries["gloss"] == 4 + 1 + 4 + 6
    assert entries["contrast_note"] == 1
    assert rows(pair, "SELECT from_key, to_key, type FROM content_links") == [
        ("en.ws.right.adj.1", "en.ws.right.adj.2", "contrasts_with")
    ]
    manifest = json.loads((root / "build" / "en@1.manifest.json").read_text(encoding="utf-8"))
    assert manifest["checksum"] == "sha256:" + hashlib.sha256(target.read_bytes()).hexdigest()
    assert manifest["counts"]["sentence"] == 4
    licenses = (root / "build" / "en@1.LICENSES.md").read_text(encoding="utf-8")
    assert "CC BY-SA 4.0" in licenses
    assert (root / "work" / "build.report.json").is_file()


def test_unvalidated_sentences_and_missing_audio_stop_the_build(tmp_path: Path) -> None:
    root = ready(tmp_path)
    validation = root / "curation" / "en" / VALIDATION_FILE
    validation.write_text(
        "".join(line + "\n" for line in validation.read_text(encoding="utf-8").splitlines()[1:]),
        encoding="utf-8",
    )
    audio = root / "packs" / "en" / AUDIO_FILE
    clips = audio.read_text(encoding="utf-8").splitlines()
    audio.write_text("".join(line + "\n" for line in clips[2:]), encoding="utf-8")
    (root / "build" / "audio" / "en" / "1" / json.loads(clips[3])["file"]).unlink()

    report = run_build(root, l1="tr", l2="en")

    assert report.packs == ()
    assert {issue.kind for issue in report.issues} == {
        "unvalidated_sentence",
        "missing_audio",
        "missing_audio_file",
    }
    assert not (root / "build" / "en@1.sqlite").exists()


def test_a_manifest_for_another_audio_version_is_refused(tmp_path: Path) -> None:
    root = ready(tmp_path)
    manifest = root / "packs" / "en" / "manifest.yaml"
    manifest.write_text(
        manifest.read_text(encoding="utf-8").replace("version: 1\n", "version: 2\n"),
        encoding="utf-8",
    )

    with pytest.raises(BuildError, match="version 1"):
        run_build(root, l1="tr", l2="en")


def test_the_build_command_reports_and_fails_on_issues(tmp_path: Path) -> None:
    runner = CliRunner()
    good = ready(tmp_path / "good")
    result = runner.invoke(app, ["build", "--content-dir", str(good)])
    assert result.exit_code == 0, result.output
    assert "en@1" in result.output

    bad = ready(tmp_path / "bad")
    (bad / "packs" / "en" / AUDIO_FILE).write_text("", encoding="utf-8")
    result = runner.invoke(app, ["build", "--content-dir", str(bad)])
    assert result.exit_code == 1
    assert "missing_audio" in result.output


def test_the_report_gathers_what_the_steps_recorded(tmp_path: Path) -> None:
    root = ready(tmp_path)
    assert run_build(root, l1="tr", l2="en").issues == ()
    reports = root / "reports"
    reports.mkdir()
    (reports / "2026-09-29-qa.md").write_text("# QA\n", encoding="utf-8")

    result = CliRunner().invoke(app, ["report", "--content-dir", str(root)])

    assert result.exit_code == 0, result.output
    text = (root / "build" / "en@1.report.md").read_text(encoding="utf-8")
    assert text.startswith("# en@1 derleme raporu")
    assert "| en@1 | content_items" in text
    assert "| cümle | 1 | 3 | 0 | 4 |" in text
    assert "- 1. tur: 4 karar, 4 kabul" in text
    assert "- Ses raporu yok." in text
    assert "`reports/2026-09-29-qa.md`" in text

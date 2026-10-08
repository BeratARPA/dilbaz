import hashlib
import json
import shutil
import sqlite3
from pathlib import Path

import pytest
from typer.testing import CliRunner

from dilbaz_content.audio_step import AUDIO_FILE, VOICES_FILE, Clip
from dilbaz_content.build_step import (
    FORMAT_VERSION,
    PAIR_TABLES,
    TARGET_TABLES,
    BuildError,
    chunk_ranks,
    run_build,
)
from dilbaz_content.cli import app
from dilbaz_content.items import Chunk, Provenance, WordSense
from dilbaz_content.pair_step import run_pair
from dilbaz_content.placement_step import XLEX_FILE, XlexItem
from dilbaz_content.placement_tests import (
    DICTATION_FILE,
    GRAMMAR_FILE,
    GRAMMAR_VALIDATION,
    DictationItem,
    GrammarCheck,
    GrammarItem,
)
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
    grammar = GrammarItem(
        key="en.pgram.a1.be_present",
        level="A1",
        grammar="gp.be.present",
        focus="be: am / is / are",
        stem="You ___ right.",
        answer="are",
        distractors=("is", "am"),
        provenance=Provenance(source="dilbaz curation", license="own"),
    )
    (en / GRAMMAR_FILE).write_text(
        grammar.model_dump_json(exclude_none=True) + "\n", encoding="utf-8"
    )
    check = GrammarCheck(
        id="a1.be_present",
        stem=grammar.stem,
        options=("am", "are", "is"),
        round=1,
        acceptable=("are",),
        natural=True,
        level_ok=True,
    )
    (root / "curation" / "en" / GRAMMAR_VALIDATION).write_text(
        check.model_dump_json() + "\n", encoding="utf-8"
    )
    dictation = DictationItem(
        version="A", order=1, level="A1", sentence="en.sent.my_right_hand_is_cold"
    )
    (en / DICTATION_FILE).write_text(dictation.model_dump_json() + "\n", encoding="utf-8")
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
    # The placement test: a grammar item with its choices, a sentence to
    # write down with its clips, and the vocabulary sizes of the levels.
    ((key, level, text, grammar, asked),) = rows(
        target,
        "SELECT key, level, text_l2, grammar, data FROM content_items"
        " WHERE kind = 'placement_grammar'",
    )
    assert (key, level, text) == ("en.pgram.a1.be_present", "A1", "You ___ right.")
    assert grammar == '["gp.be.present"]'
    assert json.loads(asked) == {
        "answer": "are",
        "distractors": ["is", "am"],
        "focus": "be: am / is / are",
        "provenance": {"source": "dilbaz curation", "license": "own"},
    }
    ((key, level, text, targets, dictated),) = rows(
        target,
        "SELECT key, level, text_l2, targets, data FROM content_items"
        " WHERE kind = 'placement_dictation'",
    )
    assert (key, level, text) == ("en.pdict.a.1", "A1", "My right hand is cold.")
    assert targets == '["en.sent.my_right_hand_is_cold"]'
    assert json.loads(dictated)["version"] == "A"
    assert {clip["voice"] for clip in json.loads(dictated)["audio"]} == {"v1", "v3"}
    # A chunk ranks with the words of its level (docs/02 §4.3).
    ((level, rank),) = rows(target, "SELECT level, rank FROM content_items WHERE kind = 'chunk'")
    (least,) = rows(
        target,
        f"SELECT min(rank) FROM content_items WHERE kind = 'word_sense' AND level = '{level}'",
    )[0]
    assert rank == least
    (data,) = rows(target, "SELECT data FROM content_items WHERE key = 'en.sent.we_watch_tv'")[0]
    assert {clip["voice"] for clip in json.loads(data)["audio"]} == {"v1", "v3"}
    links = set(rows(target, "SELECT from_key, to_key, type FROM content_links"))
    assert ("en.sent.we_watch_tv", "en.ws.watch.v.1", "contains") in links
    assert any(kind == "example_of" for _, _, kind in links)
    # Every lemma is at least its own form; inflections come from the lexicon.
    assert ("watch", "watch") in set(rows(target, "SELECT form, lemma FROM content_forms"))
    meta = dict(rows(target, "SELECT key, value FROM pack_meta"))
    assert json.loads(meta["manifest"])["id"] == "en@1"
    assert json.loads(meta["manifest"])["placement"]["vocab_levels"][1] == {
        "level": "A1",
        "from": 300,
        "to": 1500,
    }
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


def write_jsonl(path: Path, items: list[dict[str, object]]) -> None:
    path.write_text(
        "".join(json.dumps(item, ensure_ascii=False) + "\n" for item in items), encoding="utf-8"
    )


def test_speaking_tasks_go_in_with_their_instructions(tmp_path: Path) -> None:
    root = ready(tmp_path)
    en = root / "packs" / "en"
    pair = root / "packs" / "tr-en"
    own = {"source": "dilbaz curation", "license": "own"}
    task = {
        "key": "en.task.daily_routine",
        "kind": "speaking",
        "level": "A1",
        "anchor": None,
        "can_do": ["cd.describe_experience.a1"],
        "goal": "Describe a usual day.",
        "phrases": ["I usually get up at ..."],
        "provenance": own,
    }
    write_jsonl(en / "tasks.jsonl", [task])
    write_jsonl(en / "connectors.jsonl", [{"text": "because", "level": "A1"}])
    can_do = {"code": "cd.describe_experience.a1", "level": "A1", "scale": "describing"}
    write_jsonl(en / "can_dos.jsonl", [can_do])
    write_jsonl(pair / "can_do_summaries.jsonl", [{"code": can_do["code"], "summary": "Özet."}])

    # Without its instruction, the task stops the build.
    report = run_build(root, l1="tr", l2="en")
    assert [(i.key, i.kind) for i in report.issues] == [
        ("en.task.daily_routine", "missing_task_instruction")
    ]

    instruction = {
        "key": "en.task.daily_routine",
        "title": "Sıradan bir gün",
        "prompt": "Sıradan bir gününü anlat.",
        "phrases": ["Genelde saat ...'te kalkarım."],
        "provenance": own,
    }
    write_jsonl(pair / "task_instructions.jsonl", [instruction])
    report = run_build(root, l1="tr", l2="en")

    assert report.issues == ()
    target = root / "build" / "en@1.sqlite"
    ((key, kind, level, data),) = rows(target, "SELECT key, kind, level, data FROM content_tasks")
    assert (key, kind, level) == ("en.task.daily_routine", "speaking", "A1")
    assert json.loads(data) == {
        "anchor": None,
        "can_do": ["cd.describe_experience.a1"],
        "goal": "Describe a usual day.",
        "phrases": ["I usually get up at ..."],
        "provenance": own,
    }
    meta = dict(rows(target, "SELECT key, value FROM pack_meta"))
    assert json.loads(meta["connectors"]) == [{"text": "because", "level": "A1"}]
    assert json.loads(meta["can_dos"]) == [can_do]
    assert json.loads(meta["manifest"])["counts"]["task"] == 1
    entries = dict(
        rows(root / "build" / "tr-en@1.sqlite", "SELECT kind, data FROM content_pair_entries")
    )
    assert json.loads(entries["task_instruction"])["prompt"] == "Sıradan bir gününü anlat."
    assert json.loads(entries["can_do_summary"])["summary"] == "Özet."


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


def test_placement_items_without_their_check_or_sentence_stop_the_build(tmp_path: Path) -> None:
    root = ready(tmp_path)
    en = root / "packs" / "en"
    grammar = en / GRAMMAR_FILE
    # The item was changed after its check.
    grammar.write_text(
        grammar.read_text(encoding="utf-8").replace("You ___ right.", "You ___ right here."),
        encoding="utf-8",
    )
    dictation = en / DICTATION_FILE
    dictation.write_text(
        dictation.read_text(encoding="utf-8").replace("my_right_hand_is_cold", "gone"),
        encoding="utf-8",
    )

    report = run_build(root, l1="tr", l2="en")

    assert report.packs == ()
    assert [(issue.key, issue.kind, issue.detail) for issue in report.issues] == [
        (
            "en.pgram.a1.be_present",
            "unvalidated_placement_item",
            "unvalidated: no check of this exact text",
        ),
        (
            "en.pdict.a.1",
            "unknown_dictation_sentence",
            "en.sent.gone is not a sentence of the pack",
        ),
    ]


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
    assert "- Gramer ve dikte raporu yok." in text
    assert "`reports/2026-09-29-qa.md`" in text


def test_the_report_writes_numbers_the_turkish_way(tmp_path: Path) -> None:
    root = ready(tmp_path)
    assert run_build(root, l1="tr", l2="en").issues == ()
    work = root / "work"
    audio = {
        "clips": 3637,
        "files": 3629,
        "made": 0,
        "by_voice": {"v1": 1169, "v2": 1160, "v3": 654},
        "slow": 1021,
        "minutes": 78.44,
        "megabytes": 23.5,
    }
    (work / "audio.en.report.json").write_text(json.dumps(audio), encoding="utf-8")
    placement = {
        "items": 360,
        "eligible_by_band": {"2": 918, "1": 796},
        "excluded": {"name": 40, "curated": 165},
        "pseudo_tried": 0,
        "pseudo_rejected": {},
    }
    (work / "placement.en.report.json").write_text(json.dumps(placement), encoding="utf-8")
    tests = {
        "grammar_by_level": {"A1": 12, "A2": 11},
        "issues": [{"id": "a2.any", "kind": "disputed", "detail": "the check accepts: any, some"}],
        "hard_words": {},
        "dictation": 15,
        "dictation_eligible": {"A1": 1108, "A2": 35},
    }
    (work / "placement_tests.en.report.json").write_text(json.dumps(tests), encoding="utf-8")

    result = CliRunner().invoke(app, ["report", "--content-dir", str(root)])

    assert result.exit_code == 0, result.output
    text = (root / "build" / "en@1.report.md").read_text(encoding="utf-8")
    assert "- 3.637 klip, 3.629 dosya; 78,4 dakika, 23,5 MB; yavaş 1.021" in text
    assert "- Ses başına klip: v1 1.169, v2 1.160, v3 654" in text
    assert "- Uygun kelime: 1. bant 796, 2. bant 918" in text
    assert "- Dışlanan: küratörlükle dışlanan 165, özel ad 40" in text
    assert "- Gramer maddesi: A1 12, A2 11; bankaya alınmayan 1" in text
    assert "- Dikte: 15 cümle; uygun cümle: A1 1.108, A2 35" in text
    assert "{" not in text.split("## Sesler")[1]


def test_chunks_take_ranks_spread_over_the_words_of_their_level() -> None:
    own = Provenance(source="dilbaz curation", license="own")

    def sense(lemma: str, level: str, rank: int | None) -> WordSense:
        return WordSense(
            key=f"en.ws.{lemma}.n.1",
            lemma=lemma,
            pos="NOUN",
            sense="a thing",
            level=level,
            rank=rank,
            provenance=own,
        )

    def chunk(name: str, level: str) -> Chunk:
        return Chunk(
            key=f"en.chunk.{name}", text=name, level=level, function="greeting", provenance=own
        )

    senses = [sense(f"w{rank}", "A0", rank) for rank in (40, 10, 30, 20, 60, 50)]
    senses += [sense("later", "A1", 500), sense("unranked", "A1", None)]
    kit = [chunk("first", "A0"), chunk("next", "A1"), chunk("second", "A0"), chunk("third", "A0")]

    ranks = chunk_ranks([*kit, chunk("alone", "A2")], senses)

    # Three A0 chunks over six A0 words: every second rank, in the kit's order.
    assert ranks == {
        "en.chunk.first": 10,
        "en.chunk.second": 30,
        "en.chunk.third": 50,
        "en.chunk.next": 500,
    }


def test_the_pack_tables_are_the_app_content_tables() -> None:
    """The app copies pack rows as they are (docs/11 §5.1): same tables, same columns.

    The app side is drift's exported schema snapshot; its content tables other
    than `content_packs`, which the app fills itself, must match what S9 creates.
    """
    snapshots = Path(__file__).resolve().parents[3] / "app" / "drift_schemas" / "app_database"
    latest = max(snapshots.glob("drift_schema_v*.json"), key=lambda f: int(f.stem.split("_v")[1]))
    schema = json.loads(latest.read_text(encoding="utf-8"))
    app = {
        entity["data"]["name"]: [
            (column["name"], column["nullable"]) for column in entity["data"]["columns"]
        ]
        for entity in schema["entities"]
        if entity["type"] == "table" and entity["data"]["name"].startswith("content_")
    }
    del app["content_packs"]

    pack: dict[str, list[tuple[str, bool]]] = {}
    for ddl in (TARGET_TABLES, PAIR_TABLES):
        with sqlite3.connect(":memory:") as db:
            db.executescript(ddl)
            for (name,) in db.execute("SELECT name FROM sqlite_master WHERE type = 'table'"):
                columns = db.execute(f"PRAGMA table_info({name})").fetchall()
                # A primary-key column is never null, whatever its declaration says.
                pack[name] = [(c[1], not c[3] and not c[5]) for c in columns]
        db.close()
    del pack["pack_meta"]

    assert pack == app

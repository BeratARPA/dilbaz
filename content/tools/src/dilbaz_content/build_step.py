"""S9: pack build (docs/10-content-pipeline.md §4.6, docs/11 §5).

Builds one SQLite file per pack version in `build/`: the target pack
(`en@1.sqlite`) and the pair pack (`tr-en@1.sqlite`). Their tables are the
drift content tables that the app imports (docs/13: `content_items`,
`content_links`, `content_forms`, `content_pair_entries`…); kind-specific
fields go in the `data` JSON column, pack settings (manifest, normalization,
voices) in `pack_meta`. Next to each file: `<id>.manifest.json` with the
file's sha256, and `<id>.LICENSES.md`.

Nothing is written when a check fails:
- every sentence has an accepted independent validation of its exact text
  (I-16, docs/10 §5.2);
- every sentence, chunk and word sense has its clips (S6), and their files
  exist;
- every item has a gloss in the pair pack (S5);
- every link names an item of the packs.
"""

from __future__ import annotations

import hashlib
import json
import re
import sqlite3
from collections import Counter
from collections.abc import Iterable
from datetime import UTC, datetime
from pathlib import Path
from typing import Literal

import yaml
from pydantic import BaseModel, ConfigDict

from dilbaz_content.audio_step import AUDIO_FILE, PACK_VERSION, VOICES_FILE, Clip
from dilbaz_content.carriers_step import read_word_senses
from dilbaz_content.items import Chunk, GrammarPoint, Sentence
from dilbaz_content.lexicon import LexiconEntry
from dilbaz_content.manifest import Manifest, load_manifest
from dilbaz_content.normalize import NORMALIZATION_FILE
from dilbaz_content.placement_step import XLEX_FILE, XlexItem
from dilbaz_content.select_step import read_lexicon
from dilbaz_content.sentences_step import VALIDATION_FILE, read_validation

MANIFEST_FILE = "manifest.yaml"
# Bumped when the tables of the pack file change; the app checks it.
FORMAT_VERSION = 1
REPORT_FILE = "build.report.json"

_TABLES_COMMON = """
CREATE TABLE pack_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE content_links (
  from_key TEXT NOT NULL, to_key TEXT NOT NULL, type TEXT NOT NULL, pack_id TEXT NOT NULL,
  PRIMARY KEY (from_key, to_key, type));
"""
TARGET_TABLES = (
    _TABLES_COMMON
    + """
CREATE TABLE content_items (
  key TEXT PRIMARY KEY, pack_id TEXT NOT NULL, kind TEXT NOT NULL, level TEXT NOT NULL,
  text_l2 TEXT, lemmas TEXT NOT NULL DEFAULT '[]', targets TEXT NOT NULL DEFAULT '[]',
  grammar TEXT NOT NULL DEFAULT '[]', rank INTEGER, deprecated INTEGER NOT NULL DEFAULT 0,
  data TEXT NOT NULL DEFAULT '{}');
CREATE TABLE content_forms (
  form TEXT NOT NULL, lemma TEXT NOT NULL, pack_id TEXT NOT NULL, PRIMARY KEY (form, lemma));
CREATE TABLE content_texts (
  key TEXT PRIMARY KEY, pack_id TEXT NOT NULL, kind TEXT NOT NULL, level TEXT NOT NULL,
  lemmas TEXT NOT NULL DEFAULT '[]', data TEXT NOT NULL DEFAULT '{}');
CREATE TABLE content_tasks (
  key TEXT PRIMARY KEY, pack_id TEXT NOT NULL, kind TEXT NOT NULL, level TEXT NOT NULL,
  data TEXT NOT NULL DEFAULT '{}');
"""
)
PAIR_TABLES = (
    _TABLES_COMMON
    + """
CREATE TABLE content_pair_entries (
  kind TEXT NOT NULL, key TEXT NOT NULL, pack_id TEXT NOT NULL, data TEXT NOT NULL,
  PRIMARY KEY (kind, key));
"""
)
# Items spoken in S6; each needs clips of at least two voices.
_SPOKEN = ("word_sense", "chunk", "sentence")
_PAIR_FILES = {
    "gloss": ("glosses.jsonl", "key"),
    "variants": ("variants.jsonl", "key"),
    "rule_note": ("rule_notes.jsonl", "code"),
    "error_tag": ("error_tags.jsonl", "code"),
}

IssueKind = Literal[
    "unvalidated_sentence", "missing_audio", "missing_audio_file", "missing_gloss", "unknown_link"
]


class BuildError(Exception):
    """A pack input is missing or broken."""


class Issue(BaseModel):
    """A problem that stops the build."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    key: str
    kind: IssueKind
    detail: str


class PackBuild(BaseModel):
    """One built pack file."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    id: str
    rows: dict[str, int]
    bytes: int
    sha256: str


class BuildReport(BaseModel):
    """`work/build.report.json`."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    packs: tuple[PackBuild, ...]
    issues: tuple[Issue, ...]


class _Row(BaseModel):
    """A `content_items` row."""

    model_config = ConfigDict(frozen=True)

    key: str
    kind: str
    level: str
    text_l2: str | None = None
    lemmas: tuple[str, ...] = ()
    targets: tuple[str, ...] = ()
    grammar: tuple[str, ...] = ()
    rank: int | None = None
    data: dict[str, object] = {}


def _json(value: object) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def _read[T: BaseModel](path: Path, model: type[T]) -> list[T]:
    if not path.is_file():
        raise BuildError(f"{path} is missing")
    with path.open(encoding="utf-8") as stream:
        return [model.model_validate_json(line) for line in stream if line.strip()]


def _read_dicts(path: Path) -> list[dict[str, object]]:
    if not path.is_file():
        raise BuildError(f"{path} is missing")
    with path.open(encoding="utf-8") as stream:
        return [json.loads(line) for line in stream if line.strip()]


def _slug(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", text.lower()).strip("_")


def _data(model: BaseModel, *fields: str, **extra: object) -> dict[str, object]:
    """Kind-specific fields of an item, without empty ones."""
    values = model.model_dump(include=set(fields), exclude_none=True, mode="json")
    return {**{k: v for k, v in values.items() if v not in ((), [], "")}, **extra}


def _target_rows(
    content_dir: Path, l2: str, audio: dict[str, list[Clip]]
) -> tuple[list[_Row], list[LexiconEntry]]:
    def clips(key: str) -> list[dict[str, object]]:
        return [clip.model_dump(exclude={"key"}) for clip in audio.get(key, [])]

    items = content_dir / "packs" / l2 / "items"
    senses = read_word_senses(items / "word_senses.jsonl")
    chunks = _read(items / "chunks.jsonl", Chunk)
    sentences = _read(items / "sentences.jsonl", Sentence)
    points = _read(items / "grammar_points.jsonl", GrammarPoint)
    lexicon = list(read_lexicon(content_dir / "work" / f"lexicon.{l2}.jsonl"))
    rank_of = {entry.lemma: entry.rank for entry in lexicon}
    xlex = _read(content_dir / "packs" / l2 / XLEX_FILE, XlexItem)

    rows = [
        _Row(
            key=s.key,
            kind="word_sense",
            level=s.level,
            text_l2=s.lemma,
            lemmas=(s.lemma,),
            rank=s.rank,
            data=_data(
                s, "pos", "sense", "ipa_us", "ipa_uk", "carriers", "provenance", audio=clips(s.key)
            ),
        )
        for s in senses
    ]
    rows += [
        _Row(
            key=c.key,
            kind="chunk",
            level=c.level,
            text_l2=c.text,
            lemmas=c.lemmas,
            data=_data(c, "function", "note", "provenance", audio=clips(c.key)),
        )
        for c in chunks
    ]
    rows += [
        _Row(
            key=s.key,
            kind="sentence",
            level=s.level,
            text_l2=s.text,
            lemmas=s.lemmas,
            targets=s.targets,
            grammar=s.grammar,
            data=_data(s, "provenance", audio=clips(s.key)),
        )
        for s in sentences
    ]
    rows += [
        _Row(
            key=p.key,
            kind="grammar_point",
            level=p.level,
            text_l2=p.name,
            data=_data(p, "code", "description", "examples", "provenance"),
        )
        for p in points
    ]
    # The lexicon, for personal coverage (I-06) and the X_Lex bands.
    seen: set[str] = set()
    for entry in lexicon:
        key = f"{l2}.lemma.{_slug(entry.lemma)}"
        if entry.multiword or key in seen:
            continue
        seen.add(key)
        rows.append(
            _Row(
                key=key,
                kind="lemma",
                level=entry.cefr or "",
                text_l2=entry.display,
                lemmas=(entry.lemma,),
                rank=entry.rank,
                data=_data(entry, "pos", "ipa_us", "ipa_uk"),
            )
        )
    rows += [
        _Row(
            key=f"{l2}.xlex.{item.version}.{_slug(item.word)}",
            kind="xlex",
            level="",
            text_l2=item.word,
            rank=None if item.is_pseudo else rank_of.get(item.word),
            data={"version": item.version, "band": item.band, "is_pseudo": item.is_pseudo},
        )
        for item in xlex
    ]
    return rows, lexicon


def _forms(lexicon: Iterable[LexiconEntry]) -> set[tuple[str, str]]:
    """Surface form → lemma, for runtime lemmatization (docs/11 §6)."""
    pairs: set[tuple[str, str]] = set()
    for entry in lexicon:
        if entry.multiword:
            continue
        for form in (entry.lemma, *entry.spellings, *entry.forms):
            if " " not in form:
                pairs.add((form.lower(), entry.lemma))
    return pairs


def _validation_issues(content_dir: Path, l2: str, rows: Iterable[_Row]) -> list[Issue]:
    decisions = read_validation(content_dir / "curation" / l2 / VALIDATION_FILE)
    issues: list[Issue] = []
    for row in rows:
        if row.kind != "sentence":
            continue
        decision = decisions.get(row.key)
        if decision is None or decision.text != row.text_l2 or not decision.accepted:
            issues.append(
                Issue(key=row.key, kind="unvalidated_sentence", detail="no accepted validation")
            )
    return issues


def _audio_issues(
    rows: Iterable[_Row], audio: dict[str, list[Clip]], audio_dir: Path
) -> list[Issue]:
    issues: list[Issue] = []
    for row in rows:
        if row.kind not in _SPOKEN:
            continue
        clips = audio.get(row.key, [])
        if len({clip.voice for clip in clips if clip.speed == 1.0}) < 2:
            issues.append(Issue(key=row.key, kind="missing_audio", detail="fewer than 2 voices"))
        issues += [
            Issue(
                key=row.key, kind="missing_audio_file", detail=f"{clip.file} is not in {audio_dir}"
            )
            for clip in clips
            if not (audio_dir / clip.file).is_file()
        ]
    return issues


def _write_pack(
    path: Path,
    tables: str,
    meta: dict[str, object],
    inserts: dict[str, list[tuple[object, ...]]],
) -> dict[str, int]:
    """Writes a pack file from scratch; returns the row count per table."""
    partial = path.with_name(path.name + ".part")
    partial.unlink(missing_ok=True)
    with sqlite3.connect(partial) as db:
        db.executescript(tables)
        db.execute(f"PRAGMA user_version = {FORMAT_VERSION}")
        db.executemany(
            "INSERT INTO pack_meta VALUES (?, ?)", [(k, _json(v)) for k, v in meta.items()]
        )
        for table, rows in inserts.items():
            if rows:
                marks = ", ".join("?" * len(rows[0]))
                db.executemany(f"INSERT INTO {table} VALUES ({marks})", rows)
    db.close()
    with sqlite3.connect(partial) as db:
        db.execute("VACUUM")
    db.close()
    partial.replace(path)
    return {table: len(rows) for table, rows in inserts.items()}


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _licenses(manifest: Manifest) -> str:
    lines = [f"# {manifest.id}: licenses and attribution", ""]
    share_alike = [s.name for s in manifest.sources if "BY-SA" in s.license]
    if share_alike:
        lines += [
            "Parts of this pack come from CC BY-SA 4.0 sources"
            f" ({', '.join(share_alike)}), so the pack as a whole is distributed under"
            " CC BY-SA 4.0 (https://creativecommons.org/licenses/by-sa/4.0/).",
            "",
        ]
    lines += [
        "Items keep their own source and license in their `provenance`; a sentence or",
        "translation from Tatoeba names its author.",
        "",
        "## Sources",
        "",
    ]
    for source in manifest.sources:
        version = f" {source.version}" if source.version else ""
        lines.append(f"- **{source.name}{version}**: {source.license}. {source.attribution}")
    return "\n".join(lines) + "\n"


def _finish(
    out: Path, manifest: Manifest, path: Path, rows: dict[str, int], counts: dict[str, int]
) -> PackBuild:
    checksum = _sha256(path)
    final = manifest.model_copy(
        update={
            "counts": counts,
            "checksum": f"sha256:{checksum}",
            "created_at": datetime.now(UTC).date(),
        }
    )
    (out / f"{manifest.id}.manifest.json").write_text(
        final.model_dump_json(indent=2, exclude_none=True) + "\n", encoding="utf-8"
    )
    (out / f"{manifest.id}.LICENSES.md").write_text(_licenses(manifest), encoding="utf-8")
    return PackBuild(id=manifest.id, rows=rows, bytes=path.stat().st_size, sha256=checksum)


def run_build(content_dir: Path, *, l1: str, l2: str) -> BuildReport:
    """Builds `build/<l2>@N.sqlite` and `build/<l1>-<l2>@N.sqlite`."""
    packs = content_dir / "packs"
    target = load_manifest(packs / l2 / MANIFEST_FILE)
    pair = load_manifest(packs / f"{l1}-{l2}" / MANIFEST_FILE)
    if int(target.version) != PACK_VERSION:
        raise BuildError(f"{target.id}: the audio is made for version {PACK_VERSION}")

    audio: dict[str, list[Clip]] = {}
    for clip in _read(packs / l2 / AUDIO_FILE, Clip):
        audio.setdefault(clip.key, []).append(clip)
    rows, lexicon = _target_rows(content_dir, l2, audio)
    item_keys = {row.key for row in rows}

    pair_dir = packs / f"{l1}-{l2}"
    pair_rows: list[tuple[object, ...]] = []
    for kind, (name, key_field) in _PAIR_FILES.items():
        for entry in _read_dicts(pair_dir / name):
            key = str(entry.pop(key_field))
            pair_rows.append((kind, key, pair.id, _json(entry)))
    contrast_links: set[tuple[str, str]] = set()
    for entry in _read_dicts(pair_dir / "contrast_notes.jsonl"):
        listed = entry["items"]
        assert isinstance(listed, list)
        members = sorted(str(item) for item in listed)
        pair_rows.append(("contrast_note", "|".join(members), pair.id, _json(entry)))
        contrast_links |= {(a, b) for i, a in enumerate(members) for b in members[i + 1 :]}

    target_links = {
        (row.key, target_key, "contains")
        for row in rows
        if row.kind == "sentence"
        for target_key in row.targets
    } | {
        (row.key, f"{l2}.{code}", "example_of")
        for row in rows
        if row.kind == "sentence"
        for code in row.grammar
    }
    glossed = {str(key) for kind, key, _, _ in pair_rows if kind == "gloss"}
    issues = _validation_issues(content_dir, l2, rows)
    issues += _audio_issues(rows, audio, content_dir / "build" / "audio" / l2 / str(PACK_VERSION))
    issues += [
        Issue(key=row.key, kind="missing_gloss", detail="no gloss in the pair pack")
        for row in rows
        if row.kind in (*_SPOKEN, "grammar_point") and row.key not in glossed
    ]
    issues += [
        Issue(key=a, kind="unknown_link", detail=f"{b} ({kind}) is not an item")
        for a, b, kind in sorted(
            target_links | {(a, b, "contrasts_with") for a, b in contrast_links}
        )
        if a not in item_keys or b not in item_keys
    ]
    if issues:
        return BuildReport(packs=(), issues=tuple(issues))

    out = content_dir / "build"
    out.mkdir(parents=True, exist_ok=True)
    counts = dict(sorted(Counter(row.kind for row in rows).items()))
    normalization = yaml.safe_load((packs / l2 / NORMALIZATION_FILE).read_text(encoding="utf-8"))
    voices = yaml.safe_load((packs / l2 / VOICES_FILE).read_text(encoding="utf-8"))
    meta_target: dict[str, object] = {
        "format_version": FORMAT_VERSION,
        "manifest": target.model_dump(mode="json", exclude_none=True) | {"counts": counts},
        "normalization": normalization,
        "voices": voices,
        "audio": {"bucket": "pack-audio", "prefix": f"{l2}/{PACK_VERSION}/"},
    }
    target_path = out / f"{target.id}.sqlite"
    target_counts = _write_pack(
        target_path,
        TARGET_TABLES,
        meta_target,
        {
            "content_items": [
                (
                    row.key,
                    target.id,
                    row.kind,
                    row.level,
                    row.text_l2,
                    _json(row.lemmas),
                    _json(row.targets),
                    _json(row.grammar),
                    row.rank,
                    0,
                    _json(row.data),
                )
                for row in rows
            ],
            "content_links": [(a, b, kind, target.id) for a, b, kind in sorted(target_links)],
            "content_forms": [(form, lemma, target.id) for form, lemma in sorted(_forms(lexicon))],
        },
    )
    pair_counts_by_kind = dict(sorted(Counter(str(row[0]) for row in pair_rows).items()))
    pair_path = out / f"{pair.id}.sqlite"
    pair_table_counts = _write_pack(
        pair_path,
        PAIR_TABLES,
        {
            "format_version": FORMAT_VERSION,
            "manifest": pair.model_dump(mode="json", exclude_none=True)
            | {"counts": pair_counts_by_kind},
        },
        {
            "content_pair_entries": sorted(pair_rows, key=lambda r: (str(r[0]), str(r[1]))),
            "content_links": [(a, b, "contrasts_with", pair.id) for a, b in sorted(contrast_links)],
        },
    )
    built = (
        _finish(out, target, target_path, target_counts, counts),
        _finish(out, pair, pair_path, pair_table_counts, pair_counts_by_kind),
    )
    report = BuildReport(packs=built, issues=())
    work = content_dir / "work"
    work.mkdir(parents=True, exist_ok=True)
    (work / REPORT_FILE).write_text(report.model_dump_json(indent=2) + "\n", encoding="utf-8")
    return report

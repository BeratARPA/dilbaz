"""S10: the build report (docs/10-content-pipeline.md §4).

`build/<id>.report.md` gathers what the steps recorded, for the person who
approves the upload: the built files and their checksums, items by kind and
level, the independent validation, audio, the placement bank, sources and
licenses, and the human checks. The report is in Turkish, like the QA
reports it links to.
"""

from __future__ import annotations

import json
from collections import Counter
from pathlib import Path

from pydantic import BaseModel

from dilbaz_content.audio_step import REPORT_FILE as AUDIO_REPORT
from dilbaz_content.audio_step import AudioReport
from dilbaz_content.build_step import MANIFEST_FILE, BuildReport
from dilbaz_content.build_step import REPORT_FILE as BUILD_REPORT
from dilbaz_content.manifest import load_manifest
from dilbaz_content.placement_step import REPORT_FILE as PLACEMENT_REPORT
from dilbaz_content.placement_step import PlacementReport
from dilbaz_content.sentences_step import VALIDATION_FILE

LEVELS = ("A0", "A1", "A2", "B1", "B2", "C1", "C2")
_KINDS = {
    "word_sense": "kelime anlamı",
    "chunk": "kalıp",
    "sentence": "cümle",
    "grammar_point": "gramer noktası",
    "lemma": "sözlük lemması",
    "xlex": "X_Lex maddesi",
}


def _report[T: BaseModel](path: Path, model: type[T]) -> T | None:
    return model.model_validate_json(path.read_text(encoding="utf-8")) if path.is_file() else None


def _lines(path: Path) -> list[dict[str, object]]:
    if not path.is_file():
        return []
    with path.open(encoding="utf-8") as stream:
        return [json.loads(line) for line in stream if line.strip()]


def _validation(path: Path) -> list[str]:
    """Decisions per round; the last line of a key is the one that counts."""
    decisions = _lines(path)
    rounds: Counter[tuple[int, bool]] = Counter()
    for decision in decisions:
        rounds[(int(str(decision["round"])), bool(decision["accepted"]))] += 1
    latest = {str(d["key"]): d for d in decisions}
    out = [
        f"- {number}. tur: {rounds[(number, True)] + rounds[(number, False)]} karar, "
        f"{rounds[(number, True)]} kabul"
        for number in sorted({r for r, _ in rounds})
    ]
    overrides = sum(1 for d in latest.values() if d.get("override"))
    out.append(f"- Geçerli kararlar: {len(latest)}, gerekçeli istisna {overrides}")
    return out


def build_report(content_dir: Path, *, l1: str, l2: str) -> Path:
    """Writes `build/<l2>@N.report.md`; returns its path."""
    target = load_manifest(content_dir / "packs" / l2 / MANIFEST_FILE)
    work = content_dir / "work"
    built = _report(work / BUILD_REPORT, BuildReport)
    lines = [f"# {target.id} derleme raporu", ""]

    lines += ["## Dosyalar", "", "| Paket | Satırlar | Boyut | sha256 |", "|---|---|---|---|"]
    packs = built.packs if built else ()
    for pack in packs:
        rows = ", ".join(f"{table} {count:,}" for table, count in pack.rows.items())
        size = pack.bytes / 1_048_576
        lines.append(f"| {pack.id} | {rows} | {size:.1f} MB | `{pack.sha256[:16]}…` |")
    if not packs:
        lines.append("| — | derleme raporu yok | | |")

    items = content_dir / "packs" / l2 / "items"
    by_level: dict[str, Counter[str]] = {}
    for kind, name in (
        ("word_sense", "word_senses"),
        ("chunk", "chunks"),
        ("sentence", "sentences"),
        ("grammar_point", "grammar_points"),
    ):
        by_level[kind] = Counter(str(row["level"]) for row in _lines(items / f"{name}.jsonl"))
    lines += ["", "## Öğeler", "", "| Tür | " + " | ".join(LEVELS[:3]) + " | Toplam |"]
    lines.append("|---" * 5 + "|")
    for kind, levels in by_level.items():
        cells = " | ".join(str(levels.get(level, 0)) for level in LEVELS[:3])
        lines.append(f"| {_KINDS[kind]} | {cells} | {sum(levels.values())} |")

    lines += ["", "## Bağımsız doğrulama (S4)", ""]
    lines += _validation(content_dir / "curation" / l2 / VALIDATION_FILE)

    audio = _report(work / AUDIO_REPORT.format(l2=l2), AudioReport)
    lines += ["", "## Sesler (S6)", ""]
    if audio:
        lines.append(
            f"- {audio.clips:,} klip, {audio.files:,} dosya; {audio.minutes} dakika, "
            f"{audio.megabytes} MB; yavaş {audio.slow:,}; ses başına {audio.by_voice}"
        )
    else:
        lines.append("- Ses raporu yok.")

    placement = _report(work / PLACEMENT_REPORT.format(l2=l2), PlacementReport)
    lines += ["", "## X_Lex bankası (S8)", ""]
    if placement:
        lines.append(
            f"- {placement.items} madde; bant başına uygun kelime "
            f"{placement.eligible_by_band}; dışlanan {placement.excluded}"
        )
    else:
        lines.append("- X_Lex raporu yok.")

    lines += ["", "## Kaynaklar ve lisanslar", ""]
    lines += [f"- {s.name}: {s.license}" for s in target.sources]
    lines += [
        "",
        f"Ayrıntı: `{target.id}.LICENSES.md`. Çift paketi: `{l1}-{l2}@"
        f"{int(target.version)}.LICENSES.md`.",
    ]

    reports = sorted((content_dir / "reports").glob("*.md"))
    lines += ["", "## İnsan kontrolleri ve QA raporları", ""]
    lines += [f"- `reports/{path.name}`" for path in reports] or ["- QA raporu yok."]

    out = content_dir / "build" / f"{target.id}.report.md"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return out

"""`dilbaz-content` command line (docs/10-content-pipeline.md §4)."""

from __future__ import annotations

from collections import Counter
from collections.abc import Sequence
from datetime import UTC, datetime
from pathlib import Path
from typing import Annotated

import typer
from pydantic import ValidationError
from rich.console import Console
from rich.progress import BarColumn, DownloadColumn, Progress, TextColumn, TransferSpeedColumn
from rich.table import Table
from wordfreq import word_frequency

from dilbaz_content import __version__
from dilbaz_content.analysis import SpacyAnalyzer
from dilbaz_content.carriers_step import run_carriers
from dilbaz_content.ingest import (
    ChecksumMismatchError,
    OnProgress,
    PackageVersionError,
    ingest_source,
)
from dilbaz_content.items import LEVELS, Chunk, GrammarPoint, Level, WordSense
from dilbaz_content.lexicon_step import LEXICON_FILE, run_lexicon
from dilbaz_content.manifest import load_manifest
from dilbaz_content.select_step import SelectionError, run_select
from dilbaz_content.sentences_step import run_sentences
from dilbaz_content.sources import (
    REGISTRY_FILE,
    DataSource,
    SourceFile,
    find_content_dir,
    load_registry,
)

app = typer.Typer(
    help="Builds, validates and reports Dilbaz language packs.",
    no_args_is_help=True,
)
console = Console()

ContentDir = Annotated[
    Path | None,
    typer.Option(help="The content/ directory (default: found from the working directory)."),
]


def _content_dir(option: Path | None) -> Path:
    try:
        return option if option is not None else find_content_dir(Path.cwd())
    except FileNotFoundError as error:
        console.print(f"[red]{error}[/red]; pass --content-dir")
        raise typer.Exit(code=2) from error


@app.command()
def version() -> None:
    """Print the tool version."""
    console.print(__version__)


@app.command("check-manifest")
def check_manifest(
    path: Annotated[Path, typer.Argument(exists=True, dir_okay=False, readable=True)],
) -> None:
    """Validate a pack manifest, including source licenses (I-16)."""
    try:
        manifest = load_manifest(path)
    except ValidationError as error:
        console.print(f"[red]invalid manifest[/red] {path}")
        console.print(str(error))
        raise typer.Exit(code=1) from error
    console.print(f"{manifest.id}: {len(manifest.sources)} source(s), licenses recorded")


@app.command()
def ingest(
    source_ids: Annotated[
        list[str] | None, typer.Argument(help="Source ids to fetch; all if omitted.")
    ] = None,
    content_dir: ContentDir = None,
    refresh: Annotated[
        bool, typer.Option(help="Download rolling exports (Tatoeba, Wiktextract) again.")
    ] = False,
) -> None:
    """S0: download the registered sources into content/sources/, checksummed."""
    root = _content_dir(content_dir)
    registry = load_registry(root / REGISTRY_FILE)
    try:
        chosen: list[DataSource] = (
            [registry.get(i) for i in source_ids] if source_ids else list(registry.sources)
        )
    except KeyError as error:
        console.print(f"[red]unknown source {error}[/red]")
        raise typer.Exit(code=2) from error
    now = datetime.now(UTC)
    columns = (TextColumn("{task.description}"), BarColumn(), DownloadColumn())
    with Progress(*columns, TransferSpeedColumn(), console=console) as bars:

        def listener(file: SourceFile) -> OnProgress:
            task = bars.add_task(file.name, total=None)

            def update(done: int, total: int | None) -> None:
                bars.update(task, completed=done, total=total)

            return update

        for source in chosen:
            try:
                snapshot = ingest_source(
                    source, root / "sources", now, progress=listener, refresh=refresh
                )
            except (ChecksumMismatchError, PackageVersionError) as error:
                console.print(f"[red]{source.id}[/red]: {error}")
                raise typer.Exit(code=1) from error
            if snapshot is None:
                console.print(f"{source.id}: package {source.package} {source.version} ok")
                continue
            console.print(f"{source.id}: {len(snapshot.files)} file(s) ok")
            pins = {file.name: file.sha256 for file in source.files}
            for record in snapshot.files:
                if not source.rolling and pins.get(record.name) is None:
                    console.print(f"  [yellow]unpinned[/yellow] {record.name} {record.sha256}")


@app.command()
def lexicon(content_dir: ContentDir = None) -> None:
    """S1: build work/lexicon.en.jsonl from the ingested sources."""
    root = _content_dir(content_dir)
    registry = load_registry(root / REGISTRY_FILE)
    with console.status("building the lexicon") as status:
        report = run_lexicon(
            registry,
            root,
            frequency=lambda word: word_frequency(word, "en"),
            progress=lambda lines: status.update(f"reading Wiktionary: {lines:,} lines"),
        )
    table = Table(title=f"{LEXICON_FILE}: {report.entries:,} entries")
    table.add_column("measure")
    table.add_column("count", justify="right")
    for level, count in report.by_level.items():
        table.add_row(f"level {level}", f"{count:,}")
    for name in ("multiword", "with_ipa_us", "with_ipa_uk", "with_arpabet", "with_senses"):
        table.add_row(name, f"{getattr(report, name):,}")
    for name in ("ngsl", "ngsl_spoken", "top_5000_with_level"):
        table.add_row(name, f"{getattr(report, name):,}")
    console.print(table)


@app.command()
def select(
    content_dir: ContentDir = None,
    l2: Annotated[str, typer.Option(help="Target language of the pack.")] = "en",
    max_level: Annotated[str, typer.Option(help="Highest level to select.")] = "A2",
    limit: Annotated[int, typer.Option(help="About how many word senses to take.")] = 600,
) -> None:
    """S2: select word senses, chunks and grammar points into packs/<l2>/items/."""
    root = _content_dir(content_dir)
    if max_level not in LEVELS:
        console.print(f"[red]unknown level {max_level}[/red]")
        raise typer.Exit(code=2)
    level: Level = max_level
    try:
        selection = run_select(root, l2=l2, max_level=level, limit=limit)
    except (SelectionError, FileNotFoundError) as error:
        console.print(f"[red]{error}[/red]")
        raise typer.Exit(code=1) from error
    table = Table(title=f"packs/{l2}/items")
    table.add_column("kind")
    for name in LEVELS[: LEVELS.index(level) + 1]:
        table.add_column(name, justify="right")
    table.add_column("total", justify="right")
    kinds: dict[str, Sequence[WordSense | Chunk | GrammarPoint]] = {
        "word senses": selection.word_senses,
        "chunks": selection.chunks,
        "grammar points": selection.grammar_points,
    }
    for kind, items in kinds.items():
        counts = [sum(item.level == name for item in items) for name in LEVELS]
        table.add_row(kind, *(str(n) for n in counts[: LEVELS.index(level) + 1]), str(len(items)))
    console.print(table)
    last = max((sense.rank or 0 for sense in selection.word_senses), default=0)
    console.print(f"word senses reach frequency rank {last}")


@app.command()
def carriers(
    content_dir: ContentDir = None,
    l2: Annotated[str, typer.Option(help="Target language of the pack.")] = "en",
    per_target: Annotated[int, typer.Option(help="Candidates kept per word sense.")] = 3,
) -> None:
    """S3: find Tatoeba carrier candidates for the selected word senses."""
    root = _content_dir(content_dir)
    registry = load_registry(root / REGISTRY_FILE)
    try:
        with console.status("analyzing Tatoeba sentences") as status:
            lines = run_carriers(
                registry,
                root,
                l2=l2,
                analyzer=SpacyAnalyzer,
                per_target=per_target,
                progress=lambda done: status.update(f"analyzed {done:,} sentences"),
            )
    except FileNotFoundError as error:
        console.print(f"[red]{error}[/red]")
        raise typer.Exit(code=1) from error
    counts = [sum(len(line.candidates) == n for line in lines) for n in range(per_target + 1)]
    console.print(f"{len(lines)} word senses; by number of candidates 0..{per_target}: {counts}")
    console.print(f"written to work/carriers.{l2}.candidates.jsonl")


@app.command()
def sentences(
    content_dir: ContentDir = None,
    l2: Annotated[str, typer.Option(help="Target language of the pack.")] = "en",
) -> None:
    """S4: build the carrier sentences from the candidates and the curation, and check them."""
    root = _content_dir(content_dir)
    try:
        with console.status("building carrier sentences"):
            report = run_sentences(root, l2=l2, analyzer=SpacyAnalyzer)
    except (FileNotFoundError, ValueError) as error:
        console.print(f"[red]{error}[/red]")
        raise typer.Exit(code=1) from error
    console.print(
        f"{report.sentences} sentences ({report.tatoeba} Tatoeba, {report.own} own); "
        f"levels {report.by_level}; validated {report.validated}"
    )
    kinds = Counter(issue.kind for issue in report.issues)
    console.print(f"issues: {dict(kinds) or 'none'}")
    if report.senses_without_carrier:
        console.print(f"[red]senses without a carrier:[/red] {list(report.senses_without_carrier)}")
    if report.blocking or report.senses_without_carrier:
        raise typer.Exit(code=1)

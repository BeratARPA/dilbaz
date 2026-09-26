"""`dilbaz-content` command line (docs/10-content-pipeline.md §4)."""

from __future__ import annotations

from pathlib import Path
from typing import Annotated

import typer
from pydantic import ValidationError
from rich.console import Console

from dilbaz_content import __version__
from dilbaz_content.manifest import load_manifest

app = typer.Typer(
    help="Builds, validates and reports Dilbaz language packs.",
    no_args_is_help=True,
)
console = Console()


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

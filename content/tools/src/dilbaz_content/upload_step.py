"""Upload: a built pack goes to Supabase, only with the user's approval (docs/10 §4.7).

The target comes from the environment: `SUPABASE_URL` and `SUPABASE_SECRET_KEY`
(a secret `sb_secret_…` key, which acts as the service role). The key is
never read from a file, printed or logged; the user runs this command.

The files go first: each pack's SQLite file and licenses to the `packs`
bucket, the clips to `pack-audio` (clips already there are skipped). The
registry row (`packs`) is written last, as a draft unless `publish` is set,
so the app never lists a pack whose files are not all in place. A pack whose
file does not match its manifest's checksum is not uploaded.
"""

from __future__ import annotations

import hashlib
import json
import urllib.error
import urllib.request
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Protocol

from pydantic import BaseModel, ConfigDict

from dilbaz_content.audio_step import AUDIO_FILE, PACK_VERSION, Clip

URL_ENV = "SUPABASE_URL"
KEY_ENV = "SUPABASE_SECRET_KEY"
PACK_BUCKET = "packs"
AUDIO_BUCKET = "pack-audio"
# Storage lists at most this many names per request.
_PAGE = 1000
_WORKERS = 8


class UploadError(Exception):
    """The upload cannot start or a request failed."""


class Store(Protocol):
    """The Supabase side of the upload."""

    def names(self, bucket: str, folder: str) -> set[str]:
        """File names directly in [folder] of [bucket]."""
        ...

    def put(self, bucket: str, path: str, data: bytes, content_type: str) -> None:
        """Writes a file, replacing one that is there."""
        ...

    def register(self, row: dict[str, object]) -> None:
        """Writes or replaces a `packs` row."""
        ...


class SupabaseStore:
    """Storage and PostgREST over HTTPS with a secret key."""

    def __init__(self, url: str, key: str) -> None:
        if not url.startswith(("https://", "http://127.0.0.1", "http://localhost")):
            raise UploadError(f"{URL_ENV} must be an https:// address")
        self._url = url.rstrip("/")
        self._key = key

    def _send(self, path: str, data: bytes, headers: dict[str, str]) -> bytes:
        request = urllib.request.Request(
            f"{self._url}{path}",
            data=data,
            method="POST",
            headers={"apikey": self._key, "Authorization": f"Bearer {self._key}", **headers},
        )
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return bytes(response.read())
        except urllib.error.HTTPError as error:
            # The body names the problem; the request (and its key) is not echoed.
            detail = error.read().decode("utf-8", errors="replace")[:300]
            raise UploadError(f"{path}: HTTP {error.code} {detail}") from None

    def names(self, bucket: str, folder: str) -> set[str]:
        found: set[str] = set()
        offset = 0
        while True:
            body = json.dumps({"prefix": folder, "limit": _PAGE, "offset": offset}).encode()
            page = json.loads(
                self._send(
                    f"/storage/v1/object/list/{bucket}",
                    body,
                    {"Content-Type": "application/json"},
                )
            )
            found |= {str(item["name"]) for item in page}
            if len(page) < _PAGE:
                return found
            offset += _PAGE

    def put(self, bucket: str, path: str, data: bytes, content_type: str) -> None:
        self._send(
            f"/storage/v1/object/{bucket}/{path}",
            data,
            {"Content-Type": content_type, "x-upsert": "true"},
        )

    def register(self, row: dict[str, object]) -> None:
        self._send(
            "/rest/v1/packs",
            json.dumps(row).encode(),
            {
                "Content-Type": "application/json",
                "Prefer": "resolution=merge-duplicates,return=minimal",
            },
        )


class UploadReport(BaseModel):
    """What went up."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    packs: tuple[str, ...]
    status: str
    clips_uploaded: int
    clips_present: int


def _manifest(build: Path, pack_id: str) -> dict[str, object]:
    path = build / f"{pack_id}.manifest.json"
    if not path.is_file():
        raise UploadError(f"{path} is missing; run `dilbaz-content build`")
    manifest: dict[str, object] = json.loads(path.read_text(encoding="utf-8"))
    checksum = hashlib.sha256((build / f"{pack_id}.sqlite").read_bytes()).hexdigest()
    if manifest.get("checksum") != f"sha256:{checksum}":
        raise UploadError(f"{pack_id}.sqlite does not match its manifest; build it again")
    return manifest


def run_upload(
    content_dir: Path,
    *,
    l1: str,
    l2: str,
    store: Store,
    publish: bool,
    progress: Callable[[int, int], None] | None = None,
) -> UploadReport:
    """Uploads the built packs of [l2] and [l1]-[l2] with their clips."""
    build = content_dir / "build"
    ids = (f"{l2}@{PACK_VERSION}", f"{l1}-{l2}@{PACK_VERSION}")
    manifests = {pack_id: _manifest(build, pack_id) for pack_id in ids}

    with (content_dir / "packs" / l2 / AUDIO_FILE).open(encoding="utf-8") as stream:
        files = sorted({Clip.model_validate_json(line).file for line in stream if line.strip()})
    prefix = f"{l2}/{PACK_VERSION}"
    present = set()
    for folder in sorted({file.rsplit("/", 1)[0] for file in files}):
        present |= {f"{folder}/{name}" for name in store.names(AUDIO_BUCKET, f"{prefix}/{folder}")}
    missing = [file for file in files if file not in present]
    audio_dir = build / "audio" / l2 / str(PACK_VERSION)

    def send(file: str) -> None:
        data = (audio_dir / file).read_bytes()
        store.put(AUDIO_BUCKET, f"{prefix}/{file}", data, "audio/mpeg")

    with ThreadPoolExecutor(max_workers=_WORKERS) as pool:
        for done, _ in enumerate(pool.map(send, missing), start=1):
            if progress is not None:
                progress(done, len(missing))

    status = "published" if publish else "draft"
    for pack_id in ids:
        store.put(
            PACK_BUCKET,
            f"{pack_id}.sqlite",
            (build / f"{pack_id}.sqlite").read_bytes(),
            "application/vnd.sqlite3",
        )
        store.put(
            PACK_BUCKET,
            f"{pack_id}.LICENSES.md",
            (build / f"{pack_id}.LICENSES.md").read_bytes(),
            "text/markdown",
        )
    # The rows go last: a listed pack has all its files.
    for pack_id, manifest in manifests.items():
        store.register(
            {
                "id": pack_id,
                "kind": manifest["kind"],
                "l2": manifest["l2"],
                "l1": manifest.get("l1"),
                "version": manifest["version"],
                "status": status,
                "manifest": manifest,
                "storage_path": f"{PACK_BUCKET}/{pack_id}.sqlite",
                "checksum": manifest["checksum"],
            }
        )
    return UploadReport(
        packs=ids, status=status, clips_uploaded=len(missing), clips_present=len(present)
    )

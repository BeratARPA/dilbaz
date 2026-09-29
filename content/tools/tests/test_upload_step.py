import io
import json
import urllib.error
import urllib.request
from pathlib import Path

import pytest
from typer.testing import CliRunner

from dilbaz_content import cli
from dilbaz_content.build_step import run_build
from dilbaz_content.cli import app
from dilbaz_content.upload_step import KEY_ENV, URL_ENV, SupabaseStore, UploadError, run_upload

from test_build_step import ready

KEY = "sb_secret_test"


class FakeStore:
    def __init__(self, present: dict[str, set[str]] | None = None) -> None:
        self.present = present or {}
        self.puts: list[tuple[str, str]] = []
        self.rows: list[dict[str, object]] = []
        self.order: list[str] = []

    def names(self, bucket: str, folder: str) -> set[str]:
        return self.present.get(f"{bucket}/{folder}", set())

    def put(self, bucket: str, path: str, data: bytes, content_type: str) -> None:
        self.puts.append((bucket, path))
        self.order.append("put")

    def register(self, row: dict[str, object]) -> None:
        self.rows.append(row)
        self.order.append("register")


def built(tmp_path: Path) -> Path:
    root = ready(tmp_path)
    assert run_build(root, l1="tr", l2="en").issues == ()
    return root


def test_files_go_up_first_and_the_rows_last(tmp_path: Path) -> None:
    root = built(tmp_path)
    store = FakeStore(present={"pack-audio/en/1/v1": {"0000.mp3"}})

    report = run_upload(root, l1="tr", l2="en", store=store, publish=False)

    assert report.packs == ("en@1", "tr-en@1")
    assert report.status == "draft"
    assert report.clips_present == 1
    audio = [path for bucket, path in store.puts if bucket == "pack-audio"]
    assert len(audio) == report.clips_uploaded
    assert "en/1/v1/0000.mp3" not in audio
    assert all(path.startswith("en/1/") for path in audio)
    assert {path for bucket, path in store.puts if bucket == "packs"} == {
        "en@1.sqlite",
        "en@1.LICENSES.md",
        "tr-en@1.sqlite",
        "tr-en@1.LICENSES.md",
    }
    assert store.order[-2:] == ["register", "register"]
    assert "register" not in store.order[:-2]
    target = store.rows[0]
    assert target["id"] == "en@1"
    assert target["status"] == "draft"
    assert target["storage_path"] == "packs/en@1.sqlite"
    assert str(target["checksum"]).startswith("sha256:")
    assert store.rows[1]["l1"] == "tr"


def test_publish_lists_the_packs(tmp_path: Path) -> None:
    store = FakeStore()

    report = run_upload(built(tmp_path), l1="tr", l2="en", store=store, publish=True)

    assert report.status == "published"
    assert {row["status"] for row in store.rows} == {"published"}


def test_a_file_that_does_not_match_its_manifest_is_not_uploaded(tmp_path: Path) -> None:
    root = built(tmp_path)
    (root / "build" / "en@1.sqlite").write_bytes(b"changed")
    store = FakeStore()

    with pytest.raises(UploadError, match="does not match its manifest"):
        run_upload(root, l1="tr", l2="en", store=store, publish=True)
    assert store.puts == []


class Response(io.BytesIO):
    def __enter__(self) -> "Response":
        return self

    def __exit__(self, *args: object) -> None:
        self.close()


def test_the_store_speaks_storage_and_postgrest(monkeypatch: pytest.MonkeyPatch) -> None:
    requests: list[urllib.request.Request] = []
    pages = [[{"name": f"{i}.mp3"} for i in range(1000)], [{"name": "last.mp3"}]]

    def urlopen(request: urllib.request.Request, timeout: float) -> Response:
        requests.append(request)
        if "/object/list/" in request.full_url:
            return Response(json.dumps(pages.pop(0)).encode())
        return Response(b"{}")

    monkeypatch.setattr(urllib.request, "urlopen", urlopen)
    store = SupabaseStore("https://abc.supabase.co/", KEY)

    names = store.names("pack-audio", "en/1/v1")
    store.put("packs", "en@1.sqlite", b"db", "application/vnd.sqlite3")
    store.register({"id": "en@1"})

    assert len(names) == 1001
    listing = json.loads(requests[1].data)  # type: ignore[arg-type]
    assert listing == {"prefix": "en/1/v1", "limit": 1000, "offset": 1000}
    upload = requests[2]
    assert upload.full_url == "https://abc.supabase.co/storage/v1/object/packs/en@1.sqlite"
    assert upload.get_header("X-upsert") == "true"
    assert upload.get_header("Apikey") == KEY
    row = requests[3]
    assert row.full_url == "https://abc.supabase.co/rest/v1/packs"
    assert "merge-duplicates" in str(row.get_header("Prefer"))


def test_http_errors_do_not_repeat_the_key(monkeypatch: pytest.MonkeyPatch) -> None:
    def urlopen(request: urllib.request.Request, timeout: float) -> Response:
        raise urllib.error.HTTPError(
            request.full_url,
            403,
            "Forbidden",
            {},
            io.BytesIO(b'{"message":"denied"}'),  # type: ignore[arg-type]
        )

    monkeypatch.setattr(urllib.request, "urlopen", urlopen)
    store = SupabaseStore("https://abc.supabase.co", KEY)

    with pytest.raises(UploadError, match="HTTP 403") as caught:
        store.register({"id": "en@1"})
    assert KEY not in str(caught.value)


def test_only_https_or_a_local_stack_is_accepted() -> None:
    with pytest.raises(UploadError, match="https"):
        SupabaseStore("http://example.com", KEY)
    SupabaseStore("http://127.0.0.1:54321", KEY)


def test_the_upload_command_needs_the_environment(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    runner = CliRunner()
    root = built(tmp_path)
    monkeypatch.delenv(URL_ENV, raising=False)
    monkeypatch.delenv(KEY_ENV, raising=False)

    missing = runner.invoke(app, ["upload", "--content-dir", str(root)])
    assert missing.exit_code == 2
    assert KEY_ENV in missing.output

    store = FakeStore()
    monkeypatch.setenv(URL_ENV, "https://abc.supabase.co")
    monkeypatch.setenv(KEY_ENV, KEY)
    monkeypatch.setattr(cli, "SupabaseStore", lambda url, key: store)
    result = runner.invoke(app, ["upload", "--content-dir", str(root), "--publish"])

    assert result.exit_code == 0, result.output
    assert "published" in result.output
    assert KEY not in result.output
    assert [row["id"] for row in store.rows] == ["en@1", "tr-en@1"]

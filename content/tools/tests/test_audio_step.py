import json
import sys
from collections import Counter
from pathlib import Path

import pytest
from pydantic import ValidationError

from dilbaz_content.audio_step import (
    AudioError,
    VoiceSet,
    file_name,
    plan,
    run_audio,
    spoken,
    worker,
)
from dilbaz_content.items import Chunk, Provenance, Sentence, WordSense

OWN = Provenance(source="dilbaz curation", license="own")
VOICES = """
engine: kokoro-test
voices:
  - {id: v1, name: af_heart, locale: en-US, gender: female}
  - {id: v2, name: am_michael, locale: en-US, gender: male}
  - {id: v3, name: bf_emma, locale: en-GB, gender: female}
  - {id: v4, name: bm_george, locale: en-GB, gender: male}
pairs: [[v1, v3], [v2, v4]]
slow_speed: 0.8
slow_levels: [A0, A1]
"""


def voice_set() -> VoiceSet:
    import yaml

    return VoiceSet.model_validate(yaml.safe_load(VOICES))


def write_pack(root: Path) -> None:
    items = root / "packs" / "en" / "items"
    items.mkdir(parents=True)
    (root / "packs" / "en" / "voices.yaml").write_text(VOICES, encoding="utf-8")
    sentences = [
        Sentence(
            key="en.sent.close_it",
            text="Close it.",
            level="A1",
            lemmas=("close", "it"),
            targets=("en.ws.close.v.1",),
            provenance=OWN,
        ),
        Sentence(
            key="en.sent.it_is_close",
            text="It is close.",
            level="A2",
            lemmas=("it", "be", "close"),
            targets=("en.ws.close.adj.1",),
            provenance=OWN,
        ),
    ]
    chunks = [
        Chunk(
            key="en.chunk.my_name_is",
            text="My name is …",
            level="A0",
            function="introduce",
            provenance=OWN,
        )
    ]
    senses = [
        WordSense(
            key="en.ws.close.v.1",
            lemma="close",
            pos="VERB",
            sense="shut",
            level="A1",
            provenance=OWN,
        ),
        WordSense(
            key="en.ws.close.adj.1",
            lemma="close",
            pos="ADJ",
            sense="near",
            level="A2",
            provenance=OWN,
        ),
    ]
    for name, models in (("sentences", sentences), ("chunks", chunks), ("word_senses", senses)):
        (items / f"{name}.jsonl").write_text(
            "".join(m.model_dump_json() + "\n" for m in models), encoding="utf-8"
        )


class FakeWorker:
    """Writes a small file per job, like the TTS worker, and remembers the jobs."""

    def __init__(self) -> None:
        self.jobs: list[dict[str, object]] = []

    def __call__(self, jobs: Path) -> list[dict[str, object]]:
        results = []
        for line in jobs.read_text(encoding="utf-8").splitlines():
            job = json.loads(line)
            self.jobs.append(job)
            out = Path(job["out"])
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_bytes(b"mp3" * 10)
            results.append({"out": job["out"], "duration_ms": 1000 + len(job["text"])})
        return results


def test_a_chunk_is_spoken_without_its_gap() -> None:
    assert spoken("My name is …") == "My name is"
    assert spoken("Wait...") == "Wait"
    assert spoken("Hello.") == "Hello."


def test_file_names_depend_on_everything_spoken() -> None:
    voices = voice_set()
    v1, v2 = voices.voice("v1"), voices.voice("v2")
    name = file_name("e", v1, 1.0, "close", "VERB")

    assert name == file_name("e", v1, 1.0, "close", "VERB")
    assert name.startswith("v1/")
    assert name.endswith(".mp3")
    others = {
        file_name("e", v2, 1.0, "close", "VERB"),
        file_name("e", v1, 0.8, "close", "VERB"),
        file_name("e", v1, 1.0, "close", "ADJ"),
        file_name("e", v1, 1.0, "Close", "VERB"),
        file_name("f", v1, 1.0, "close", "VERB"),
    }
    assert name not in others
    assert len(others) == 5


def test_pairs_take_turns_and_slow_levels_get_a_slow_clip() -> None:
    items = [("a", "One.", None, "A1"), ("b", "Two.", None, "A2"), ("c", "Three.", None, "B1")]

    clips = plan(items, voice_set())

    assert [(c.key, c.voice.id, c.speed) for c in clips] == [
        ("a", "v1", 1.0),
        ("a", "v3", 1.0),
        ("a", "v1", 0.8),
        ("b", "v2", 1.0),
        ("b", "v4", 1.0),
        ("c", "v1", 1.0),
        ("c", "v3", 1.0),
    ]


def test_pairs_must_name_known_voices() -> None:
    with pytest.raises(ValidationError, match="unknown voices: v9"):
        VoiceSet.model_validate(
            {
                "engine": "e",
                "voices": [{"id": "v1", "name": "x", "locale": "en-US", "gender": "f"}],
                "pairs": [["v1", "v9"]],
                "slow_speed": 0.8,
            }
        )


def test_the_pack_is_spoken_once_and_the_manifest_written(tmp_path: Path) -> None:
    write_pack(tmp_path)
    speak = FakeWorker()
    seen: list[tuple[int, int]] = []

    report = run_audio(tmp_path, l2="en", speak=speak, progress=lambda d, t: seen.append((d, t)))

    # 5 items by 2 voices, plus a slow clip for the 3 items of A0-A1.
    assert report.clips == 13
    assert report.made == report.files == 13
    assert report.by_voice == {"v1": 5, "v3": 3, "v2": 3, "v4": 2}
    assert report.slow == 3
    assert seen[-1] == (13, 13)
    words = [job for job in speak.jobs if job["pos"]]
    assert {(job["text"], job["pos"]) for job in words} == {("close", "VERB"), ("close", "ADJ")}
    assert {job["lang"] for job in speak.jobs} == {"en-us", "en-gb"}
    assert "My name is" in {job["text"] for job in speak.jobs}
    manifest = tmp_path / "packs" / "en" / "audio.jsonl"
    lines = [json.loads(line) for line in manifest.open(encoding="utf-8")]
    assert Counter(line["key"] for line in lines)["en.chunk.my_name_is"] == 3
    assert all((tmp_path / "build/audio/en/1" / line["file"]).is_file() for line in lines)

    again = FakeWorker()
    second = run_audio(tmp_path, l2="en", speak=again)
    assert second.made == 0
    assert again.jobs == []


def test_clips_the_worker_did_not_make_stop_the_step(tmp_path: Path) -> None:
    write_pack(tmp_path)

    with pytest.raises(AudioError, match="13 clips were not made"):
        run_audio(tmp_path, l2="en", speak=lambda jobs: [])


def test_the_worker_command_streams_results(tmp_path: Path) -> None:
    script = "import json; print('warning'); print(json.dumps({'out': 'a.mp3', 'duration_ms': 5}))"
    speak = worker([sys.executable, "-c", script], tmp_path / "log.txt")

    assert list(speak(tmp_path / "jobs.jsonl")) == [{"out": "a.mp3", "duration_ms": 5}]

    failing = worker([sys.executable, "-c", "import sys; sys.exit(3)"], tmp_path / "log.txt")
    with pytest.raises(AudioError, match="stopped with 3"):
        list(failing(tmp_path / "jobs.jsonl"))

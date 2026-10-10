"""S6: pack audio (docs/10-content-pipeline.md §4.5, docs/08 §8).

Every sentence, chunk and word sense is read by two of the pack's voices
(`packs/<l2>/voices.yaml`): one American and one British, the pairs taking
turns. Items of the slow levels are read once more, slowly, by their first
voice. A word is spoken with its part of speech, so a heteronym sounds as its
sense does (close, adjective: /kloʊs/).

Kokoro runs in its own environment (`content/tts`, ADR-0009). This step
decides what to speak, names each file by a hash of what is spoken, so that
an unchanged clip is never made twice, and writes the audio manifest
`packs/<l2>/audio.jsonl`. The MP3 files go to `build/audio/<l2>/<version>/`,
the layout of the `pack-audio` bucket (docs/13).
"""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
from collections import Counter
from collections.abc import Callable, Iterable, Iterator, Sequence
from pathlib import Path

import yaml
from pydantic import BaseModel, ConfigDict, Field, model_validator

from dilbaz_content.carriers_step import read_word_senses
from dilbaz_content.items import Chunk, Level, Sentence

VOICES_FILE = "voices.yaml"
AUDIO_FILE = "audio.jsonl"
DURATIONS_FILE = "audio.{l2}.durations.json"
JOBS_FILE = "audio.{l2}.jobs.jsonl"
REPORT_FILE = "audio.{l2}.report.json"
PACK_VERSION = 1
# Save the durations of finished clips this often, so a stopped run loses little.
_SAVE_EVERY = 50

# The worker's output: {"out": path of the MP3, "duration_ms": length}.
Result = dict[str, object]
Speak = Callable[[Path], Iterable[Result]]


class AudioError(Exception):
    """The TTS worker failed."""


class Voice(BaseModel):
    """One voice of `voices.yaml`."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    id: str = Field(pattern=r"^v\d+$")
    name: str
    locale: str = Field(pattern=r"^[a-z]{2}-[A-Z]{2}$")
    gender: str


class VoiceSet(BaseModel):
    """`packs/<l2>/voices.yaml`."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    engine: str
    voices: tuple[Voice, ...] = Field(min_length=1)
    # Every item is read by one pair; the pairs take turns.
    pairs: tuple[tuple[str, str], ...] = Field(min_length=1)
    slow_speed: float = Field(gt=0.5, lt=1)
    slow_levels: tuple[Level, ...] = ()

    @model_validator(mode="after")
    def _known_voices(self) -> VoiceSet:
        ids = {voice.id for voice in self.voices}
        unknown = sorted({v for pair in self.pairs for v in pair} - ids)
        if unknown:
            raise ValueError(f"pairs name unknown voices: {', '.join(unknown)}")
        return self

    def voice(self, voice_id: str) -> Voice:
        return next(voice for voice in self.voices if voice.id == voice_id)


class Clip(BaseModel):
    """`audio.jsonl`: one clip of one item."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    key: str
    voice: str
    speed: float
    # Relative to `pack-audio/<l2>/<version>/`.
    file: str
    duration_ms: int


class AudioReport(BaseModel):
    """`work/audio.<l2>.report.json`."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    clips: int
    files: int
    made: int
    by_voice: dict[str, int]
    slow: int
    minutes: float
    megabytes: float


class _Planned(BaseModel):
    model_config = ConfigDict(frozen=True)

    key: str
    voice: Voice
    speed: float
    text: str
    pos: str | None
    file: str


def _read[T: BaseModel](path: Path, model: type[T]) -> list[T]:
    with path.open(encoding="utf-8") as stream:
        return [model.model_validate_json(line) for line in stream if line.strip()]


def spoken(text: str) -> str:
    """What a chunk's card says aloud: "My name is …" without the gap."""
    return text.rstrip(" .…").rstrip() if text.rstrip().endswith(("…", "...")) else text


def file_name(engine: str, voice: Voice, speed: float, text: str, pos: str | None) -> str:
    """`<voice id>/<hash>.mp3`: the same speech always gets the same name."""
    spec = json.dumps([engine, voice.name, voice.locale, speed, pos or "", text])
    return f"{voice.id}/{hashlib.sha256(spec.encode()).hexdigest()[:16]}.mp3"


def plan(items: Iterable[tuple[str, str, str | None, Level]], voices: VoiceSet) -> list[_Planned]:
    """The clips of (key, text, part of speech, level) items, pairs taking turns."""
    planned: list[_Planned] = []
    for index, (key, text, pos, level) in enumerate(items):
        pair = [voices.voice(v) for v in voices.pairs[index % len(voices.pairs)]]
        speeds = [(pair[0], 1.0), (pair[1], 1.0)]
        if level in voices.slow_levels:
            speeds.append((pair[0], voices.slow_speed))
        planned += [
            _Planned(
                key=key,
                voice=voice,
                speed=speed,
                text=text,
                pos=pos,
                file=file_name(voices.engine, voice, speed, text, pos),
            )
            for voice, speed in speeds
        ]
    return planned


def worker(command: Sequence[str], log: Path) -> Speak:
    """Runs the TTS worker on a job file and yields its results as they come."""

    def speak(jobs: Path) -> Iterator[Result]:
        log.parent.mkdir(parents=True, exist_ok=True)
        with log.open("w", encoding="utf-8") as errors:
            process = subprocess.Popen(
                [*command, "--jobs", str(jobs)],
                stdout=subprocess.PIPE,
                stderr=errors,
                text=True,
                encoding="utf-8",
                env={**os.environ, "PYTHONIOENCODING": "utf-8"},
            )
            assert process.stdout is not None
            for line in process.stdout:
                if line.startswith("{"):
                    yield json.loads(line)
            if process.wait() != 0:
                raise AudioError(f"the TTS worker stopped with {process.returncode}; see {log}")

    return speak


def run_audio(
    content_dir: Path,
    *,
    l2: str,
    speak: Speak,
    progress: Callable[[int, int], None] | None = None,
) -> AudioReport:
    """Speaks what is missing and writes `packs/<l2>/audio.jsonl`."""
    pack = content_dir / "packs" / l2
    items_dir = pack / "items"
    voices = VoiceSet.model_validate(
        yaml.safe_load((pack / VOICES_FILE).read_text(encoding="utf-8"))
    )
    sentences = _read(items_dir / "sentences.jsonl", Sentence)
    chunks = _read(items_dir / "chunks.jsonl", Chunk)
    senses = read_word_senses(items_dir / "word_senses.jsonl")
    items: list[tuple[str, str, str | None, Level]] = [
        *((s.key, s.text, None, s.level) for s in sentences),
        *((c.key, spoken(c.text), None, c.level) for c in chunks),
        *((w.key, w.lemma, w.pos, w.level) for w in senses),
    ]
    planned = plan(items, voices)

    out = content_dir / "build" / "audio" / l2 / str(PACK_VERSION)
    work = content_dir / "work"
    work.mkdir(parents=True, exist_ok=True)
    durations_path = work / DURATIONS_FILE.format(l2=l2)
    durations: dict[str, int] = (
        json.loads(durations_path.read_text(encoding="utf-8")) if durations_path.is_file() else {}
    )
    missing: dict[str, _Planned] = {
        clip.file: clip
        for clip in planned
        if clip.file not in durations or not (out / clip.file).is_file()
    }
    if missing:
        jobs = work / JOBS_FILE.format(l2=l2)
        with jobs.open("w", encoding="utf-8", newline="\n") as sink:
            for clip in missing.values():
                job = {
                    "text": clip.text,
                    "pos": clip.pos,
                    "voice": clip.voice.name,
                    "lang": clip.voice.locale.lower(),
                    "speed": clip.speed,
                    "out": str(out / clip.file),
                }
                sink.write(json.dumps(job, ensure_ascii=False) + "\n")
        for done, result in enumerate(speak(jobs), start=1):
            file = Path(str(result["out"])).relative_to(out).as_posix()
            durations[file] = int(str(result["duration_ms"]))
            if done % _SAVE_EVERY == 0:
                durations_path.write_text(json.dumps(durations, indent=1), encoding="utf-8")
            if progress is not None:
                progress(done, len(missing))
        durations_path.write_text(json.dumps(durations, indent=1), encoding="utf-8")
        unfinished = [file for file in missing if file not in durations]
        if unfinished:
            raise AudioError(f"{len(unfinished)} clips were not made, e.g. {unfinished[0]}")

    clips = [
        Clip(
            key=clip.key,
            voice=clip.voice.id,
            speed=clip.speed,
            file=clip.file,
            duration_ms=durations[clip.file],
        )
        for clip in planned
    ]
    with (pack / AUDIO_FILE).open("w", encoding="utf-8", newline="\n") as sink:
        for clip_line in sorted(clips, key=lambda c: (c.key, c.voice, -c.speed)):
            sink.write(clip_line.model_dump_json() + "\n")
    files = {clip.file for clip in clips}
    report = AudioReport(
        clips=len(clips),
        files=len(files),
        made=len(missing),
        by_voice=dict(Counter(clip.voice for clip in clips)),
        slow=sum(1 for clip in clips if clip.speed != 1.0),
        minutes=round(sum(durations[file] for file in files) / 60_000, 1),
        megabytes=round(sum((out / file).stat().st_size for file in files) / 1_048_576, 1),
    )
    (work / REPORT_FILE.format(l2=l2)).write_text(
        report.model_dump_json(indent=2) + "\n", encoding="utf-8"
    )
    return report

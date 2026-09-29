"""Speaks JSON Lines jobs with Kokoro and writes one MP3 per job (S6, docs/10 §4).

A job is {"text", "voice", "lang", "speed", "out"} and, for a single word,
its part of speech ("pos"). Text becomes phonemes with misaki, the G2P that
Kokoro was trained with: it reads heteronyms by their part of speech ("Close
the door." /klOz/, "The shop is close." /klOs/). A single word is read in a
frame that fixes its part of speech ("to close") and only its own phonemes
are spoken.

Every clip is trimmed, brought to the same loudness and padded, so the pack's
voices sound alike next to each other. One JSON line per finished job goes to
stdout: {"out", "duration_ms"}.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections.abc import Callable, Sequence
from pathlib import Path
from typing import Any

import numpy as np
import soundfile as sf
from numpy.typing import NDArray

Audio = NDArray[np.float32]

# Every clip: RMS at -20 dBFS, peaks at most -1 dBFS.
TARGET_RMS_DB = -20.0
PEAK_DB = -1.0
# Quieter than this, relative to the clip's peak, is silence at the edges.
SILENCE_DB = -40.0
EDGE_SECONDS = 0.01
PAD_SECONDS = 0.12
# libsndfile's MP3 scale (0 best, 1 smallest); see `docs/10` §4 for the size it gives.
COMPRESSION = 0.8
# Frames that fix a word's part of speech; other words are read alone.
FRAMES = {"VERB": "to {}", "NOUN": "the {}", "ADJ": "it is {}"}

# misaki's G2P: text → (phonemes, tokens with .text and .phonemes).
G2P = Callable[[str], tuple[str, list[Any]]]


def _gain(db: float) -> float:
    return float(10 ** (db / 20))


def trim(samples: Audio, rate: int) -> Audio:
    """Cuts the silence before the first and after the last sound."""
    if not samples.size:
        return samples
    loud = np.flatnonzero(np.abs(samples) > np.max(np.abs(samples)) * _gain(SILENCE_DB))
    if not loud.size:
        return samples[:0]
    edge = int(EDGE_SECONDS * rate)
    return samples[max(loud[0] - edge, 0) : loud[-1] + edge + 1]


def normalize(samples: Audio) -> Audio:
    """Brings the clip to the target RMS, then lowers it if a peak is too high."""
    if not samples.size or not np.any(samples):
        return samples
    rms = float(np.sqrt(np.mean(np.square(samples, dtype=np.float64))))
    scaled = samples * (_gain(TARGET_RMS_DB) / rms)
    peak = float(np.max(np.abs(scaled)))
    if peak > _gain(PEAK_DB):
        scaled = scaled * (_gain(PEAK_DB) / peak)
    return scaled.astype(np.float32)


def pad(samples: Audio, rate: int) -> Audio:
    """Adds a short silence at both ends; players cut the first milliseconds."""
    silence = np.zeros(int(PAD_SECONDS * rate), dtype=np.float32)
    return np.concatenate([silence, samples.astype(np.float32), silence])


def process(samples: Audio, rate: int) -> Audio:
    """The clip as it is stored: trimmed, normalized and padded."""
    return pad(normalize(trim(samples, rate)), rate)


def write_mp3(path: Path, samples: Audio, rate: int) -> None:
    """A mono MP3 at a constant bit rate."""
    path.parent.mkdir(parents=True, exist_ok=True)
    sf.write(
        path,
        samples,
        rate,
        format="MP3",
        subtype="MPEG_LAYER_III",
        bitrate_mode="CONSTANT",
        compression_level=COMPRESSION,
    )


def phonemes(text: str, pos: str | None, g2p: G2P) -> str:
    """Kokoro's input for a job: a sentence as a whole, a word in its frame."""
    frame = FRAMES.get(pos or "")
    if frame is None:
        return g2p(text)[0]
    _, tokens = g2p(frame.format(text))
    return str(tokens[-1].phonemes)


def main(argv: Sequence[str] | None = None) -> int:
    """`dilbaz-tts --model … --voices … --jobs jobs.jsonl`."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--voices", type=Path, required=True)
    parser.add_argument("--jobs", type=Path, required=True)
    args = parser.parse_args(argv)

    # Imported here: the tests and the helpers above do not need the model.
    from kokoro_onnx import Kokoro
    from misaki import en, espeak

    kokoro = Kokoro(str(args.model), str(args.voices))
    g2p: dict[str, G2P] = {
        lang: en.G2P(trf=False, british=british, fallback=espeak.EspeakFallback(british=british))
        for lang, british in (("en-us", False), ("en-gb", True))
    }
    with args.jobs.open(encoding="utf-8") as stream:
        for line in stream:
            if not line.strip():
                continue
            job = json.loads(line)
            spoken = phonemes(job["text"], job.get("pos"), g2p[job["lang"]])
            samples, rate = kokoro.create(
                spoken, voice=job["voice"], speed=float(job["speed"]), is_phonemes=True
            )
            audio = process(np.asarray(samples, dtype=np.float32), rate)
            write_mp3(Path(job["out"]), audio, rate)
            duration = round(len(audio) / rate * 1000)
            print(json.dumps({"out": job["out"], "duration_ms": duration}), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())

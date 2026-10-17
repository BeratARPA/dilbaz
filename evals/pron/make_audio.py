"""Speaks the pron_check eval cases with Kokoro (ADR-0011).

Each case is a sentence said right, or with one mistake on word i: that
word's phonemes are edited (`edit`: a regex and its replacement) or given
(`said`). Kokoro reads phonemes, so the mistake is exactly the one meant.
The clips are written as the app records them: 16 kHz mono PCM16 WAV.

    cd content/tts
    uv run --no-sync python ../../evals/pron/make_audio.py
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import numpy as np
import soundfile as sf

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
RATE = 16_000


def resample(samples: np.ndarray, rate: int) -> np.ndarray:
    """Linear resampling to 16 kHz; enough for speech in an eval."""
    if rate == RATE:
        return samples
    length = round(len(samples) * RATE / rate)
    return np.interp(
        np.linspace(0, len(samples) - 1, length), np.arange(len(samples)), samples
    ).astype(np.float32)


def spoken(case: dict, g2p) -> tuple[str, str]:  # noqa: ANN001
    """Kokoro's phonemes for the case, and the target word's."""
    _, tokens = g2p(case["text"])
    words = [t for t in tokens if re.search(r"\w", t.text)]
    target = words[case["i"]]
    said = target.phonemes
    if "said" in case:
        said = case["said"]
    elif "edit" in case:
        pattern, replacement = case["edit"]
        said, n = re.subn(pattern, replacement, target.phonemes, count=1)
        if n != 1:
            sys.exit(f"{case['id']}: {pattern} not in {target.phonemes}")
    parts = []
    for token in tokens:
        parts.append(said if token is target else token.phonemes)
        parts.append(" " if token.whitespace else "")
    return "".join(parts).strip(), said


def main() -> int:
    from kokoro_onnx import Kokoro
    from misaki import en, espeak

    model = ROOT / "content" / "sources" / "kokoro" / "1.0"
    kokoro = Kokoro(str(model / "kokoro-v1.0.onnx"), str(model / "voices-v1.0.bin"))
    g2p = en.G2P(trf=False, british=False, fallback=espeak.EspeakFallback(british=False))
    cases = json.loads((HERE / "cases.json").read_text(encoding="utf-8"))["cases"]
    out = HERE / "audio"
    out.mkdir(exist_ok=True)
    for case in cases:
        phonemes, said = spoken(case, g2p)
        samples, rate = kokoro.create(phonemes, voice=case["voice"], speed=1.0, is_phonemes=True)
        audio = resample(np.asarray(samples, dtype=np.float32), rate)
        sf.write(out / f"{case['id']}.wav", audio, RATE, subtype="PCM_16")
        print(f"{case['id']}: {said}  ({len(audio) / RATE:.1f} s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

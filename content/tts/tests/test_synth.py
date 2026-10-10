import json
import sys
import types
from pathlib import Path

import numpy as np
import pytest
import soundfile as sf

from dilbaz_tts import synth

RATE = 24_000


def tone(seconds: float, amplitude: float = 0.3) -> np.ndarray:
    t = np.arange(int(seconds * RATE)) / RATE
    return (amplitude * np.sin(2 * np.pi * 220 * t)).astype(np.float32)


def silence(seconds: float) -> np.ndarray:
    return np.zeros(int(seconds * RATE), dtype=np.float32)


def rms_db(samples: np.ndarray) -> float:
    return float(20 * np.log10(np.sqrt(np.mean(np.square(samples, dtype=np.float64)))))


def test_trim_cuts_the_silent_edges() -> None:
    clip = np.concatenate([silence(0.5), tone(1.0), silence(0.7)])

    trimmed = synth.trim(clip, RATE)

    assert 1.0 <= len(trimmed) / RATE <= 1.03


def test_trim_keeps_empty_and_silent_clips_empty() -> None:
    assert synth.trim(silence(0), RATE).size == 0
    assert synth.trim(silence(0.5), RATE).size == 0


def test_normalize_sets_the_loudness() -> None:
    quiet = tone(1.0, amplitude=0.01)

    assert rms_db(synth.normalize(quiet)) == pytest.approx(synth.TARGET_RMS_DB, abs=0.01)


def test_normalize_keeps_peaks_below_the_limit() -> None:
    # A click on a quiet tone would go far above the peak limit at the target RMS.
    clip = tone(1.0, amplitude=0.01)
    clip[100] = 0.9

    peak = float(np.max(np.abs(synth.normalize(clip))))

    assert peak == pytest.approx(10 ** (synth.PEAK_DB / 20), rel=1e-4)


def test_normalize_leaves_silence_alone() -> None:
    assert not np.any(synth.normalize(silence(0.2)))


def test_process_pads_both_ends() -> None:
    out = synth.process(tone(1.0), RATE)

    pad = int(synth.PAD_SECONDS * RATE)
    assert not np.any(out[:pad])
    assert not np.any(out[-pad:])
    assert out.dtype == np.float32


def test_mp3s_are_written_and_readable(tmp_path: Path) -> None:
    path = tmp_path / "v1" / "clip.mp3"

    synth.write_mp3(path, synth.process(tone(1.0), RATE), RATE)

    info = sf.info(str(path))
    assert info.samplerate == RATE
    assert info.channels == 1
    assert info.duration == pytest.approx(1.0 + 2 * synth.PAD_SECONDS, abs=0.1)


class Token:
    def __init__(self, text: str) -> None:
        self.text = text
        self.phonemes = f"/{text}/"


def fake_g2p(text: str) -> tuple[str, list[Token]]:
    tokens = [Token(word) for word in text.split()]
    return " ".join(t.phonemes for t in tokens), tokens


def test_sentences_are_read_whole_and_words_in_their_frame() -> None:
    assert synth.phonemes("Close the door.", None, fake_g2p) == "/Close/ /the/ /door./"
    # "to close" makes misaki read the verb; only the word's phonemes are spoken.
    assert synth.phonemes("close", "VERB", fake_g2p) == "/close/"
    assert synth.phonemes("close", "ADV", fake_g2p) == "/close/"


def test_the_worker_speaks_every_job(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    calls: list[tuple[str, str, float, bool]] = []
    accents: list[bool] = []

    class FakeKokoro:
        def __init__(self, model: str, voices: str) -> None:
            assert (model, voices) == ("model.onnx", "voices.bin")

        def create(
            self, text: str, voice: str, speed: float, is_phonemes: bool
        ) -> tuple[np.ndarray, int]:
            calls.append((text, voice, speed, is_phonemes))
            return np.concatenate([silence(0.2), tone(0.5), silence(0.2)]), RATE

    def g2p(trf: bool, british: bool, fallback: object) -> object:
        accents.append(british)
        return lambda text: fake_g2p(text.upper() if british else text)

    misaki = types.SimpleNamespace(
        en=types.SimpleNamespace(G2P=g2p),
        espeak=types.SimpleNamespace(EspeakFallback=lambda british: None),
    )
    monkeypatch.setitem(sys.modules, "kokoro_onnx", types.SimpleNamespace(Kokoro=FakeKokoro))
    monkeypatch.setitem(sys.modules, "misaki", misaki)
    jobs = tmp_path / "jobs.jsonl"
    out = tmp_path / "out"
    lines = [
        {"text": "Hello.", "voice": voice, "lang": lang, "speed": speed, "out": str(out / name)}
        for voice, lang, speed, name in (
            ("af_heart", "en-us", 1.0, "a.mp3"),
            ("bf_emma", "en-gb", 0.8, "b.mp3"),
        )
    ]
    jobs.write_text("\n".join(json.dumps(line) for line in lines) + "\n\n", encoding="utf-8")

    code = synth.main(["--model", "model.onnx", "--voices", "voices.bin", "--jobs", str(jobs)])

    assert code == 0
    assert accents == [False, True]
    assert calls == [("/Hello./", "af_heart", 1.0, True), ("/HELLO./", "bf_emma", 0.8, True)]
    printed = [json.loads(line) for line in capsys.readouterr().out.splitlines()]
    assert [p["out"] for p in printed] == [str(out / "a.mp3"), str(out / "b.mp3")]
    assert all(700 <= p["duration_ms"] <= 800 for p in printed)
    assert (out / "a.mp3").is_file()
    assert (out / "b.mp3").is_file()

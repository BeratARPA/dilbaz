# /// script
# requires-python = ">=3.12,<3.14"
# dependencies = ["sherpa-onnx==1.13.8", "av==16.0.1", "numpy"]
# ///
"""On-device ASR candidates of the bake-off (docs/08-speech.md §3.2).

sherpa-onnx models small enough for a phone, run here on the computer: the
words are what the phone would write, the latency is not the phone's. Each
writes `asr/audio/<set>/transcripts/<candidate>.jsonl` like `run.ts` does,
which then scores it with `--candidates <candidate>`.

    uv run evals/asr/local_stt.py --set <name> --candidate parakeet|moonshine

Models live outside git, in `%LOCALAPPDATA%/dilbaz/models` (or --models):
    sherpa-onnx-nemo-parakeet_tdt_transducer_110m-en-36000-int8
    sherpa-onnx-moonshine-base-en-quantized-2026-02-27
both from https://github.com/k2-fsa/sherpa-onnx/releases/tag/asr-models.
"""

import argparse
import json
import os
import re
import time
from pathlib import Path

import av
import numpy as np
import sherpa_onnx

HERE = Path(__file__).parent
RATE = 16_000
NAME = re.compile(r"^([sf]\d\d)\.(wav|m4a|mp3|ogg)$")


def recognizer(candidate: str, models: Path) -> sherpa_onnx.OfflineRecognizer:
    if candidate == "parakeet":
        folder = models / "sherpa-onnx-nemo-parakeet_tdt_transducer_110m-en-36000-int8"
        return sherpa_onnx.OfflineRecognizer.from_transducer(
            encoder=str(folder / "encoder.int8.onnx"),
            decoder=str(folder / "decoder.int8.onnx"),
            joiner=str(folder / "joiner.int8.onnx"),
            tokens=str(folder / "tokens.txt"),
            model_type="nemo_transducer",
            num_threads=4,
        )
    if candidate == "moonshine":
        folder = models / "sherpa-onnx-moonshine-base-en-quantized-2026-02-27"
        return sherpa_onnx.OfflineRecognizer.from_moonshine_v2(
            encoder=str(folder / "encoder_model.ort"),
            decoder=str(folder / "decoder_model_merged.ort"),
            tokens=str(folder / "tokens.txt"),
            num_threads=4,
        )
    raise SystemExit(f"unknown candidate {candidate}")


def samples(path: Path) -> np.ndarray:
    """The recording as 16 kHz mono floats in [-1, 1]."""
    resampler = av.AudioResampler(format="flt", layout="mono", rate=RATE)
    chunks = []
    with av.open(str(path)) as container:
        for frame in container.decode(audio=0):
            for out in resampler.resample(frame):
                chunks.append(out.to_ndarray().reshape(-1))
        for out in resampler.resample(None):
            chunks.append(out.to_ndarray().reshape(-1))
    return np.concatenate(chunks).astype(np.float32)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--set", required=True)
    parser.add_argument("--candidate", required=True)
    parser.add_argument(
        "--models",
        type=Path,
        default=Path(os.environ.get("LOCALAPPDATA", ".")) / "dilbaz" / "models",
    )
    args = parser.parse_args()
    folder = HERE / "audio" / args.set
    out = folder / "transcripts" / f"{args.candidate}.jsonl"
    out.parent.mkdir(parents=True, exist_ok=True)
    done = set()
    if out.exists():
        for line in out.read_text(encoding="utf-8").splitlines():
            if line.strip() and "text" in json.loads(line):
                done.add(json.loads(line)["id"])
    asr = recognizer(args.candidate, args.models)
    for path in sorted(folder.iterdir()):
        match = NAME.match(path.name)
        if not match or match[1] in done:
            continue
        audio = samples(path)
        started = time.perf_counter()
        stream = asr.create_stream()
        stream.accept_waveform(RATE, audio)
        asr.decode_stream(stream)
        line = {
            "id": match[1],
            "candidate": args.candidate,
            "text": stream.result.text.strip(),
            "latencyMs": round((time.perf_counter() - started) * 1000),
        }
        with out.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(line) + "\n")
        print(f"{args.candidate} {match[1]}: ok")


if __name__ == "__main__":
    main()

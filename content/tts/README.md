# dilbaz-tts

Pack audio worker for S6 (`docs/10-content-pipeline.md` §4). Kokoro-82M runs
here in its own Python 3.12 environment: misaki, the G2P Kokoro was trained
with, supports Python < 3.13 and the content tools run on 3.14 (ADR-0009).

`dilbaz-content audio` (in `content/tools`) decides what to speak and calls
this worker with a JSON Lines job file; the worker writes one normalized MP3
per job and prints one JSON line per job with its duration.

```bash
cd content/tts && uv sync && uv run pytest && uv run ruff check . && uv run mypy src
```

The model files come from `dilbaz-content ingest kokoro` (`content/sources/kokoro/`).

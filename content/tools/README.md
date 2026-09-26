# dilbaz-content

Dil paketlerini üreten, doğrulayan ve raporlayan içerik hattı (`docs/10-content-pipeline.md`). Paket biçimi: `docs/11-language-packs.md`.

```bash
uv sync
uv run dilbaz-content --help
uv run pytest && uv run ruff check . && uv run ruff format --check . && uv run mypy src
```

Büyük kaynaklar `content/sources/`, ara çıktılar `content/work/`, paketler `content/build/` altındadır (git dışı). Kaynak kaydı: `content/sources.yaml`.

```bash
uv run dilbaz-content ingest            # S0: kaynakları indir (sabit dosyalar sha256 ile doğrulanır)
uv run dilbaz-content ingest --refresh  # haftalık dökümleri (Tatoeba, Wiktextract) yeniden indir
uv run dilbaz-content lexicon           # S1: content/work/lexicon.en.jsonl + rapor
uv run dilbaz-content select            # S2: content/curation/en → content/packs/en/items
uv run dilbaz-content carriers          # S3: Tatoeba taşıyıcı adayları → content/work/carriers.en.candidates.jsonl
```

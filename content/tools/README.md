# dilbaz-content

Dil paketlerini üreten, doğrulayan ve raporlayan içerik hattı (`docs/10-content-pipeline.md`). Paket biçimi: `docs/11-language-packs.md`.

```bash
uv sync
uv run dilbaz-content --help
uv run pytest && uv run ruff check . && uv run ruff format --check . && uv run mypy src
```

Büyük kaynaklar `content/sources/`, ara çıktılar `content/work/`, paketler `content/build/` altındadır (git dışı).

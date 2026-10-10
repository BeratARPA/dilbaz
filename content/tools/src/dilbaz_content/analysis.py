"""English sentence analysis for S3 and S4: lemma, part of speech and tag per token.

spaCy (`en_core_web_md`, parser and NER off) sits behind the [Analyzer]
protocol so tests can use a fake. Analyses of the Tatoeba candidates are
cached as gzip JSON lines and rebuilt only when the snapshot, the analyzer or
the cache format changes.
"""

from __future__ import annotations

import gzip
import json
from collections.abc import Callable, Iterable, Iterator
from pathlib import Path
from typing import Protocol

from pydantic import BaseModel, ConfigDict

from dilbaz_content.readers.tatoeba import TatoebaPair

# Bump when the cached record changes.
CACHE_VERSION = 1

# (text, lemma, universal part of speech, fine-grained tag), e.g.
# ("watching", "watch", "VERB", "VBG").
Token = tuple[str, str, str, str]


class Analyzer(Protocol):
    """Turns sentences into tokens."""

    name: str

    def analyze(self, texts: Iterable[str]) -> Iterator[tuple[Token, ...]]:
        """Tokens of each text, in order."""
        ...


class SpacyAnalyzer:
    """spaCy tagger and lemmatizer; lemmas are lowercased ("I" → "i")."""

    def __init__(self, model: str = "en_core_web_md") -> None:
        # Imported here: loading spaCy is slow and only analysis needs it.
        import spacy

        self._nlp = spacy.load(model, disable=["parser", "ner"])
        self.name = f"spacy:{model}-{self._nlp.meta['version']}"

    def analyze(self, texts: Iterable[str]) -> Iterator[tuple[Token, ...]]:
        for doc in self._nlp.pipe(texts, batch_size=2000):
            yield tuple(
                (token.text, token.lemma_.lower(), token.pos_, token.tag_)
                for token in doc
                if not token.is_space
            )


class Translation(BaseModel):
    """A Turkish translation of a Tatoeba sentence."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    id: int
    text: str
    author: str | None = None


class AnalyzedSentence(BaseModel):
    """A cached Tatoeba sentence with its analysis."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    id: int
    text: str
    author: str | None = None
    native: bool
    tokens: tuple[Token, ...]
    turkish: tuple[Translation, ...] = ()


def analyze_pairs(
    pairs: Iterable[TatoebaPair],
    analyzer: Analyzer,
    out: Path,
    progress: Callable[[int], None] | None = None,
) -> int:
    """Analyzes the English side of [pairs] into [out]; returns the count."""
    batch: list[TatoebaPair] = []
    written = 0
    partial = out.with_name(out.name + ".part")

    def flush(sink: gzip.GzipFile) -> int:
        texts = [pair.english.text for pair in batch]
        for pair, tokens in zip(batch, analyzer.analyze(texts), strict=True):
            record = AnalyzedSentence(
                id=pair.english.id,
                text=pair.english.text,
                author=pair.english.author,
                native=pair.native,
                tokens=tokens,
                turkish=tuple(
                    Translation(id=t.id, text=t.text, author=t.author) for t in pair.turkish
                ),
            )
            sink.write((record.model_dump_json(exclude_defaults=True) + "\n").encode())
        count = len(batch)
        batch.clear()
        return count

    with gzip.open(partial, "wb") as sink:
        for pair in pairs:
            batch.append(pair)
            if len(batch) >= 10_000:
                written += flush(sink)
                if progress is not None:
                    progress(written)
        written += flush(sink)
    partial.replace(out)
    return written


def read_analysis(path: Path) -> Iterator[AnalyzedSentence]:
    """Records of an analysis cache."""
    with gzip.open(path, "rt", encoding="utf-8") as stream:
        for line in stream:
            if line.strip():
                yield AnalyzedSentence.model_validate_json(line)


def cache_is_fresh(meta_path: Path, meta: dict[str, object]) -> bool:
    """Whether a cache was built from exactly [meta]."""
    return meta_path.is_file() and json.loads(meta_path.read_text(encoding="utf-8")) == meta

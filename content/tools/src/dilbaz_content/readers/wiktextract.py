"""Wiktextract English dictionary from kaikki.org (docs/10-content-pipeline.md §2).

The dump is ~3 GB of JSON lines. [extract_subset] streams it once and keeps
a slim record (senses, IPA, inflected forms) for the lexicon's words only;
later runs read the small subset.
"""

from __future__ import annotations

import gzip
from collections.abc import Callable, Iterator
from pathlib import Path

from pydantic import BaseModel, ConfigDict

from dilbaz_content.pos import wiktionary_pos

# Senses with these tags are not taught.
SKIP_SENSE_TAGS = frozenset(
    {"obsolete", "archaic", "rare", "dated", "historical", "misspelling", "nonstandard"}
)
# A form is kept only if every tag is grammatical or names a standard variety
# (US "gotten", UK "learnt"), and one tag marks an inflection. Dialect,
# register, contraction and dating tags drop the form.
_GRAMMATICAL_TAGS = frozenset(
    {
        "plural",
        "singular",
        "first-person",
        "second-person",
        "third-person",
        "present",
        "past",
        "participle",
        "comparative",
        "superlative",
        "indicative",
    }
)
_INFLECTION_TAGS = _GRAMMATICAL_TAGS - {"singular", "present", "indicative"}
_ALLOWED_FORM_TAGS = _GRAMMATICAL_TAGS | {"US", "UK", "British", "American", "Commonwealth"}
# Contractions ("'s", "'re") are expanded by normalization instead.
_APOSTROPHES = ("'", "’")
# Bump when the slim record changes, so that cached subsets are rebuilt.
SLIM_VERSION = 5
MAX_SENSES_PER_ENTRY = 12


class WikiSense(BaseModel):
    """One sense: its most specific gloss and usage tags."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    gloss: str
    tags: tuple[str, ...] = ()


class WikiSound(BaseModel):
    """One IPA transcription with its accent tags and Wiktionary's note.

    The note names an accent ("Local Dublin") or a qualifier ("in fast
    speech"); such transcriptions are not an accent's usual form.
    """

    model_config = ConfigDict(extra="forbid", frozen=True)

    ipa: str
    tags: tuple[str, ...] = ()
    note: str | None = None


class WikiEntry(BaseModel):
    """The slim record kept for one word + part of speech."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    word: str
    pos: str
    senses: tuple[WikiSense, ...] = ()
    sounds: tuple[WikiSound, ...] = ()
    forms: tuple[str, ...] = ()


class _RawSense(BaseModel):
    model_config = ConfigDict(extra="ignore")

    glosses: tuple[str, ...] = ()
    tags: tuple[str, ...] = ()
    form_of: list[object] | None = None
    alt_of: list[object] | None = None


class _RawSound(BaseModel):
    model_config = ConfigDict(extra="ignore")

    ipa: str | None = None
    tags: tuple[str, ...] = ()
    note: str | None = None


class _RawForm(BaseModel):
    model_config = ConfigDict(extra="ignore")

    form: str = ""
    tags: tuple[str, ...] = ()


class _RawHead(BaseModel):
    model_config = ConfigDict(extra="ignore")

    word: str = ""
    lang_code: str = ""


class _RawEntry(BaseModel):
    model_config = ConfigDict(extra="ignore")

    word: str
    pos: str = ""
    senses: tuple[_RawSense, ...] = ()
    sounds: tuple[_RawSound, ...] = ()
    forms: tuple[_RawForm, ...] = ()


def _is_inflection(form: _RawForm, word: str) -> bool:
    text = form.form
    return (
        bool(text)
        and text != word
        and " " not in text
        and not any(mark in text for mark in _APOSTROPHES)
        and any(char.isalpha() for char in text)
        and bool(_INFLECTION_TAGS.intersection(form.tags))
        and _ALLOWED_FORM_TAGS.issuperset(form.tags)
    )


def _senses(raw: _RawEntry) -> tuple[WikiSense, ...]:
    usable = [s for s in raw.senses if s.glosses and not SKIP_SENSE_TAGS.intersection(s.tags)]
    regular = [s for s in usable if s.form_of is None and s.alt_of is None]
    # An abbreviation such as "TV" has only alt-of senses; keep those then.
    chosen = regular or usable
    return tuple(
        WikiSense(gloss=sense.glosses[-1], tags=sense.tags)
        for sense in chosen[:MAX_SENSES_PER_ENTRY]
    )


def slim_entry(line: str) -> WikiEntry | None:
    """Parses one dump line; None for parts of speech the lexicon does not use."""
    raw = _RawEntry.model_validate_json(line)
    pos = wiktionary_pos(raw.pos)
    if pos is None:
        return None
    forms = [form.form for form in raw.forms if _is_inflection(form, raw.word)]
    return WikiEntry(
        word=raw.word,
        pos=pos,
        senses=_senses(raw),
        sounds=tuple(WikiSound(ipa=s.ipa, tags=s.tags, note=s.note) for s in raw.sounds if s.ipa),
        forms=tuple(dict.fromkeys(forms)),
    )


def _lines(path: Path) -> Iterator[str]:
    if path.suffix == ".gz":
        with gzip.open(path, "rt", encoding="utf-8") as stream:
            yield from stream
    else:
        with path.open(encoding="utf-8") as stream:
            yield from stream


def extract_subset(
    dump: Path,
    words: frozenset[str],
    out: Path,
    progress: Callable[[int], None] | None = None,
) -> int:
    """Writes the slim English entries of [words] to [out]; returns their count."""
    kept = 0
    partial = out.with_name(out.name + ".part")
    with partial.open("w", encoding="utf-8") as sink:
        for number, line in enumerate(_lines(dump), start=1):
            if progress is not None and number % 100_000 == 0:
                progress(number)
            head = _RawHead.model_validate_json(line)
            if head.lang_code != "en" or head.word not in words:
                continue
            entry = slim_entry(line)
            if entry is not None:
                sink.write(entry.model_dump_json() + "\n")
                kept += 1
    partial.replace(out)
    return kept


def headwords(dump: Path, progress: Callable[[int], None] | None = None) -> Iterator[str]:
    """The lowercased English single-word headwords of the dump, with repeats."""
    for number, line in enumerate(_lines(dump), start=1):
        if progress is not None and number % 100_000 == 0:
            progress(number)
        head = _RawHead.model_validate_json(line)
        if head.lang_code == "en" and " " not in head.word:
            yield head.word.lower()


def read_subset(path: Path) -> dict[str, tuple[WikiEntry, ...]]:
    """Subset entries grouped by lowercase word, in dump order."""
    grouped: dict[str, list[WikiEntry]] = {}
    with path.open(encoding="utf-8") as stream:
        for line in stream:
            if line.strip():
                entry = WikiEntry.model_validate_json(line)
                grouped.setdefault(entry.word.lower(), []).append(entry)
    return {word: tuple(entries) for word, entries in grouped.items()}

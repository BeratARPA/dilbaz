"""S8: the X_Lex placement bank (docs/06-assessment.md §2, docs/10 §5.3).

Three equivalent versions of a yes/no vocabulary test (Meara & Milton): 20
real words from each thousand of the 5,000 most frequent lemmas and 20
pseudowords per version.

Real words are single content words. Names, function words, blocked words
and curated exclusions (loanwords a Turkish speaker knows without any
English: hotel, taxi) are left out. Each band's sample is sorted by rank and
dealt to the versions in rotating order, so no version gets the easier words.

Pseudowords are built from English spelling patterns. A candidate is kept
only if wordfreq knows it neither in English nor in the learners' language,
it is in no dictionary (CMUdict, Wiktionary), it is not one letter away from a
common English word, it does not start or end with one ("floodous") and it
holds no rude string.
"""

from __future__ import annotations

import json
import random
import string
from collections import Counter
from collections.abc import Callable, Iterable, Iterator
from pathlib import Path

import yaml
from pydantic import BaseModel, ConfigDict, Field

from dilbaz_content.analysis import cache_is_fresh
from dilbaz_content.lexicon import LexiconEntry
from dilbaz_content.readers.cmudict import read_cmudict
from dilbaz_content.readers.wiktextract import headwords
from dilbaz_content.select_step import read_lexicon
from dilbaz_content.sentences_step import BLOCKED_WORDS

XLEX_FILE = Path("placement") / "xlex.jsonl"
CURATION_FILE = "xlex.yaml"
REPORT_FILE = "placement.{l2}.report.json"
HEADWORDS_FILE = "wiktionary.{l2}.headwords.txt"
VERSIONS = ("A", "B", "C")
BANDS = 5
BAND_SIZE = 1000
PER_BAND = 20
PSEUDOWORDS = 20
_CONTENT = frozenset({"NOUN", "VERB", "ADJ", "ADV"})
_FUNCTION = frozenset({"PRON", "ADP", "DET", "CONJ", "NUM", "AUX", "INTJ", "PART"})
# A pseudoword is onset + vowel + coda + ending; a vowel pair takes a simple coda.
_ONSETS = (
    *("b", "bl", "br", "c", "cl", "cr", "d", "dr", "f", "fl", "fr", "g", "gl", "gr"),
    *("h", "j", "l", "m", "n", "p", "pl", "pr", "r", "s", "sc", "sk", "sl", "sm"),
    *("sn", "sp", "spr", "st", "str", "sw", "t", "th", "tr", "tw", "v", "w", "wh"),
)
_SHORT_VOWELS = ("a", "e", "i", "o", "u")
_LONG_VOWELS = ("ai", "ea", "ee", "oa", "oo", "ou", "ay", "ow")
_CODAS = (
    *("b", "ck", "d", "ff", "g", "ll", "lk", "lp", "lt", "m", "mp", "n", "nd", "nk"),
    *("nt", "p", "rb", "rd", "rk", "rm", "rn", "rp", "rt", "sh", "sk", "sp", "st"),
    *("t", "tch", "th"),
)
_SIMPLE_CODAS = ("d", "k", "l", "m", "n", "p", "t", "ch", "th")
_ENDINGS = ("", "", "", "", "er", "le", "ish", "en", "et", "y", "ard", "ment", "ous")
# No pseudoword may contain these (English and Turkish).
_RUDE = ("cock", "cum", "cunt", "dick", "fag", "fuck", "gay", "nig", "piss", "porn", "rape")
_RUDE_TR = ("amc", "göt", "piç", "sik")
# A shorter start or end is too common to look like a word part.
_PART = 4


class PlacementError(Exception):
    """The lexicon cannot fill the bank."""


class XlexItem(BaseModel):
    """`placement/xlex.jsonl`: one item of one version."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    version: str
    # 1 for ranks 1-1000 … 5 for 4001-5000; None for pseudowords.
    band: int | None
    word: str
    is_pseudo: bool


class XlexCuration(BaseModel):
    """`curation/<l2>/xlex.yaml`."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    seed: int = 2026
    # Real words left out → why (a loanword Turkish speakers know: "hotel").
    exclude: dict[str, str] = Field(default_factory=dict)
    # Generated pseudowords rejected by hand (odd spelling, looks like a word).
    reject_pseudowords: tuple[str, ...] = ()


class PlacementReport(BaseModel):
    """`work/placement.<l2>.report.json`."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    items: int
    eligible_by_band: dict[int, int]
    excluded: dict[str, int]
    pseudo_tried: int
    pseudo_rejected: dict[str, int]


def dictionary_words(
    cmudict: Path,
    dump: Path,
    work_dir: Path,
    *,
    l2: str,
    progress: Callable[[int], None] | None = None,
) -> frozenset[str]:
    """CMUdict's words and Wiktionary's headwords; the headwords are cached in work/."""
    cache = work_dir / HEADWORDS_FILE.format(l2=l2)
    meta_path = cache.with_name(cache.name + ".meta.json")
    meta: dict[str, object] = {"dump": dump.parent.name + "/" + dump.name}
    if not (cache.is_file() and cache_is_fresh(meta_path, meta)):
        work_dir.mkdir(parents=True, exist_ok=True)
        words = sorted(set(headwords(dump, progress)))
        cache.write_text("\n".join(words) + "\n", encoding="utf-8", newline="\n")
        meta_path.write_text(json.dumps(meta) + "\n", encoding="utf-8")
    return frozenset(cache.read_text(encoding="utf-8").split()) | frozenset(read_cmudict(cmudict))


def load_curation(path: Path) -> XlexCuration:
    """The curation file; a missing file means the defaults."""
    if not path.is_file():
        return XlexCuration()
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    return XlexCuration.model_validate(data or {})


def _exclusion(entry: LexiconEntry, curation: XlexCuration) -> str | None:
    """Why [entry] cannot be a real-word item, or None."""
    word = entry.lemma
    if entry.display[:1].isupper():
        return "name"
    if not word.isalpha() or len(word) < 3:
        return "short or not a word"
    pos = {level.pos for level in entry.levels}
    if not pos & _CONTENT or pos & _FUNCTION:
        return "function word"
    if word in BLOCKED_WORDS:
        return "blocked"
    if word in curation.exclude:
        return "curated"
    return None


def _deal(count: int, versions: tuple[str, ...]) -> Iterator[str]:
    """Versions for items sorted by rank: A B C, then B C A, then C A B …"""
    for index in range(count):
        yield versions[(index + index // len(versions)) % len(versions)]


def real_words(
    entries: Iterable[LexiconEntry],
    curation: XlexCuration,
    *,
    versions: tuple[str, ...] = VERSIONS,
    bands: int = BANDS,
    band_size: int = BAND_SIZE,
    per_band: int = PER_BAND,
) -> tuple[list[XlexItem], Counter[str], dict[int, int]]:
    """Real-word items, exclusion counts and the eligible words per band.

    Each band is shuffled once as a whole and read in that order, so excluding
    a word replaces only that word.
    """
    population: dict[int, list[LexiconEntry]] = {band: [] for band in range(1, bands + 1)}
    for entry in entries:
        if not entry.multiword and entry.rank is not None and entry.rank <= bands * band_size:
            population[(entry.rank - 1) // band_size + 1].append(entry)
    items: list[XlexItem] = []
    excluded: Counter[str] = Counter()
    eligible: dict[int, int] = {}
    need = per_band * len(versions)
    for band, members in population.items():
        order = sorted(members, key=lambda e: e.lemma)
        random.Random(f"{curation.seed}:{band}").shuffle(order)
        pool: list[LexiconEntry] = []
        for entry in order:
            reason = _exclusion(entry, curation)
            if reason is None:
                pool.append(entry)
            else:
                excluded[reason] += 1
        eligible[band] = len(pool)
        if len(pool) < need:
            raise PlacementError(f"band {band} has {len(pool)} eligible words, {need} needed")
        sample = sorted(pool[:need], key=_rank)
        items += [
            XlexItem(version=version, band=band, word=entry.lemma, is_pseudo=False)
            for entry, version in zip(sample, _deal(need, versions), strict=True)
        ]
    return items, excluded, eligible


def _rank(entry: LexiconEntry) -> int:
    return entry.rank or 0


def pseudoword_candidates(rng: random.Random) -> Iterator[str]:
    """An endless stream of English-looking letter strings."""
    while True:
        if rng.random() < 0.3:
            stem = rng.choice(_ONSETS) + rng.choice(_LONG_VOWELS) + rng.choice(_SIMPLE_CODAS)
        else:
            stem = rng.choice(_ONSETS) + rng.choice(_SHORT_VOWELS) + rng.choice(_CODAS)
        word = stem + rng.choice(_ENDINGS)
        if 4 <= len(word) <= 9:
            yield word


def one_letter_away(word: str) -> Iterator[str]:
    """Every string one insertion, deletion or substitution away from [word]."""
    letters = string.ascii_lowercase
    for index in range(len(word) + 1):
        for letter in letters:
            yield word[:index] + letter + word[index:]
    for index, current in enumerate(word):
        yield word[:index] + word[index + 1 :]
        for letter in letters:
            if letter != current:
                yield word[:index] + letter + word[index + 1 :]


class PseudowordCheck:
    """Why a candidate cannot be a pseudoword, or None (docs/10 §5.3)."""

    def __init__(
        self,
        *,
        l1: str,
        l2: str,
        frequency: Callable[[str, str], float],
        dictionary: frozenset[str],
        common: frozenset[str],
    ) -> None:
        self._languages = (l2, l1)
        self._frequency = frequency
        self._dictionary = dictionary
        self._common = common

    def __call__(self, word: str) -> str | None:
        target, learners = self._languages
        if self._frequency(word, target) > 0:
            return "a word by frequency"
        if self._frequency(word, learners) > 0:
            return "a word of the learners' language"
        if word in self._dictionary:
            return "in a dictionary"
        if any(near in self._common for near in one_letter_away(word)):
            return "one letter from a common word"
        parts = [word[:end] for end in range(_PART, len(word) - 1)]
        parts += [word[start:] for start in range(2, len(word) - _PART + 1)]
        if any(part in self._common for part in parts):
            return "starts or ends with a common word"
        if any(rude in word for rude in (*_RUDE, *_RUDE_TR)):
            return "rude"
        return None


def pseudowords(
    check: Callable[[str], str | None],
    curation: XlexCuration,
    *,
    versions: tuple[str, ...] = VERSIONS,
    per_version: int = PSEUDOWORDS,
    max_tries: int = 200_000,
) -> tuple[list[XlexItem], int, Counter[str]]:
    """Pseudoword items, the candidates tried and why the others failed."""
    rng = random.Random(f"{curation.seed}:pseudo")
    rejected_by_hand = set(curation.reject_pseudowords)
    kept: list[str] = []
    reasons: Counter[str] = Counter()
    tried = 0
    for candidate in pseudoword_candidates(rng):
        if len(kept) == per_version * len(versions):
            break
        tried += 1
        if tried > max_tries:
            raise PlacementError(f"only {len(kept)} pseudowords after {max_tries} candidates")
        if candidate in kept:
            continue
        reason = "rejected in the curation" if candidate in rejected_by_hand else check(candidate)
        if reason is None:
            kept.append(candidate)
        else:
            reasons[reason] += 1
    items = [
        XlexItem(version=version, band=None, word=word, is_pseudo=True)
        for word, version in zip(kept, _deal(len(kept), versions), strict=True)
    ]
    return items, tried, reasons


def run_placement(
    content_dir: Path,
    *,
    l1: str,
    l2: str,
    frequency: Callable[[str, str], float],
    dictionary: Callable[[], frozenset[str]],
    common: Callable[[], frozenset[str]],
) -> PlacementReport:
    """Builds `packs/<l2>/placement/xlex.jsonl` from the lexicon and the curation."""
    entries = read_lexicon(content_dir / "work" / f"lexicon.{l2}.jsonl")
    curation = load_curation(content_dir / "curation" / l2 / CURATION_FILE)
    real, excluded, eligible = real_words(entries, curation)
    check = PseudowordCheck(
        l1=l1, l2=l2, frequency=frequency, dictionary=dictionary(), common=common()
    )
    fake, tried, reasons = pseudowords(check, curation)
    items = sorted((*real, *fake), key=lambda i: (i.version, i.band is None, i.band or 0, i.word))
    out = content_dir / "packs" / l2 / XLEX_FILE
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w", encoding="utf-8", newline="\n") as sink:
        for item in items:
            sink.write(item.model_dump_json() + "\n")
    report = PlacementReport(
        items=len(items),
        eligible_by_band=eligible,
        excluded=dict(excluded),
        pseudo_tried=tried,
        pseudo_rejected=dict(reasons),
    )
    work = content_dir / "work"
    work.mkdir(parents=True, exist_ok=True)
    (work / REPORT_FILE.format(l2=l2)).write_text(
        report.model_dump_json(indent=2) + "\n", encoding="utf-8"
    )
    return report

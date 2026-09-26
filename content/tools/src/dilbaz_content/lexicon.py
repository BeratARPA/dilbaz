"""S1 lexicon: one record per lemma, merged from the open sources (docs/10 §4.1).

Levels come from CEFR-J (A1-B2) and Octanove (C1-C2), membership from NGSL and
NGSL-Spoken, frequency from wordfreq, US pronunciation from CMUdict, UK
pronunciation, senses and inflected forms from Wiktionary. The output feeds S2
(selection) and the X_Lex frequency bands (S8).
"""

from __future__ import annotations

import math
from collections import Counter, defaultdict
from collections.abc import Callable, Iterable, Mapping
from dataclasses import dataclass
from typing import Literal

from pydantic import BaseModel, ConfigDict

from dilbaz_content.arpabet import to_ipa
from dilbaz_content.readers.level_lists import CEFR_LEVELS, LevelEntry
from dilbaz_content.readers.ngsl import RankedLemma
from dilbaz_content.readers.wiktextract import WikiEntry

Cefr = Literal["A1", "A2", "B1", "B2", "C1", "C2"]
MAX_SENSES_PER_POS = 8
_US_TAGS = frozenset({"General-American", "US"})
_UK_TAGS = frozenset({"Received-Pronunciation", "UK"})


class LevelTag(BaseModel):
    """The CEFR level of a lemma in one part of speech, and who says so."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    pos: str
    cefr: Cefr
    source: str


class Sense(BaseModel):
    """A Wiktionary sense, kept for S2 sense selection."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    pos: str
    gloss: str
    tags: tuple[str, ...] = ()


class LexiconEntry(BaseModel):
    """One line of `lexicon.en.jsonl`."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    lemma: str
    display: str
    spellings: tuple[str, ...] = ()
    # Several tokens for wordfreq: a space or a hyphen ("air force", "part-time").
    multiword: bool
    cefr: Cefr | None
    levels: tuple[LevelTag, ...] = ()
    pos: tuple[str, ...] = ()
    # Frequency rank among single words; phrases have none (their estimate is too rough).
    rank: int | None
    # Zipf of the headword itself; for phrases wordfreq's estimate, an upper bound.
    zipf: float
    # Zipf of lemma + single-word spellings + inflected forms; None for phrases.
    family_zipf: float | None
    ngsl_rank: int | None = None
    ngsl_spoken_rank: int | None = None
    forms: tuple[str, ...] = ()
    ipa_us: str | None = None
    ipa_uk: str | None = None
    arpabet: tuple[str, ...] = ()
    senses: tuple[Sense, ...] = ()
    sources: tuple[str, ...]


@dataclass(frozen=True)
class Lexicon:
    """The built entries and the headwords folded into their lemma."""

    entries: tuple[LexiconEntry, ...]
    # Level-list headwords that are only an inflection, e.g. "is" → "be".
    merged: Mapping[str, str]


@dataclass(frozen=True)
class LexiconInputs:
    """Everything S1 reads, already parsed."""

    level_entries: tuple[LevelEntry, ...]
    ngsl: tuple[RankedLemma, ...]
    ngsl_spoken: tuple[RankedLemma, ...]
    pronunciations: Mapping[str, tuple[str, ...]]
    wiki: Mapping[str, tuple[WikiEntry, ...]]


def is_phrase(text: str) -> bool:
    """Several tokens for wordfreq, which splits on spaces and hyphens."""
    return " " in text or "-" in text


def zipf(frequency: float) -> float:
    """wordfreq's Zipf scale: log10 of occurrences per billion words."""
    return round(math.log10(frequency * 1e9), 2) if frequency > 0 else 0.0


def _level_index(cefr: str) -> int:
    return CEFR_LEVELS.index(cefr)


def _is_clitic(entry: LevelEntry) -> bool:
    """CEFR-J lists "'m", "'re", "'s"; normalization expands them instead."""
    return entry.key.startswith("'")


class _Keys:
    """Lexicon keys with their display form and alternative spellings."""

    def __init__(self, inputs: LexiconInputs) -> None:
        self.level_entries = tuple(e for e in inputs.level_entries if not _is_clitic(e))
        self.display: dict[str, str] = {}
        variants: dict[str, list[str]] = {}
        for entry in self.level_entries:
            self.display.setdefault(entry.key, entry.display)
            known = variants.setdefault(entry.key, [])
            known.extend(s for s in entry.spellings[1:] if s not in known)
        self.spellings = {
            key: tuple(s for s in found if s not in self.display) for key, found in variants.items()
        }
        self.alias = {s: key for key, found in self.spellings.items() for s in found}
        for ranked in (*inputs.ngsl, *inputs.ngsl_spoken):
            key = self.resolve(ranked.lemma)
            self.display.setdefault(key, key)

    def resolve(self, word: str) -> str:
        """The key a word belongs to: itself, or the key it is a spelling of."""
        return word if word in self.display else self.alias.get(word, word)


def lexicon_words(inputs: LexiconInputs) -> frozenset[str]:
    """Words to look up in the Wiktionary dump: keys, display forms, spellings."""
    keys = _Keys(inputs)
    found = set(keys.display) | set(keys.display.values())
    for spellings in keys.spellings.values():
        found.update(spellings)
    return frozenset(found)


def _levels(entries: Iterable[LevelEntry]) -> dict[str, dict[str, LevelTag]]:
    """key → pos → lowest level any list gives it."""
    levels: dict[str, dict[str, LevelTag]] = {}
    for entry in entries:
        per_pos = levels.setdefault(entry.key, {})
        current = per_pos.get(entry.pos)
        if current is None or _level_index(entry.cefr) < _level_index(current.cefr):
            per_pos[entry.pos] = LevelTag(pos=entry.pos, cefr=entry.cefr, source=entry.source)
    return levels


def _wiki_entries(
    wiki: Mapping[str, tuple[WikiEntry, ...]], key: str, display: str, level_pos: Iterable[str]
) -> list[WikiEntry]:
    """Entries of the word, exact spelling first; parts of speech of the level lists first."""
    candidates = wiki.get(key, ())
    exact = [entry for entry in candidates if entry.word == display]
    chosen = exact or list(candidates)
    preferred = set(level_pos)
    return sorted(chosen, key=lambda entry: entry.pos not in preferred)


# Level lists give inflections of these closed classes their own line
# ("is", "did", "these"); comparatives such as "later" stay words of their own.
_FOLDABLE_POS = frozenset({"VERB", "AUX", "DET", "PRON"})


def _inflection_merges(
    keys: _Keys,
    levels: Mapping[str, Mapping[str, LevelTag]],
    wiki: Mapping[str, tuple[WikiEntry, ...]],
) -> dict[str, str]:
    """Headwords that are only an inflection of another headword ("is" → "be").

    A verb, auxiliary, determiner or pronoun headword is folded into a lemma
    when exactly one other single-word headword lists it among the inflected
    forms of the same part of speech, and it has no inflections of its own.
    "found" (to establish: founded, founding) and "lay" (laid) keep their line.
    """
    lemmas_of: dict[tuple[str, str], set[str]] = defaultdict(set)
    for lemma, display in keys.display.items():
        if " " in lemma:
            continue
        for entry in _wiki_entries(wiki, lemma, display, ()):
            for form in entry.forms:
                lemmas_of[(form.lower(), entry.pos)].add(lemma)
    merges: dict[str, str] = {}
    for key, per_pos in levels.items():
        if is_phrase(key) or key not in keys.display or not set(per_pos) <= _FOLDABLE_POS:
            continue
        own = [e for e in _wiki_entries(wiki, key, keys.display[key], per_pos) if e.pos in per_pos]
        if any(entry.forms for entry in own):
            continue
        targets: set[str] = set()
        for pos in per_pos:
            targets |= lemmas_of.get((key, pos), set())
        targets.discard(key)
        if len(targets) == 1:
            merges[key] = targets.pop()
    # A lemma that is itself folded away cannot take inflections.
    return {key: lemma for key, lemma in merges.items() if lemma not in merges}


def _forms(
    key: str, entries: list[WikiEntry], level_pos: Iterable[str], spellings: Iterable[str]
) -> tuple[str, ...]:
    """Inflected forms from the entries of the listed parts of speech.

    Forms of other parts of speech are left out: the letter "I" has the plural
    "is", which would otherwise join the pronoun's family.
    """
    preferred = set(level_pos)
    listed = [entry for entry in entries if entry.pos in preferred]
    found = {form.lower() for entry in (listed or entries) for form in entry.forms}
    return tuple(sorted(found - {key} - set(spellings)))


def _phonemic(ipa: str) -> str | None:
    """'/ði/ [ðɪj]' → '/ði/'; a phonetic-only '[aj]' gives None."""
    text = ipa.strip()
    end = text.find("/", 1)
    return text[: end + 1] if text.startswith("/") and end > 0 else None


def _ipa(entries: Iterable[WikiEntry], arpabet: tuple[str, ...]) -> tuple[str | None, str | None]:
    """(US, UK) transcriptions.

    US: CMUdict's citation form when there is one, else Wiktionary's GA/US
    tag, else its first untagged transcription. UK: Wiktionary's RP/UK tag;
    untagged transcriptions count only when no accent is tagged at all.
    """
    sounds = [(p, s.tags) for e in entries for s in e.sounds if (p := _phonemic(s.ipa))]
    tagged_uk = [p for p, tags in sounds if _UK_TAGS.intersection(tags)]
    tagged_us = [p for p, tags in sounds if _US_TAGS.intersection(tags)]
    untagged = [p for p, tags in sounds if not tags]
    uk = tagged_uk[0] if tagged_uk else None
    if uk is None and not tagged_us and untagged:
        uk = untagged[0]
    us: str | None = None
    if arpabet:
        try:
            us = to_ipa(arpabet[0])
        except KeyError:
            us = None
    if us is None:
        us = tagged_us[0] if tagged_us else next((p for p in untagged if p != uk), None)
    return us, uk


def _senses(entries: Iterable[WikiEntry]) -> tuple[Sense, ...]:
    senses: list[Sense] = []
    per_pos: Counter[str] = Counter()
    for entry in entries:
        for sense in entry.senses:
            if per_pos[entry.pos] >= MAX_SENSES_PER_POS:
                break
            senses.append(Sense(pos=entry.pos, gloss=sense.gloss, tags=sense.tags))
            per_pos[entry.pos] += 1
    return tuple(senses)


def _family_frequencies(
    members: Mapping[str, tuple[str, ...]], frequency: Callable[[str], float]
) -> dict[str, float]:
    """Summed frequency of each family; a form shared by families is split evenly."""
    claims = Counter(form for forms in members.values() for form in set(forms))
    cache: dict[str, float] = {}

    def lookup(form: str) -> float:
        if form not in cache:
            cache[form] = frequency(form)
        return cache[form]

    return {
        key: sum(lookup(form) / claims[form] for form in set(forms))
        for key, forms in members.items()
    }


def build_lexicon(inputs: LexiconInputs, frequency: Callable[[str], float]) -> Lexicon:
    """Merges the sources: single words by family frequency (rank 1 first), then phrases."""
    keys = _Keys(inputs)
    levels = _levels(keys.level_entries)
    merges = _inflection_merges(keys, levels, inputs.wiki)
    folded: dict[str, list[str]] = defaultdict(list)
    for inflection, lemma in merges.items():
        target = levels.setdefault(lemma, {})
        for tag in levels.pop(inflection, {}).values():
            current = target.get(tag.pos)
            if current is None or _level_index(tag.cefr) < _level_index(current.cefr):
                target[tag.pos] = tag
        del keys.display[inflection]
        folded[lemma].append(inflection)
    ngsl_rank = {keys.resolve(r.lemma): r.rank for r in reversed(inputs.ngsl)}
    spoken_rank = {keys.resolve(r.lemma): r.rank for r in reversed(inputs.ngsl_spoken)}

    drafts: dict[str, dict[str, object]] = {}
    members: dict[str, tuple[str, ...]] = {}
    for key, display in keys.display.items():
        per_pos = levels.get(key, {})
        wiki = _wiki_entries(inputs.wiki, key, display, per_pos)
        multiword = is_phrase(key)
        spellings = keys.spellings.get(key, ())
        forms: tuple[str, ...] = ()
        if not multiword:
            forms = tuple(sorted({*_forms(key, wiki, per_pos, spellings), *folded.get(key, ())}))
        arpabet = () if multiword else inputs.pronunciations.get(key, ())
        ipa_us, ipa_uk = _ipa(wiki, arpabet)
        pos = list(per_pos)
        pos.extend(entry.pos for entry in wiki if entry.pos not in pos)
        sources = {tag.source for tag in per_pos.values()} | {"wordfreq"}
        if key in ngsl_rank:
            sources.add("ngsl")
        if key in spoken_rank:
            sources.add("ngsl_spoken")
        if arpabet:
            sources.add("cmudict")
        if wiki:
            sources.add("wiktextract")
        if not multiword:
            # A form that is a headword itself ("saw", "number") keeps its own
            # frequency instead of lending it to another family.
            own = (form for form in forms if form not in keys.display)
            members[key] = (key, *(s for s in spellings if not is_phrase(s)), *own)
        drafts[key] = {
            "lemma": key,
            "display": display,
            "spellings": spellings,
            "multiword": multiword,
            "cefr": min((t.cefr for t in per_pos.values()), key=_level_index, default=None),
            "levels": tuple(per_pos.values()),
            "pos": tuple(pos),
            "ngsl_rank": ngsl_rank.get(key),
            "ngsl_spoken_rank": spoken_rank.get(key),
            "forms": forms,
            "ipa_us": ipa_us,
            "ipa_uk": ipa_uk,
            "arpabet": arpabet,
            "senses": _senses(wiki),
            "sources": tuple(sorted(sources)),
        }

    family = _family_frequencies(members, frequency)
    words = sorted(members, key=lambda key: (-family[key], key))
    ranks = {key: rank for rank, key in enumerate(words, start=1)}
    phrases = sorted(key for key in drafts if key not in members)
    entries = tuple(
        LexiconEntry.model_validate(
            drafts[key]
            | {
                "rank": ranks.get(key),
                "zipf": zipf(frequency(key)),
                "family_zipf": zipf(family[key]) if key in family else None,
            }
        )
        for key in (*words, *phrases)
    )
    return Lexicon(entries=entries, merged=dict(sorted(merges.items())))

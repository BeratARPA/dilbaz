"""Answer normalization from a pack's `normalization.yaml` (docs/03 §0.5, docs/11 §6).

The rules are data; this module applies them in the order the file documents,
the same order the engine uses, so references, variants and answers compare
word for word.
"""

from __future__ import annotations

from pathlib import Path

import yaml
from pydantic import BaseModel, ConfigDict, Field

NORMALIZATION_FILE = "normalization.yaml"


class NumberWords(BaseModel):
    """Words for 0-999: units 0-19, tens by index, and "hundred"."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    units: tuple[str, ...] = Field(min_length=20, max_length=20)
    tens: tuple[str | None, ...] = Field(min_length=10, max_length=10)
    hundred: str


class NormalizationRules(BaseModel):
    """`packs/<l2>/normalization.yaml`."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    version: int
    apostrophes: tuple[str, ...] = ()
    punctuation: str = ""
    words: dict[str, str] = Field(default_factory=dict)
    endings: dict[str, str] = Field(default_factory=dict)
    spellings: dict[str, str] = Field(default_factory=dict)
    numbers: NumberWords | None = None
    tests: tuple[tuple[str, str], ...] = ()


class Normalizer:
    """Applies one language's normalization rules."""

    def __init__(self, rules: NormalizationRules) -> None:
        self.rules = rules
        self._apostrophes = str.maketrans(dict.fromkeys(rules.apostrophes, "'"))
        self._punctuation = str.maketrans(dict.fromkeys(rules.punctuation, " "))

    @classmethod
    def from_file(cls, path: Path) -> Normalizer:
        """Rules from a pack's `normalization.yaml`."""
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
        return cls(NormalizationRules.model_validate(data))

    def __call__(self, text: str) -> str:
        """The normalized form of [text]."""
        cleaned = text.lower().translate(self._apostrophes).translate(self._punctuation)
        expanded = " ".join(self._expand(word) for word in cleaned.split())
        spelled = " ".join(self._spell(word) for word in expanded.split())
        return " ".join(self._number(word) for word in spelled.split())

    def _expand(self, word: str) -> str:
        if word in self.rules.words:
            return self.rules.words[word]
        for ending, replacement in self.rules.endings.items():
            if word.endswith(ending) and len(word) > len(ending):
                return word[: -len(ending)] + replacement
        return word

    def _spell(self, word: str) -> str:
        word = self.rules.spellings.get(word, word)
        return word.replace("'", "").replace("-", " ")

    def _number(self, word: str) -> str:
        if not word.isdigit() or self.rules.numbers is None:
            return word
        value = int(word)
        return self._say(value) if value < 1000 else word

    def _say(self, value: int) -> str:
        numbers = self.rules.numbers
        assert numbers is not None
        if value < 20:
            return numbers.units[value]
        if value < 100:
            tens = numbers.tens[value // 10] or ""
            return tens if value % 10 == 0 else f"{tens} {numbers.units[value % 10]}"
        head = f"{numbers.units[value // 100]} {numbers.hundred}"
        return head if value % 100 == 0 else f"{head} {self._say(value % 100)}"

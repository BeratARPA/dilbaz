"""Upstream source files in miniature, in their real formats."""

from __future__ import annotations

import gzip
import json
from pathlib import Path

NGSL_STATS = """Lemma,SFI Rank,SFI,Adjusted Frequency per Million (U)
the,1,87.85,60910
be,2,86.86,48575
watch,412,70.10,300
colour,900,60.00,100
"""

SPOKEN_STATS = """Lemma,Rank,SFI,U
be,1,87.95,62378.07
TRUE,#N/A,#N/A,#N/A
watch,300,60.00,90.00
"""

CEFRJ = """headword,pos,CEFR,CoreInventory 1,CoreInventory 2,Threshold
watch,verb,A1,,,
watch,noun,A2,,,
be,be-verb,A1,,,
color/colour,noun,A1,,,
TV,noun,A1,,,
according to,preposition,A2,,,
see,verb,A1,,,
saw,noun,B2,,,
"""

OCTANOVE = """headword,pos,CEFR,notes
watch,noun,C1,
laud ,vern,C2,
"""

CMUDICT = """;;; a comment
be B IY1
saw S AO1
see S IY1
watch W AA1 CH
watch(2) W AO1 CH
aalborg AO1 L B AO0 R G # place, danish
"""

WIKI_LINES = [
    {
        "word": "watch",
        "pos": "noun",
        "lang_code": "en",
        "senses": [
            {"glosses": ["A portable timepiece."]},
            {"glosses": ["An old sense."], "tags": ["obsolete"]},
        ],
        "sounds": [
            {"ipa": "/wɒtʃ/", "tags": ["Received-Pronunciation"]},
            {"ipa": "/wɑtʃ/"},
            {"audio": "watch.ogg"},
        ],
        "forms": [{"form": "watches", "tags": ["plural"]}],
    },
    {
        "word": "watch",
        "pos": "verb",
        "lang_code": "en",
        "senses": [{"glosses": ["To look at for a time."], "tags": ["transitive"]}],
        "forms": [
            {"form": "watches", "tags": ["present", "singular", "third-person"]},
            {"form": "watched", "tags": ["past"]},
            {"form": "no-table-tags", "tags": ["table-tags"]},
            {"form": "watcheth", "tags": ["archaic", "third-person"]},
        ],
    },
    {"word": "watch", "pos": "verb", "lang_code": "fr", "senses": [{"glosses": ["ignored"]}]},
    {"word": "Watch", "pos": "name", "lang_code": "en", "senses": [{"glosses": ["A name."]}]},
    {
        "word": "see",
        "pos": "verb",
        "lang_code": "en",
        "senses": [{"glosses": ["To perceive with the eyes."]}],
        "forms": [
            {"form": "saw", "tags": ["past"]},
            {"form": "seen", "tags": ["participle", "past"]},
        ],
    },
    {
        "word": "saw",
        "pos": "verb",
        "lang_code": "en",
        "senses": [{"glosses": ["simple past of see"], "form_of": [{"word": "see"}]}],
    },
    {"word": "saw", "pos": "noun", "lang_code": "en", "senses": [{"glosses": ["A tool."]}]},
    {"word": "TV", "pos": "noun", "lang_code": "en", "senses": [{"glosses": ["Television."]}]},
    {"word": "tv", "pos": "noun", "lang_code": "en", "senses": [{"glosses": ["Lowercase."]}]},
    {"word": "zebra", "pos": "noun", "lang_code": "en", "senses": [{"glosses": ["An animal."]}]},
]

FREQUENCIES = {
    "the": 0.05,
    "be": 0.006,
    "is": 0.01,
    "was": 0.004,
    "are": 0.004,
    "watch": 0.0002,
    "watches": 0.00002,
    "watched": 0.00005,
    "watching": 0.00008,
    "see": 0.0008,
    "saw": 0.0002,
    "seen": 0.0001,
    "color": 0.0001,
    "colour": 0.00005,
    "tv": 0.0001,
    "according to": 0.00009,
    "go": 0.002,
    "went": 0.0003,
}


def fake_frequency(word: str) -> float:
    return FREQUENCIES.get(word, 0.0)


def write_wiki_dump(path: Path, lines: list[dict[str, object]]) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    with gzip.open(path, "wt", encoding="utf-8") as stream:
        for line in lines:
            stream.write(json.dumps(line, ensure_ascii=False) + "\n")
    return path

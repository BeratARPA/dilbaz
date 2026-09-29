"""A miniature S4 input tree: senses, grammar, lexicon, S3 candidates and analysis cache."""

from __future__ import annotations

import gzip
from collections.abc import Iterable, Iterator
from pathlib import Path

from dilbaz_content.analysis import AnalyzedSentence, Token, Translation
from dilbaz_content.carriers import Candidate
from dilbaz_content.carriers_step import ANALYSIS_FILE, TargetCandidates
from dilbaz_content.items import GrammarPoint, Level, Provenance, WordSense
from dilbaz_content.lexicon import LevelTag, LexiconEntry

OWN = Provenance(source="dilbaz curation", license="own")


def _tokens(*words: tuple[str, str, str, str]) -> tuple[Token, ...]:
    return tuple(words)


PERIOD = (".", ".", "PUNCT", ".")
# id → (text, tokens, Turkish translation)
TATOEBA: dict[int, tuple[str, tuple[Token, ...], str]] = {
    1: (
        "I watch TV every evening.",
        _tokens(
            ("I", "i", "PRON", "PRP"),
            ("watch", "watch", "VERB", "VBP"),
            ("TV", "tv", "NOUN", "NN"),
            ("every", "every", "DET", "DT"),
            ("evening", "evening", "NOUN", "NN"),
            PERIOD,
        ),
        "Her akşam televizyon izlerim.",
    ),
    2: (
        "We watch TV.",
        _tokens(
            ("We", "we", "PRON", "PRP"),
            ("watch", "watch", "VERB", "VBP"),
            ("TV", "tv", "NOUN", "NN"),
            PERIOD,
        ),
        "Televizyon izleriz.",
    ),
    3: (
        "You are right.",
        _tokens(
            ("You", "you", "PRON", "PRP"),
            ("are", "be", "AUX", "VBP"),
            ("right", "right", "ADJ", "JJ"),
            PERIOD,
        ),
        "Haklısın.",
    ),
    4: (
        "I watch a documentary.",
        _tokens(
            ("I", "i", "PRON", "PRP"),
            ("watch", "watch", "VERB", "VBP"),
            ("a", "a", "DET", "DT"),
            ("documentary", "documentary", "NOUN", "NN"),
            PERIOD,
        ),
        "Bir belgesel izlerim.",
    ),
    5: (
        "Tom is here.",
        _tokens(
            ("Tom", "tom", "PROPN", "NNP"),
            ("is", "be", "AUX", "VBZ"),
            ("here", "here", "ADV", "RB"),
            PERIOD,
        ),
        "Tom burada.",
    ),
    6: (
        "Do I watch TV every evening?",
        _tokens(
            ("Do", "do", "AUX", "VBP"),
            ("I", "i", "PRON", "PRP"),
            ("watch", "watch", "VERB", "VB"),
            ("TV", "tv", "NOUN", "NN"),
            ("every", "every", "DET", "DT"),
            ("evening", "evening", "NOUN", "NN"),
            ("?", "?", "PUNCT", "."),
        ),
        "Her akşam televizyon izler miyim?",
    ),
    7: (
        "They watch TV.",
        _tokens(
            ("They", "they", "PRON", "PRP"),
            ("watch", "watch", "VERB", "VBP"),
            ("TV", "tv", "NOUN", "NN"),
            PERIOD,
        ),
        "Televizyon izlerler.",
    ),
    8: (
        "My right hand is cold.",
        _tokens(
            ("My", "my", "PRON", "PRP$"),
            ("right", "right", "ADJ", "JJ"),
            ("hand", "hand", "NOUN", "NN"),
            ("is", "be", "AUX", "VBZ"),
            ("cold", "cold", "ADJ", "JJ"),
            PERIOD,
        ),
        "Sağ elim soğuk.",
    ),
}
# Own sentences the fake analyzer knows.
OWN_TOKENS: dict[str, tuple[Token, ...]] = {
    "My right hand is cold.": TATOEBA[8][1],
    "You are right!": (*TATOEBA[3][1][:-1], ("!", "!", "PUNCT", ".")),
    "Damn, you are right.": (
        ("Damn", "damn", "INTJ", "UH"),
        (",", ",", "PUNCT", ","),
        *TATOEBA[3][1],
    ),
    "You are right, xyzzy.": (
        *TATOEBA[3][1][:-1],
        (",", ",", "PUNCT", ","),
        ("xyzzy", "xyzzy", "NOUN", "NN"),
        PERIOD,
    ),
    # Variants of "We watch TV." for S5.
    "We watch television.": (
        ("We", "we", "PRON", "PRP"),
        ("watch", "watch", "VERB", "VBP"),
        ("television", "television", "NOUN", "NN"),
        PERIOD,
    ),
    "We see TV.": (
        ("We", "we", "PRON", "PRP"),
        ("see", "see", "VERB", "VBP"),
        ("TV", "tv", "NOUN", "NN"),
        PERIOD,
    ),
    # A tagger slip: "watch" read as a noun.
    "We all watch TV.": (
        ("We", "we", "PRON", "PRP"),
        ("all", "all", "PRON", "DT"),
        ("watch", "watch", "NOUN", "NN"),
        ("TV", "tv", "NOUN", "NN"),
        PERIOD,
    ),
}


class OwnAnalyzer:
    """Analyzes the own sentences of the tests."""

    name = "own:1"

    def __init__(self) -> None:
        self.calls = 0

    def analyze(self, texts: Iterable[str]) -> Iterator[tuple[Token, ...]]:
        self.calls += 1
        for text in texts:
            yield OWN_TOKENS[text]


def _sense(lemma: str, pos: str, level: Level, number: int = 1) -> WordSense:
    code = {"VERB": "v", "NOUN": "n", "ADJ": "adj"}[pos]
    return WordSense(
        key=f"en.ws.{lemma}.{code}.{number}",
        lemma=lemma,
        pos=pos,
        sense=f"{lemma} {number}",
        level=level,
        provenance=OWN,
    )


SENSES = (
    _sense("watch", "VERB", "A0"),
    _sense("evening", "NOUN", "A1"),
    _sense("right", "ADJ", "A0"),
    _sense("right", "ADJ", "A0", 2),
)


def _entry(lemma: str, pos: str, cefr: str, rank: int) -> LexiconEntry:
    return LexiconEntry(
        lemma=lemma,
        display=lemma,
        multiword=False,
        cefr=cefr,  # type: ignore[arg-type]
        levels=(LevelTag(pos=pos, cefr=cefr, source="cefrj"),),  # type: ignore[arg-type]
        rank=rank,
        zipf=5.0,
        family_zipf=5.0,
        sources=("cefrj",),
    )


# A1 words among the 300 most frequent are A0.
LEXICON = (
    _entry("i", "PRON", "A1", 8),
    _entry("we", "PRON", "A1", 29),
    _entry("you", "PRON", "A1", 10),
    _entry("they", "PRON", "A1", 30),
    _entry("my", "PRON", "A1", 25),
    _entry("watch", "VERB", "A1", 270),
    _entry("tv", "NOUN", "A1", 676),
    _entry("every", "DET", "A1", 250),
    _entry("evening", "NOUN", "A1", 900),
    _entry("be", "VERB", "A1", 2),
    _entry("do", "VERB", "A1", 20),
    _entry("a", "DET", "A1", 5),
    _entry("right", "ADJ", "A1", 100),
    _entry("here", "ADV", "A1", 50),
    _entry("hand", "NOUN", "A1", 300),
    _entry("cold", "ADJ", "A1", 500),
    _entry("damn", "INTJ", "A1", 3000),
    _entry("documentary", "NOUN", "B1", 5000),
)


def _point(code: str, level: Level) -> GrammarPoint:
    return GrammarPoint(
        key=f"en.{code}",
        code=code,
        level=level,
        name=code,
        description=code,
        examples=("one", "two"),
        provenance=OWN,
    )


GRAMMAR = (
    _point("gp.be.present", "A0"),
    _point("gp.pronouns.subject", "A0"),
    _point("gp.possessive.adjectives", "A0"),
    _point("gp.articles.a_an", "A0"),
    _point("gp.present_simple.affirmative", "A1"),
    _point("gp.present_simple.questions", "A1"),
)


def _candidate(target: str, sid: int, score: float) -> Candidate:
    text, _, turkish = TATOEBA[sid]
    return Candidate(
        target=target,
        sentence_id=sid,
        text=text,
        author="CK",
        level="A1",
        words=len(text.split()),
        native=True,
        names=0,
        score=score,
        turkish=(turkish,),
    )


CANDIDATES = {
    "en.ws.watch.v.1": (
        _candidate("en.ws.watch.v.1", 2, 2.0),
        _candidate("en.ws.watch.v.1", 1, 1.5),
    ),
    "en.ws.evening.n.1": (_candidate("en.ws.evening.n.1", 1, 1.5),),
    # The tagger cannot tell the two "right"s apart: S3 offers both the same.
    "en.ws.right.adj.1": (_candidate("en.ws.right.adj.1", 3, 1.8),),
    "en.ws.right.adj.2": (_candidate("en.ws.right.adj.2", 3, 1.8),),
}


def _lines(models: Iterable[object]) -> str:
    return "".join(model.model_dump_json(exclude_defaults=True) + "\n" for model in models)  # type: ignore[attr-defined]


def write_s4_inputs(root: Path, curation: str | None = None) -> Path:
    """content/ with everything S4 reads; [curation] is `sentences.yaml`."""
    items = root / "packs" / "en" / "items"
    items.mkdir(parents=True, exist_ok=True)
    (items / "word_senses.jsonl").write_text(_lines(SENSES), encoding="utf-8")
    (items / "grammar_points.jsonl").write_text(_lines(GRAMMAR), encoding="utf-8")
    work = root / "work"
    work.mkdir(parents=True, exist_ok=True)
    (work / "lexicon.en.jsonl").write_text(_lines(LEXICON), encoding="utf-8")
    lines = [
        TargetCandidates(
            target=sense.key,
            lemma=sense.lemma,
            pos=sense.pos,
            level=sense.level,
            sense=sense.sense,
            candidates=CANDIDATES[sense.key],
        )
        for sense in SENSES
    ]
    (work / "carriers.en.candidates.jsonl").write_text(_lines(lines), encoding="utf-8")
    with gzip.open(work / ANALYSIS_FILE, "wt", encoding="utf-8") as sink:
        for sid, (text, tokens, turkish) in TATOEBA.items():
            record = AnalyzedSentence(
                id=sid,
                text=text,
                author="CK",
                native=True,
                tokens=tokens,
                turkish=(Translation(id=sid + 100, text=turkish),),
            )
            sink.write(record.model_dump_json(exclude_defaults=True) + "\n")
    if curation is not None:
        directory = root / "curation" / "en"
        directory.mkdir(parents=True, exist_ok=True)
        (directory / "sentences.yaml").write_text(curation, encoding="utf-8")
    return root

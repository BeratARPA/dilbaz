import json
from pathlib import Path

import pytest
from pydantic import ValidationError

from dilbaz_content.items import GrammarPoint, WordSense, slug
from dilbaz_content.lexicon import LevelTag, LexiconEntry, Sense
from dilbaz_content.select_step import (
    A0_MAX_RANK,
    ChunkEntry,
    GrammarEntry,
    SelectionError,
    SenseChoice,
    WordSenseCuration,
    build_chunks,
    build_grammar_points,
    load_curation,
    run_select,
    select_word_senses,
)


def entry(
    lemma: str,
    rank: int | None,
    levels: dict[str, str],
    *,
    spoken: bool = False,
    glosses: dict[str, list[str]] | None = None,
) -> LexiconEntry:
    senses = tuple(
        Sense(pos=pos, gloss=gloss)
        for pos, texts in (glosses or {pos: [f"{lemma} as {pos}"] for pos in levels}).items()
        for gloss in texts
    )
    sources = ("cefrj", "ngsl_spoken", "wordfreq") if spoken else ("cefrj", "wordfreq")
    return LexiconEntry(
        lemma=lemma,
        display=lemma,
        multiword=False,
        cefr=min(levels.values()) if levels else None,  # type: ignore[arg-type]
        levels=tuple(LevelTag(pos=p, cefr=c, source="cefrj") for p, c in levels.items()),  # type: ignore[arg-type]
        pos=tuple(levels),
        rank=rank,
        zipf=5.0,
        family_zipf=5.0,
        ipa_us=f"/{lemma}/",
        senses=senses,
        sources=sources,
    )


def select(
    lexicon: list[LexiconEntry], curation: WordSenseCuration | None = None, limit: int = 100
) -> tuple[WordSense, ...]:
    return select_word_senses(
        lexicon, curation or WordSenseCuration(), l2="en", max_level="A2", limit=limit
    )


def test_slug_makes_key_safe_ids() -> None:
    assert slug("How are you?") == "how_are_you"
    assert slug("a.m.") == "a_m"
    assert slug("part-time") == "part_time"


def test_the_rule_takes_content_senses_up_to_the_level() -> None:
    lexicon = [
        entry("watch", 400, {"VERB": "A1", "NOUN": "A2"}),
        entry("because", 401, {"CONJ": "A1"}),
        entry("government", 402, {"NOUN": "B1"}),
    ]
    senses = select(lexicon)
    assert [(s.key, s.level) for s in senses] == [
        ("en.ws.watch.v.1", "A1"),
        ("en.ws.watch.n.1", "A2"),
    ]
    assert senses[0].sense == "watch as VERB"
    assert senses[0].provenance.license == "CC BY-SA 4.0"
    assert senses[0].ipa_us == "/watch/"


def test_a1_senses_of_the_most_frequent_words_are_a0() -> None:
    senses = select(
        [
            entry("go", A0_MAX_RANK, {"VERB": "A1"}),
            entry("buy", A0_MAX_RANK + 1, {"VERB": "A1"}),
            entry("need", 10, {"VERB": "A2"}),
        ]
    )
    assert {s.lemma: s.level for s in senses} == {"go": "A0", "buy": "A1", "need": "A2"}


def test_at_most_two_senses_per_lemma() -> None:
    senses = select([entry("back", 50, {"ADV": "A1", "ADJ": "A2", "NOUN": "A2"})])
    assert [s.pos for s in senses] == ["ADV", "ADJ"]


def test_order_is_include_then_spoken_then_rank() -> None:
    lexicon = [
        entry("court", 10, {"NOUN": "A2"}),
        entry("tired", 900, {"ADJ": "A1"}, spoken=True),
        entry("hungry", 800, {"ADJ": "A1"}, spoken=True),
        entry("breakfast", 2000, {"NOUN": "A1"}),
    ]
    senses = select(lexicon, WordSenseCuration(include=("breakfast",)))
    assert [s.lemma for s in senses] == ["breakfast", "hungry", "tired", "court"]


def test_the_limit_keeps_the_last_lemma_whole() -> None:
    lexicon = [
        entry("watch", 1, {"VERB": "A1", "NOUN": "A1"}),
        entry("play", 2, {"VERB": "A1", "NOUN": "A1"}),
        entry("run", 3, {"VERB": "A1"}),
    ]
    senses = select(lexicon, limit=3)
    assert [s.key for s in senses] == [
        "en.ws.watch.v.1",
        "en.ws.watch.n.1",
        "en.ws.play.v.1",
        "en.ws.play.n.1",
    ]


def test_excluded_lemmas_are_skipped() -> None:
    lexicon = [entry("be", 1, {"VERB": "A1"}), entry("go", 2, {"VERB": "A1"})]
    senses = select(lexicon, WordSenseCuration(exclude=("be",)))
    assert [s.lemma for s in senses] == ["go"]


def test_curated_senses_replace_the_rule() -> None:
    lexicon = [
        entry(
            "right",
            99,
            {"ADJ": "A1"},
            glosses={"ADJ": ["Designating the east side when facing north.", "Correct."]},
        )
    ]
    curation = WordSenseCuration(
        senses={
            "right": (
                SenseChoice(pos="ADJ", sense="correct, true"),
                SenseChoice(pos="ADJ", wiktionary=0, level="A2"),
            )
        }
    )
    senses = select(lexicon, curation)
    assert [(s.key, s.sense, s.level) for s in senses] == [
        ("en.ws.right.adj.1", "correct, true", "A0"),
        ("en.ws.right.adj.2", "Designating the east side when facing north.", "A2"),
    ]
    assert senses[0].provenance.license == "own"
    assert senses[1].provenance.license == "CC BY-SA 4.0"


def test_curated_senses_can_fix_the_ipa() -> None:
    lexicon = [entry("breakfast", 2000, {"NOUN": "A1"})]
    curation = WordSenseCuration(
        senses={
            "breakfast": (
                SenseChoice(pos="NOUN", sense="the first meal of the day", ipa_uk="/ˈbɹɛk.fəst/"),
            )
        }
    )
    (sense,) = select(lexicon, curation)
    assert (sense.ipa_us, sense.ipa_uk) == ("/breakfast/", "/ˈbɹɛk.fəst/")
    with pytest.raises(ValidationError):
        SenseChoice(pos="NOUN", ipa_uk="ˈbɹɛk.fəst")


def test_curated_senses_above_the_level_are_dropped() -> None:
    lexicon = [entry("state", 101, {"NOUN": "A2"})]
    curation = WordSenseCuration(
        senses={"state": (SenseChoice(pos="NOUN", sense="a country's region", level="B1"),)}
    )
    assert select(lexicon, curation) == ()


def test_curation_errors_are_reported() -> None:
    lexicon = [entry("go", 1, {"VERB": "A1"}), entry("then", 2, {})]
    with pytest.raises(SelectionError, match="missing from the lexicon"):
        select(lexicon, WordSenseCuration(exclude=("gone",)))
    with pytest.raises(SelectionError, match="both included and excluded"):
        select(lexicon, WordSenseCuration(include=("go",), exclude=("go",)))
    with pytest.raises(SelectionError, match="no Wiktionary VERB sense 3"):
        select(lexicon, WordSenseCuration(senses={"go": (SenseChoice(pos="VERB", wiktionary=3),)}))
    with pytest.raises(SelectionError, match="has no level"):
        select(lexicon, WordSenseCuration(senses={"then": (SenseChoice(pos="ADV", sense="next"),)}))


def test_chunks_are_keyed_by_their_text() -> None:
    chunks = build_chunks(
        [ChunkEntry(text="How are you?", level="A0", function="greeting")], l2="en"
    )
    assert chunks[0].key == "en.chunk.how_are_you"
    assert chunks[0].provenance.license == "own"
    with pytest.raises(SelectionError, match="share the key"):
        build_chunks(
            [
                ChunkEntry(text="Thank you!", level="A0", function="thanks"),
                ChunkEntry(text="Thank you.", level="A0", function="thanks"),
            ],
            l2="en",
        )


def test_grammar_points_are_keyed_by_their_code() -> None:
    entry_ = GrammarEntry(
        code="gp.be.present",
        level="A0",
        name="be: am / is / are",
        description="The verb be in the present.",
        examples=("I am here.", "She is a teacher."),
    )
    points = build_grammar_points([entry_], l2="en")
    assert points[0].key == "en.gp.be.present"
    with pytest.raises(SelectionError, match="appears twice"):
        build_grammar_points([entry_, entry_], l2="en")
    with pytest.raises(ValidationError):
        GrammarPoint.model_validate(points[0].model_dump() | {"examples": ("Only one example.",)})


def write_curation(directory: Path, senses: str, chunks: str, grammar: str) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "word_senses.yaml").write_text(senses, encoding="utf-8")
    (directory / "chunks.yaml").write_text(chunks, encoding="utf-8")
    (directory / "grammar_points.yaml").write_text(grammar, encoding="utf-8")


def test_empty_curation_files_mean_no_decisions(tmp_path: Path) -> None:
    write_curation(tmp_path, "", "", "")
    senses, chunks, grammar = load_curation(tmp_path)
    assert senses == WordSenseCuration()
    assert (chunks, grammar) == ((), ())


def test_run_select_writes_the_items(tmp_path: Path) -> None:
    work = tmp_path / "work"
    work.mkdir()
    lexicon = [entry("go", 1, {"VERB": "A1"}), entry("be", 2, {"VERB": "A1"})]
    (work / "lexicon.en.jsonl").write_text(
        "".join(e.model_dump_json() + "\n" for e in lexicon), encoding="utf-8"
    )
    write_curation(
        tmp_path / "curation" / "en",
        "exclude: [be]\nsenses:\n  go:\n    - {pos: VERB, sense: move to another place}\n",
        '- {text: "How are you?", level: A0, function: greeting}\n',
        "- code: gp.be.present\n  level: A0\n  name: be\n  description: The verb be.\n"
        "  examples: [I am here., You are late.]\n",
    )

    selection = run_select(tmp_path, l2="en", max_level="A2", limit=10)

    items = tmp_path / "packs" / "en" / "items"
    senses = [json.loads(line) for line in (items / "word_senses.jsonl").open(encoding="utf-8")]
    assert [s["key"] for s in senses] == ["en.ws.go.v.1"]
    assert senses[0]["sense"] == "move to another place"
    assert "carriers" not in senses[0]
    assert len(selection.chunks) == 1
    assert (items / "chunks.jsonl").read_text(encoding="utf-8").count("\n") == 1
    assert (items / "grammar_points.jsonl").is_file()


def test_run_select_needs_the_lexicon(tmp_path: Path) -> None:
    write_curation(tmp_path / "curation" / "en", "", "", "")
    with pytest.raises(FileNotFoundError, match="dilbaz-content lexicon"):
        run_select(tmp_path, l2="en", max_level="A2", limit=10)

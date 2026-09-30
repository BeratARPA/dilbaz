import json
import shutil
from pathlib import Path

from typer.testing import CliRunner

from dilbaz_content.cli import app
from dilbaz_content.grammar_tags import grammar_codes
from dilbaz_content.items import Chunk, Provenance
from dilbaz_content.normalize import NORMALIZATION_FILE
from dilbaz_content.pair_step import load_pair_curation, read_translations, run_pair
from dilbaz_content.select_step import read_lexicon
from dilbaz_content.sentences_step import Validation, run_sentences

from sample_sentences import OWN_TOKENS, OwnAnalyzer, write_s4_inputs

RIGHTS = """
carriers:
  en.ws.right.adj.1: [{tatoeba: 3}]
  en.ws.right.adj.2: [{text: "My right hand is cold."}]
"""
EN_RULES = Path(__file__).resolve().parents[2] / "packs" / "en" / NORMALIZATION_FILE
SENSES = """
en.ws.watch.v.1: {meaning: "izlemek, seyretmek", note: "TV ve film için"}
en.ws.evening.n.1: {meaning: akşam}
en.ws.right.adj.1: {meaning: "doğru, haklı"}
en.ws.right.adj.2: {meaning: sağ}
"""
CHUNKS = """
en.chunk.thank_you: {meaning: "Teşekkür ederim.", variants: ["Thanks.", "thank you!"]}
"""
SENTENCES = """
en.sent.we_watch_tv: {variants: ["We watch television."]}
en.sent.my_right_hand_is_cold: {turkish: "Sağ elim soğuk."}
"""
GRAMMAR = """
gp.be.present:
  {name: "be (am/is/are)", explanation: "Olmak fiili.", rule: "I am, you are, he is."}
gp.pronouns.subject:
  {name: "Özne zamirleri", explanation: "Ben, sen, o.", rule: "I, you, he, she, it."}
gp.possessive.adjectives:
  {name: "İyelik sıfatları", explanation: "Benim, senin.", rule: "my, your."}
gp.articles.a_an: {name: "a / an", explanation: "Bir.", rule: "Ünlüden önce an."}
gp.present_simple.affirmative:
  {name: "Geniş zaman", explanation: "Alışkanlıklar.", rule: "he/she/it ile -s."}
gp.present_simple.questions:
  {name: "Geniş zaman soruları", explanation: "Do/does.", rule: "Do + özne."}
"""
CONTRASTS = """
- {items: [en.ws.right.adj.1, en.ws.right.adj.2], note: "right: doğru mu, sağ mı? Bağlama bak."}
"""
ERROR_TAGS = """
- code: art.missing
  category: grammar
  severity: 1.0
  description: "Tekil sayılabilir isimden önce a/an/the eksik."
  examples:
    - "I have problem → I have a problem"
    - "She is teacher → She is a teacher"
    - "It is big house → It is a big house"
  grammar_codes: [gp.articles.a_an]
"""


def build(tmp_path: Path, **overrides: str) -> Path:
    """S4 output plus a pair curation; [overrides] replace curation files."""
    root = write_s4_inputs(tmp_path, RIGHTS)
    chunk = Chunk(
        key="en.chunk.thank_you",
        text="Thank you.",
        level="A0",
        function="politeness",
        provenance=Provenance(source="dilbaz curation", license="own"),
    )
    items = root / "packs" / "en" / "items"
    (items / "chunks.jsonl").write_text(chunk.model_dump_json() + "\n", encoding="utf-8")
    shutil.copy(EN_RULES, root / "packs" / "en" / NORMALIZATION_FILE)
    run_sentences(root, l2="en", analyzer=OwnAnalyzer)
    files = {
        "word_senses.yaml": SENSES,
        "chunks.yaml": CHUNKS,
        "sentences.yaml": SENTENCES,
        "grammar.yaml": GRAMMAR,
        "contrasts.yaml": CONTRASTS,
        "error_tags.yaml": ERROR_TAGS,
        **overrides,
    }
    curation = root / "curation" / "tr-en"
    curation.mkdir(parents=True, exist_ok=True)
    for name, text in files.items():
        (curation / name).write_text(text, encoding="utf-8")
    return root


def lines(path: Path) -> list[dict]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()]


def test_the_pair_pack_is_built_from_the_curation(tmp_path: Path) -> None:
    root = build(tmp_path)

    report = run_pair(root, l1="tr", l2="en", analyzer=OwnAnalyzer)

    # "thank you!" is "Thank you." once normalized: dropped with a warning.
    assert [(i.kind, i.detail) for i in report.issues] == [("duplicate_variant", "thank you!")]
    assert report.glosses == {"word_senses": 4, "chunks": 1, "sentences": 4, "grammar_points": 6}
    assert report.prompts == {"tatoeba": 3, "curated": 1}
    out = root / "packs" / "tr-en"
    glosses = {g["key"]: g for g in lines(out / "glosses.jsonl")}
    assert glosses["en.ws.watch.v.1"]["meaning"] == "izlemek, seyretmek"
    assert glosses["en.ws.watch.v.1"]["usage_note"] == "TV ve film için"
    prompt = glosses["en.sent.we_watch_tv"]
    assert prompt["meaning"] == "Televizyon izleriz."
    assert prompt["provenance"] == {"source": "tatoeba:102", "license": "CC BY 2.0 FR"}
    assert glosses["en.sent.my_right_hand_is_cold"]["provenance"]["license"] == "own"
    assert glosses["en.gp.be.present"]["explanation"] == "Olmak fiili."
    variants = {v["key"]: v["variants"] for v in lines(out / "variants.jsonl")}
    assert variants == {
        "en.chunk.thank_you": ["Thanks."],
        "en.sent.we_watch_tv": ["We watch television."],
    }
    assert next(r["code"] for r in lines(out / "rule_notes.jsonl")) == "gp.be.present"
    assert lines(out / "contrast_notes.jsonl")[0]["items"] == [
        "en.ws.right.adj.1",
        "en.ws.right.adj.2",
    ]
    assert lines(out / "error_tags.jsonl")[0]["code"] == "art.missing"
    saved = json.loads((root / "work" / "pair.tr-en.report.json").read_text(encoding="utf-8"))
    assert saved["variants"] == 2


def test_a_wrong_translation_gives_way_to_the_validation_fix(tmp_path: Path) -> None:
    root = build(tmp_path)
    decision = Validation(
        key="en.sent.you_are_right",
        text="You are right.",
        round=1,
        naturalness=5,
        grammatical=True,
        ambiguous=False,
        sense_ok=True,
        suitable=True,
        turkish_ok=False,
        turkish_fix="Haklısın, evet.",
        accepted=True,
    )
    path = root / "curation" / "en" / "sentences.validation.jsonl"
    path.write_text(decision.model_dump_json() + "\n", encoding="utf-8")

    report = run_pair(root, l1="tr", l2="en", analyzer=OwnAnalyzer)

    assert report.prompts == {"tatoeba": 2, "curated": 1, "validation_fix": 1}
    glosses = {g["key"]: g for g in lines(root / "packs" / "tr-en" / "glosses.jsonl")}
    assert glosses["en.sent.you_are_right"]["meaning"] == "Haklısın, evet."
    assert glosses["en.sent.you_are_right"]["provenance"]["source"] == "dilbaz validation"


def test_variants_are_deduplicated_and_keep_the_target(tmp_path: Path) -> None:
    sentences = """
en.sent.we_watch_tv:
  {variants: ["we  watch TV!", "We watch television.", "We see TV.", "We all watch TV."]}
en.sent.my_right_hand_is_cold: {turkish: "Sağ elim soğuk."}
"""
    root = build(tmp_path, **{"sentences.yaml": sentences})

    report = run_pair(root, l1="tr", l2="en", analyzer=OwnAnalyzer)

    # "We all watch TV." keeps the word although the tagger reads it as a noun.
    assert {(i.kind, i.detail) for i in report.issues} == {
        ("duplicate_variant", "thank you!"),
        ("duplicate_variant", "we  watch TV!"),
        ("variant_missing_target", "We see TV. (lacks en.ws.watch.v.1)"),
    }
    assert [i.kind for i in report.blocking] == ["variant_missing_target"]


def test_a_variant_may_say_the_target_in_another_form(tmp_path: Path) -> None:
    sentences = """
en.sent.we_watch_tv: {variants: ["We love watching TV."]}
en.sent.my_right_hand_is_cold: {turkish: "Sağ elim soğuk."}
"""
    root = build(tmp_path, **{"sentences.yaml": sentences})
    lexicon = root / "work" / "lexicon.en.jsonl"

    # The tagger calls "watching" a noun of its own: without the forms it is lost.
    report = run_pair(root, l1="tr", l2="en", analyzer=OwnAnalyzer)
    assert [i.kind for i in report.blocking] == ["variant_missing_target"]

    entries = [
        e.model_copy(update={"forms": ("watches", "watching")}) if e.lemma == "watch" else e
        for e in read_lexicon(lexicon)
    ]
    lexicon.write_text("".join(e.model_dump_json() + "\n" for e in entries), encoding="utf-8")
    assert run_pair(root, l1="tr", l2="en", analyzer=OwnAnalyzer).blocking == ()


def test_alternatives_are_right_answers_without_the_target(tmp_path: Path) -> None:
    sentences = """
en.sent.we_watch_tv:
  variants: ["We watch television."]
  alternatives: ["We see TV.", "We all watch TV.", "we watch television!"]
en.sent.my_right_hand_is_cold: {turkish: "Sağ elim soğuk."}
"""
    root = build(tmp_path, **{"sentences.yaml": sentences})

    report = run_pair(root, l1="tr", l2="en", analyzer=OwnAnalyzer)

    # "We all watch TV." says "watch": a variant, never an alternative.
    assert {(i.kind, i.detail) for i in report.issues} == {
        ("duplicate_variant", "thank you!"),
        ("duplicate_variant", "we watch television!"),
        ("alternative_has_target", "We all watch TV. (has en.ws.watch.v.1)"),
    }
    assert report.alternatives == 2
    variants = {v["key"]: v for v in lines(root / "packs" / "tr-en" / "variants.jsonl")}
    assert variants["en.sent.we_watch_tv"]["variants"] == ["We watch television."]
    assert variants["en.sent.we_watch_tv"]["alternatives"] == ["We see TV.", "We all watch TV."]


def test_cards_with_the_same_prompt_accept_each_others_answer(tmp_path: Path) -> None:
    same = """
en.sent.we_watch_tv: {turkish: "teşekkür ederim!"}
en.sent.my_right_hand_is_cold: {turkish: "Sağ elim soğuk."}
"""
    # The chunk accepts "We watch TV.", the sentence card not "Thank you.".
    chunks = CHUNKS.replace('"Thanks.",', '"Thanks.", "We watch TV.",')
    root = build(tmp_path / "same", **{"sentences.yaml": same, "chunks.yaml": chunks})

    report = run_pair(root, l1="tr", l2="en", analyzer=OwnAnalyzer)

    (issue,) = report.blocking
    assert (issue.key, issue.kind) == ("en.sent.we_watch_tv", "prompt_clash")
    assert issue.detail == "same prompt as en.chunk.thank_you; each must accept the other's answer"
    # A context tells the two prompts apart.
    context = same.replace('ederim!"}', 'ederim!", context: "TV"}')
    root = build(tmp_path / "context", **{"sentences.yaml": context})
    assert run_pair(root, l1="tr", l2="en", analyzer=OwnAnalyzer).blocking == ()


def test_a_rule_note_must_not_hold_an_answer(tmp_path: Path) -> None:
    grammar = GRAMMAR.replace(
        'rule: "he/she/it ile -s."', 'rule: "Örnek: We watch TV. he/she/it ile -s."'
    )
    root = build(tmp_path, **{"grammar.yaml": grammar})

    report = run_pair(root, l1="tr", l2="en", analyzer=OwnAnalyzer)

    (issue,) = report.blocking
    assert (issue.key, issue.kind) == ("gp.present_simple.affirmative", "rule_note_leak")


def test_a_rule_example_must_not_give_a_cards_form(tmp_path: Path) -> None:
    grammar = GRAMMAR.replace(
        'rule: "he/she/it ile -s."', 'rule: "he/she/it ile -s; öbürleri yalın: see → watch."'
    )
    root = build(tmp_path, **{"grammar.yaml": grammar})

    report = run_pair(root, l1="tr", l2="en", analyzer=OwnAnalyzer)

    assert {(i.key, i.kind, i.detail) for i in report.blocking} == {
        (
            "gp.present_simple.affirmative",
            "rule_note_leak",
            f"the example form 'watch' is in the answer {text!r}",
        )
        for text in ("We watch TV.", "I watch TV every evening.")
    }


def test_chunk_alternatives_are_the_function_in_other_words(tmp_path: Path) -> None:
    chunks = """
en.chunk.thank_you:
  {meaning: "Teşekkür ederim.", variants: ["Thanks."], alternatives: ["Cheers.", "thanks!"]}
"""
    root = build(tmp_path, **{"chunks.yaml": chunks})

    report = run_pair(root, l1="tr", l2="en", analyzer=OwnAnalyzer)

    assert [(i.kind, i.detail) for i in report.issues] == [("duplicate_variant", "thanks!")]
    assert report.alternatives == 1
    variants = {v["key"]: v for v in lines(root / "packs" / "tr-en" / "variants.jsonl")}
    assert variants["en.chunk.thank_you"]["variants"] == ["Thanks."]
    assert variants["en.chunk.thank_you"]["alternatives"] == ["Cheers."]


def test_missing_and_unknown_entries_block_the_build(tmp_path: Path) -> None:
    root = build(
        tmp_path,
        **{
            "word_senses.yaml": SENSES.replace("en.ws.evening.n.1: {meaning: akşam}\n", "")
            + "en.ws.zebra.n.1: {meaning: zebra}\n",
            "sentences.yaml": "en.sent.we_watch_tv: {variants: []}\n",
            "contrasts.yaml": "- {items: [en.ws.right.adj.1, en.ws.left.adj.1], note: x}\n",
            "error_tags.yaml": ERROR_TAGS.replace("[gp.articles.a_an]", "[gp.nope]"),
        },
    )

    report = run_pair(root, l1="tr", l2="en", analyzer=OwnAnalyzer)

    assert {(i.key, i.kind) for i in report.blocking} == {
        ("en.ws.evening.n.1", "missing_gloss"),
        ("en.ws.zebra.n.1", "unknown_key"),
        ("en.sent.my_right_hand_is_cold", "missing_prompt"),
        ("en.ws.left.adj.1", "unknown_key"),
        ("art.missing", "unknown_grammar_code"),
    }


def test_missing_files_mean_no_entries(tmp_path: Path) -> None:
    curation = load_pair_curation(tmp_path)
    assert (curation.senses, curation.contrasts) == ({}, ())
    assert read_translations(tmp_path / "missing.jsonl") == {}


def test_the_pair_command_reports_and_fails_on_blocking_issues(tmp_path: Path) -> None:
    runner = CliRunner()
    # Without sentence variants nothing needs spaCy.
    good = build(
        tmp_path / "good",
        **{"sentences.yaml": SENTENCES.replace('{variants: ["We watch television."]}', "{}")},
    )
    result = runner.invoke(app, ["pair", "--content-dir", str(good)])
    assert result.exit_code == 0, result.output
    assert "'curated': 1" in " ".join(result.output.split())
    bad = build(tmp_path / "bad", **{"word_senses.yaml": "{}"})
    result = runner.invoke(app, ["pair", "--content-dir", str(bad)])
    assert result.exit_code == 1
    assert "missing_gloss" in result.output


def test_each_listed_answer_of_a_sentence_carries_its_grammar(tmp_path: Path) -> None:
    root = build(tmp_path)

    run_pair(root, l1="tr", l2="en", analyzer=OwnAnalyzer)

    rows = {
        row["key"]: row
        for row in map(json.loads, (root / "packs" / "tr-en" / "variants.jsonl").open())
    }
    text = "We watch television."
    assert rows["en.sent.we_watch_tv"]["grammar"] == {text: list(grammar_codes(OWN_TOKENS[text]))}
    assert "grammar" not in rows["en.chunk.thank_you"], "set phrases need none"

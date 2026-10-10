/**
 * `speaking_annotate` prompt (docs/07-ai-tutor.md §4.2, §5).
 *
 * The system prompt is fixed: role, rules, the pair's catalogs and the
 * examples, so that providers can cache it. Only the user message changes.
 * Changing this file means a new version and an eval run (docs/07 §8).
 */
import type { Catalog } from "../catalogs/catalog.ts";
import type {
  SpeakingAnnotateInput,
  SpeakingAnnotateWire,
} from "../schemas/speaking_annotate.ts";

export const speakingAnnotatePromptVersion = "speaking_annotate@1";

/**
 * Error categories a transcript can show: pronunciation is not judged from
 * text, and perception belongs to dictation.
 */
export const speakingCategories = ["grammar", "vocabulary", "pragmatics"];

const rules =
  `You are the speaking annotator of Dilbaz, an app in which Turkish speakers learn English by speaking. A learner did a speaking task. Speech recognition wrote down what they said word by word, exactly as said: their own forms, errors and hesitations stay; nothing is corrected. You mark the transcript. The app computes every number from your marks and shows the learner feedback. You do not grade or score, and you do not decide what the learner practises.

# The input
- ctx.level: the learner's CEFR level, A0 the lowest. ctx.explain_in "l1": write strengths and hints in Turkish; "l2": in simple English.
- task.prompt_l1: the task as the learner read it, in Turkish. task.goal: what doing the task means.
- words: the transcript as "[i]word" items, i being the word's index. There is no punctuation. Hesitation sounds (uh, um) and Turkish words appear as recognized, sometimes in English-looking spellings.

# What to mark
Word indices refer to the words given. A span runs from start_i to end_i, both included.
- clauses: split the whole transcript into clauses: a subject with a finite verb, or a verbless piece the speaker meant as a unit ("and my brother"). Clauses follow the word order and do not overlap; every word belongs to one clause. A hesitation or a repair belongs to the clause it interrupts; one between clauses belongs to the next clause. as_unit numbers the AS-units from 0: an independent clause or a verbless unit, with its subordinate clauses ("because...", "when...", "that..."); a coordinated clause with its own subject ("and I drink coffee") starts a new AS-unit. error_free: false when the clause has an error you marked.
- errors: every error of grammar, vocabulary or pragmatics you are sure of: the span of the wrong words, one tag of the tag catalog, correction = the words that should replace the span, and severity: 1 the meaning stays clear, 2 noticeable, 3 the meaning breaks or changes. For a missing word, the span is the word before the gap and the correction includes the missing word ("home" → "home is"). Mark what is wrong in standard English, not what is only unusual; natural variants are correct. Do not mark pronunciation, recognition doubts, hesitations or repairs. When you are not sure something is an error, do not mark it.
- fillers: hesitation words: kind "l2" for English ones (uh, um, er, hmm), "l1" for Turkish ones ("şey", "yani", "ıı", or as recognized: "shay", "yanni").
- repairs: words the learner abandoned or repeated before saying them again: "he go he goes" marks "he go"; "is is" marks the first "is".
- structures_used: clear uses of the grammar points of the grammar catalog, with correct false when that use is wrong.
- task_outcome: "done" when the speech covers the main points of the goal in language one can follow; "partial" when it covers only some of them; "not_done" when it is off the task, a few isolated words or nothing.
- strengths: one or two concrete things that went well, each naming what the learner said ("'because'u iki kez doğru kullandın."). Empty only when nothing went well.
- corrections: up to 5 marked errors worth practising, the most useful first. original: the learner's sentence as said (its whole AS-unit), without fillers and repairs. corrected: the same with every error fixed and nothing else changed. meaning_l1: what the corrected sentence means, in the learner's own language (ctx.l1), as a natural sentence; it becomes the prompt of a card. tag and severity: those of its main error. ladder: h1 names only the kind of error, h2 only where it is (quoting the learner's own words), h3 the rule. None of h1-h3 may contain a word of the correction that the learner did not say: the learner finds the fix.
- Texts for the learner (strengths, ladder) are in the language of ctx.explain_in; at levels A0-A2 each is at most 20 everyday words.

# Rules
- Use only tags of the tag catalog and codes of the grammar catalog; never invent one.
- Mark every error you are sure of, even many: the app chooses what to practise.
- Never change the transcript; indices must point to the words given.`;

type Example = {
  level: SpeakingAnnotateInput["ctx"]["level"];
  task: { prompt_l1: string; goal: string };
  /** The transcript, words separated by spaces. */
  said: string;
  output: SpeakingAnnotateWire;
};

const examples: Example[] = [
  {
    level: "A1",
    task: {
      prompt_l1:
        "Sıradan bir gününü anlat: sabah, gün içinde ve akşam neler yaparsın?",
      goal:
        "Describe a typical day: what you do in the morning, during the day and in the evening.",
    },
    said:
      "i get up at seven uh and i drink coffee then i go to work by bus i am work in a office and i come home at six",
    output: {
      clauses: [
        { start_i: 0, end_i: 4, as_unit: 0, error_free: true },
        { start_i: 5, end_i: 9, as_unit: 1, error_free: true },
        { start_i: 10, end_i: 16, as_unit: 2, error_free: true },
        { start_i: 17, end_i: 22, as_unit: 3, error_free: false },
        { start_i: 23, end_i: 28, as_unit: 4, error_free: true },
      ],
      errors: [
        {
          start_i: 18,
          end_i: 19,
          tag: "be.extra",
          correction: "work",
          severity: 1,
        },
        {
          start_i: 21,
          end_i: 21,
          tag: "art.wrong",
          correction: "an",
          severity: 1,
        },
      ],
      fillers: [{ i: 5, kind: "l2" }],
      repairs: [],
      structures_used: [
        { code: "gp.prepositions.time", start_i: 3, end_i: 4, correct: true },
        {
          code: "gp.present_simple.affirmative",
          start_i: 7,
          end_i: 9,
          correct: true,
        },
        {
          code: "gp.present_simple.affirmative",
          start_i: 17,
          end_i: 19,
          correct: false,
        },
        { code: "gp.articles.a_an", start_i: 21, end_i: 22, correct: false },
      ],
      task_outcome: "done",
      strengths: [
        "Saatleri 'at seven' ve 'at six' diye doğru söyledin.",
        "'then' ve 'and' ile anlattıklarını sıraladın.",
      ],
      corrections: [
        {
          original: "i am work in a office",
          corrected: "I work in an office.",
          meaning_l1: "Bir ofiste çalışıyorum.",
          tag: "be.extra",
          severity: 1,
          ladder: {
            h1: "Bir kelime fazla, bir kelimenin de biçimi yanlış.",
            h2: "'am work' ve 'a office' kısımlarına bak.",
            h3:
              "Asıl fiil varken be fiili gelmez. Ünlüyle başlayan kelimeden önce a biçim değiştirir.",
          },
        },
      ],
    },
  },
  {
    level: "A1",
    task: {
      prompt_l1:
        "Evini anlat: kaç oda var, odalarda neler var, en sevdiğin yer neresi?",
      goal:
        "Describe your home: the rooms, what is in them and your favorite place.",
    },
    said: "my home uh shay my home big i don't know",
    output: {
      clauses: [
        { start_i: 0, end_i: 6, as_unit: 0, error_free: false },
        { start_i: 7, end_i: 9, as_unit: 1, error_free: true },
      ],
      errors: [
        {
          start_i: 5,
          end_i: 5,
          tag: "be.missing",
          correction: "home is",
          severity: 2,
        },
      ],
      fillers: [{ i: 2, kind: "l2" }, { i: 3, kind: "l1" }],
      repairs: [{ start_i: 0, end_i: 1 }],
      structures_used: [],
      task_outcome: "not_done",
      strengths: ["'I don't know' kalıbını doğru kullandın."],
      corrections: [
        {
          original: "my home big",
          corrected: "My home is big.",
          meaning_l1: "Evim büyük.",
          tag: "be.missing",
          severity: 2,
          ladder: {
            h1: "Cümlede bir kelime eksik.",
            h2: "'home' ile 'big' arasına bak.",
            h3: "Bir şeyin nasıl olduğunu anlatırken be fiili gerekir.",
          },
        },
      ],
    },
  },
  {
    level: "A2",
    task: {
      prompt_l1: "Dün neler yaptın? Sabahtan akşama kadar anlat.",
      goal: "Say what you did yesterday, from morning to evening.",
    },
    said:
      "yesterday i wake up at eight and i went to my office then i have a meeting with my boss it was very boring after work i meet my friend and we eat pizza",
    output: {
      clauses: [
        { start_i: 0, end_i: 5, as_unit: 0, error_free: false },
        { start_i: 6, end_i: 11, as_unit: 1, error_free: true },
        { start_i: 12, end_i: 19, as_unit: 2, error_free: false },
        { start_i: 20, end_i: 23, as_unit: 3, error_free: true },
        { start_i: 24, end_i: 29, as_unit: 4, error_free: false },
        { start_i: 30, end_i: 33, as_unit: 5, error_free: false },
      ],
      errors: [
        {
          start_i: 2,
          end_i: 2,
          tag: "tense.past_missing",
          correction: "woke",
          severity: 1,
        },
        {
          start_i: 14,
          end_i: 14,
          tag: "tense.past_missing",
          correction: "had",
          severity: 1,
        },
        {
          start_i: 27,
          end_i: 27,
          tag: "tense.past_missing",
          correction: "met",
          severity: 1,
        },
        {
          start_i: 32,
          end_i: 32,
          tag: "tense.past_missing",
          correction: "ate",
          severity: 1,
        },
      ],
      fillers: [],
      repairs: [],
      structures_used: [
        {
          code: "gp.past_simple.irregular",
          start_i: 2,
          end_i: 2,
          correct: false,
        },
        {
          code: "gp.past_simple.irregular",
          start_i: 8,
          end_i: 8,
          correct: true,
        },
        {
          code: "gp.past_simple.irregular",
          start_i: 14,
          end_i: 14,
          correct: false,
        },
        { code: "gp.past_simple.be", start_i: 20, end_i: 21, correct: true },
        {
          code: "gp.past_simple.irregular",
          start_i: 27,
          end_i: 27,
          correct: false,
        },
        {
          code: "gp.past_simple.irregular",
          start_i: 32,
          end_i: 32,
          correct: false,
        },
      ],
      task_outcome: "done",
      strengths: [
        "'went' ve 'it was' ile geçmiş zamanı doğru kurdun.",
        "'then' ve 'after work' ile olayları sıraladın.",
      ],
      corrections: [
        {
          original: "yesterday i wake up at eight",
          corrected: "Yesterday I woke up at eight.",
          meaning_l1: "Dün sekizde uyandım.",
          tag: "tense.past_missing",
          severity: 1,
          ladder: {
            h1: "Fiilin zamanı yanlış.",
            h2: "'wake' kelimesine bak.",
            h3: "Dün olanı anlatırken fiilin geçmiş biçimi kullanılır.",
          },
        },
        {
          original: "then i have a meeting with my boss",
          corrected: "Then I had a meeting with my boss.",
          meaning_l1: "Sonra patronumla bir toplantım vardı.",
          tag: "tense.past_missing",
          severity: 1,
          ladder: {
            h1: "Fiilin zamanı yanlış.",
            h2: "'have' kelimesine bak.",
            h3: "Geçmişte olan bir şeyi geçmiş zamanla anlat.",
          },
        },
        {
          original: "after work i meet my friend",
          corrected: "After work, I met my friend.",
          meaning_l1: "İşten sonra arkadaşımla buluştum.",
          tag: "tense.past_missing",
          severity: 1,
          ladder: {
            h1: "Fiilin zamanı yanlış.",
            h2: "'meet' kelimesine bak.",
            h3: "Dün olanı anlatırken fiilin geçmiş biçimi kullanılır.",
          },
        },
      ],
    },
  },
  {
    level: "A2",
    task: {
      prompt_l1:
        "Bir mağazadasın. Geçen hafta aldığın bir ürün çalışmıyor. Sorunu anlat ve ne istediğini söyle: yenisini mi, paranı mı?",
      goal:
        "You are in a store. Explain that something you bought does not work, and say what you want: a new one or your money back.",
    },
    said: "hello this phone not working i buy it last week give me new phone",
    output: {
      clauses: [
        { start_i: 0, end_i: 0, as_unit: 0, error_free: true },
        { start_i: 1, end_i: 4, as_unit: 1, error_free: false },
        { start_i: 5, end_i: 9, as_unit: 2, error_free: false },
        { start_i: 10, end_i: 13, as_unit: 3, error_free: false },
      ],
      errors: [
        {
          start_i: 2,
          end_i: 2,
          tag: "be.missing",
          correction: "phone is",
          severity: 1,
        },
        {
          start_i: 6,
          end_i: 6,
          tag: "tense.past_missing",
          correction: "bought",
          severity: 1,
        },
        {
          start_i: 10,
          end_i: 13,
          tag: "prag.too_direct",
          correction: "can I have a new phone, please",
          severity: 2,
        },
        {
          start_i: 12,
          end_i: 12,
          tag: "art.missing",
          correction: "a new",
          severity: 1,
        },
      ],
      fillers: [],
      repairs: [],
      structures_used: [
        {
          code: "gp.past_simple.irregular",
          start_i: 6,
          end_i: 6,
          correct: false,
        },
      ],
      task_outcome: "done",
      strengths: ["Sorunu ve ürünü ne zaman aldığını açıkça söyledin."],
      corrections: [
        {
          original: "give me new phone",
          corrected: "Can I have a new phone, please?",
          meaning_l1: "Yeni bir telefon alabilir miyim, lütfen?",
          tag: "prag.too_direct",
          severity: 2,
          ladder: {
            h1: "İstek fazla doğrudan, bir kelime de eksik.",
            h2: "'give me new phone' kısmına bak.",
            h3:
              "Mağazada bir şey isterken soru biçiminde ve kibarca sor. Tekil isimden önce a gelir.",
          },
        },
        {
          original: "this phone not working",
          corrected: "This phone is not working.",
          meaning_l1: "Bu telefon çalışmıyor.",
          tag: "be.missing",
          severity: 1,
          ladder: {
            h1: "Bir kelime eksik.",
            h2: "'phone' ile 'not' arasına bak.",
            h3: "-ing ile anlatırken be fiili gerekir.",
          },
        },
        {
          original: "i buy it last week",
          corrected: "I bought it last week.",
          meaning_l1: "Onu geçen hafta aldım.",
          tag: "tense.past_missing",
          severity: 1,
          ladder: {
            h1: "Fiilin zamanı yanlış.",
            h2: "'buy' kelimesine bak.",
            h3: "Geçen hafta olan bir şey için geçmiş zaman kullanılır.",
          },
        },
      ],
    },
  },
  {
    level: "A1",
    task: {
      prompt_l1:
        "Bir kafedesin. Garsona ne yiyip içmek istediğini söyle, fiyatını sor ve hesabı iste.",
      goal:
        "You are in a café. Order something to eat and drink, ask the price and ask for the check.",
    },
    said: "coffee please and uh cake how much",
    output: {
      clauses: [
        { start_i: 0, end_i: 4, as_unit: 0, error_free: true },
        { start_i: 5, end_i: 6, as_unit: 1, error_free: true },
      ],
      errors: [],
      fillers: [{ i: 3, kind: "l2" }],
      repairs: [],
      structures_used: [],
      task_outcome: "partial",
      strengths: ["'please' ile kibarca istedin."],
      corrections: [],
    },
  },
  {
    level: "A2",
    task: {
      prompt_l1:
        "Bildiğin iki şehri karşılaştır: hangisi daha büyük, daha ucuz ya da daha güzel? Hangisini tercih edersin, neden?",
      goal:
        "Compare two cities you know: which is bigger, cheaper or nicer, and which one you prefer and why.",
    },
    said:
      "istanbul is more big than izmir yani izmir is is smaller but i prefer izmir because the life is more relaxed",
    output: {
      clauses: [
        { start_i: 0, end_i: 5, as_unit: 0, error_free: false },
        { start_i: 6, end_i: 10, as_unit: 1, error_free: true },
        { start_i: 11, end_i: 14, as_unit: 2, error_free: true },
        { start_i: 15, end_i: 20, as_unit: 2, error_free: false },
      ],
      errors: [
        {
          start_i: 2,
          end_i: 3,
          tag: "comp.form",
          correction: "bigger",
          severity: 1,
        },
        {
          start_i: 16,
          end_i: 17,
          tag: "art.extra",
          correction: "life",
          severity: 1,
        },
      ],
      fillers: [{ i: 6, kind: "l1" }],
      repairs: [{ start_i: 8, end_i: 8 }],
      structures_used: [
        { code: "gp.comparatives", start_i: 2, end_i: 4, correct: false },
        { code: "gp.comparatives", start_i: 10, end_i: 10, correct: true },
        {
          code: "gp.conjunctions.basic",
          start_i: 11,
          end_i: 11,
          correct: true,
        },
        {
          code: "gp.conjunctions.basic",
          start_i: 15,
          end_i: 15,
          correct: true,
        },
      ],
      task_outcome: "done",
      strengths: [
        "'smaller' ile karşılaştırmayı doğru yaptın.",
        "'because' ile tercihinin nedenini söyledin.",
      ],
      corrections: [
        {
          original: "istanbul is more big than izmir",
          corrected: "Istanbul is bigger than Izmir.",
          meaning_l1: "İstanbul İzmir'den daha büyük.",
          tag: "comp.form",
          severity: 1,
          ladder: {
            h1: "Karşılaştırma biçimi yanlış.",
            h2: "'more big' kısmına bak.",
            h3: "Kısa sıfatlarda more kullanılmaz; sıfata ek gelir.",
          },
        },
        {
          original: "i prefer izmir because the life is more relaxed",
          corrected: "I prefer Izmir because life is more relaxed.",
          meaning_l1: "İzmir'i tercih ederim çünkü hayat daha sakin.",
          tag: "art.extra",
          severity: 1,
          ladder: {
            h1: "Fazladan bir kelime var.",
            h2: "'the life' kısmına bak.",
            h3: "Genel anlamda kullanılan isimden önce the gelmez.",
          },
        },
      ],
    },
  },
];

/** The transcript as the model reads it: "[0]i [1]get …". */
export function transcriptOf(words: readonly { w: string }[]): string {
  return words.map((word, i) => `[${i}]${word.w}`).join(" ");
}

/** The call's input as the model sees it: fixed key order, no times. */
export function speakingAnnotateUserMessage(
  input: Pick<SpeakingAnnotateInput, "ctx" | "task" | "words">,
): string {
  const { ctx, task } = input;
  return JSON.stringify({
    ctx: {
      l1: ctx.l1,
      l2: ctx.l2,
      level: ctx.level,
      explain_in: ctx.explain_in,
    },
    task: { prompt_l1: task.prompt_l1, goal: task.goal },
    words: transcriptOf(input.words),
  });
}

/** The examples' transcripts as words, for the prompt and its tests. */
export const exampleWords = examples.map((example) =>
  example.said.split(" ").map((w, i) => ({
    i,
    w,
    start_ms: i * 400,
    end_ms: i * 400 + 300,
  }))
);

function exampleText(example: Example, index: number): string {
  const input = speakingAnnotateUserMessage({
    ctx: { l1: "tr", l2: "en", level: example.level, explain_in: "l1" },
    task: { ...example.task, can_do_codes: [] },
    words: exampleWords[index],
  });
  return `Input: ${input}\nOutput: ${JSON.stringify(example.output)}`;
}

/** The examples, for their tests. */
export const speakingExamples = examples;

/** The fixed system prompt of a pair's [catalog]. */
export function speakingAnnotateSystemPrompt(catalog: Catalog): string {
  const tags = catalog.errorTags
    .filter((tag) => speakingCategories.includes(tag.category))
    .map((tag) => `${tag.code}: ${tag.description} (${tag.example})`);
  const codes = Object.entries(catalog.ruleNotes)
    .map(([code, note]) => `${code}: ${note}`);
  return [
    rules,
    `# Tag catalog (${catalog.pack})\n${tags.join("\n")}`,
    `# Grammar catalog\n${codes.join("\n")}`,
    `# Examples\n${examples.map(exampleText).join("\n\n")}`,
    "Answer with one JSON object that matches the schema, nothing else.",
  ].join("\n\n");
}

/** Transcripts of the examples; eval cases must not reuse them. */
export const exampleTranscripts = examples.map((e) => e.said);

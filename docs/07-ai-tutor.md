# 07 — Yapay Zekâ Öğretmen (Claude)

Bu doküman Dilbaz'ın LLM kullanımını tanımlar: rotalar, model politikası, API kuralları, pedagojik korkuluklar, prompt sözleşmeleri, değerlendirme ve maliyet.

> **Kodlayan ajan için zorunlu:** Claude API ile ilgili herhangi bir kodu yazmadan ya da değiştirmeden önce **`claude-api` skill'ini yükle** ve oradaki güncel API biçimlerini kullan. Bu dokümandaki API ayrıntıları 2026-09 itibarıyladır. Skill ve resmi SDK dokümantasyonu bu dokümandan önce gelir.

## 1. İlkeler

1. **LLM bir araçtır, öğretmen değil.** Pedagojik kararları (ne zaman ipucu, ne zaman cevap, hangi öğe, hangi etkinlik) motor verir. LLM yalnızca tanımlı rotalarda, tanımlı sözleşmeyle çalışır.
2. **Önce deterministik kontrol:** Kesin eşleşme, hizalama, cevap anahtarı gibi kod ile yapılabilen her şey kodla yapılır. LLM, belirsiz olanı değerlendirir.
3. **Yapılandırılmış çıktı:** Her rota bir JSON şemasıyla konuşur. Serbest metin yalnızca şemadaki metin alanlarındadır.
4. **Kapalı listeler:** Hata etiketleri, gramer kodları ve bağlaçlar paketten gelen kapalı listelerdir. LLM liste dışı kod üretemez; üretirse çıktı reddedilir.
5. **Korkuluklar kodda da uygulanır:** Promptta "cevabı verme" demek yetmez. İstemci, H4'ü açma koşulları sağlanmadan göstermez. Sunucu, H1–H3'ün doğru cevabı içermediğini kontrol eder (I-02, I-11).
6. **Çekirdek döngü asla LLM'e bağımlı olmaz:** LLM erişilemezse ya da bütçe dolmuşsa kartlar deterministik kontrolle devam eder. Kullanıcıya "ayrıntılı geri bildirim daha sonra" denir.

## 2. Model politikası

- **Varsayılan model: `claude-opus-5`, tüm rotalar.** (2026-09 fiyatı: girdi $5, çıktı $25 / 1M token; önbellek okuma ~0,1×; Batch API %50 indirimli.)
- Model ve rota ayarları tek bir yapılandırma dosyasındadır: `supabase/functions/_shared/llm_config.ts` (Python araçlarında `tools/llm_config.py`). Kodda model adı sabit yazılmaz.
- Rota başına **effort** ayarı:

  | Rota | Effort | Gerekçe |
  |---|---|---|
  | `answer_check` | low | Hız, yüksek hacim |
  | `gap_suggest` | low | |
  | `roleplay_turn` | low | Gecikme önemli |
  | `comprehension_check` | low | |
  | `speaking_annotate` | medium (aylık testte high) | |
  | `roleplay_debrief` | medium | |
  | `writing_feedback` | medium | |
  | `mediation_check` | medium | |
  | Batch içerik üretimi | medium | Doğrulama geçişi high |

- **Model değiştirmek kullanıcının kararıdır.** Maliyet ya da gecikme sorun olursa önce şu adımlar denenir:
  1. Deterministik ön kontrollerin kapsamını artırmak
  2. Prompt önbelleği
  3. Effort düşürmek
  4. Batch kullanmak

  Daha ucuz bir modele (ör. `claude-sonnet-5`, `claude-haiku-4-5`) geçiş ancak kullanıcı onaylarsa ve eval sonuçları eşikleri koruyorsa yapılır.

## 3. API kullanım kuralları (Edge Functions, TypeScript/Deno)

- Resmî SDK kullanılır: `import Anthropic from "npm:@anthropic-ai/sdk"`. Ham `fetch` ya da OpenAI uyumlu ara katman kullanılmaz.
- **Yapılandırılmış çıktı:** `client.messages.parse({ ..., output_config: { format: zodOutputFormat(Schema) } })` → `parsed_output`. `parsed_output` null ise → tek bir yeniden deneme, sonra hata.
- **Durma nedenleri her zaman kontrol edilir:**
  - `refusal` → `stop_details` loglanır, kullanıcıya nötr bir hata gösterilir.
  - `max_tokens` → `max_tokens` artırılarak tek yeniden deneme.
- **Reddetme yedeklemesi:** Etkileşimli rotalarda sunucu tarafı fallback açıktır (`fallbacks: "default"` + beta `server-side-fallback-2026-07-01`). Batch API bu parametreyi kabul etmez. Yapılandırılmış çıktı ile beta yolunun birlikte kullanımı skill ile doğrulanır.
- **Yapılmayacaklar:**
  - Assistant prefill yok (modelde desteklenmiyor)
  - `temperature` ve diğer örnekleme parametreleri yok (400 döner)
  - `budget_tokens` yok. Düşünme derinliği yalnızca `output_config.effort` ile ayarlanır.
- **`max_tokens`:** Düşük tutulmaz; kesilmiş çıktı daha pahalıya gelir.

  | Rota | `max_tokens` |
  |---|---|
  | answer_check | 4000 |
  | gap_suggest | 3000 |
  | roleplay_turn | 3000 |
  | comprehension_check | 3000 |
  | speaking_annotate | 12000 |
  | roleplay_debrief | 12000 |
  | writing_feedback | 12000 |
  | mediation_check | 12000 |

  16K üstü gerekirse streaming kullanılır.
- **Prompt önbelleği:**
  - Her rotanın sistem promptu sabittir: rubrik, etiket kataloğu, örnekler. Model için minimum önbelleklenebilir önek 512 tokendır; bu uzunluk aşılır.
  - Sistem bloğunda `cache_control: {type: "ephemeral"}` kullanılır. Değişken içerik yalnızca `messages` içindedir.
  - Sistem promptunda tarih, UUID, sırasız JSON olmaz.
  - `usage.cache_read_input_tokens` loglanır ve izlenir.
  - Rol oyununda geçmiş yalnızca sona eklenerek büyür, böylece önbellek korunur.
- **Hata yönetimi:** SDK'nın tipli hata sınıfları kullanılır. 429/5xx için SDK yeniden denemesi yeterlidir. 400/404 yeniden denenmez.
- **Kullanım kaydı ve bütçe:**
  - Her çağrı `llm_usage` tablosuna yazılır: rota, model, token türleri, hesaplanan maliyet.
  - Günlük kullanıcı başı tavan: `llm_config.dailyBudgetUsd = 1.50`. Aşılırsa rota `budget_exceeded` döner, istemci deterministik moda geçer.
- **Gizlilik:** LLM'e yalnızca metin gider (transkript, istem, öğe bilgisi). Ses, isim, e-posta gitmez.

## 4. Rotalar ve sözleşmeler

Şemalar zod benzeri gösterimle verilmiştir. Kaynak kod: `supabase/functions/_shared/schemas/`. Tüm rotalar şu ortak bağlamı alır:

```ts
const Ctx = z.object({
  l1: z.string(), l2: z.string(),            // "tr", "en"
  level: z.enum(["A0","A1","A2","B1","B2","C1","C2"]),
  explain_in: z.enum(["l1","l2"]),           // iskele matrisinden (02 §3)
});
```

Etiket kataloğu (kod + kısa açıklama + örnek) sistem promptunda sabit olarak durur ve önbelleğe alınır.

### 4.1 `answer_check` — kart cevabı değerlendirme (A01, A02, A04, A08, A22)

Yalnızca deterministik ön kontrol eşleşmediğinde çağrılır (`03` §0.5). **Tek çağrıda tüm merdiveni** döndürür; istemci merdiveni adım adım açar.

```ts
Input = { ctx, item: { key, prompt_l1, reference_l2, variants: string[], target_span: string,
          grammar_codes: string[], context_note?: string },
          response: { text, source: "asr"|"typed", asr_confidence?: number },
          attempt_no: 1|2|3, previous_responses: string[] }

Output = {
  verdict: "correct"|"acceptable_variant"|"minor_error"|"wrong"|"off_target"|"unintelligible"|"uncertain",
  target_ok: boolean,                      // hata hedef öğeye mi dokunuyor?
  error_tags: string[],                    // kapalı listeden
  error_spans: { start: number, end: number, tag: string }[],   // response.text içinde karakter aralığı
  ladder: { h1: string, h2: string, h3: string, h4: string },   // h4 = düzeltilmiş tam cümle
  variant_to_learn: string | null,         // acceptable_variant ise kişisel varyant olarak eklenir
  confidence: number                       // 0..1
}
```

**Kurallar (sistem promptu + sunucu doğrulaması):**
- `correct` ya da `acceptable_variant` ise merdiven boş dizelerdir.
- h1: yalnızca hata türü. h2: yalnızca yer. h3: kural. **h1–h3, düzeltilmiş hedef parçayı içeremez.** Sunucu normalize edilmiş dize kontrolü yapar; ihlalde merdiven yeniden istenir ya da h1–h3 genel şablonlarla değiştirilir.
- A seviyelerinde açıklamalar Türkçe ve en fazla 20 kelimedir.
- Anlamı koruyan doğal ifadeler reddedilmez (I-17). Emin değilse `uncertain` döner.

### 4.2 `speaking_annotate` — konuşma transkripti işaretleme (A11, A13 debrief girişi, A15, A21, A23)

```ts
Input = { ctx, task: { prompt_l1, goal, can_do_codes: string[] },
          words: { i: number, w: string, start_ms: number, end_ms: number }[],   // ASR çıktısı
          catalog_version: string }

Output = {
  clauses: { start_i: number, end_i: number, as_unit: number, error_free: boolean }[],
  errors: { start_i: number, end_i: number, tag: string, correction: string, severity: 1|2|3 }[],
  fillers: { i: number, kind: "l2"|"l1" }[],
  repairs: { start_i: number, end_i: number }[],
  structures_used: { code: string, start_i: number, end_i: number, correct: boolean }[],
  task_outcome: "done"|"partial"|"not_done",
  strengths: string[],                     // en fazla 2, somut, açıklama dilinde
  top_corrections: { original: string, corrected: string, tag: string,
                     ladder: { h1: string, h2: string, h3: string } }[]   // en fazla 3
}
```

- Akıcılık ölçümleri **LLM'den değil**, kelime zamanlarından deterministik hesaplanır (`06` §3.3).
- Öğe kullanımı (aktarım) deterministik lemma eşleşmesiyle bulunur. LLM yalnızca hata aralıklarını verir.
- `top_corrections` seçim önceliği: kalıcı hata etiketi > anlamı bozan (severity 3) > sıklık.

### 4.3 `gap_suggest` — Söyleyemediklerim (A19)

```ts
Input  = { ctx, l1_text: string, context: "live_class"|"daily"|"pair"|"speaking_task"|"media", note?: string }
Output = { l2_natural: string, l2_simple: string,
           key_chunk: { text: string, gloss_l1: string },
           register: "neutral"|"informal"|"formal",
           notes_l1: string | null }
```

- Çıktıdaki kelimeler sunucuda paketin seviye listesiyle kontrol edilir.
- A seviyelerinde `l2_simple` içinde seviye+1'in üstünde birden fazla kelime varsa tek bir "sadeleştir" yeniden çağrısı yapılır.

### 4.4 `roleplay_turn` ve `roleplay_debrief` (A13)

```ts
TurnInput  = { ctx, scenario: { ai_role, learner_role, learner_goal, setting },
               history: { speaker: "ai"|"learner", text: string }[], learner_utterance: string }
TurnOutput = { reply_l2: string,
               hidden_notes: { turn: number, tag: string, correction: string }[],
               goal_progress: "not_started"|"in_progress"|"achieved",
               end: boolean }

DebriefOutput = { task_outcome, strengths: string[], top_corrections: [...en fazla 3],
                  useful_chunks: { text: string, gloss_l1: string }[] }   // yapay zekânın kullandığı faydalı kalıplar
```

- Yapay zekâ öğrencinin seviyesinde konuşur. Cevaplar kısadır (1–2 cümle), ara sıra doğal netleştirme soruları sorar.
- Konuşma sırasında **düzeltme yapmaz**. Hatalar `hidden_notes`'a gider.

### 4.5 `writing_feedback` (A20)

```ts
Output = { strengths: string[],
           errors: { start: number, end: number, tag: string, ladder: { h1, h2, h3, h4 } }[],
           coherence_comment: string | null,          // B2+
           rewrite_focus: string[] }                  // en fazla 3 odak
```

### 4.6 `mediation_check` (A21) ve `comprehension_check` (A16, A17)

```ts
MediationOutput     = { covered_points: string[], missed_points: string[],
                        language: { error_tags: string[], top_corrections: [...en fazla 2] } }
ComprehensionOutput = { result: "correct"|"partial"|"wrong", feedback: string }
```

### 4.7 Batch rotaları (Python araçları, çevrimdışı)

İçerik hattı (`10-content-pipeline.md`) Message Batches API kullanır (%50 indirimli, asenkron). Sonuçlar `custom_id` ile eşlenir, sıraya güvenilmez. Rotalar:

- `content.sentences` — hedef lemma için taşıyıcı cümleler
- `content.gloss_tr` — Türkçe karşılık ve açıklama
- `content.validate` — doğallık, seviye ve anlam kontrolü; ayrı bir geçiş
- `content.grammar_note`
- `content.tasks`, `content.texts`, `content.dialogues`
- `content.pseudowords`
- `content.contrast_sets`

## 5. Sistem promptu yapısı (her rota)

```text
[1] Rol ve amaç: "Sen Dilbaz'ın {rota} bileşenisin. Pedagojik kararları sen vermezsin; …"
[2] Dilbaz'ın değişmez kuralları (bu rotayla ilgili olanlar, I-xx kodlarıyla)
[3] Rubrik ve karar tanımları (verdict tablosu, severity ölçeği)
[4] Kapalı katalog(lar): hata etiketleri / gramer kodları / bağlaçlar (paket sürümüyle)
[5] Seviyeye göre dil kuralları (açıklama dili, uzunluk, kelime düzeyi)
[6] 6–12 örnek (girdi → çıktı), Türkçe konuşanlara özgü tipik hatalar dahil
[7] Çıktı talimatı: yalnızca şemaya uygun JSON
```

- Katalog sürümü değiştiğinde önbellek doğal olarak yenilenir.
- Promptlar `supabase/functions/_shared/prompts/*.md` dosyalarında versiyonlanır. Değişiklik → eval zorunlu (§8).

## 6. Pedagojik korkuluklar (özet)

| Korkuluk | Nerede uygulanır |
|---|---|
| Öğrenci denemeden cevap yok | İstemci (akış), sunucu (rota ancak cevapla çağrılabilir) |
| H1–H3 cevabı içermez | Prompt + sunucu dize kontrolü |
| H4 yalnızca son adımda ya da "göster" ile | İstemci |
| Akıcılık görevinde araya girme yok | Rota tasarımı (hidden_notes) |
| En fazla 3 düzeltme | Şema + sunucu kırpma |
| Kapalı etiket listesi | Şema enum'u + sunucu doğrulaması |
| Seviyeye uygun dil | Prompt + deterministik seviye listesi kontrolü |
| Anlamı koruyan varyantlar kabul | Rubrik + eval'de "yanlış negatif" eşiği |
| Emin değilse `uncertain` | Rubrik + istemci akışı |

## 7. Başarısızlık durumları

| Durum | Davranış |
|---|---|
| Ağ yok / zaman aşımı | Kart: deterministik sonuç. Eşleşmezse "şimdilik doğru sayıldı, sonra kontrol edilecek" kuyruğu (`attempts.pending_llm = true`). Görev: kayıt yerelde bekler, senkronda işlenir. |
| `refusal` (fallback sonrası da) | Nötr mesaj, deneme `uncertain` sayılır, olay loglanır |
| Şema ihlali / katalog dışı kod | 1 yeniden deneme, sonra `uncertain` |
| Bütçe aşıldı | Deterministik mod, kullanıcıya bilgi (suçlayıcı değil) |
| LLM ile deterministik sonuç çelişirse | Deterministik "doğru" ise her zaman doğru kabul edilir |

## 8. Değerlendirme (eval) seti

LLM rotalarının kalitesi ölçülmeden prompt ya da model değiştirilmez.

- **Konum:** `evals/tutor/<rota>/cases.jsonl`. Çalıştırıcı: `evals/run.ts` (Deno); sonuçlar `evals/results/<tarih>-<rota>.json`.
- **Vaka kaynakları:**
  1. Türkçe konuşanlara özgü sentetik hatalar
  2. Kabul edilmesi gereken zor varyantlar
  3. Anlaşılmaz ASR çıktıları
  4. Zamanla kullanıcıların izniyle anonimleştirilmiş gerçek denemeler
- **Başlangıç eşikleri:**

  | Rota | Ölçüt | Eşik |
  |---|---|---|
  | answer_check | Verdict doğruluğu (altın set, ≥ 200 vaka) | ≥ %90 |
  | answer_check | Doğru/varyant cevabı "yanlış" sayma | ≤ %3 |
  | answer_check | H1–H3'te cevap sızıntısı | %0 |
  | answer_check | Şema geçerliliği / katalog dışı etiket | %100 / %0 |
  | speaking_annotate | Hata tespiti F1 (30 altın transkript) | ≥ 0,75 |
  | speaking_annotate | EFC oranı mutlak farkı (medyan) | ≤ 0,10 |
  | speaking_annotate | Görev sonucu uyumu | ≥ %85 |
  | gap_suggest | Seviye üstü kelime (A seviyeleri, `l2_simple`) | ≤ 1 kelime/cümle |
  | roleplay_turn | Seviye+1 üstü kelime oranı | ≤ %5 |
  | roleplay_turn | Konuşma sırasında düzeltme | %0 |

- Uygulama sırasında `claude-api` skill'inin `build-eval` akışı kullanılır. Her eval çalıştırmasının maliyeti ölçülür ve raporlanır.

## 9. Maliyet tahmini (2 kullanıcı)

Varsayımlar (kişi başı günlük):
- 20 LLM'li kart kontrolü (deterministik ön kontrol sonrası)
- 2 konuşma işaretlemesi
- 5 Söyleyemediklerim önerisi
- Haftada 3 rol oyunu (10 tur)

| Rota | Kişi başı aylık (tahmini) |
|---|---|
| answer_check | ~$5–7 |
| speaking_annotate | ~$3–4 |
| gap_suggest | ~$1–2 |
| roleplay | ~$2–3 |
| Aylık test (çift işaretleme) | < $1 |
| **Toplam** | **~$12–17** → **iki kişi ~$25–35/ay** |

- İçerik üretimi (Batch, bir kerelik): seviye paketi başına ~$20–60. Tüm A0–C2 yolculuğu boyunca ~$150–300.
- Gerçek maliyet `llm_usage` tablosundan ölçülür, İlerleme > Ayarlar'da gösterilir.
- Maliyet beklentinin üstündeyse `claude-api` skill'inin `cost-optimize` akışı uygulanır. Model değişikliği kullanıcı onayıyla yapılır (§2).

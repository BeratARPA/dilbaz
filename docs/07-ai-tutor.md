# 07 — Yapay Zekâ Öğretmen (LLM)

Bu doküman Dilbaz'ın LLM kullanımını tanımlar: rotalar, sağlayıcı ve model politikası, API kuralları, pedagojik korkuluklar, prompt sözleşmeleri, değerlendirme ve kota planı.

> **Kodlayan ajan için zorunlu:** Sağlayıcılar ücretsiz katmanlardır (ADR-0009). LLM kodu yazmadan önce sağlayıcının güncel belgesini **context7** ile doğrula; hafızadan API yazma. Claude API yeniden açılırsa önce **`claude-api` skill'ini yükle** (ADR-0005). Bu dokümandaki ayrıntılar 2026-09 itibarıyladır; resmî belgeler bu dokümandan önce gelir.

## 1. İlkeler

1. **LLM bir araçtır, öğretmen değil.** Pedagojik kararları (ne zaman ipucu, ne zaman cevap, hangi öğe, hangi etkinlik) motor verir. LLM yalnızca tanımlı rotalarda, tanımlı sözleşmeyle çalışır.
2. **Önce deterministik kontrol:** Kesin eşleşme, hizalama, cevap anahtarı gibi kod ile yapılabilen her şey kodla yapılır. LLM, belirsiz olanı değerlendirir.
3. **Yapılandırılmış çıktı:** Her rota bir JSON şemasıyla konuşur. Serbest metin yalnızca şemadaki metin alanlarındadır.
4. **Kapalı listeler:** Hata etiketleri, gramer kodları ve bağlaçlar paketten gelen kapalı listelerdir. LLM liste dışı kod üretemez; üretirse çıktı reddedilir.
5. **Korkuluklar kodda da uygulanır:** Promptta "cevabı verme" demek yetmez. İstemci, H4'ü açma koşulları sağlanmadan göstermez. Sunucu, H1–H3'ün doğru cevabı içermediğini kontrol eder (I-02, I-11).
6. **Çekirdek döngü asla LLM'e bağımlı olmaz:** LLM erişilemezse, kota dolmuşsa ya da kullanıcı veri onayı vermemişse kartlar deterministik değerlendirmeyle devam eder (ADR-0009 §2). Kullanıcıya "ayrıntılı geri bildirim daha sonra" denir.

## 2. Sağlayıcı ve model politikası (ADR-0009)

- **Bütçe sıfır:** Yalnızca ücretsiz katmanlar kullanılır. Her rota için sıra: birincil sağlayıcı → yedek sağlayıcı → deterministik yol.

  | Rota | Birincil | Yedek | Son çare |
  |---|---|---|---|
  | `answer_check` | Gemini Flash-Lite | Groq `openai/gpt-oss-120b` | Deterministik değerlendirme |
  | `gap_suggest` | Gemini Flash | Gemini Flash-Lite → Groq | Yakalama + bekleyen öneri |
  | `speaking_annotate` (aylık test dahil) | Gemini Flash | Gemini Flash-Lite | Deterministik akıcılık ölçümleri; işaretleme sonradan |
  | Sonraki fazların rotaları | O fazda eval ile seçilir | | |

  - **Sıra eval'le kesinleşir.** Bu sıra bir tahmindir; her rota için birincil ve yedek sağlayıcıyı eval belirler (§8). "En iyi", eşikleri geçenler arasında en yüksek doğruluğu veren seçenektir; eşitlikte gecikmeye bakılır.
  - **Groq ve uzun rotalar:** Groq'un ücretsiz katmanındaki dakikada 8K token sınırı, uzun rotalara (`speaking_annotate`) izin vermez.
- **Ayarların yeri:** Sağlayıcılar, model adları, rota sıraları ve kotalar tek bir yapılandırma dosyasındadır: `supabase/functions/_shared/llm_config.ts`. Kodda model adı sabit yazılmaz. İçerik araçlarında çalışma anı LLM'i yoktur; içerik Claude Code oturumlarında üretilir (`10`).
- **Düşünme derinliği:** Rota başına anlamsal bir **effort** düzeyi tanımlanır. Adaptör bunu sağlayıcının ayarına çevirir (ör. Gemini'de düşünme düzeyi, `gpt-oss`'ta `reasoning_effort`).

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

- **Değişiklik kuralı:** Sağlayıcı, model ya da prompt değiştirmek kullanıcının kararıdır ve eval sonuçlarıyla desteklenir. Kota ya da gecikme sorun olursa önce şu adımlar denenir:
  1. Deterministik ön kontrollerin ve paket varyantlarının kapsamını artırmak
  2. Önbelleğe uygun sabit sistem promptu
  3. Effort düşürmek
  4. Rotayı aynı ailenin kotası daha geniş bir modeline taşımak

## 3. API kullanım kuralları (Edge Functions, TypeScript/Deno)

- **SDK:** Resmî SDK'lar kullanılır. OpenAI uyumlu uç nokta sunan sağlayıcılar (Groq ve Gemini'nin uyumluluk katmanı) tek bir adaptörü paylaşabilir. Seçim F1-15'te belgelerle (context7) doğrulanır. Sağlayıcılar `_shared/llm/` altında ortak bir arayüzün arkasındadır.
- **Yapılandırılmış çıktı:**
  - Şema zod ile tanımlanır ve sağlayıcıya JSON Schema olarak verilir (yapılandırılmış çıktı ya da JSON modu).
  - Dönen JSON sunucuda zod ile **her zaman** doğrulanır.
  - Geçersizse tek bir yeniden deneme yapılır, sonra sıradaki sağlayıcıya geçilir. Hepsi başarısız olursa sonuç `uncertain` sayılır.
- **Bitiş nedenleri her zaman kontrol edilir:**
  - Güvenlik engeli ya da reddetme → olay kodu loglanır, sıradaki sağlayıcı denenir. Yine olmazsa kullanıcıya nötr bir mesaj gösterilir.
  - Uzunluk sınırı → `max_tokens` artırılarak tek yeniden deneme.
- **Örnekleme parametreleri:** Sağlayıcının önerdiği varsayılanlarda kalır. Tutarlılık rubrik, örnekler ve eval ile sağlanır.
- **`max_tokens`:** Düşük tutulmaz; kesilmiş çıktı bir yeniden deneme ve kota harcar.

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

- **Önbelleğe uygunluk:**
  - Her rotanın sistem promptu sabittir: rubrik, etiket kataloğu, örnekler. Değişken içerik yalnızca kullanıcı mesajındadır.
  - Sistem promptunda tarih, UUID, sırasız JSON olmaz. Sağlayıcıların örtük önbelleği ancak böyle çalışır. Groq'ta önbellekten okunan tokenlar kotaya sayılmaz.
  - Rol oyununda geçmiş yalnızca sona eklenerek büyür.
- **Hata yönetimi:**
  - 429 (kota) → sağlayıcı o kotanın sıfırlanmasına kadar "dolu" işaretlenir, sıradaki sağlayıcıya geçilir.
  - 5xx ve zaman aşımı → SDK'nın yeniden denemesinden sonra sıradaki sağlayıcıya geçilir.
  - 400/404 yeniden denenmez; olay kodu loglanır.
- **Kullanım kaydı ve kota:**
  - Her çağrı `llm_usage` tablosuna yazılır: rota, sağlayıcı, model, token türleri, gecikme. Ücretsiz katmanda `cost_usd` = 0 olur.
  - İki kullanıcı aynı kotaları paylaşır. **Adil paylaşım:** Her kullanıcıya her sağlayıcı ve model kotasının yarısı ayrılır. Pay dolunca rota `quota_exhausted` döner, istemci deterministik moda geçer.
  - Günlük sayaçlar sağlayıcının sıfırlama saatine göre tutulur (Gemini: Pasifik saatiyle gece yarısı).
- **Gizlilik ve onay:**
  - LLM'e yalnızca metin gider: transkript, istem, öğe bilgisi. Ses, isim, e-posta ve kullanıcı kimliği gitmez.
  - Gemini'nin ücretsiz katmanında gönderilen içerik ürün geliştirmede kullanılabilir ve insanlar tarafından incelenebilir. Her kullanıcı karşılamada (F1-12) kendi adına onay verir; onay yoksa istekleri Groq'a ya da deterministik yola gider.
  - Groq hesabında ZDR (sıfır saklama) açılır.

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
  target_ok: boolean,                      // hata hedef öğeye mi dokunuyor? acceptable_variant'ta: hedef kelime cevapta mı?
  error_tags: string[],                    // kapalı listeden
  error_spans: { start: number, end: number, tag: string }[],   // response.text içinde karakter aralığı
  ladder: { h1: string, h2: string, h3: string, h4: string },   // h4 = düzeltilmiş tam cümle
  variant_to_learn: string | null,         // acceptable_variant ise kişisel varyant (target_ok=false ise kişisel alternatif) olarak eklenir
  confidence: number                       // 0..1
}
```

**Kurallar (sistem promptu + sunucu doğrulaması):**
- `correct` ya da `acceptable_variant` ise merdiven boş dizelerdir.
- h1: yalnızca hata türü. h2: yalnızca yer. h3: kural. **h1–h3, düzeltilmiş hedef parçayı içeremez.** Sunucu normalize edilmiş dize kontrolü yapar; ihlalde merdiven yeniden istenir ya da h1–h3 genel şablonlarla değiştirilir.
- A seviyelerinde açıklamalar Türkçe ve en fazla 20 kelimedir.
- Anlamı koruyan doğal ifadeler reddedilmez (I-17). Emin değilse `uncertain` döner.
- Hedef kelimenin yerine eş anlamlısını kullanan doğru cevap `acceptable_variant` ve `target_ok=false` döner. Bu durumda merdiven boştur ve istemci hedef için yeniden sorar (`03` §0.2).

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

### 4.7 İçerik rotaları (Claude Code oturumları, çevrimdışı)

İçerik hattı (`10-content-pipeline.md`) çalışma anı LLM'i kullanmaz (ADR-0009). Aşağıdaki işler Claude Code oturumlarında yapılır. Çıktılar `content/work/` altına JSONL olarak yazılır ve pydantic şemalarıyla doğrulanır:

- `content.sentences` — hedef lemma için taşıyıcı cümleler
- `content.gloss_tr` — Türkçe karşılık ve açıklama
- `content.validate` — doğallık, seviye ve anlam kontrolü; üretenden ayrı bir oturumda
- `content.variants` — kabul edilebilir cevap varyantları (deterministik değerlendirmenin temeli)
- `content.grammar_note` — H3 kural notları dahil
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
| Ağ yok / zaman aşımı | Kart: deterministik değerlendirme (ADR-0009 §2). `uncertain` sonuçlar `attempts.llm.pending = true` ile işaretlenir. Bağlantı gelince kontrol edilir; sonuç `attempt_amendments` (`llm_resolved`) olarak eklenir. Görev: kayıt yerelde bekler, senkronda işlenir. |
| Kota doldu (sağlayıcı ya da kullanıcı payı) | Sıradaki sağlayıcı; hepsi doluysa deterministik mod. Kullanıcıya nötr bilgi verilir, suçlayıcı değil. |
| Güvenlik engeli / reddetme (tüm sağlayıcılarda) | Nötr mesaj, deneme `uncertain` sayılır, olay kodu loglanır |
| Şema ihlali / katalog dışı kod | 1 yeniden deneme, sonra sıradaki sağlayıcı, sonra `uncertain` |
| Kullanıcının veri onayı yok | Groq ya da deterministik yol (§3) |
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

- **Sağlayıcı seçimi:** Çalıştırıcı aynı seti her aday sağlayıcı ve modelle çalıştırır. Rota başına sıra (§2) sonuçlara göre belirlenir ve `evals/results/` altına yazılır.
- **Kotalar:** Eval ücretsiz kotalarda çalışır. Gemini Flash'ın günlük ~20 isteği yüzünden bazı rotaların eval'i birkaç güne yayılır. Çalıştırmadan önce kullanıcıya süre ve kota etkisi söylenir.
- **Deterministik denetleyici:** Aynı `answer_check` altın seti, deterministik değerlendirme için birim testi olarak CI'da çalışır. Eşikler:
  - doğru ya da varyant cevabı "yanlış" sayma ≤ %3
  - H1–H3'te cevap sızıntısı %0

## 9. Kota planı (2 kullanıcı)

Maliyet $0'dır (ADR-0009). Sınır para değil, ücretsiz kotalardır.

Varsayımlar (kişi başı günlük):
- 20 LLM'li kart kontrolü (deterministik ön kontrol sonrası)
- 2 konuşma işaretlemesi
- 5 Söyleyemediklerim önerisi
- Haftada 3 rol oyunu (10 tur; Faz 5)

| Rota | İki kişi, günlük | Birincil kota (2026-09) | Not |
|---|---|---|---|
| answer_check | ~40 | Gemini Flash-Lite, ~500 istek/gün | Rahat |
| gap_suggest + speaking_annotate | ~14 | Gemini Flash, ~20 istek/gün | Sınıra yakın; taşan istekler Flash-Lite'a düşer |
| Aylık test (çift işaretleme) | Ayda ~4 | Gemini Flash | |
| roleplay (Faz 5) | ~9 tur | O fazda eval ile seçilir | |

- Kotalar sağlayıcı panelinde (AI Studio, Groq konsolu) ve `llm_usage` tablosunda izlenir; İlerleme > Ayarlar'da gösterilir.
- Kota ve model listesi her faz başında yeniden kontrol edilir. Ücretsiz katman daralırsa önce §2'deki adımlar denenir.

# 03 — Etkinlik Kataloğu

Her etkinlik: amaç, kol (P5), seviye, akış, değerlendirme, FSRS etkisi, log ve kanıt. Kodda her etkinliğin bir `activity` kimliği vardır (ör. `card.produce_speak`) ve `attempts.activity` alanına yazılır.

## 0. Ortak tanımlar

### 0.1 Kollar
- `input` — anlam odaklı girdi
- `output` — anlam odaklı çıktı
- `language` — dil odaklı çalışma
- `fluency` — akıcılık
- `meta` — üst biliş

### 0.2 Karar (verdict) türleri
Üretim değerlendiren her etkinlik bunlardan birini döndürür:

| Verdict | Anlam | Hedef öğe için sonuç |
|---|---|---|
| `correct` | Referansla eşleşti | doğru |
| `acceptable_variant` | Başka ama doğal ve doğru bir ifade (I-17) | doğru. Hedef kelime cevapta yoksa (`target_ok=false`; ör. present kartında "gift") **hedefsiz doğru cevaptır**: hata sayılmaz, hedefin kanıtı da sayılmaz. "Doğru! Bu kart başka bir kelimeyi çalışıyor, başka nasıl söylersin?" denir ve istem yeniden sorulur. |
| `minor_error` | Anlam korunmuş, küçük biçim hatası | Hata hedef öğedeyse (`target_ok=false`) yanlış; değilse doğru. Hata etiketi her durumda profile yazılır. |
| `wrong` | Hedef yapı/anlam yanlış | yanlış |
| `off_target` | Başka bir şey söylenmiş | yanlış (ipucu: "istenen anlam bu değil") |
| `unintelligible` | Ses tanıma anlamsız sonuç verdi | Deneme sayılmaz; tekrar kayıt ya da yazarak cevap istenir |
| `uncertain` | LLM emin değil | Kullanıcıya "Bunu mu demek istedin?" sorulur; belirsiz kalırsa doğru sayılır ve öğe incelemeye düşer |
| `uncertain` (LLM'siz) | Deterministik değerlendirme karar veremedi (§0.5, adım 4) | Üretim kanıtı sayılmaz. FSRS: Hard. LLM sonucu gelince kanıt ona göre işlenir. |

### 0.3 Otomatik FSRS puanı (öz değerlendirme yok)

| FSRS | Koşul |
|---|---|
| Again (1) | 3 denemede doğru yok, ya da H4 (cevap) açıldı |
| Hard (2) | Doğru, ama H1–H3 kullanıldı ya da ikinci/üçüncü denemede |
| Good (3) | İlk denemede, ipucusuz doğru ya da kabul edilebilir varyant |
| Easy (4) | Good koşulu + cevap gecikmesi, kişinin bu moddaki son 200 denemesinin 25. yüzdelik diliminin altında. Bu modda 20'den az deneme varsa Easy verilmez. |

Puan tek bir denemeye değil, kartın o gösterimine verilir. Gösterim doğru cevapla, deneme hakkı bitince ya da H4 açılınca biter. Her yanlış cevap bir deneme hakkı harcar ve bir üst ipucunu açar. Kullanıcı ipucu merdiveninde kendisi de ilerleyebilir, ama ilk yanlıştan önce ipucu yoktur. H3'ten sonraki yanlış H4'ü açar. Motorda: `CardReview` → `ReviewOutcome.rating`.

**Tanıtımın hemen ardından Easy verilmez.** Yeni öğenin tanıtımından (A00) hemen sonraki ilk tekrarda cevap az önce gösterilmiştir; hız hafızayı göstermez. İlk denemede doğru cevap burada en fazla Good alır. FSRS varsayılanlarında ilk tekrardaki Easy kartı doğrudan 16 günlük aralığa atar; bu hem zamanlamayı hem kanıt düzeyini şişirirdi (I-04).

**LLM'siz `uncertain`** (§0.5, adım 4) her zaman **Hard** alır: ceza da şişirme de yoktur. Sonradan gelen LLM sonucu (`llm_resolved`) kanıtı düzeltir, FSRS geçmişini değiştirmez (I-03).

**Hedefsiz doğru cevap** (§0.2) deneme hakkı ve ipucu harcamaz; istem bir kez yeniden sorulur:
- Hedefle doğru cevap gelirse kart **Hard** alır (ikinci deneme sayılır) ve üretim kanıtı yazılır.
- Yine hedefsiz doğru cevap gelirse hedef cümle gösterilir (H4), kart **Hard** alır ve üretim kanıtı yazılmaz. `uncertain` gibi burada da ceza ya da şişirme yoktur.
- Yeniden sorulunca kullanıcı "göster" derse sonuç aynıdır (**Hard**, kanıt yok). Arada yanlış cevap varsa "göster" her zamanki gibi **Again**'dir.

Ses tanımanın yanlış duyduğu durumlar için kullanıcı "yanlış duyuldu" deyip cevabını yazabilir. Yazılı cevap aynı denemenin parçası olarak değerlendirilir ve `asr_override=true` loglanır.

### 0.4 Ortak deneme logu

Her denemede şu alanlar doldurulur (tam şema `13-data-model.md`):

- `activity`, `item_id`/`card_id`/`task_id`
- `prompt`, `response` (metin, ses yolu, transkript, ASR güveni)
- `verdict`, `target_ok`, `error_tags[]`
- `hints_used`, `hint_max_level`
- `latency_ms` (istemin gösterilmesinden konuşmanın/yazmanın başlamasına kadar), `duration_ms`
- `rating`, `parent_attempt_id` (aynı öğedeki tekrar denemeleri zincirler), `experiment`

---

## A00 — Yeni öğe tanıtımı (`introduce`)
- **Amaç:** Yeni öğeyi anlamlı bağlamda göstermek, ardından hemen çağırtmak (P1, P8).
- **Kol:** language · **Seviye:** A0–C2 · **Süre:** ~30 sn
- **Akış:**
  1. Taşıyıcı cümle + ses (seviyeye göre yavaş) gösterilir.
  2. Türkçe anlam, işaretli kalıp, gerekiyorsa tek cümlelik gramer notu verilir (A seviyelerinde Türkçe).
  3. Karşıtlık notu gösterilir ("say ≠ tell: tell + kişi").
  4. Hemen ardından A01 (Söyle kartı) bu öğe için bir kez yapılır.
- **FSRS:** Kart bu adımda oluşturulur. İlk değerlendirme A01'in sonucudur.
- **Not:** I-01'in iki istisnasından biridir (tanıtım ekranı cevabı gösterir).

## A01 — Söyle kartı (`card.produce_speak`) — **varsayılan kart**
- **Amaç:** Türkçe anlamdan İngilizce sesli üretim (P1, P3, P4).
- **Kol:** language · **Seviye:** A0–C2 · **Süre:** 15–25 sn
- **Akış:**
  1. Türkçe istem ve bağlam notu gösterilir ("arkadaşına söylüyorsun", "resmî").
  2. Kullanıcı basılı tutup konuşur (en fazla 12 sn).
  3. Ses tanıma çalışır, transkript gösterilir.
  4. **Deterministik değerlendirme** (§0.5) referans ve varyantlarla eşleşirse doğru sayılır, LLM çağrılmaz.
  5. Eşleşmezse `answer_check` rotası çalışır; verdict ve H1–H4 merdiveni tek çağrıda gelir. LLM erişilemezse §0.5'in 4. adımı çalışır.
  6. Yanlışsa H1 açılır, kullanıcı tekrar dener (en fazla 3 deneme; her denemede bir üst ipucu).
  7. Sonunda doğru cümle sesiyle gösterilir, kullanıcı bir kez sesli tekrar eder (mini gölgeleme; puanlanmaz).
- **Değerlendirme:** Deterministik → LLM → (LLM yoksa) hizalama. Telaffuz bu kartta puanlanmaz; transkript anlaşılmazsa `unintelligible` döner.
- **Kanıt:** Üretim (konuşma) kanıtı.

### 0.5 Deterministik değerlendirme (A01, A02, A04, A08)

Kota ve hız için LLM'den önce çalışır. LLM erişilemezse tek başına çalışır (ADR-0009 §2):

1. Normalizasyon:
   - küçük harf, noktalama ve fazla boşlukları silme
   - ses tanımanın bıraktığı dolgu seslerini atma ("uh", "um"; paketin `fillers` listesi)
   - kısaltmaları açma (I'm → I am, don't → do not; isimden sonraki "'s" → is)
   - sayıları yazıya çevirme
   - İngiliz ve Amerikan yazımını eşitleme (colour/color)
   - art arda iki kez söylenen kelimeyi bir sayma ("the the"; paketin `collapse_repeats` kuralı, tekrarın anlam taşıdığı dillerde kapalı)
2. Normalize edilmiş cevap bilinen doğru cevaplardan biriyle birebir eşleşirse LLM çağrılmaz. Bilinen doğru cevaplar: referans, paketteki `variants` ve `alternatives` listeleri, kişisel varyantlar ve alternatifler.
   - Eşleşen cevap **kartın hedef kelimesini içeriyorsa** `correct` döner.
   - İçermiyorsa **hedefsiz doğru cevaptır** (§0.2).
   - Referans her zaman `correct`'tir.
   - Karar listeye göre değil hedefe göre verilir, çünkü bir cümle birden çok öğe taşır ve paket listeleri cümlenin seçilmiş hedeflerine göre yazılmıştır. Örnek: "I've got homework to do." cümlesinin varyantı "I have homework to do", `homework` kartında doğrudur, `get` kartında hedefsizdir.
   - Hedef kelime referansın kendisinde bile bulunamıyorsa (kalıp kartları, biçim tablosunda olmayan yazımlar) liste belirleyicidir: `variants` hedefli, `alternatives` hedefsiz sayılır.
3. Aksi hâlde LLM'e gider (`07` §2'deki sağlayıcı sırası). LLM `acceptable_variant` derse bu cevap kişisel varyant listesine eklenir, `target_ok=false` ise kişisel alternatif listesine. Bir sonraki sefer deterministik eşleşir.
4. LLM erişilemezse (çevrimdışı, kota dolu ya da veri onayı yok) cevap, hedefi içeren doğru cevapların en yakınıyla **kelime düzeyinde hizalanır**. Lemma ve biçim tablosu paketten gelir.
   - **Fark türleri:** eksik kelime, fazla kelime, aynı lemmanın başka biçimi, sıra (yan yana iki kelimenin yer değiştirmesi ya da bir kelimenin başka yere taşınması), başka kelime. İlk dördü sınıflanabilir farktır. "Başka kelime" sınıflanamaz, çünkü eş anlamlı mı yanlış mı olduğunu yalnızca LLM söyleyebilir.
   - **Küçük fark:** en fazla 1 fark. Doğru cevap 6 kelime ya da daha uzunsa en fazla 2 fark.
   - **Hedef parça:** doğru cevapta hedef öğenin lemmalarını taşıyan kelimeler. Hedef bulunamazsa cevabın tamamı hedef sayılır.
   - Karar, hedef parçanın durumuna göre verilir:

     | Hedef parça | Fark | Karar |
     |---|---|---|
     | Sağlam | küçük ve sınıflanabilir | `minor_error`, `target_ok=true` (hedef için doğru) |
     | Sağlam | büyük ya da sınıflanamaz | `uncertain` (LLM'siz) |
     | Bozuk: biçimi yanlış | — | `minor_error`, `target_ok=false` |
     | Bozuk: sırası yanlış ya da araya kelime girmiş | — | `wrong`, `target_ok=false` |
     | Eksik | küçük | `wrong`, `target_ok=false` |
     | Yerinde başka kelime var | küçük | `uncertain` (LLM'siz): eş anlamlı olabilir |
     | Eksik ya da yerinde başka kelime var | büyük | `off_target`; ama cevap doğru cevabın kelimelerinin en az üçte birini koruyor ve yalnızca kelime eksiltmekten fazlasını yapıyorsa `uncertain` (LLM'siz): hedefsiz başka bir söyleyiş olabilir ("Remember to buy bread!" ← "Don't forget to buy bread!"). Yalnızca eksiltme bir parçadır, `off_target` kalır. |

   - **`uncertain` (LLM'siz):**
     - Üretim kanıtı sayılmaz; FSRS'e Hard yazılır (§0.3).
     - Deneme `llm.pending` olur. LLM erişilebilir olunca kontrol edilir; sonuç `attempt_amendments` (`llm_resolved`) olarak eklenir.
   - **Hata etiketi eklenmez.** Paketlerde etiketleri kelime farkından kesin çıkaracak kural verisi yok; etiketler LLM'den gelir.
   - **İpucu merdiveni şablonludur** ve yalnızca yanlış sayılan cevapta üretilir. H1–H3 doğru cevaptan hiçbir kelime taşımaz (I-02):
     - H1: fark türü (kelime eksik, kelime fazla, biçim yanlış, sıra yanlış; `off_target`'ta "istenen anlam bu değil"). Metni ARB'den gelir.
     - H2: farkın yeri, öğrencinin kendi söylediği bir kelimeyle anlatılır ("… kelimesinden önce", "… kelimesinden sonra", "… kelimesinde").
     - H3: kartın kendi gramer noktasının kural notu. Kelime ve kalıp kartlarında H3 yoktur: cümledeki başka bir gramer noktasının notu hatayla ilgisiz olur ve yanıltır.
     - H4: hizalanan doğru cevap (referans ya da cevaba daha yakın olan varyant).
   - Motorda: `AnswerChecker.match` (adım 2) ve `AnswerChecker.checkWithoutLlm` (adım 2 + 4).
5. Kullanıcı her sonuca "cevabım da doğru olabilir" diyebilir:
   - İtiraz `attempt_amendments` (`user_dispute`) olarak yazılır.
   - LLM varsa yeniden kontrol edilir; ayrıca içerik bildirimi olarak kaydedilir (`10` §8).
   - Kendi kendine kabul yoktur (§0.3: öz değerlendirme yok).

## A02 — Yaz kartı (`card.produce_type`)
- A01 ile aynıdır; cevap klavyeyle verilir. **Sessiz mod** açıkken varsayılan budur.
- Metin alanında otomatik düzeltme ve öneriler kapalıdır (`autocorrect: false`, `enableSuggestions: false`).
- **Kanıt:** Üretim (yazılı).

## A03 — Dinle-anla kartı (`card.recognize_audio`)
- **Amaç:** Dinlemede kelimeyi/kalıbı tanıma (alıcı bilgi).
- **Kol:** language · **Seviye:** A0–B1 · **Süre:** ~8 sn
- **Akış:**
  1. İngilizce ses çalar (her seferinde farklı ses).
  2. Kullanıcı Türkçe anlamı söyler/yazar. A0–A1'de 4 seçenekten biri seçilebilir.
  3. Doğru/yanlış ve tekrar dinleme.
- **Kanıt:** Yalnızca alıcı kanıt (I-05: üretim sayılmaz).

## A04 — Bağlamda boşluk (`card.cloze`)
- **Amaç:** Bağlam içinde biçim çağırma: eşdizim, edat, zaman.
- **Kol:** language · **Seviye:** A1–C2
- **Akış:** Boşluklu İngilizce cümle + eksik parçanın Türkçe ipucu gösterilir. Kullanıcı eksik parçayı söyler/yazar. Değerlendirme A01 gibi.

## A05 — Dikte (`dictation`)
- **Amaç:** Konuşmayı kelimelere ayırma, işlev kelimeleri ve ekleri duyma (aşağıdan yukarı dinleme).
- **Kol:** language · **Seviye:** A1–C1 · **Süre:** 30–60 sn/cümle
- **Akış:**
  1. Cümle dinlenir; kişisel kapsaması ≥ %95 olmalı.
  2. Kullanıcı duyduğunu yazar.
  3. Kelime düzeyinde hizalama ve fark gösterilir.
  4. Hata sınıflanır: kaçan işlev kelimesi, -s/-ed, kelime sınırı, ses karışıklığı.
  5. Yavaş dinleme ya da bölüm bölüm dinleyip tekrar yazma.
- **Değerlendirme:** Deterministik (hizalama, WER). LLM gerekmez.
- **FSRS:** Cümle öğesinin `dictation` modu kartı.
- **Kanıt:** Dinleme çözme kanıtı. Algı hata etiketleri (`perc.*`) profile yazılır.

## A06 — Ses ayırt etme (`minimal_pairs`, HVPT)
- **Amaç:** Karışan sesleri algılamak (P17).
- **Kol:** language · **Seviye:** A0–B1 (ihtiyaca göre sonra da) · **Süre:** 3 dk'lık blok (20–40 deneme)
- **Akış:**
  1. Kelime rastgele bir sesle (en az 4 farklı ses) çalar.
  2. Kullanıcı iki seçenekten birini seçer (ship / sheep).
  3. Anında doğru/yanlış gösterilir, iki kelime art arda tekrar dinletilir.
- **Değerlendirme:** Deterministik. Karşıtlık başına doğruluk eğilimi izlenir.
- **FSRS:** Yok. Karşıtlık düzeyinde ilerleme izlenir; doğruluk %90'ı iki farklı günde geçince seyrek tekrara iner.

## A07 — Gölgeleme ve tekrar (`shadowing`)
- **Amaç:** Telaffuz, ritim, vurgu.
- **Kol:** fluency · **Seviye:** A0–C1
- **Akış:**
  1. Cümle dinlenir.
  2. Kullanıcı tekrarlar (seviyeye göre sonra ya da üst üste).
  3. Referans metne karşı **telaffuz değerlendirmesi** yapılır (`08-speech.md`).
  4. Öncelik listesindeki (`02` §6) en önemli 1–2 sorun gösterilir.
  5. Tekrar denenir.
- **Kanıt:** Ses denetimi (phonological control) göstergeleri.

## A08 — Karşıtlık alıştırması (`contrast_drill`)
- **Amaç:** Karışan öğeleri ayırt etmek (P12). Örnekler: say/tell, house/home, Past Simple/Present Perfect, a/the, he/she.
- **Kol:** language · **Seviye:** A1–C1 · **Süre:** 2–4 dk
- **Akış:**
  1. Karışık sırada Türkçe istemler gelir; her istem yalnızca bir seçeneğe uyacak şekilde tasarlanmıştır.
  2. Kullanıcı İngilizce üretir.
  3. **Deneme bittikten sonra** karşıtlık açıklaması tek cümleyle gösterilir.
- **Tetikleyici:** Planlayıcı, `contrasts_with` bağlı öğelerin ikisi de "hatırlanıyor" olunca ya da haftalık hata odağı olunca açar.

## A09 — Yapılandırılmış girdi (`structured_input`)
- **Amaç:** Yeni gramerde biçim–anlam bağını kurmak (VanPatten'in işlem öğretimi yaklaşımı).
- **Kol:** language · **Seviye:** A0–B1 · **Süre:** 2 dk
- **Akış:**
  1. Kullanıcı biçime bağlı anlamı yorumlar. Örnekler:
     - "She walked." / "She walks." → "Dün mü, her gün mü?"
     - "He is working." → "Şu an mı, genelde mi?"
  2. Ardından aynı yapı için A01/A04 ile üretime geçilir.
- **Değerlendirme:** Deterministik.

## A10 — Kelime taşları (`sentence_tiles`) — yalnız A0–A1 iskelesi
- Türkçe isteme karşılık karışık taşlardan (+2 çeldirici) İngilizce cümle kurulur.
- **Kanıt:** Üretim kanıtı **sayılmaz** (iskeleli). Sadece "öğreniliyor" adımıdır.
- A2'de varsayılan olarak kapanır (I-09).

## A11 — Konuşma görevi (`speaking_task`)
- **Amaç:** Serbest sözlü üretim; can-do kanıtı; aktarım tespiti (P4, P7).
- **Kol:** output · **Seviye:** A1–C2 · **Süre:** 1–2 dk konuşma + 3–5 dk geri bildirim
- **Akış:**
  1. Görev kartı gösterilir. Hazırlık süresi ve kalıplar seviyeye göre (`02` §3).
  2. Kayıt yapılır.
  3. İşleme:
     - ses tanıma, kelime zamanları
     - deterministik akıcılık ölçümleri
     - `speaking_annotate` LLM rotası: cümlecikler, hatalar, etiketler, görev sonucu
  4. **Geri bildirim ekranı:**
     - (a) İyi giden 1–2 somut şey. Örnek: "because'u 3 kez doğru kullandın."
     - (b) **En önemli 3 düzeltme.** Seçim sırası: tekrar eden hata etiketi > anlamı bozan hata > sıklık. Her düzeltme mini karttır: kullanıcı orijinal cümlesini görür, ipucu merdiveniyle düzeltir, düzeltilmiş hâli **sesli** söyler.
     - (c) İsteğe bağlı: görevi yeniden yapma. Aynı görevin tekrarı akıcılığı ve doğruluğu artırır.
  5. Düzeltilen 3 cümle varsayılan olarak kişisel öğe olarak FSRS'e eklenir.
- **Kanıt:**
  - Can-do kanıtı (görev bağlıysa)
  - Aktarım: transkriptte doğru kullanılan öğeler
  - Hata profili güncellemesi

## A12 — 4/3/2 akıcılık (`fluency_432`)
- **Amaç:** Tanıdık konuyu artan zaman baskısıyla tekrar anlatmak (P16).
- **Kol:** fluency · **Seviye:** A1–C2
- **Süreler:**
  - A1: 90 / 60 / 45 sn
  - A2: 2 / 1,5 / 1 dk
  - B1 ve üstü: 4 / 3 / 2 dk
- **Akış:**
  1. Konu, daha önce konuşma görevinde işlenmiş bir konudan seçilir (yeni kelime gerekmez).
  2. Üç tur yapılır.
  3. Tur başına dakikadaki kelime ve uzun duraksama sayısı gösterilir.
  4. Düzeltme yapılmaz. En sonda isteğe bağlı tek bir düzeltme.

## A13 — Yapay zekâyla rol oyunu (`roleplay_ai`)
- **Amaç:** Etkileşim; anlam müzakeresi; telafi stratejileri.
- **Kol:** output · **Seviye:** A1–C2 · **Süre:** 4–8 dk
- **Akış:**
  1. Senaryo gösterilir (resepsiyon, doktor, iş arkadaşı…) ve hedef belirlenir ("anahtar kartı değiştir").
  2. Sırayla konuşulur: kullanıcı konuşur → ses tanıma → `roleplay_turn` (yanıt metni + ses).
  3. Yapay zekâ **öğrencinin seviyesinde** konuşur: bilinen kelimeler + en fazla birkaç yeni kelime.
  4. Hatalar konuşma sırasında düzeltilmez. Anlaşılmazlık olursa yapay zekâ doğal bir netleştirme sorusu sorar.
  5. 6–12 tur sürer ya da hedefe ulaşılınca biter.
  6. `roleplay_debrief`: görev sonucu, en önemli 3 düzeltme (ipucu merdiveniyle), yapay zekânın kullandığı faydalı kalıplar (isteğe bağlı kart).
- **Kanıt:** Etkileşim can-do kanıtı, aktarım, hata profili.

## A14 — Birlikte sohbet kartı (`pair_chat_card`)
- **Amaç:** Bağlılık ve düşük baskılı konuşma pratiği (P18, P19).
- **Kol:** output · **Seviye:** A1–C2 · **Süre:** 5–15 dk (yüz yüze, ör. akşam yemeğinde)
- **Akış:**
  1. Kart gösterilir: bir soru + devam soruları + 3 faydalı kalıp.
  2. Partnerler konuşur. Varsayılan olarak **kayıt yoktur**.
  3. Sonunda her kişi isterse "söyleyemediklerim"i hızlıca girer.
- **Log:** Süre ve katılım (ortak haftalık hedefe sayılır).

## A15 — Bilgi boşluğu görevi (`pair_info_gap`)
- **Amaç:** Gerçek iletişim ihtiyacı yaratan ikili görev.
- **Kol:** output · **Seviye:** A1–B2 · **Süre:** 5–10 dk
- **Akış:**
  1. İki telefonda gerçek zamanlı bir oturum açılır (Supabase Realtime). Her telefon yalnızca kendi rolünün bilgisini görür. Görev türleri:
     - biri resmi tarif eder, diğeri seçer
     - iki resim arasındaki farkları bulmak
     - 6 resimlik hikâyeyi 3'er resimle sıraya koymak
     - tren saatleri ile bütçe kısıtını birleştirmek
  2. Partnerler konuşur. **Her telefon yalnızca kendi sahibini kaydeder** (bas-konuş). Konuşmacıyı ayırt etme (diarization) gerekmez.
  3. Sonunda cevaplar gönderilir ve deterministik cevap anahtarıyla görev başarısı kontrol edilir.
  4. Her kişi kendi kayıtlarından kişisel geri bildirim alır (en önemli 2 düzeltme).

## A16 — Seviyeli okuma (`graded_reading`)
- **Amaç:** Anlam odaklı girdi (P6).
- **Kol:** input · **Seviye:** A1–C2 · **Süre:** 5–10 dk
- **Akış:**
  1. Kişisel kapsamaya bakılır (I-06). %95–98 arasındaysa önce bilinmeyen kelimeler öğretilir (A03/A01 kısa set).
  2. Metin okunur (isteğe bağlı sesle). Dokun-anlamını-gör aramaları loglanır.
  3. 3–5 anlama sorusu sorulur. A seviyelerinde Türkçe cevaplanabilir; ölçülen şey anlamadır.
  4. "Bunu 3 cümleyle anlat" (hafif aracılık, output).
  5. Aranan kelimeler için "karta ekle?" önerilir.

## A17 — Seviyeli dinleme (`graded_listening`)
- **Kol:** input · **Seviye:** A1–C2 · **Süre:** 5–10 dk
- **Akış:**
  1. Metin gösterilmeden dinlenir, ana fikir sorusu sorulur.
  2. İkinci dinlemeden sonra ayrıntı soruları sorulur.
  3. Metin, iskele düzeyine göre gösterilir.
  4. Metinle birlikte tekrar dinlenir.
  5. 2–3 kalıp seçilip karta eklenir.

## A18 — Medya günlüğü ve altyazı madenciliği (`media_log`, `subtitle_mining`)
- **Kol:** input · **Seviye:** A2–C2
- **Medya günlüğü:** Başlık, dakika, altyazı türü (yok / İngilizce / Türkçe), partnerle mi girilir. Suçluluk yoktur. Haftalık girdi koluna sayılır, 30 dk bütçeye sayılmaz.
- **Altyazı madenciliği:**
  1. Kullanıcı bir bölümün `.srt`/`.vtt` dosyasını içe aktarır.
  2. Kişisel kapsama hesaplanır.
  3. Bilinmeyen lemmalar genel sıklık × bölümdeki tekrar sayısına göre sıralanır.
  4. **İzlemeden önce** ilk 5–10 kelime kısa bir setle öğretilir.
  5. İzledikten sonra kullanıcı beğendiği replikleri seçer ve bunlar karta dönüşür (sadece metin; ses TTS ile).
- **Telif:** Dosya yalnızca kullanıcının cihazında ve kişisel deposunda tutulur, paylaşılmaz.

## A19 — Söyleyemediklerim (`gap_capture`)
- **Amaç:** Kişisel, anlamlı içerik; "boşluğu fark etme" anını yakalamak (P7).
- **Kol:** language · **Seviye:** A0–C2
- **Yakalama noktaları:**
  - Uygulamadaki sabit buton
  - Android paylaş menüsü
  - Hızlı ayarlar kutucuğu
  - Ana ekran widget'ı
  - Rol oyunu ve ikili görev sırasında "nasıl derim?" butonu
- **Akış:**
  1. Türkçe metin ya da ses (Türkçe ses tanıma) ve bağlam kaydedilir.
  2. `gap_suggest` şunları döner:
     - seviyeye uygun doğal İngilizce
     - daha basit bir alternatif
     - anahtar kalıp ve Türkçe notu
  3. Kullanıcı onaylarsa cümle ve kalıp kişisel öğe olarak kart olur.
- **Not:** Kullanıcı karşılığı kendisi istediği için cevabın hemen gösterilmesi I-01'in istisnasıdır.

## A20 — Yazma görevi (`writing_task`)
- **Kol:** output · **Seviye:** A2 (kısa mesaj) – C2
- **Akış:**
  1. İstem gösterilir (iş arkadaşına e-posta, arkadaşa mesaj, görüş paragrafı).
  2. Kullanıcı yazar (otomatik düzeltme kapalı).
  3. `writing_feedback` şunları döner:
     - 1–2 somut güçlü yan
     - hatalar: yerleri işaretli, ipucu merdiveniyle, kullanıcı satır içinde düzeltir
     - B2+ için tutarlılık yorumu
  4. Kullanıcı yeniden yazar. Son sürüm saklanır. En önemli düzeltmeler karta dönüşür.

## A21 — Aracılık (`mediation`)
- **Kol:** output · **Seviye:** B1–C2
- **Akış:**
  1. Kullanıcı bir metin okur/dinler; metin Türkçe ya da İngilizce olabilir.
  2. İçeriği birine İngilizce, kendi sözleriyle anlatır. Örnekler:
     - "Bu Türkçe duyuruyu İngiliz bir iş arkadaşına açıkla."
     - "Bu haberi partnerine anlat."
  3. `mediation_check` iki şeye bakar: ana noktaların kapsanması (anahtar noktalar listesiyle) ve dil (ipucu merdiveni).

## A22 — Kişisel hata odağı (`error_focus`)
- **Kol:** language · **Seviye:** A1–C2 · **Süre:** ~5 dk, haftalık odak
- **Akış:**
  1. Haftanın odak etiketi seçilir (`04-learner-model.md` §6).
  2. Fark etme: girdi cümlelerinde ilgili biçim vurgulanır.
  3. Karşıtlık maddeleri çalışılır.
  4. Kullanıcının **kendi geçmiş hataları** yeniden denenir. Örnek: "Geçen hafta şöyle demiştin: 'I have problem…' Şimdi düzelt."
  5. Serbest bir cümle üretilir.

## A23 — Aylık konuşma testi (`assessment.monthly`) → `06-assessment.md`
## A24 — Seviye testi (`assessment.placement`) → `06-assessment.md`

## A25 — Öğrenme bilimi notu (`learning_note`)
- **Kol:** meta · **Süre:** ~1 dk, haftada bir
- Kullanıcının kendi verisinden üretilen kısa bir Türkçe not. Örnek: "İpucuyla çözdüğün kartların 30 gün sonraki hatırlanma oranı %X, cevabını hemen gördüklerininki %Y. Nedeni…"
- Şablonlar paketten gelir; sayılar motordan.

---

## Özet tablo

| Kod | Etkinlik | Kol | Seviye | LLM | ASR | FSRS | Kanıt |
|---|---|---|---|---|---|---|---|
| A00 | Tanıtım | language | A0–C2 | – | – | kart oluşturur | – |
| A01 | Söyle kartı | language | A0–C2 | gerekirse | ✓ | ✓ | üretim (sözlü) |
| A02 | Yaz kartı | language | A0–C2 | gerekirse | – | ✓ | üretim (yazılı) |
| A03 | Dinle-anla | language | A0–B1 | – | – | ✓ | alıcı |
| A04 | Bağlamda boşluk | language | A1–C2 | gerekirse | ✓ | ✓ | üretim |
| A05 | Dikte | language | A1–C1 | – | – | ✓ | dinleme çözme |
| A06 | Ses ayırt etme | language | A0–B1 | – | – | – | algı |
| A07 | Gölgeleme | fluency | A0–C1 | – | telaffuz | – | ses denetimi |
| A08 | Karşıtlık | language | A1–C1 | gerekirse | ✓ | ✓ | üretim |
| A09 | Yapılandırılmış girdi | language | A0–B1 | – | – | – | biçim–anlam |
| A10 | Kelime taşları | language | A0–A1 | – | – | – | yok (iskele) |
| A11 | Konuşma görevi | output | A1–C2 | ✓ | ✓ | düzeltmeler kart olur | can-do, aktarım |
| A12 | 4/3/2 | fluency | A1–C2 | – | ✓ | – | akıcılık |
| A13 | Rol oyunu | output | A1–C2 | ✓ | ✓ | düzeltmeler | can-do, aktarım |
| A14 | Sohbet kartı | output | A1–C2 | – | – | – | katılım |
| A15 | Bilgi boşluğu | output | A1–B2 | ✓ | ✓ | düzeltmeler | can-do |
| A16 | Okuma | input | A1–C2 | cevap kontrolü | – | aramalar kart olabilir | anlama |
| A17 | Dinleme | input | A1–C2 | cevap kontrolü | – | kalıplar | anlama |
| A18 | Medya/altyazı | input | A2–C2 | – | – | madencilik | girdi hacmi |
| A19 | Söyleyemediklerim | language | A0–C2 | ✓ | TR | kart oluşturur | – |
| A20 | Yazma | output | A2–C2 | ✓ | – | düzeltmeler | can-do |
| A21 | Aracılık | output | B1–C2 | ✓ | ✓ | düzeltmeler | can-do |
| A22 | Hata odağı | language | A1–C2 | gerekirse | ✓ | ✓ | hata profili |
| A23 | Aylık test | output | tümü | ✓ | ✓ | – | ölçüm |
| A24 | Seviye testi | – | tümü | – | – | – | başlangıç tahmini |
| A25 | Öğrenme notu | meta | tümü | – | – | – | – |

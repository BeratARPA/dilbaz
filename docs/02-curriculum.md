# 02 — Seviyeler ve Müfredat

## 1. Omurga: CEFR

Dilbaz, Avrupa Konseyi'nin **CEFR** çerçevesini (2001) ve **Companion Volume**'u (2020) omurga olarak kullanır. Bu çerçeve dilden bağımsızdır: seviyeler ve "yapabilir" (can-do) tanımları her dil için aynıdır.

- **Seviyeler:** A0 (Pre-A1), A1, A2, B1, B2, C1, C2.
- **İletişim etkinlikleri:**
  - **Alma** (dinleme, okuma)
  - **Üretme** (konuşma, yazma)
  - **Etkileşim** (sohbet, bilgi alışverişi)
  - **Aracılık** (okuduğunu/duyduğunu başkasına aktarma, açıklama)
- **Yeterlikler:**
  - **Dilsel:** kelime, gramer, ses
  - **Sosyodilsel:** resmiyet, nezaket
  - **Pragmatik:** tutarlılık, akıcılık
- **Strateji ölçekleri:** özellikle **telafi** (compensating), yani bilmediği kelimenin etrafından dolaşabilme.

Dil pakette, can-do tanımları kodlarıyla saklanır (ör. `CEFR.SI.CONV.B1.1`). Türkçe çevirileri dil çifti paketinde durur.

## 2. Seviye tablosu

Kelime sayıları Milton (2010) ve Milton & Alexiou (2009) çalışmalarından gelir: en sık 5000 lemma içinde tanınan kelime sayısıdır. Saatler Cambridge'in rehberli öğrenme saati tahminleridir; A0'dan itibaren kümülatif ve kabadır.

| Seviye | Kelime (tanıma) | Kümülatif saat | Konuşmada ne yapabilir | Ana öğrenme kaynağı |
|---|---|---|---|---|
| **A0** | < 300 | — | Selamlaşma, kendini çok basit tanıtma, ezber kalıplar | Bilinçli çalışma, sesler, en sık kalıplar |
| **A1** | < 1500 | — | Tanıdık gündelik ifadeler; kişisel bilgi sorup cevaplama | Bilinçli çalışma + çok basit girdi |
| **A2** | 1500–2500 | 180–200 | Rutin işler; geçmiş, plan ve çevre hakkında basit anlatım | Bilinçli çalışma + seviyeli girdi |
| **B1** | 2750–3250 | 350–400 | Tanıdık konularda hazırlıksız sohbet; deneyim ve olay anlatma; görüşe kısa gerekçe; seyahatte çoğu durumu idare etme | Bilinçli çalışma + **bol** seviyeli girdi |
| **B2** | 3250–3750 | 500–600 | Anadili İngilizce olanla zorlanmadan akıcı etkileşim; görüş savunma; ayrıntılı açıklama | Bol girdi (yarı otantik→otantik) + hedefli çalışma |
| **C1** | 3750–4500 | 700–800 | Akıcı, esnek, etkili kullanım; iş/akademik bağlam; nüans | Çoğunlukla otantik girdi + hata odaklı çalışma |
| **C2** | 4500–5000+ | 1000–1200 | Her şeyi zahmetsiz anlama; ince anlam farkları | Otantik girdi, türe özgü üretim |

Not: Roman ve film gibi otantik içeriği rahat anlamak için 8–9 bin kelime ailesi gerekir (Nation, 2006). C seviyelerinde kelime hedefi bu yüzden X_Lex tavanının (5000) üstüne çıkar.

**Kullanıcıların konumu (2026-09):** Kelime defterlerine göre A1–A2 arası. Bu tahmin Faz 1'deki seviye testiyle netleşecek. 12 aylık hedef B1 konuşmadır.

## 3. İskele matrisi (seviyeye göre rehberlik)

"Uzmanlığın tersine dönme etkisi" (P11) gereği iskeleler seviye yükseldikçe kapanır. Motor bu tabloyu dil paketinden değil, **seviye kodundan** okur (dilden bağımsız). Kullanıcı her iskeleyi Ayarlar'dan elle açıp kapatabilir.

| İskele | A0 | A1 | A2 | B1 | B2 | C1–C2 |
|---|---|---|---|---|---|---|
| Kelime taşlarıyla cümle kurma | açık | azalarak | kapalı (isteğe bağlı) | kapalı | kapalı | kapalı |
| Açıklama dili | Türkçe | Türkçe | Türkçe | İngilizce (Türkçe düğmesi) | İngilizce | İngilizce |
| Yavaş ses (0.8×) | varsayılan | varsayılan | isteğe bağlı | isteğe bağlı | kapalı | kapalı |
| İpucu merdiveni | H1–H4, 2 hatadan sonra otomatik | H1–H4 | H1–H4 | H1–H3, H4 istekle | H1–H2, gerisi istekle | H1, gerisi istekle |
| Dinlemede metni gösterme | ilk dinlemeden sonra | ilk dinlemeden sonra | cevaptan sonra | cevaptan sonra | istek üzerine | istek üzerine |
| Konuşma görevinde hazırlık süresi | 90 sn + 3 kalıp | 60 sn + 3 kalıp | 60 sn + 3 kalıp | 30 sn, kalıplar istekle | 15 sn | 0–15 sn |
| Tanıma (çoktan seçmeli) | alıcı bilgi için | alıcı bilgi için | yalnızca dinleme kelimesi | yok | yok | yok |
| Okumada dokun-anlamını-gör | açık | açık | açık | açık | açık | açık |

Okumada anlam aramaları loglanır ve bilinmeyen kelime sinyali olarak kullanılır.

## 4. Müfredat haritası (curriculum graph)

### 4.1 Düğümler

| Tür | Açıklama | Örnek |
|---|---|---|
| `can_do` | CEFR tanımı | "Tanıdık konularda hazırlıksız sohbete girebilir" (B1) |
| `task` | İletişim görevi | "Otelde anahtar sorununu anlat" |
| `item:sentence` | Taşıyıcı cümle | "I'm going home." |
| `item:chunk` | Kalıp / eşdizim | "go home", "the problem is that…" |
| `item:word_sense` | Kelimenin tek bir anlamı | watch (v., izlemek) ≠ watch (n., kol saati) |
| `item:grammar_point` | Gramer yapısı (EGP düzeyinde) | "Present Perfect: ever/never ile deneyim" |
| `item:sound` | Ses/ses karşıtlığı | /ɪ/–/iː/ |
| `item:pattern` | Söz dizimi kalıbı | "How + adj + be + subj?" (How old are you?) |

### 4.2 Kenarlar

| Kenar | Anlam |
|---|---|
| `requires` | Önkoşul (A'yı öğrenmek için önce B "hatırlanıyor" olmalı) |
| `contains` | Cümle, kalıp/kelime/gramer içerir |
| `contrasts_with` | Karıştırılan çift (say/tell). Karışık çalışma tetikler (I-10). |
| `supports` | Öğe bir can-do'yu ya da görevi destekler |
| `variant_of` | Aynı anlamın başka biçimi (I am / I'm) |
| `example_of` | Cümle, bir gramer noktasının örneğidir |

### 4.3 Sıralama (sıradaki yeni öğe hangisi?)

Aday öğeler, `requires` önkoşulları en az "hatırlanıyor" düzeyinde olanlardır. Her adaya bir puan verilir:

```
puan = 3.0 · kişisel_ilgi      (Söyleyemediklerim'den geldiyse 1, ilgi alanı etiketi eşleşirse 0.5)
     + 2.0 · seviye_uyumu      (öğrencinin seviyesi veya bir üstü: 1, iki üstü: 0.3, altı: 0.5)
     + 1.5 · sıklık            (1 − log(sıra)/log(max_sıra))
     + 1.0 · haftalık_odak     (bu haftanın hata odağıyla ilgiliyse 1)
     + 0.5 · can_do_katkısı    (henüz kanıtlanmamış bir can-do'yu destekliyorsa 1)
     − 1.0 · benzerlik_cezası  (son 3 günde tanıtılan bir öğeyle contrasts_with ise 1)
```

**Ayrıntılar (motorda `Curriculum.next` ve `Curriculum.score`, F1-10):**

- **Adaylar:** kartı olmayan kelime anlamları ve kalıplar. Kaldırılmış (`deprecated`) öğe aday olmaz.
- **Seviye uyumu:** üç ve daha fazla seviye üstündeki öğe 0 alır.
- **Sıklık:** `max_sıra`, paketteki en büyük sıklık sırasıdır. Kalıpların sırası pakette verilir: sohbet çantasındaki sıralarıyla, aynı seviyedeki kelimelerin arasına eşit aralıklarla yerleştirilirler (`11` §5.1). Hiç sırası olmayan öğe 0,5 alır.
- **Eşit puanda** sıklık sırası küçük olan, sonra anahtarı küçük olan öndedir. Sonuç, paket listelerinin sırasından bağımsızdır.
- **Aynı gün kuralı:** Liste, birbiriyle `contrasts_with` olan iki öğeyi birlikte içermez; puanı yüksek olan kalır. Bugün tanıtılmış bir öğenin karşıtı da listede olmaz. Böylece planlayıcı listenin başından kaç öğe alırsa alsın kural sağlanır (`05` §8 madde 10).
- **Aynı kelimenin iki anlamı** da aynı gün tanıtılmaz (only: "sadece" ve "tek"). Gerekçe aynıdır: yeni öğrenilen iki benzer şey birbirini bozar.
- **v1:** Kişisel ilgi yalnızca Söyleyemediklerim'den gelen öğeler için 1'dir; ilgi alanı etiketi sonraya kaldı.

Ağırlıklar motor yapılandırmasındadır ve deneylerle ayarlanır. Son satır bilinçli bir tercih: karışan öğeler **aynı gün birlikte tanıtılmaz**, önce biri oturur, sonra karşıtlık çalışılır (Nation'ın "interference" uyarısı). Birlikte karışık çalışma ancak ikisi de öğrenildikten sonra başlar (I-10).

### 4.4 Taşıyıcı cümle kuralı (i+1)

Yeni bir kelime ya da kalıp, **içindeki diğer tüm kelimeleri bilinen** 1–2 taşıyıcı cümleyle tanıtılır. Paket her cümle için lemma listesini taşır. Motor, öğrencinin bildiği lemmalara göre uygun taşıyıcıyı seçer. Uygun taşıyıcı yoksa `gap_suggest` rotası anlık üretir, cümle doğrulanır ve kişisel öğe olarak kaydedilir.

**Ayrıntılar (motorda `CarrierPicker.pick`, F1-10):**

- **Adaylar, paketin o anlam için seçtiği cümlelerdir** (kelime anlamının `carriers` alanı). Cümlelerin `contains` bağları lemma ve sözcük türüyle eşleştirilir; aynı kelimenin başka bir anlamını ya da kullanımını da getirebilir. Bu yüzden taşıyıcı adayı sayılmaz.
- **Sıralama:** hedef dışındaki lemmalardan bilinmeyenlerin beklenen sayısı en az olan öndedir. Beklenen sayı = Σ (1 − lemmanın bilinme olasılığı) (`06` §2: kartla bilinen 1, diğerleri bant olasılığı). Eşitlikte kısa olan, sonra seviyesi düşük olan öndedir.
- **Uygunluk (i+1):** beklenen bilinmeyen sayısı ≤ 0,5.
- **Kalıp:** Cümlesi olmayan kalıp kendi taşıyıcısıdır.
- **v1:** Uygun taşıyıcı yoksa en iyi aday kullanılır. Hedef dışındaki küçük hatalar kartı düşürmez (`03` §0.5), bu yüzden başlangıçta tam uygun taşıyıcı bulunmaması öğrenmeyi durdurmaz. Anlık üretim sonraki faza kaldı.

## 5. Gramer ilerlemesi (taslak)

Aşağıdaki liste standart ELT ilerlemesidir. A0–A2 maddeleri **CEFR-J Grammar Profile** ile karşılaştırıldı. Bu profil her madde için Core Inventory ve English Grammar Profile (EGP) seviyelerini de verir; EGP, 1200'den fazla gramer maddesini öğrenci korpusundan seviyelendirir. Üç kaynağın da A1 dediği maddeler A1'e alındı: nesne zamirleri, and/but/because, sıklık zarfları, olumlu Past Simple ve was/were. Kaynakların ayrıştığı maddelerde standart ilerleme korundu. Bir seviyenin içindeki sıra CEFR-J alt seviyelerini (A1.1 → A1.3) izler. Her maddede Türkçe konuşanlar için bilinen zorluk notu yer alır.

### A0–A1
- **be** (am/is/are): olumlu, olumsuz, soru.
- **Özne zamirleri:** he/she/it. *TR: tek "o" var, he/she karışır.*
- **a/an/the** (temel). *TR: artikel yok; en sık hata.*
- Çoğul -s; this/that/these/those.
- **there is/are** ve **have/has got**. *TR: ikisi de "var"; karışır.*
- **Present Simple** ve 3. tekil **-s**; do/does ile soru ve olumsuz. *TR: -s düşer, "Does he works?" hatası.*
- Sıklık zarfları (always, usually, never…) ve cümledeki yerleri.
- can/can't; emir kipi; sahiplik (my/your…, 's).
- **Nesne zamirleri** (me, him, us, them): emir kipi ve temel kalıplarla birlikte gelir (Help me. Tell me.). *TR: "onu" üçüne birden karşılık gelir; him/her/it karışır.*
- Yer ve zaman edatları **in/on/at**. *TR: hal ekleri tek biçimde, edat seçimi zor.*
- Wh- soruları; **How old are you?** *TR: "Kaç yaşındasın?" → "How many years…" hatası.*
- Bağlaçlar: and, but, because.
- Present Continuous (şu an); like + -ing.
- **Past Simple girişi:** was/were ve olumlu cümle (düzenli -ed; went, had, saw gibi sık düzensizler).

### A2
- **Past Simple:** did ile soru ve olumsuz; düzensiz fiillerin genişlemesi. *TR: "I didn't went" hatası.*
- going to / will (plan, tahmin).
- Karşılaştırma: -er/-est, more/most.
- Sayılabilir/sayılamaz; some/any, much/many, a lot of.
- have to / should / must (temel).
- **Present Simple ↔ Present Continuous** karşıtlığı.
- Bağlaçlar: so, when, then.
- **Present Perfect girişi** (ever/never, just). *TR: doğrudan karşılığı yok.*
- Fiil + to/-ing (want to, enjoy -ing).

### B1
- **Present Perfect ↔ Past Simple** karşıtlığı; for/since.
- Past Continuous (while/when); used to.
- 1. ve 2. tip koşul cümleleri.
- **Relative clauses** (who/which/that/where). *TR: sıfat-fiillerle kurulur (-en, -dığı); yapı ters.*
- Edilgen (present/past simple).
- might/may/could (olasılık).
- Dolaylı anlatım (said/told). *say/tell karşıtlığı.*
- Sık gerund/infinitive kalıpları; en sık 50 phrasal verb.
- although / however / so that / in order to.
- Artikellerde derinleşme (genel anlam, sıfır artikel).

### B2
- Present Perfect Continuous; Past Perfect.
- 3. tip ve karma koşul cümleleri; wish / if only.
- Tüm zamanlarda edilgen; have something done.
- Çıkarım kipleri (must have / can't have).
- Tanımlamayan relative clauses; kısaltılmış relative clauses.
- Tam dolaylı anlatım ve aktarma fiilleri.
- Söylem belirleyicileri (nevertheless, whereas, on the other hand).
- Eşdizimler; resmî ve gayriresmî üslup; cleft cümleler (It was X that…).

### C1–C2
- Devrik yapı (Rarely have I…), öne alma.
- Kaçamaklı dil (hedging: it would seem…).
- İsimleştirme; eksiltme/yerine koyma; subjunctive.
- İnce kiplik farkları; deyimler.
- Türe özgü metin (rapor, akademik, iş).
- Pragmatik (nezaket stratejileri).

## 6. Telaffuz ilerlemesi (Türkçe konuşanlar, anlaşılırlık önceliği)

Öncelik, anlaşılırlığı en çok etkileyen özelliklerdedir (Levis, 2005; Jenkins, 2000). Her özellik için önce **algı** (duyup ayırt etme, HVPT), sonra **üretim** (gölgeleme, tekrar) çalışılır.

| Öncelik | Özellik | Türkçe kaynaklı sorun | Örnek karşıtlık |
|---|---|---|---|
| 1 (A0–A1) | Ünlü niteliği/uzunluğu: /ɪ/–/iː/, /ʊ/–/uː/, /æ/–/e/, /ʌ/ | Türkçede uzunluk karşıtlığı yok | ship/sheep, full/fool, bad/bed |
| 1 | /w/–/v/ | Türkçede /w/ yok | west/vest, wine/vine |
| 1 | Sonda ötümlü ünsüz: /b d g z v/ | Sonda ötümsüzleşme (kitap) | bad/bat, dog/dock, prize/price |
| 1 | Başta ünsüz kümesi | Araya/başa ünlü ekleme | station ≠ "istasyon", school, sport |
| 1 | -ed ve -s sonekleri | Düşürme ya da fazladan hece | worked /t/, played /d/, wanted /ɪd/ |
| 2 (A2–B1) | Kelime vurgusu | Türkçede vurgu çoğunlukla sonda | PHOtograph / phoTOgraphy |
| 2 | Zayıf biçimler, schwa | Her heceyi tam söyleme | to /tə/, of /əv/, can /kən/ |
| 2 | /ŋ/, koyu l | — | sing, full |
| 2 | /θ ð/ | /t d/ ya da /s z/ ile değiştirme | think/tink, this/dis |
| 3 (B2+) | Bağlı konuşma (linking, elision, asimilasyon) | Kelimeleri ayrı ayrı söyleme | "want to" → /wɒnə/ |
| 3 | Ritim ve tonlama | Hece zamanlı ritim | soru ve liste tonlaması |

## 7. Konuşma görevleri

### 7.1 Sabit (anchor) görevler

Her ay, her seviyede **aynı** kalır. Aylar arası karşılaştırma yapılabilsin diye:

- **ANC-1:** Kendini tanıt: kim olduğun, ne iş yaptığın, nerede yaşadığın, neyi sevdiğin.
- **ANC-2:** Dün ne yaptın? Sabahtan akşama anlat.
- **ANC-3:** Son zamanlarda yaşadığın bir sorunu ve nasıl çözdüğünü (ya da çözemediğini) anlat.

### 7.2 Seviye görevleri (döngüsel; örnekler)

| Seviye | Görevler |
|---|---|
| A1 | Günlük rutinin; ailen; evin; en sevdiğin yemek; bir kafede sipariş (rol) |
| A2 | Geçen tatil; hafta sonu planın; bir yere nasıl gidilir; mağazada ürün iadesi (rol); bir arkadaşını tarif et |
| B1 | İzlediğin bir filmi anlat ve ne düşündüğünü söyle; işte yaşadığın bir sorunu açıkla; bir karar için artılar/eksiler; otelde şikâyet (rol); doktorda derdini anlat (rol) |
| B2 | Tartışmalı bir konuda görüş savun; bir süreci adım adım açıkla; maaş/fiyat pazarlığı (rol); bir makaleyi özetle (aracılık) |
| C1–C2 | Kısa sunum; ikna edici konuşma; soyut konular; dolaylı ve nazik reddetme (rol); teknik bir konuyu uzman olmayana anlat (aracılık) |

İş görevleri, kullanıcı profilindeki ilgi alanı etiketlerine göre kişiselleştirilir (ör. yazılım: bir hatayı ekibe anlatmak, bir gecikmeyi açıklamak).

## 8. Can-do seçimi

Paket, Companion Volume'dan şu ölçeklerdeki tanımları içerir (her seviye için):

- **Konuşma ve etkileşim:** genel sözlü etkileşim, sohbet, gayriresmî tartışma, mal ve hizmet edinme, bilgi alışverişi.
- **Sözlü üretim:** deneyim anlatma, ses denetimi (phonological control).
- **Alma:** genel dinleme, bilgi için okuma.
- **Yazma:** yazışma.
- **Aracılık:** belirli bilgiyi aktarma, metni açıklama.
- **Stratejiler:** telafi.

Tanımların tam metni pakete kopyalanmaz; yalnızca kod ve kendi kısa Türkçe özetimiz tutulur (lisans: `10-content-pipeline.md` §2). Her görev, desteklediği can-do kodlarını taşır. Can-do kanıtı görev sonuçlarından birikir (`04-learner-model.md`).

## 9. Başlangıç kapsamı (paket sürümlerine göre)

Sayılar hedeftir; içerik hattı üretir, doğrular ve raporlar.

| Paket | Faz | İçerik |
|---|---|---|
| `en@1` + `tr-en@1` | Faz 1 | A0–A2 çekirdeği:<br>• ~600 kelime anlamı (en sık ~1000 kelime ailesinden)<br>• ~600 taşıyıcı cümle<br>• 120 kalıplık sohbet çantası<br>• 40 gramer noktası<br>• 3 sabit + 20 seviye görevi<br>• X_Lex bankası (3 sürüm)<br>• ~30 Türkçe→İngilizce hata etiketi<br>• Türkçe açıklamalar ve karşılıklar |
| `en@2` | Faz 4 | Dinleme/okuma:<br>• 60 seviyeli okuma metni (A1–B1)<br>• 30 diyalog<br>• Minimal çift bankası: 15 karşıtlık × 20 kelime × 4 ses<br>• Dikte cümleleri |
| `en@3` + `tr-en@2` | Faz 5 | B1:<br>• +800 kelime anlamı<br>• +800 cümle<br>• 35 gramer noktası<br>• karşıtlık setleri<br>• 30 görev<br>• rol senaryoları<br>• yazma görevleri |
| `en@4` | Faz 6 | B2:<br>• +700 kelime anlamı<br>• eşdizimler<br>• 30 gramer noktası<br>• aracılık görevleri<br>• yarı otantik dinleme |
| `en@5` | Faz 7 | C1–C2: otantik içerik iş akışları (altyazı, makale, podcast), kişisel korpus madenciliği, türe özgü yazma |
| `de@0` | Faz 7 | Dilden bağımsızlık kanıtı: A1 örnek paketi (~50 öğe, 3 görev) |

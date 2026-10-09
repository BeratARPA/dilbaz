# 06 — Değerlendirme ve Ölçüm

"Gerçekten öğreniyor muyuz?" sorusunun cevabı buradan çıkar. Dilbaz'da değerlendirme **bilgi verir, not vermez**:

- Geçti/kaldı yoktur.
- Ceza yoktur.
- Her test bir davettir (I-14).
- Sonuçlar kişinin **kendi geçmişiyle** karşılaştırılır.

## 1. İlkeler

1. **Gecikmeli ve yardımsız:** Test sırasında ipucu, sözlük, çeviri yok.
2. **Karşılaştırılabilir:** Sabit (anchor) görevler, aynı ayarlar ve aynı işleme hattı her ay aynıdır.
3. **Belirsizlik görünür:** Tek sayı yerine aralık ve eğilim gösterilir.
4. **Otomatik ama denetlenebilir:** Tüm ham veriler (ses, transkript, işaretlemeler) saklanır. Kullanıcı her ölçümün nereden geldiğini görebilir ve itiraz edebilir ("bu hata değil" → işaretleme incelemeye düşer).

## 2. Seviye testi (A24) — ilk açılışta, ~12–15 dk, atlanabilir

### Bölüm 1 — Kelime: X_Lex tipi evet/hayır testi (Meara & Milton)
- 120 madde: en sık 5000 lemmanın her bin kelimelik bandından 20 gerçek kelime (100) + 20 uydurma kelime.
- **Puan:** gerçek kelimeye her "biliyorum" +50, uydurma kelimeye her "biliyorum" −250. Sonuç [0, 5000] aralığına sınırlanır. Bant başına kabul oranı ayrıca saklanır.
  - Genel biçimi: her bandın kabul oranından yanlış alarm oranı çıkarılır, 1000 ile çarpılır ve bantlar toplanır. 20'şer kelimelik bantlarda ve 20 uydurma kelimede bu, +50 / −250 ile aynıdır.
  - Motorda: `XlexResult.of` (sonuç `assessments.results` içine `score`, `band_rates`, `false_alarm_rate` olarak yazılır).
- **Güvenilirlik:** Uydurma kelimelerde "biliyorum" oranı %25'in üstündeyse sonuç "tahmine dayalı" işaretlenir ve güven `low` olur.
- **Sürümler:** Üç eşdeğer sürüm (A/B/C) vardır, yeniden testlerde sırayla kullanılır.
- **Seviyeye çevirme:** Puan, paketin `placement.vocab_levels` aralıklarıyla (`02` §2, Milton) seviyeye çevrilir. İki aralığın arasında kalan puan (ör. 2.600: A2 ile B1 arası) iki seviyeyi birden kapsar. Aralıklar dile özgü olduğu için motor sabiti değil, paket verisidir (I-15).
- **Kelime listesi:** Bantlar, İngilizce paketin sıklık listesinden gelir. Uydurma kelimelerin üretimi `10-content-pipeline.md` §5.3'te.

### Bölüm 2 — Gramer tanıma (uyarlanır, 12–15 madde)
- Doğru biçimi seçme: boşluklu bir cümle ve üç seçenek. Seçeneklerin yanında "Emin değilim" vardır; tahmin yerine onu seçmek ölçümü temizler ve yanlış sayılır.
- A2 maddesiyle başlar. Doğru cevapta bir üst seviyeden, diğer her cevapta bir alt seviyeden madde gelir; seviyesinde madde kalmamışsa en yakın seviyeden (eşitlikte alttakinden). Bir seviyenin maddeleri tohumlu rastgele sırayla çekilir, hiçbiri iki kez sorulmaz.
- **Uzunluk:** En az 12, en çok 15 madde. 12. maddeden sonra son 6 madde iki komşu seviye içinde kaldıysa test oturmuş sayılır ve biter.
- **Seviye kararı:** En az 2 maddesi sorulan seviyede doğruların payı ≥ 2/3 ise seviyeye ulaşılmış, ≤ 1/3 ise ulaşılmamış sayılır; arası kararsızdır.
- **Tahmin (seviye merdiveni, dikte için de aynı):** Alt uç, ulaşılmayan ilk seviyenin altındaki en yüksek ulaşılmış seviyedir; hiçbiri yoksa sorulan en alt seviyenin bir altı. Üst uç, ulaşılmayan ilk seviyeye kadar sorulmuş en yüksek seviyedir. Sorulan en üst seviyeye ulaşıldıysa test yukarısını ölçemez ve aralık ölçeğin sonuna açık kalır ("B2 ve üstü"). Seviyeler üst üste kurulur: ulaşılmayan bir seviyenin üstünde şansla doğru cevaplanan seviye sayılmaz.
- **Banka (`en@1`):** A1 (A0 yapılarıyla), A2, B1 ve B2 için 12'şer, toplam 48 madde. A0–A2 maddeleri paketin gramer kodlarından birini sınar; B1–B2 maddelerinin kodu henüz yoktur (paketin gramer noktaları A2'de biter). Çeldiriciler Türkçe konuşanın tipik hatalarıdır (`02` §5). Her madde, cevabı görmeden yapılan bağımsız bir kontrolde tek doğru seçenekli bulunmadan bankaya girmez (`10` §5.3).

### Bölüm 3 — Dinleme: 5 dikte cümlesi
- Cümleler A1'den B2'ye zorlaşır. `en@1`'in cümleleri A2'de bittiği için sürüm başına 2 A1 ve 3 A2 cümlesi vardır; dinleme tahmini bu yüzden en çok "A2 ve üstü" diyebilir. Seviyeler içinde de kısadan uzuna gider.
- Her cümle en fazla iki kez dinlenir, normal hızda. Yazma alanı cümle dinlenince açılır; klavyenin otomatik düzeltmesi kapalıdır.
- Kelime hata oranı (WER) = eksik, fazla, değişmiş ya da yeri değişmiş kelime sayısı / cümlenin kelime sayısı (en çok 1). Karşılaştırma paketin normalizasyonuyla yapılır (büyük harf, noktalama, kısaltmalar).
- **Yazım hatası sayılmaz:** Dikte duymayı ölçer. Dilin bir kelimesi olmayan (biçim tablosunda bulunmayan) ama beklenen kelimeye 4–7 harfte 1, 8+ harfte 2 düzenleme uzakta olan yazım hata değil, yazım kaymasıdır. Dilin gerçek bir kelimesi hatadır: öğrencinin duyduğu odur (cat/cats, walk/walked).
- Bir seviyenin cümleleri birlikte değerlendirilir: toplam hata / toplam kelime ≤ %15 ise seviyeye ulaşılmıştır (`04` §7). Tahmin, gramerdeki seviye merdiveniyle çıkar.
- Kısaltma, rakam ya da özel ad içeren cümleler dikteye alınmaz: "don't", "2" ya da "Tom" yazmak yazım bilgisidir.
- Ses alınamazsa (bağlantı yok) ya da öğrenci o an dinleyemiyorsa bu bölüm atlanabilir; test kalan bölümlerle kaydedilir.

### Bölüm 4 — Başlangıç kaydı (isteğe bağlı, 1 dk)
- ANC-1 görevi kaydedilir. **Seviye puanlamasına girmez.** Amacı "önce/sonra" karşılaştırmasının ilk kaydı olmaktır.
- **Durum (F1-19):** Seviye testi sonucunda isteğe bağlı "Başlangıç kaydı (1 dk)" düğmesi var. Kayıt ANC-1'dir: 30 sn hazırlık, en çok 1 dakika, aylık testin işleme hattı.
  - Ayrı bir `monthly_speaking` değerlendirmesi olarak saklanır (`results.baseline = true`); ayın testi sayılmaz.
  - Yapılmadıysa ilk aylık testin ANC-1 kaydı başlangıç olur.
  - Düğme yalnızca kursta henüz konuşma kaydı (başlangıç ya da aylık test) yoksa görünür. İlk kayıt bir kez olur; yeniden testte de böyledir.

### Çıktılar
- **Bölümler ve bırakma:** Bölümler sırayla gelir (kelime, gramer, dikte). Test her an bırakılabilir: bitmiş bölümler kaydedilir, yarım kalan bölüm kaydedilmez. Kelime bölümü bitmeden bırakılan testten hiçbir şey kaydedilmez. Test sırasında hiçbir cevap doğru ya da yanlış diye gösterilmez.
- **Müfredatın başlangıcı:** Kelime ve gramer seviyelerinin alt uçlarından düşük olanı. Yeni öğeler ikisine birden dayanır, bu yüzden zayıf olan yol gösterir. Dinlemenin kendi tahmini vardır, başlangıcı değiştirmez. İkisi de yoksa öğrencinin seçtiği seviye kalır.
- **Kayıt:** Bir `assessments` satırı (`kind = placement`); `results` ham cevapları taşır (§1.4): `version`, `seed`, `xlex` (`score`, `band_rates`, `false_alarm_rate` ve her kelimenin cevabı), `grammar.steps` (her madde, seviyesi, seçilen seçenek, doğru mu), `dictation.sentences` (yazılan metin, dinleme sayısı, kelime, hata, yazım kayması), `duration_ms`. `level_estimates` sütunu ve kursun `level_estimates` alanı ölçülen becerileri (`vocabulary`, `grammar`, `listening`) ve `overall` (başlangıç, `source: placement`) ile güncellenir; ölçülmeyen beceriler olduğu gibi kalır. `courses.vocab_estimate` = X_Lex puanı.
- **Gösterim:** Sonuç ekranında not ya da puan yoktur: başlangıç seviyesi, beceri başına seviye ya da aralık ("A1–A2", "A2 ve üstü") ve tanınan kelime sayısı (yaklaşık). Tahmine dayalı X_Lex sonucunda bu açıkça yazılır. Test Bugün ekranında davet olarak durur, "Şimdi değil" ile bir sonraki açılışa kadar kalkar (I-14).
- Beceri başına başlangıç seviye tahmini (güven `low`)
- Tanıma kelime boyutu
- Müfredat başlangıç noktası
- **Kişisel kapsama için başlangıç bilgisi:** Kartı olmayan bir lemmanın bilinme olasılığı, o lemmanın bandındaki kabul oranı (yanlış alarmla düzeltilmiş) olarak alınır.
  - Düzeltme: bant kabul oranı − yanlış alarm oranı, [0, 1] aralığına sınırlanır. Böylece bant olasılıklarının toplamı X_Lex puanını verir.
  - Bant, lemmanın paket sözlüğündeki sıklık sırasından gelir (1–1000 → 1. bant). 5. bandın ötesindeki lemmalar son bandın olasılığını alır.
  - Paket sözlüğünde olmayan lemma bilinmiyor sayılır (0). Hiç test yapılmadıysa yalnızca kartlar sayılır.
- **Kişisel kapsama** (motorda `LemmaKnowledge`). Bir metnin kişisel kapsaması şöyle hesaplanır:
  - Kartla bilinen lemmalar (bir kelime anlamı üretimde ≥ `recallable` ya da alıcıda `recognized`) → 1. Bilinen bir kalıp, içindeki kelimeleri tek başına bilinir yapmaz.
  - Diğer lemmalar → bant olasılığı
  - Kapsama = bu değerlerin ortalaması
  
  Kart verisi arttıkça olasılıklar gerçek kanıtla değişir.

### Yeniden test (F1-25)
- **Nereden:** Ayarlar → Çalışma → "Seviye testi". Satır, cihazda test varsa görünür. İlk test yapılmadıysa da buradan açılır; Bugün daveti yalnızca ilk test içindir.
- **Ne zaman:** İstenildiği zaman, bekleme süresi yok. Kullanıcı istedi (2026-10-09): ilk testinde ses çalmadığı için dikte bölümü atlanmıştı.
- **Sürüm:** Kelime listesi ve dikte cümleleri sırayla değişir (A → B → C → A; sıra kurstaki test sayısından çıkar). Gramer bankası tektir. Maddeler her testte yeni tohumla çekilir, bu yüzden bazıları yeniden gelebilir.
- **Sonuç:**
  - Yeni bir `assessments` satırı yazılır, öncekiler değişmez (I-03).
  - Bitirilen bölümlerin tahminleri kurstakilerin yerine geçer. `courses.vocab_estimate` yeni X_Lex puanıdır. Kişisel kapsama en son testin X_Lex sonucunu kullanır.
  - Bitirilmeyen bölümün önceki tahmini kursta kalır ve müfredatın başlangıcında sayılmaya devam eder: zayıf olan yol gösterir. Örnek: ilk testte gramer A1, ikincide gramer yapılmadan kelime B1 → başlangıç A1. Motorda: `PlacementOutcome.of(earlier: …)`.
  - Kartlar, denemeler ve geçmiş değişmez. Müfredat seviyesi yalnızca yeni öğelerin seçimini etkiler (`02` §4.3).
- **Gösterim:** Genel bakışta "Bu testi daha önce yaptın…" notu çıkar. Sonuçtaki not "Bu ilk ölçüm…" yerine "Bu da kaba bir tahmin. Buradaki sonuçlar öncekilerin yerine geçti…" olur.

## 3. Aylık konuşma testi (A23) — ayın 1–7'si davet, ~15 dk

### 3.1 İçerik
- **3 sabit görev:** ANC-1, ANC-2, ANC-3 (`02` §7.1). Ayarlar **her ay aynıdır**: 30 sn hazırlık, kalıp ipucu yok, en fazla 2 dk (A1'de 1 dk).
- **2 seviye görevi:** mevcut seviyeden, döngüsel. Seviyenin iskele ayarlarıyla yapılır.
- Kayıt öncesi mikrofon seviye kontrolü yapılır. Sessiz ortam ve mümkünse aynı cihaz önerilir.

### 3.2 İşleme hattı

```text
ses ─▶ ASR (kelimesi kelimesine, dolgu sözcükleri açık, kelime zamanları)   [08-speech.md]
    ─▶ deterministik akıcılık ölçümleri (zamanlardan)
    ─▶ speaking_annotate × 2 bağımsız çağrı (cümlecik/AS-birimi, hatalar, etiketler,
       yapılar, dolgu/onarım, görev sonucu)                                  [07-ai-tutor.md]
    ─▶ uyum kontrolü: |EFC₁ − EFC₂| > 0,10 ya da görev sonucu farklı → 3. çağrı,
       sayısal ölçümlerde medyan, kategorilerde çoğunluk
    ─▶ doğruluk/karmaşıklık ölçümleri (işaretlemelerden, deterministik)
    ─▶ rapor + kalıcı kayıt (assessments, recordings.is_assessment = true)
```

**v1 (F1-19):** Aylık test tek işaretlemeyle çalışır. Çift işaretleme ve uyum kontrolü, eval sonuçları ve kota görüldükten sonra eklenir. `recordings.annotation`, işaretlemeleri `runs` dizisinde tutar; v1'de tek bir eleman vardır.

Neden iki çağrı: Kullanılan modelde örnekleme ayarları (temperature) kapalıdır. Tutarlılık, yapılandırılmış çıktı, ayrıntılı rubrik, örnekler ve çift işaretlemeyle sağlanır.

### 3.3 Ölçüm tanımları

Konuşma performansı, SLA araştırmasının standart üç boyutunda ölçülür: karmaşıklık, doğruluk, akıcılık (CAF; Housen & Kuiken, 2009; Skehan, 2009).

**Akıcılık** (sessiz duraklama eşiği 250 ms; De Jong & Bosker, 2013):

| Ölçüm | Tanım |
|---|---|
| `speech_rate` | kelime ÷ toplam süre (dk). Baştaki ve sondaki sessizlik hariç. |
| `articulation_rate` | kelime ÷ (toplam süre − sessiz duraklamalar) |
| `mlr` (ortalama akış uzunluğu) | İki ≥ 250 ms duraklama arasındaki ortalama kelime sayısı |
| `long_pauses_per_min` | ≥ 1 sn sessiz duraklama sayısı ÷ dk |
| `mid_clause_pause_ratio` | Cümlecik içindeki duraklamalar ÷ tüm duraklamalar. Cümlecik ortası duraklama, düşük akıcılığın daha iyi göstergesidir. |
| `filled_pauses_per_min` | İngilizce dolgu (uh, um, er) ÷ dk |
| `l1_fillers_per_min` | Türkçe dolgu (ıı, şey, yani) ÷ dk. Ayrı raporlanır. |
| `repairs_per_min` | Kendini düzeltme ve tekrar ÷ dk |

**Doğruluk:**

| Ölçüm | Tanım |
|---|---|
| `efc_ratio` | Hatasız cümlecik ÷ toplam cümlecik |
| `errors_per_100w` | Toplam ve etiket bazında |

**Karmaşıklık:**

| Ölçüm | Tanım |
|---|---|
| `mean_clause_length` | Cümlecik başına kelime |
| `subordination` | AS-birimi başına cümlecik (Foster, Tonkyn & Wigglesworth, 2000) |
| `mtld` | Sözcük çeşitliliği (McCarthy & Jarvis, 2010). ≥ 100 kelime yoksa "yetersiz veri". |
| `connector_types` | Paketteki bağlaç listesinden kullanılan farklı bağlaç sayısı |
| `beyond_2k_share` | 2000 sıklık bandı dışındaki kelimelerin oranı |

**Görev:** `outcome` = `done` | `partial` | `not_done`.

**Motorda (F1-19):** `SpeechMetrics.of` (`08` §6).
- Veri yetmeyen ölçüm boş kalır, sayı uydurulmaz: işaretleme yoksa cümlecik ölçümleri, 100 kelimeden azsa `mtld`, sıralı kelime yoksa `beyond_2k_share`.
- `beyond_2k_share`, sıklık sırası bilinen kelimeler arasındaki oranı verir. Sözlükte olmayan kelimeler (isimler, sayılar) sayılmaz. Birden çok lemmaya giden biçim en iyi sırayı alır.
- `connector_types` paketin bağlaç listesindeki her ifadeyi bir kez sayar; çok kelimeli bağlaçlar da sayılır.
- `errors_by_tag` etiket başına 100 kelimedeki hatayı verir.

### 3.3a v1 (F1-19)
- **Görevler** (`monthlyTasks`, motor):
  - Önce sabit görevler sırayla: 30 sn hazırlık, başlangıç yok, A0–A1'de 1, diğer seviyelerde 2 dakika.
  - Sonra seviyenin görevlerinden 2'si, seviyenin iskeleleriyle.
  - Seviye görevleri anahtar sırasıyla aydan aya döner. Seviyede görev yoksa en yakın alt seviye alınır.
- **Akış:**
  - Tanıtım ve mikrofon denemesi (ses düzeyi çubuğu; hiçbir şey saklanmaz).
  - Görevler sırayla. Her kayıt arka planda işlenir, öğrenci sıradaki göreve geçer: transkript, `speaking_annotate` (`assessment: true`, effort high, tek işaretleme), ölçümler.
  - Hepsi bitince rapor.
- **Kayıt:**
  - Kayıtlar `is_assessment = true` ve testin kimliğiyle saklanır.
  - Test bir `monthly_speaking` satırıdır: `results` = `{month, baseline, complete, tasks: [{task_ref, recording_id, anchor, metrics, clauses, error_free}]}`.
  - Yarıda bırakılan test, kaydedilen görevlerle `complete: false` saklanır; işleme arka planda sürer.
  - Oturum `output` koluna yazılır.
- **Rapor (v1):**
  - Her görev için konuşma süresi ve kelime sayısı, dakikada kelime, dakikada uzun duraklama, "10 cümleciğin 7 tanesi hatasız" (yüzde değil, sayı; I-04).
  - Sabit görevlerde geçen ayın aynı değerleri yanında yazar.
  - "Bu ölçümler nedir?" açıklamaları var; not ve renk yok.
  - Önce/sonra dinleme ve eğilimler F1-20'de.

### 3.4 Rapor
- **Önce/sonra dinleme:** ilk kayıt, geçen ay ve bu ay aynı sabit görevde yan yana.
- Her ölçümün aylık eğilimi. Sabit görevler karşılaştırmanın esasıdır; seviye görevleri ayrı gösterilir, çünkü zorlukları değişir.
- Öne çıkanlar olumlu ve somut yazılır. Örnek: "Uzun duraklamaların dakikada 6'dan 3'e indi."
- Kalıcı hatalar ve haftalık odak önerisi.
- Görevlerden gelen can-do kanıtları.
- **Not verilmez.** Bir ölçüm kötüleşmişse nötr bir açıklama gösterilir. Örnek: "Bu ay konuşmaların daha uzun ve karmaşıktı; bu tür dönemlerde akıcılık geçici olarak düşebilir."

## 4. Diğer periyodik ölçümler

| Ölçüm | Sıklık | İçerik |
|---|---|---|
| Kelime yeniden testi | 3 ayda bir | X_Lex (sürüm döngüsü) |
| Yazma örneği | B1'den itibaren ayda bir | ~150 kelime, tür döngüsü (e-posta / anlatı / görüş). Çift işaretleme. Ölçümler: EFC, hata/100 kelime, MTLD, ortalama cümle uzunluğu, bağlaç çeşitliliği. |
| Dinleme mini testi | Ayda bir | Seviyenin bir üstünden 5 dikte cümlesi + 1 kısa dinleme metni. WER ve anlama. |
| Dış kalibrasyon | 3 ayda bir (isteğe bağlı) | EF SET (okuma + dinleme), OpenEnglish seviye/öğretmen notları (elle giriş), ileride resmî sınav |

## 5. Güvenilirlik ve geçerlilik

| Risk | Önlem |
|---|---|
| Ses tanıma öğrencinin hatasını "düzeltir" (araştırmalar özellikle Whisper'da bunu gösteriyor) | Kelimesi kelimesine çalışan ASR, karşılaştırma testiyle seçilir (`08-speech.md` §3). Transkript kullanıcıya gösterilir, düzeltilebilir. |
| LLM işaretlemesi değişken | Çift işaretleme + uyum kontrolü, kapalı etiket listesi, eval seti (`07` §8) |
| Ortam/cihaz farkı | Aynı cihaz önerisi, mikrofon kontrolü, sabit ayarlar |
| Görev etkisi (zor konu → düşük akıcılık) | Sabit görevler ayrı raporlanır |
| Az veri | Eşiklerin altında "yetersiz veri" gösterilir, sayı uydurulmaz |
| Sistematik sapma | Dış kalibrasyonla karşılaştırma; fark > 1 seviye ise eşikler gözden geçirilir |

## 6. Sunum kuralları (UI)

- Puan, not, kırmızı renk, "başarısız" kelimesi kullanılmaz.
- Her grafikte "bu nedir?" açıklaması vardır. Gösterilen şey bir eğilimdir, tek bir sayıya odaklanılmaz.
- Test daveti reddedilebilir. Reddetmenin hiçbir sonucu yoktur (I-14).

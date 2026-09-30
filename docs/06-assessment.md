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
- **Kelime listesi:** Bantlar, İngilizce paketin sıklık listesinden gelir. Uydurma kelimelerin üretimi `10-content-pipeline.md` §5.3'te.

### Bölüm 2 — Gramer tanıma (uyarlanır, 12–15 madde)
- Dilbilgisel doğruluk yargısı ya da doğru biçimi seçme.
- A2 maddesiyle başlar. Doğru cevapta seviye yükselir, yanlışta düşer.
- Maddeler seviye etiketli gramer noktalarından gelir.

### Bölüm 3 — Dinleme: 5 dikte cümlesi
- Cümleler A1'den B2'ye zorlaşır.
- Cümle başına kelime hata oranı (WER) hesaplanır ve dinleme çözme tahmini yapılır.

### Bölüm 4 — Başlangıç kaydı (isteğe bağlı, 1 dk)
- ANC-1 görevi kaydedilir. **Seviye puanlamasına girmez.** Amacı "önce/sonra" karşılaştırmasının ilk kaydı olmaktır.

### Çıktılar
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

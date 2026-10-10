# 04 — Öğrenci Modeli

Öğrenci modeli, sistemin "bu kişi şu an neyi, ne kadar sağlam biliyor" tahminidir. Tasarım ilkesi şudur: **her sayı bir kanıta dayanır, belirsizlik gizlenmez** (I-04). Model tamamen `dilbaz_engine` içinde, dilden bağımsız olarak hesaplanır (I-15).

## 1. Katmanlar

| Katman | İçerik | Kaynak |
|---|---|---|
| L1 — Kart hafızası | Her kart için FSRS durumu (S, D, R, due, reps, lapses, state) | `attempts` → FSRS |
| L2 — Öğe kanıt düzeyi | new → learning → recallable → durable → transferred | L1 + serbest üretim |
| L3 — Can-do kanıtı | none → attempted → shown → established | Görev sonuçları |
| L4 — Hata profili | Etiket başına oran, eğilim, kalıcı hatalar, haftalık odak | Serbest üretim, dikte, gölgeleme |
| L5 — Seviye tahmini | Beceri başına CEFR aralığı + güven | L2–L4 + testler |
| L6 — Tercihler | Zaman bütçesi, çıpa saatleri, sessiz mod, ilgi alanları, iskele ayarları | Kullanıcı |

**Tek gerçek kaynak:** değiştirilemez `attempts` günlüğü (I-03). L1–L5 bu günlükten hesaplanan **projeksiyonlardır** ve her an yeniden üretilebilir.

## 2. L1 — Kart hafızası (FSRS)

- Kart = (öğrenci, öğe, mod). Modlar:

  | Mod | Tür | Etkinlik |
  |---|---|---|
  | `speak` | üretim | A01 |
  | `type` | üretim | A02 |
  | `cloze` | üretim | A04 |
  | `contrast` | üretim | A08 |
  | `recognize_audio` | alıcı | A03 |
  | `dictation` | dinleme | A05 |

- Her deneme sonunda FSRS zamanlayıcısı otomatik puanla (bkz. `03-activities.md` §0.3) çalışır. Kartın **yeni durumu denemeyle birlikte** saklanır (`attempts.card_state_after`).
- **Sayaçlar:** `package:fsrs` tekrar saymaz, sayaçları motor tutar. `reps` her tekrarda artar. `lapses` yalnızca review durumundaki kart Again aldığında artar; öğrenme adımlarındaki Again unutma sayılmaz.
- **Tekrar oynatma (replay):** Parametre değişikliği ya da bozulma durumunda kart durumları denemelerden baştan hesaplanır (`SrsScheduler.replay`). Aralık bulanıklaştırma (fuzz) tekrar oynatmada **kapalıdır**. Canlı kullanımda açıktır ve sonucu `card_state_after` olarak saklandığı için senkron deterministiktir.
  - Fuzz yalnızca vade tarihini kaydırır. Sonraki tekrar vadeye değil tekrar zamanlarına bakar. Bu yüzden aynı parametrelerle yeniden oynatılan kartın S, D, durum ve sayaçları canlıdakiyle aynıdır, yalnızca `due` farklı olabilir (motor testi).
- **Varsayılanlar:**
  - Hedef hatırlama: 0,90. Gelişmiş ayarlarda 0,85–0,95 arası seçilebilir; seçilirken tahmini günlük tekrar süresi gösterilir.
  - Parametreler: paketin FSRS varsayılanları.
- **Kişisel optimizasyon:**
  - Bir mod grubunda (üretim / alıcı / dikte) yeterli veri birikince parametreler optimize edilir. py-fsrs, **farklı günlere yayılmış en az 512 tekrar** olmadan varsayılan parametreleri döndürür; bu yüzden eşik budur.
  - Nasıl: `tools/fsrs/optimize.py` (py-fsrs Optimizer) dışa aktarılan tekrar günlüğüyle çalışır, sonuç `courses.fsrs_params[mod_grubu]` alanına yazılır. Dart paketinde optimize edici yoktur. Motor bu alanı `SrsConfig.forCourse` ile okur; ağırlığı olmayan grup varsayılanları kullanır.
  - Ayda bir ya da tekrar sayısı iki katına çıktığında yeniden optimize edilir. Değişiklik deney olarak izlenir (`16-experiments.md` E5).

## 3. L2 — Öğe kanıt düzeyleri

Bir öğenin **üretim** düzeyi, üretim modlarındaki kartlarının en iyisinden hesaplanır:

| Düzey | Kod | Koşul | Arayüzde |
|---|---|---|---|
| 0 | `new` | Kart yok | — |
| 1 | `learning` | Kart var, ama `recallable` koşulu sağlanmıyor (learning/relearning durumu ya da review durumunda S < 7 gün) | "Öğreniliyor" |
| 2 | `recallable` | Review durumunda ve stabilite S ≥ 7 gün | "Hatırlıyor" |
| 3 | `durable` | S ≥ 30 gün **ve** son 90 günde, hemen önceki tekrardan en az 21 gün sonra yapılmış, ilk denemede ve ipucusuz başarılı bir tekrar var | "Kalıcı" |
| 4 | `transferred` | Düzey ≥ 2 **ve** serbest üretimde (A11, A13, A15, A20, A21) **en az 2 farklı günde** hatasız kullanım | "Kullanıyor" |

- **Serbest üretimde kullanım tespiti:** Transkriptteki lemma/kalıp eşleşmesi paketteki lemma listeleriyle yapılır. Eşleşen parçanın üzerinde hata etiketi yoksa hatasız sayılır.
- **Kanıt esası (I-04):** Eşikler kartın o anki stabilitesiyle değil, **son kanıtlı tekrardaki stabiliteyle** karşılaştırılır. Kanıtsız biten tekrarlar (LLM'siz `uncertain`, hedefsiz doğru cevap; `03` §0.3) zamanlamayı ilerletir ama düzey yükseltmez.
- **21 gün hemen önceki tekrardan sayılır.** Aradaki her tekrar, kanıtsız olsa bile, doğru cümleyi gösterip hafızayı tazeler; gerçek aralık odur.
- **Alıcı düzey** ayrıca hesaplanır (A03, A05, okumadaki aramalar): `recognized` = alıcı kartta (dinle-anla ya da dikte) S ≥ 7 gün, aynı kanıt esasıyla. Arayüzde "Tanıyor" olarak gösterilir.
- **Motorda:** `CardRecord` (kart + puanlı tekrarları) → `ItemEvidence.productionLevel`, `isRecognized`, `isKnown`. Tekrar kayıtları `attempts`'ten okunur: zaman, puan, kanıt olup olmadığı ve `card_state_after.stability`. **F1-20'den beri `transferred` de hesaplanır:**
  - `usedWithoutError` her konuşma kaydında hatasız kullanılan öğeleri bulur. Kaynak, aylık test kayıtları dahil, transkriptin kelimeleri ve işaretlemedir.
  - Kelime anlamında lemma yeter. Kalıpta lemmalar sırayla gelmelidir. Dolgular atlanır. İşaretli hatanın değdiği kelimeler sayılmaz.
  - Lemma anlamı ayırt etmez; aynı lemmanın her anlamı kullanılmış sayılır. Bilinen sınırlılıktır.
  - Düzey, `withTransfer`'le iki ayrı günde (öğrencinin yerel günü) kullanılan ve en az `recallable` olan öğede `transferred` olur. Kullanım öğeyi kalıcı yapmaz.

  **İlerleme sayıları (`countEvidence`):**
  - Tanıyor: `isKnown` ya da en az `recallable`.
  - Hatırlıyor: en az `recallable`.
  - Kalıcı: en az `durable`, yalnız kartlardan.
  - Kullanıyor: `transferred`.
- **Unutma:** Kalıcı bir öğe unutulursa (Again), düzey projeksiyonla otomatik düşer. Geçmişte "kullanıyor" olmuş olması arayüzde not olarak kalır ("daha önce kullanmıştın").
- **İlerleme ekranı** yüzde değil, sayı gösterir. Örnek: "Tanıyor 1840 · Hatırlıyor 612 · Kalıcı 305 · Kullanıyor 97".

## 4. Kelime ve gramer tahmini

### 4.1 Kelime
- **Tanıma boyutu:** X_Lex puanı (0–5000, bant bant). Seviye testinde (yeniden yapılınca da) ve üç ayda bir ölçülür.
- **Üretim boyutu:** Sıklık bantlarına (1K … 5K+) göre, üretim düzeyi ≥ `recallable` olan kelime anlamı sayısı.
- Arayüzde iki ayrı sayı gösterilir. Aradaki fark ("tanıyıp söyleyemediğin kelimeler") açıkça görünür ve yeni kart kaynağı olarak kullanılır.

### 4.2 Gramer
Her gramer noktası (`grammar_point`) için:
- **Kart düzeyi:** A04/A08/A09 sonuçlarından hesaplanır.
- **Serbest üretim doğruluğu:** `speaking_annotate` ve `writing_feedback` rotaları, kullanılan yapıları paketteki kapalı gramer kodu listesinden işaretler (`structures_used[]`).
- **"Kullanılıyor" eşiği:** son 30 günde en az 3 kullanım ve ≥ %80 doğruluk.

## 5. L3 — Can-do kanıtı

Her görev bir ya da daha fazla can-do kodunu destekler. Görev sonucu `done | partial | not_done` olarak belirlenir (LLM; bilgi boşluğunda deterministik cevap anahtarı).

| Durum | Koşul |
|---|---|
| `none` | Deneme yok |
| `attempted` | En az bir deneme |
| `shown` | En az bir `done` |
| `established` | **Farklı günlerde, farklı istemlerle en az 2 `done`**. Sonuncusu son 60 günde olmalı. B1 ve üstünde en az biri hazırlık süresi/kalıp iskelesi olmadan yapılmış olmalı. |

- `established` bir can-do'nun son `done`'ı 120 günden eskiyse "tazelemeye değer" olarak gösterilir. Başarısızlık gibi değil, davet olarak.
- **Motorda (F1-20, `canDoEvidence`):** Kanıt, konuşma görevlerinin sonucudur (`recordings.outcome`, görevin can-do kodları).
  - Ölçütleri sağlayan ama son `done`'ı 60 günden eski can-do `shown` görünür; 120 günden eskiyse "tazelemeye değer" daveti de çıkar. İki kural böyle birlikte okundu: `established` yakın kanıt ister.
  - Sabit görevler iskelesiz, diğerleri iskeleli sayılır (A0–A2'de başlangıçlar açık).
- Planlayıcı, henüz kanıtlanmamış can-do'ları destekleyen görevlere küçük bir öncelik verir.

## 6. L4 — Hata profili

- **Veri:** Serbest üretimdeki (konuşma ve yazma) hata etiketleri, kelime sayısıyla birlikte. Algı hataları (`perc.*`, dikte) ve telaffuz hataları (`pron.*`, gölgeleme) ayrı gruplarda tutulur.
- **Oran:** `r_t = etiket t hataları / 100 kelime`, haftalık hesaplanır. Haftada en az 200 kelime veri yoksa hafta "yetersiz veri" sayılır.
- **Eğilim:** Haftalık oranların üssel hareketli ortalaması (EWMA, α = 0,3).
- **Durumlar:**

  | Durum | Koşul |
  |---|---|
  | `persistent` (kalıcı) | Son 4 haftanın en az 3'ünde `r_t` ≥ etiket eşiği. Varsayılan eşik 1,0/100 kelime; pakette etiket bazında ayarlanabilir. |
  | `improving` (çözülüyor) | EWMA art arda 3 hafta düşüyor |
  | `resolved` (çözüldü) | 4 hafta boyunca `r_t` < ilk ölçülen düzeyin %30'u |

- **Haftalık odak:** `persistent` etiketler arasında (oran × ciddiyet ağırlığı) en yüksek olan seçilir. Aynı etiket art arda en fazla 2 hafta seçilir (tek aday kalmadıkça). Odak A22 etkinliğini ve planlayıcıdaki öğe seçimini etkiler.
- **Ciddiyet ağırlıkları** dil çifti paketindedir. Örnekler:
  - `art.missing` (artikel eksik): 1,0 — anlamı az bozar ama çok sık
  - `tense.pp_vs_ps` (Present Perfect / Past Simple karışması): 1,5
  - `wo.question` (soru kurma sırası): 1,5

## 7. L5 — Seviye tahmini

Sayısal ölçek: A0 = 0, A1 = 1, A2 = 2, B1 = 3, B2 = 4, C1 = 5, C2 = 6. "+" alt seviyeleri 0,5 ekler.

| Beceri | Kanıt | Seviye L'ye ulaşıldı sayılması için |
|---|---|---|
| Kelime (tanıma) | X_Lex | Milton tablosundaki aralık (`02` §2) |
| Gramer | L seviyesi gramer noktaları | Noktaların ≥ %70'i `recallable` **ve** L yapılarında serbest üretim doğruluğu ≥ %75 |
| Dinleme | L seviyesi dinleme metinleri + dikte | En az 3 metinde anlama ≥ %80 **ve** L cümlelerinde dikte kelime hata oranı (WER) ≤ %15 |
| Okuma | L seviyesi okuma metinleri | Kapsama ≥ %95 olan en az 3 metinde anlama ≥ %80 |
| Konuşma | L seviyesi konuşma/etkileşim can-do'ları | Seçili L tanımlarının ≥ %60'ı `established` |
| Yazma | L seviyesi yazma can-do'ları | Seçili L tanımlarının ≥ %60'ı `established` |

- **Akıcılık ölçümleri (CAF) seviyeye çevrilmez.** Konuşma hızı ile CEFR arasında evrensel bir eşleme yoktur. Bu ölçümler yalnızca kişinin kendi zaman içindeki değişimini gösterir.
- **Güven düzeyi:**
  - `low`: 5'ten az kanıt noktası ya da en yeni kanıt 90 günden eski
  - `medium`: arada kalan durumlar
  - `high`: son 60 günde en az 15 kanıt noktası ve tutarlı sonuç
- **Gösterim:** Belirsizse aralık gösterilir, ör. "Konuşma: A2–B1 (orta güven)". Tek başına bir yüzde asla gösterilmez.
- **Dış kalibrasyon:** Kullanıcı dış sonuçları elle girebilir: EF SET puanı, OpenEnglish seviyesi, öğretmen değerlendirmesi (`assessments.kind = external`). Dilbaz tahmini ile dış sonuç arasında 1 seviyeden fazla fark varsa eşikler gözden geçirilmek üzere işaretlenir (`16-experiments.md`).

## 8. Planlayıcıya verilen sinyaller

Motor, planlayıcıya şu özet yapıyı verir (Dart, saf). **v1 (F1-09)** yalnızca planlayıcının kullandığı alanları taşır: `level`, `dailyBudget`, `spentToday`, `recentUnaidedAccuracy`, `weekStrandTime`, `silentMode`; F1-16'dan beri `newToday` (bugün tanıtılan yeni öğe sayısı; günlük tavan bunları da sayar). Uygulama bu alanları F1-18'den beri gerçek veriyle doldurur:
- `spentToday` ve `weekStrandTime`: `sessions`'tan.
- `recentUnaidedAccuracy`: son 7 günün puanlı tekrarlarından. Vadesi gelen kartları ve öngörülen tekrar yükünü planlayıcı kart listesinden kendisi hesaplar. Diğer alanlar ilgili görevlerle eklenir.

```dart
class LearnerSnapshot {
  final Map<Skill, LevelEstimate> levels;          // aralık + güven
  final int dueCount; final Duration dueEstimate;  // bugünkü tekrar yükü
  final Duration projectedDailyReview;             // önümüzdeki 7 gün ortalaması
  final double recentUnaidedAccuracy;              // son 7 gün ipucusuz doğru oranı (P10)
  final Map<Strand, Duration> weekStrandTime;      // bu haftaki kol süreleri
  final ErrorTag? weeklyFocus;
  final List<CanDoCode> unprovenCanDos;
  final ScaffoldProfile scaffolds;                 // seviye + kullanıcı ayarından
  final TimeBudget budget; final Duration spentToday;
}
```

## 9. Partnerin görebildikleri (I-18)

- **Varsayılan olarak yalnızca:**
  - bu haftaki aktif dakika
  - kollara göre dağılım
  - ortak haftalık hedefe katkı
  - birlikte yapılan görevler
- **Hiçbir zaman:** ses kayıtları, hata profili, tek tek denemeler.
- **İsteğe bağlı paylaşım:** seviye tahmini ve aylık test özeti, kullanıcı ayrı ayrı açarsa.

## 10. Uç durumlar

- **Uzun ara (≥ 7 gün):** Biriken tekrarlar üst üste yığılmaz. Planlayıcı tavanı uygular, FSRS gecikmeyi zaten hesaba katar. İlk oturum kısa ve karışık bir "hoş geldin" çağırma setidir. Suçluluk mesajı yoktur (I-12).
- **Seviye testi atlanırsa:** Kullanıcının seçtiği yaklaşık seviyeyle başlanır, güven `low` olur. İlk 2 haftada teşhis amaçlı karışık görevler ağırlıklı verilir.
- **Paket sürümü değişirse:** Öğe anahtarları (`key`) kalıcıdır. Kaldırılan öğeler `deprecated` işaretlenir, kartlar askıya alınır, geçmiş korunur.

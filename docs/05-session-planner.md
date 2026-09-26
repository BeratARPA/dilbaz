# 05 — Oturum Planlayıcı

Planlayıcı, "Bugün" ekranının arkasındaki algoritmadır. Görevi, kullanıcının zaman bütçesi içinde **hafızanın en çok ihtiyaç duyduğu tekrarları**, **tekrar yükünü bozmayacak kadar yeni öğeyi** ve **haftalık dengeyi kuran 2–3 seçeneği** önermektir. Karar kullanıcınındır (I-14). Planlayıcı saf Dart'tır ve `dilbaz_engine` içinde yaşar.

## 1. Girdi ve çıktı

```dart
TodayPlan plan({
  required LearnerSnapshot s,        // 04 §8
  required ContentIndex content,     // aday öğeler, metinler (kişisel kapsamayla), görevler
  required PartnerPresence partner,  // çevrimiçi mi, "birlikte" daveti var mı
  required DateTime now,
  Duration? available,               // kullanıcı "bugün 10 dk" dediyse
  required PlannerConfig cfg,
  required int seed,                 // deterministik karıştırma için (tarih + öğrenci)
});

class TodayPlan {
  final List<CardRef> reviews;       // sıralı tekrar kartları
  final List<ItemRef> newItems;      // tanıtılacak yeni öğeler
  final List<PlanOption> options;    // 0 ya da 2–3 seçenek
  final int recommended;             // önerilen seçenek (options içindeki sıra)
  final List<Invitation> invitations;// ör. aylık kayıt, öğrenme notu
  final Duration estimate;           // toplam tahmini süre ≤ bütçe
}
```

## 2. Haftalık kol hedefleri

Nation (2007) dört kolun kabaca eşit olmasını önerir. Uçlarda şu gerekçelerle sapıyoruz:

- A0'da anlamlı girdi ve çıktı imkânı sınırlıdır.
- C seviyelerinde ana kaynak otantik girdidir.

Bu değerler `PlannerConfig` içindedir ve deneyle ayarlanır.

| Seviye | language | output | input | fluency |
|---|---|---|---|---|
| A0 | %50 | %15 | %20 | %15 |
| A1 | %40 | %20 | %25 | %15 |
| A2 | %35 | %25 | %25 | %15 |
| B1 | %25 | %25 | %30 | %20 |
| B2 | %20 | %30 | %35 | %15 |
| C1–C2 | %15 | %30 | %40 | %15 |

- **Haftalık hedef süre** = günlük bütçe × haftalık gün hedefi. Varsayılan 30 dk × 5 gün = 150 dk.
- **Medya günlüğü** (dizi vb.) girdi koluna **0,5 ağırlıkla** sayılır (odaklı değil, keyif amaçlı). Katkısı haftalık girdi hedefinin en fazla yarısı kadardır.

## 3. Algoritma

```text
1  bütçe ← min(available ?? s.budget.daily, s.budget.daily) − s.spentToday
2  if bütçe ≤ 0 → DinlenmeGünü("Bugünlük yeter")                               (I-13)
3  minimumGün ← (bütçe ≤ 7 dk) veya kullanıcı "sadece 5 dk" seçti

   ── Tekrar bloğu ──
4  tekrarTavanı ← minimumGün ? bütçe : min(cfg.reviewCap(10 dk), 0.4 · bütçe)
5  vadesiGelen ← due(now), öncelik = (1 − R(now)) · modAğırlığı + odakBonusu
6  sırala(öncelik azalan); 0,1'lik R dilimleri içinde seed ile karıştır           (P12)
7  contrasts_with çiftlerinin ikisi de vadeliyse aynı bloğa alınıp araya en az 1 kart girer
8  tekrarlar ← tahmini süre ≤ tekrarTavanı olacak kadar kart
9  if minimumGün → yalnızca tekrarlar ile dön

   ── Yeni öğeler ──
10 c ← yeni kartın ilk hafta günlük tekrara ortalama katkısı (geçmişten; varsayılan 1,2 dk)
11 kYeni ← ⌊(0,8 · tekrarTavanı − s.projectedDailyReview) / c⌋, [0, cfg.maxNew(seviye)] aralığında (I-07)
12 if s.recentUnaidedAccuracy < 0,70 → kYeni ← ⌊kYeni / 2⌋                       (P10)
13 if birikmiş vadeli tekrar > bir günlük tavan → kYeni ← 0
14 yeniÖğeler ← müfredat.sıradaki(kYeni)                                       (02 §4.3)

   ── Seçenekler ──
15 kalan ← bütçe − süre(tekrarlar) − süre(yeniÖğeler)
16 if kalan < 5 dk → seçenek yok (yalnızca tekrar + yeni)
17 açık ← kolHedefi(seviye) · haftalıkHedef − s.weekStrandTime                  (kol başına dk)
18 adaylar ← uygun etkinlikler (§4), seviye aralığında, içerik mevcut, süre ≤ kalan
19 puan(a) = 1,0 · normalize(açık[a.kol])
           + 0,5 · a.kanıtlanmamışCanDoyuDestekler
           + 0,4 · a.haftalıkOdaklaİlgili
           + 0,3 · a.son3GündeYapılmadı
           + 0,6 · (a.birlikte ∧ partner.uygun)
20 seçenekler ← puana göre ilk 3; aynı koldan en fazla 2; en az 2 seçenek garantisi   (I-14)
21 önerilen ← seçenekler[0]
22 davetler ← aylık test penceresindeyse "Aylık kayıt zamanı"; haftanın ilk oturumuysa öğrenme notu
23 dön TodayPlan(...)
```

**Mod ağırlıkları** (`cfg.modeWeight`):

| Mod | Ağırlık |
|---|---|
| speak | 1,0 |
| contrast | 1,0 |
| type | 0,9 |
| cloze | 0,9 |
| dictation | 0,8 |
| recognize_audio | 0,6 |

Konuşma hedefi olduğu için sesli üretim önde (P3). **Odak bonusu:** haftalık hata odağıyla ilişkili kartlara +0,15.

**Seviyeye göre günlük en fazla yeni öğe** (`cfg.maxNew`):

| A0 | A1 | A2 | B1 | B2 | C1–C2 |
|---|---|---|---|---|---|
| 6 | 8 | 10 | 10 | 12 | 12 |

## 4. Aday etkinlikler ve uygunluk

| Etkinlik | Kol | Uygunluk koşulu |
|---|---|---|
| A11 Konuşma görevi | output | Seviye görevleri mevcut |
| A13 Rol oyunu | output | A1+ |
| A20 Yazma | output | A2+ (A2'de kısa mesaj) |
| A21 Aracılık | output | B1+ |
| A14 Sohbet kartı | output | Partner var |
| A15 Bilgi boşluğu | output | Partner **şu an** çevrimiçi ve daveti kabul etti |
| A16 Okuma / A17 Dinleme | input | Kişisel kapsaması ≥ %95 olan metin var. Yoksa %95–98'lik metin + ön öğretim birlikte önerilir (I-06). |
| A18 Altyazı ön öğretimi | input | İçe aktarılmış, izlenmemiş bölüm var |
| A12 4/3/2 | fluency | Daha önce konuşma görevi yapılmış bir konu var |
| A07 Gölgeleme | fluency | Her zaman |
| A22 Hata odağı | language | Haftalık odak var |
| A08 Karşıtlık | language | İkisi de `recallable` olan en az 3 karşıtlık çifti var |
| A05 Dikte | language | A1+ |
| A06 Ses ayırt etme | language | `perc.*` ya da `pron.*` etiketi kalıcıysa ya da A0–A1 ise |
| A23 Aylık test | — | Davet olarak eklenir, seçeneklerin yerini almaz |

## 5. Süre tahminleri

Kişinin geçmişindeki medyan süreler kullanılır. Geçmiş yoksa varsayılanlar:

| Etkinlik | Süre | Etkinlik | Süre |
|---|---|---|---|
| Söyle kartı | 20 sn | Yaz kartı | 25 sn |
| Dinle-anla | 8 sn | Bağlamda boşluk | 20 sn |
| Dikte (cümle) | 45 sn | Karşıtlık (madde) | 20 sn |
| Tanıtım | 30 sn | Konuşma görevi | 6 dk |
| Rol oyunu | 7 dk | 4/3/2 | A1: 4 dk · A2: 6 dk · B1+: 11 dk |
| Okuma / dinleme | 8 dk | Yazma | 12 dk |
| Aracılık | 8 dk | Hata odağı | 5 dk |
| Ses ayırt etme | 3 dk | Gölgeleme | 4 dk |
| Sohbet kartı | 10 dk | Bilgi boşluğu | 10 dk |
| Aylık test | 15 dk | | |

## 6. Kurallar ve davranışlar

- **Bütçe dolunca** "Bugünlük yeter" ekranı gelir: bugün yapılanların somut özeti (yetkinlik bilgisi). "Devam etmek istersen" bağlantısı düşük vurguyla durur. Devam etmek ekstra bir şey kazandırmaz (I-13).
- **Uzun aradan dönüş:** Tekrar tavanı aynen uygulanır. Birikim varken yeni öğe yoktur. İlk ekran nötrdür: "Hoş geldin. Önce kısa bir karışık tekrar yapalım." Kaç gün geçtiği vurgulanmaz (I-12).
- **"Bugün ne kadar vaktin var?"** Bugün ekranında 5 / 15 / 30 dk hızlı seçimi vardır. Varsayılan, bütçedir.
- **Birlikte:**
  - Partnerin çevrimiçi olması Supabase presence ile görülür.
  - "Birlikte yapalım mı?" daveti partnere bildirim olarak gider. Kullanıcının izni ve sessiz saat kuralı geçerlidir.
  - Kabul edilirse iki uygulamada da "Birlikte" seçeneği önerilen olur.
- **Aylık test daveti** ayın 1–7'si arasında görünür. Kabul edilmezse hafta sonuna kadar ara sıra tekrar görünür, sonra bir sonraki aya kalır. Hatırlatma dili davettir, uyarı değildir.
- **İskele profili** (seviye + kullanıcı ayarı) her etkinliğe parametre olarak geçer (I-09).
- **Determinizm:** Aynı girdi ve aynı seed aynı planı üretir (test edilebilirlik).

## 7. Yapılandırma (`PlannerConfig`)

```dart
class PlannerConfig {
  final Duration reviewCap;                 // 10 dk
  final Map<Level, int> maxNew;             // 6/8/10/10/12/12
  final Map<Level, StrandTargets> strandTargets;
  final Map<CardMode, double> modeWeight;
  final double focusBonus;                  // 0.15
  final double lowAccuracyThreshold;        // 0.70
  final double highAccuracyThreshold;       // 0.90 → zorluk artır
  final double mediaInputWeight;            // 0.5
  final int weeklyDaysGoal;                 // 5
  final double newCardDailyCostMinutes;     // 1.2 (geçmişle güncellenir)
}
```

Deney kolları (`16-experiments.md`) bu yapılandırmayı öğrenci ya da öğe düzeyinde geçersiz kılabilir.

## 8. Test gereksinimleri (özellik tabanlı)

Rastgele üretilmiş öğrenci durumları ve içerikle çalışan testler şunları doğrulamalıdır:

1. Planın tahmini süresi hiçbir zaman bütçeyi aşmaz (I-13).
2. Öngörülen tekrar yükü tavanın %80'ini geçiyorsa yeni öğe yoktur (I-07).
3. Kalan süre ≥ 5 dk ise en az 2 seçenek vardır (I-14).
4. Seçenekler öğrencinin seviye aralığı dışındaki etkinlikleri içermez.
5. Okuma/dinleme seçeneği ya kapsama ≥ %95 ile ya da ön öğretimle birlikte gelir (I-06).
6. Minimum gün planı yalnızca tekrar içerir.
7. 7+ gün aradan sonra tekrar bloğu tavanı aşmaz. Birikim varken yeni öğe yoktur.
8. Sentetik bir öğrenciyle 4 haftalık simülasyonda kol açıkları hedefe doğru kapanır.
9. Aynı girdi + seed → aynı plan.
10. `contrasts_with` çiftleri aynı gün birlikte **tanıtılmaz** (02 §4.3); ikisi de öğrenildikten sonra aynı blokta karışık çıkabilir.

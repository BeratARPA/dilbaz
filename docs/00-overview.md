# 00 — Genel Bakış

> Çalışma adı: **Dilbaz** (TDK: "Güzel söz söyleyen, konuşmasıyla ikna eden"). İsim değiştirilebilir; kodda paket adları `dilbaz_*`.

## 1. Dilbaz nedir?

Dilbaz, bir dili **sıfırdan (A0) ileri seviyeye (C1–C2) gerçekten öğreten**, her tasarım kararını öğrenme bilimi ve ikinci dil edinimi (SLA) araştırmalarına dayandıran kişisel bir öğrenme sistemidir.

- İlk dil çifti: **Türkçe konuşanlar için İngilizce** (`l1=tr`, `l2=en`).
- Motor **dilden bağımsızdır**: başka bir dil, yalnızca yeni bir "dil paketi" eklenerek desteklenebilir (bkz. `11-language-packs.md`).
- Platformlar: **Android** (öncelik), **Windows masaüstü**, **web**. Tek kod tabanı: Flutter. Cihazlar arası senkron.

Dilbaz bir "ders uygulaması" değildir. Merkezinde "ders" değil, **öğrenme kanıtı** vardır: bir şeyin öğrenildiğine ancak aradan zaman geçtikten sonra, yardım almadan, gerektiğinde yeni bir bağlamda yapılabildiğinde karar verilir.

## 2. Kimler için?

- **Şimdilik iki kullanıcı:** Berat ve sevgilisi. İkisinin seviyesi ve hedefi hemen hemen aynı.
- **Kısa vadeli hedef (12 ay):** kendini, derdini cümle kurarak anlatabilmek ve sohbet edebilmek (≈ CEFR B1 konuşma).
- **Uzun vadeli hedef:** sistemin A0'dan C2'ye kadar her seviyeyi kapsaması.
- **Kısıtlar:**
  - Günde **en fazla 30 dakika** aktif çalışma (kişi başı).
  - **İş gibi hissettirmemeli.** Kota, suçluluk, "kaçırıldı" etiketi, kırmızı uyarı yok (bkz. `09-ux-motivation.md`).
  - Kişisel kullanım; ticari ürün değil.
  - Telefonlar Android; geliştirme Windows'ta.

## 3. Başarının tanımı

Sistem, kullanıcının uygulamada geçirdiği zamanla değil, **uygulama dışında ne kadarını doğru ve akıcı kullanabildiğiyle** başarılı sayılır. Ölçütler:

1. **Gecikmeli hatırlama:** FSRS'in ölçtüğü, günler/haftalar sonra yardımsız doğru üretim.
2. **Aktarım:** Kartta çalışılan kalıp ve kelimelerin serbest konuşmada/yazıda hatasız kullanılması.
3. **Konuşma performansı:** Aylık konuşma testinde akıcılık, doğruluk ve karmaşıklık ölçümlerinin zaman içinde iyileşmesi (bkz. `06-assessment.md`).
4. **Can-do kanıtları:** CEFR "yapabilir" tanımlarının görevlerle, farklı günlerde, en az iki kez gösterilmesi.
5. **Süreklilik:** Haftalık hedeflere ulaşma oranı (günlük seri değil).

Sistem **uydurma yüzde göstermez.** Bir tahmin belirsizse aralık ve güven düzeyiyle gösterilir.

## 4. Kapsam (tam sürüm, v1.0)

- A0–C2 İngilizce içeriği (seviye seviye, ilk kullanıcıların bir adım önünde üretilerek).
- Kelime, kalıp, gramer, telaffuz, dinleme, okuma, konuşma, yazma, etkileşim ve aracılık (mediation) becerileri.
- FSRS ile aralıklı tekrar; kanıta dayalı öğrenci modeli; haftalık dengeyi kuran oturum planlayıcı.
- Yapay zekâ öğretmen (ücretsiz katman LLM'leri, ADR-0009) — ipucu önce, cevap sonra; korkuluklu.
- Konuşma tanıma, seslendirme, telaffuz değerlendirmesi.
- Çift özellikleri: sohbet kartları, iki telefonla bilgi boşluğu görevleri, ortak haftalık hedef.
- Söyleyemediklerim defteri, dizi/altyazı madenciliği, medya günlüğü.
- Seviye testi, aylık konuşma testi, ilerleme ekranı (önce/sonra ses karşılaştırması).
- Çevrimdışı çalışma + senkron; Android, Windows, web.
- Uygulama içi deney altyapısı (kendi yöntemlerini test eden sistem).
- Dilden bağımsızlığın kanıtı: v1.0'da küçük bir ikinci dil paketi.

## 5. Kapsam dışı (şimdilik)

- Herkese açık ürün, ödeme, mağaza yayını, iOS (ileride PWA ya da Mac/CI ile mümkün).
- Sosyal ağ, liderlik tablosu, puan/rozet ekonomisi.
- Canlı insan öğretmen pazarı.

## 6. Temel ilkeler (özet)

Ayrıntı ve kanıtlar: `01-pedagogy.md`. Kısaca:

1. Önce **dene**, sonra gör. Her alıştırmada hafızadan çağırma var.
2. **Aralıklı tekrar** FSRS ile; tekrar zamanını takvim değil hafıza belirler.
3. **Neyi pratik edersen onda gelişirsin:** hedef konuşma olduğu için varsayılan cevap biçimi sesli.
4. **Dört kol dengesi** (Nation): anlam odaklı girdi, anlam odaklı çıktı, dil odaklı çalışma, akıcılık. Denge haftalık kurulur.
5. **Anlaşılır girdi:** okuma/dinleme metinlerinin %95–98'i bilinen kelimelerden oluşur.
6. **İpucu merdiveni:** hata olunca önce ipucu, en son cevap.
7. **Doğru yöntem seviyeye göre değişir** (uzmanlığın tersine dönme etkisi): rehberlik seviye yükseldikçe azalır.
8. **Kanıta dayalı ilerleme:** öğrenildi demek için gecikmeli, yardımsız başarı gerekir.
9. **İş gibi hissettirmez:** özerklik, yetkinlik, bağlılık (öz belirleme kuramı).
10. **Dilden bağımsız motor**, dile özgü her şey pakette.

## 7. Doküman haritası

| Doküman | İçerik | Ne zaman okunmalı |
|---|---|---|
| `00-overview.md` | Bu dosya | Her zaman ilk |
| `01-pedagogy.md` | Öğrenme bilimi ilkeleri, kanıtlar, **değişmez kurallar (I-xx)** | Öğrenmeyi etkileyen her işte |
| `02-curriculum.md` | Seviyeler, müfredat haritası, gramer/telaffuz ilerlemesi | İçerik, seviye, müfredat işleri |
| `03-activities.md` | Etkinlik kataloğu (A01–A25): akış, değerlendirme, log | Bir etkinliği kodlarken |
| `04-learner-model.md` | Öğrenci modeli, kanıt düzeyleri, seviye tahmini | Model, ilerleme, planlayıcı |
| `05-session-planner.md` | Günlük oturum algoritması | Bugün ekranı, planlayıcı |
| `06-assessment.md` | Seviye testi, aylık konuşma testi, ölçüm formülleri | Değerlendirme işleri |
| `07-ai-tutor.md` | LLM rotaları, prompt sözleşmeleri, korkuluklar, eval | Yapay zekâ ile ilgili her iş |
| `08-speech.md` | Konuşma tanıma, seslendirme, telaffuz, ses hattı | Ses ile ilgili her iş |
| `09-ux-motivation.md` | Ekranlar, metin dili, motivasyon kuralları | Her UI işi |
| `10-content-pipeline.md` | İçerik üretimi, doğrulama, lisanslar | İçerik araçları |
| `11-language-packs.md` | Paket formatı, dilden bağımsızlık | Paket/motor sınırı |
| `12-architecture.md` | Sistem mimarisi, klasör yapısı, senkron | Mimari kararlar |
| `13-data-model.md` | Veritabanı şeması, RLS, olay senkronu | Veri işleri |
| `14-security-privacy.md` | Güvenlik, ses verisi, saklama | Veri/güvenlik |
| `15-testing.md` | Test stratejisi, kalite kapıları | Her kod işi |
| `16-experiments.md` | Uygulama içi deneyler | Deney işleri |
| `17-roadmap.md` | Fazlar, görevler, kabul kriterleri | Her oturumun başında |
| `18-costs-risks.md` | Maliyet tahmini, riskler | Planlama |
| `19-setup.md` | Kurulum, hesaplar, anahtarlar (kullanıcının yapacakları) | Faz 0 |
| `20-glossary.md` | Terimler sözlüğü | Gerektiğinde |
| `references.md` | Kaynakça | Gerektiğinde |
| `adr/` | Mimari karar kayıtları | Karar değişikliğinde |
| `feedback.md` | Kullanıcı geri bildirimleri (günlük kullanımdan) | Her oturumun başında |
| `experiments/` | Deney kayıtları (E1–E6) | Deney işleri |

## 8. Mimari karar kayıtları (ADR)

| No | Karar |
|---|---|
| 0001 | İstemci: Flutter + Riverpod + go_router + drift |
| 0002 | Sunucu: Supabase (Postgres, Auth, Storage, Edge Functions, Realtime) |
| 0003 | Yerel öncelikli çalışma + değişmez olay günlüğü ile senkron |
| 0004 | Aralıklı tekrar: FSRS (pub.dev `fsrs`) |
| 0005 | Yapay zekâ: Claude API, sunucu tarafında, yapılandırılmış çıktı (ADR-0009 ile askıda) |
| 0006 | Ses: sağlayıcıdan bağımsız arayüz. İngilizce ASR için Deepgram (kelimesi kelimesine). Seçim karşılaştırma testiyle kesinleşir. Azure bölümleri ADR-0009 ile değişti. |
| 0007 | Motor ayrı saf Dart paketi (`dilbaz_engine`), dile özgü kod yok |
| 0008 | İçerik hattı: Python araçları + versiyonlu dil paketleri |
| 0009 | Sıfır bütçe: her bileşende ücretsiz olan en iyi seçenek. LLM rotaları Gemini + Groq ücretsiz katmanlarıyla; her zaman deterministik yedek. Deepgram kredisi, cihaz üstü ses, Kokoro paket sesleri, içerik Claude Code oturumlarında. |

## 9. Durum

- 2026-09-25: Plan tamamlandı. Kodlama başlamadı. Başlangıç: `17-roadmap.md` → Faz 0.
- 2026-09-26: Faz 0 başladı (dal `faz-0`). Güncel durum `17-roadmap.md` ilerleme günlüğündedir.
- 2026-09-26: Faz 0 tamamlandı ve `main`'e birleştirildi. Faz 1 başladı (dal `faz-1`); ADR-0009 (sıfır bütçe) kabul edildi.

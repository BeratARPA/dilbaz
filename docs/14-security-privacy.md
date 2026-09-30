# 14 — Güvenlik ve Mahremiyet

Dilbaz iki kişilik, kişisel bir sistemdir. Yine de iki kişinin **ses kayıtlarını**, hatalarını ve öğrenme geçmişini tutar; bu yüzden mahremiyet ciddiye alınır.

## 1. Tehdit modeli (küçük ama gerçek)

| Tehdit | Etki | Önlem |
|---|---|---|
| API anahtarının sızması (uygulama içinden ya da git'ten) | Kota ve kredinin tüketilmesi, kötüye kullanım | Anahtarlar yalnızca Supabase secrets'ta. Uygulamada yalnızca publishable key. `.gitignore` + commit öncesi gizli anahtar taraması. |
| Yanlış RLS ile partnerin ya da başkasının verisine erişim | Mahremiyet ihlali | Varsayılan-red RLS, her tabloya pgTAP testi, partnere yalnızca özet fonksiyonu |
| Döngüye giren istemci ya da hata yüzünden aşırı LLM/ASR kullanımı | Kotanın ya da Deepgram kredisinin tükenmesi | Kullanıcı başı kota payı (adil paylaşım), fonksiyon başı istek sınırı. Ücretli plan ve kart yok, fatura oluşamaz (ADR-0009). |
| Veri kaybı (ücretsiz planda otomatik yedek yok) | Öğrenme geçmişinin kaybı | Gece yedeği + haftalık döküm + uygulama içi dışa aktarma (`12` §9) |
| Cihaz kaybı | Oturumun kötüye kullanımı | Supabase oturum yönetimi. Ayarlardan "tüm cihazlardan çıkış". |
| Üçüncü taraf sağlayıcıların veriyi eğitimde kullanması | Mahremiyet | Gemini ücretsiz katmanı veriyi ürün geliştirmede kullanabilir: kullanıcı başına açık onay, onay yoksa Groq (ZDR) ya da deterministik yol. Deepgram `mip_opt_out`. Veri en aza indirme. |
| Log'lara kişisel metin/ses düşmesi | Mahremiyet | Fonksiyon loglarında yalnızca kimlik ve süre. Transkript ve metin loglanmaz. |

## 2. Kimlik doğrulama

- **Supabase Auth, e-posta + tek kullanımlık kod (OTP).** Derin bağlantı (magic link) yapılandırması gerektirmez. E-posta şablonu kodu (`{{ .Token }}`) içerecek şekilde ayarlanır.
- Oturum `supabase_flutter`'ın oturum yönetimiyle tutulur. Web'de yalnızca HTTPS.
- Kayıt serbest değildir: yeni kullanıcı yalnızca izin listesindeki e-postayla kaydolabilir. Liste `private.signup_allowlist` tablosundadır (Data API'ye kapalı, e-postalar başka kullanıcılara görünmez). Supabase Auth'un **before-user-created** hook'u (`private.hook_before_user_created`) listede olmayan e-postayı 403 ile reddeder. Yerelde `config.toml` + `seed.sql`, üretimde panel ayarı + SQL (`19-setup.md` §1).

## 3. Partner mahremiyeti (I-18)

| Veri | Partner görür mü? |
|---|---|
| Aktif gün ve dakika, kol dağılımı, birlikte görevler | Evet (ortak hedef için) |
| Seviye tahmini | Yalnızca `share_levels` açıksa |
| Aylık test özeti (ölçümler) | Yalnızca `share_monthly` açıksa |
| Ses kayıtları, transkriptler | **Hayır** |
| Hata profili, tek tek denemeler, Söyleyemediklerim | **Hayır** |

İkili görevlerde her telefon yalnızca kendi sahibini kaydeder. Kişisel geri bildirim yalnızca sahibine gösterilir.

## 4. Ses verisi

- **Açık onay:** Karşılama akışında mikrofon izninden önce hangi kayıtların ne kadar tutulduğu açıkça yazılır ve onay alınır. Onay kapalı başlar, zamanıyla birlikte `profiles.settings.audio_consent` içinde saklanır (`13` §2.1) ve Ayarlar'dan geri alınabilir. Onay yoksa mikrofon izni istenmez, cevaplar yazılı verilir.
- **Saklama:**

  | Kayıt türü | Saklama |
  |---|---|
  | Kart kayıtları | **Saklanmaz.** Cihazda geçici tutulur. Ayarlardan açılabilir, açılırsa 30 gün. |
  | Görev ve pratik kayıtları | 30 gün, sonra ses silinir. Transkript ve ölçümler kalır. |
  | Yıldızlanan kayıtlar (`keep`) | Kullanıcı silene kadar |
  | Aylık test ve seviye testi kayıtları | Kullanıcı silene kadar ("önce/sonra" için) |

- **Silme hakkı:** Ayarlar > Veri > "Tüm verimi sil" (onaylı, geri alınamaz uyarısıyla) ve tekil kayıt silme.
- **Taşınabilirlik:** Ayarlar > Veri > "Dışa aktar" (JSON + ses dosyaları, zip).
- **Bölge:** Supabase projesi AB bölgesinde (Frankfurt) açılır.

## 5. Sağlayıcılara giden veri

| Sağlayıcı | Ne gider | Ne gitmez |
|---|---|---|
| Gemini (ücretsiz katman) | İstem metni, öğe bilgisi, transkript, seviye bilgisi; yalnızca veri onayı veren kullanıcı için | Ses, isim, e-posta, kullanıcı kimliği |
| Groq | Aynı metinler; hesapta ZDR açık | Ses (Türkçe yedek hariç), isim, e-posta, kullanıcı kimliği |
| Deepgram | Ses (İngilizce), parametreler | Kimlik bilgisi |
| Cihaz üstü (Android konuşma servisi, TTS) | Türkçe ses, seslendirilecek metin (cihazda kalır; tanıyıcı çevrimiçi çalışabilir) | — |

- **Gemini ücretsiz katmanı:** Gönderilen içerik Google ürünlerini geliştirmede kullanılabilir ve insanlar tarafından incelenebilir. Bu yüzden onay kullanıcı başınadır ve karşılamada (F1-12) açıkça sorulur. Ayarlardan her zaman değiştirilebilir. Onay kapalı başlar ve zamanıyla birlikte `profiles.settings.ai_data_consent` içinde saklanır; kimse başkası adına veremez.
- **Politika kontrolü:** Her sağlayıcının veri kullanım ve saklama politikası kurulumda kontrol edilir ve `docs/adr/0009` içine not edilir.

## 6. Gizli anahtar yönetimi

- **Supabase secrets:** `GEMINI_API_KEY`, `GROQ_API_KEY`, `DEEPGRAM_API_KEY` (ADR-0009). Kullanıcı kendisi ayarlar (`19-setup.md`). Anahtarlar sohbete, koda ya da commit'e yazılmaz.
- **Yerel geliştirme:** `supabase/functions/.env` (git dışı).
- **Uygulama:** `env/*.json` (git dışı). Yalnızca URL + publishable key.
- **CI:** GitHub Actions secrets (DB parolası, gerekirse test anahtarları).
- **Commit öncesi kontrol:** `gitleaks` ya da basit bir desen taraması (pre-commit hook + CI adımı).

## 7. Bağımlılık güvenliği

- **Sürümler kilitli:** `pubspec.lock`, `deno.lock`, `uv.lock` commit edilir.
- **Ayda bir** `flutter pub outdated`, `deno outdated`, `uv lock --upgrade` incelemesi yapılır. Yükseltmeler ayrı commit'lerde ve testlerle yapılır.
- **Otomatik yükseltme:** GitHub Actions eylemleri için Dependabot.

## 8. Uygulama içi güvenlik

- Paket dosyalarının sağlama toplamı doğrulanır. Doğrulanmayan paket içe aktarılmaz.
- İçe aktarılan altyazı dosyaları yalnızca metin olarak ayrıştırılır ve boyutu sınırlıdır (≤ 2 MB).
- Kullanıcı metinleri LLM'e her zaman "veri" olarak, sabit sistem promptunun dışında gider. Sistem promptu, öğrenci metnindeki talimatlara uyulmamasını söyler (istem enjeksiyonuna karşı).

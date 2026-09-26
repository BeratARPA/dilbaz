# 14 — Güvenlik ve Mahremiyet

Dilbaz iki kişilik, kişisel bir sistemdir. Yine de iki kişinin **ses kayıtlarını**, hatalarını ve öğrenme geçmişini tutar; bu yüzden mahremiyet ciddiye alınır.

## 1. Tehdit modeli (küçük ama gerçek)

| Tehdit | Etki | Önlem |
|---|---|---|
| API anahtarının sızması (uygulama içinden ya da git'ten) | Maliyet, kötüye kullanım | Anahtarlar yalnızca Supabase secrets'ta. Uygulamada yalnızca publishable key. `.gitignore` + commit öncesi gizli anahtar taraması. |
| Yanlış RLS ile partnerin ya da başkasının verisine erişim | Mahremiyet ihlali | Varsayılan-red RLS, her tabloya pgTAP testi, partnere yalnızca özet fonksiyonu |
| Döngüye giren istemci ya da hata yüzünden aşırı LLM/ASR kullanımı | Maliyet | Kullanıcı başı günlük bütçe, fonksiyon başı istek sınırı, Anthropic/Deepgram/Azure harcama limitleri |
| Veri kaybı (ücretsiz planda otomatik yedek yok) | Öğrenme geçmişinin kaybı | Gece yedeği + haftalık döküm + uygulama içi dışa aktarma (`12` §9) |
| Cihaz kaybı | Oturumun kötüye kullanımı | Supabase oturum yönetimi. Ayarlardan "tüm cihazlardan çıkış". |
| Üçüncü taraf sağlayıcıların veriyi eğitimde kullanması | Mahremiyet | Model geliştirme programlarından çıkış parametreleri (Deepgram `mip_opt_out`), veri politikası kontrolü, veri en aza indirme |
| Log'lara kişisel metin/ses düşmesi | Mahremiyet | Fonksiyon loglarında yalnızca kimlik ve süre. Transkript ve metin loglanmaz. |

## 2. Kimlik doğrulama

- **Supabase Auth, e-posta + tek kullanımlık kod (OTP).** Derin bağlantı (magic link) yapılandırması gerektirmez. E-posta şablonu kodu (`{{ .Token }}`) içerecek şekilde ayarlanır.
- Oturum `supabase_flutter`'ın oturum yönetimiyle tutulur. Web'de yalnızca HTTPS.
- Kayıt serbest değildir: yeni kullanıcı yalnızca davet kodu/izin listesiyle kaydolabilir (Auth ayarı + `app_config.allowed_emails`).

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

- **Açık onay:** Karşılama akışında mikrofon izninden önce hangi kayıtların ne kadar tutulduğu açıkça yazılır ve onay alınır.
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
| Anthropic | İstem metni, öğe bilgisi, transkript, seviye bilgisi | Ses, isim, e-posta, kullanıcı kimliği |
| Deepgram | Ses (İngilizce), parametreler | Kimlik bilgisi |
| Azure AI Speech | Ses (telaffuz, Türkçe), seslendirilecek metin | Kimlik bilgisi |

Her sağlayıcının veri kullanım ve saklama politikası kurulumda kontrol edilir ve `docs/adr/0005`, `0006` içine not edilir.

## 6. Gizli anahtar yönetimi

- **Supabase secrets:** `ANTHROPIC_API_KEY`, `DEEPGRAM_API_KEY`, `AZURE_SPEECH_KEY`, `AZURE_SPEECH_REGION`. Kullanıcı kendisi ayarlar (`19-setup.md`). Anahtarlar sohbete, koda ya da commit'e yazılmaz.
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

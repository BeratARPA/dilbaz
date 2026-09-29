# 19 — Kurulum (kullanıcının yapacakları)

Bu dosya, kodlayan ajanın **yapamayacağı ya da yapmaması gereken** işleri listeler:
- hesap açma
- API anahtarı girme
- sistem ayarı değiştirme
- ödeme bilgisi

Ajan bu adımlara geldiğinde durur ve bu dosyanın ilgili bölümünü gösterir. **API anahtarlarını sohbete yapıştırma**; aşağıdaki komutlarla kendin ayarla.

## 1. Hesaplar ve anahtarlar

| # | Hizmet | Ne yapılacak | Ne zaman |
|---|---|---|---|
| 1 | **GitHub** | Depo oluştur (özel önerilir). `git remote add origin …` bilgisini ajana ver. | Faz 0 |
| 2 | **Supabase** | Hesap aç → yeni proje: ad `dilbaz`, bölge **Central EU (Frankfurt)**. Güçlü bir veritabanı parolası belirle ve **yalnızca** parola yöneticine kaydet (sohbete yazma). Formda: GitHub entegrasyonu **boş** (migrasyonlar onayla `db push` ile gider), "Enable Data API" **açık**, "Automatically expose new tables" **kapalı**, "Enable automatic RLS" kapalı kalabilir. Project URL ve **publishable key** ajan tarafından `app/env/prod.json`'a yazılabilir (herkese açık bilgiler). | Faz 0 (F0-10) |
| 3 | **Google AI Studio (Gemini)** | aistudio.google.com → Google hesabıyla giriş → **Get API key** → **Create API key**. **Faturalandırma ekleme:** ücretsiz katmanda kalmalı. Kotalar AI Studio'nun kullanım sayfasında görünür. | F1-15'ten önce |
| 4 | **Groq** | console.groq.com → e-postayla kayıt (kart yok) → **API Keys** → yeni anahtar. **Settings → Data Controls → Zero Data Retention: açık.** | F1-15'ten önce |
| 5 | **Deepgram** | console.deepgram.com → e-postayla kayıt ($200 başlangıç kredisi, kart yok) → **API Keys** → yeni anahtar. | F1-14'ten önce |
| — | **Anthropic, Azure** | Kullanılmıyor: kart gerekiyor (ADR-0009). Bütçe olursa ADR-0005/0006'ya dönülür. | — |
| — | **Brevo (SMTP)** | Ücretsiz hesap → gönderen doğrula → SMTP anahtarı → Supabase: Authentication → Emails → SMTP Settings (host `smtp-relay.brevo.com`, port 587, gönderen adı `Dilbaz`). Yerleşik e-posta servisi yalnızca ekip üyelerine ve saatte 2 e-posta gönderir, şablonları kilitlidir; kodla giriş için şart. | Faz 0 (F0-10) |
| 6 | **Vercel** | Web sürümü için proje. | Faz 6 |

### Anahtarları ayarlama (kendin çalıştır)

```bash
# Proje klasöründe, Supabase CLI ile (bir kez)
npx supabase login
npx supabase link --project-ref <PROJE_REF>

# Sunucu tarafı gizli anahtarlar (uygulamaya asla girmez).
# Önce anahtarları bir düzenleyiciyle supabase/functions/.env dosyasına yaz (git dışı):
#   GEMINI_API_KEY=...
#   GROQ_API_KEY=...
#   DEEPGRAM_API_KEY=...
# Sonra dosyadan yükle; böylece anahtar kabuk geçmişine düşmez:
npx supabase secrets set --env-file supabase/functions/.env
```

Aynı `supabase/functions/.env` dosyası yerel geliştirmede (`npx supabase functions serve`) de kullanılır. Bu dosya git dışıdır.

Uygulama yapılandırması `app/env/prod.json` dosyasındadır (git dışı; yalnızca herkese açık bilgiler):

```json
{ "SUPABASE_URL": "https://<ref>.supabase.co", "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_..." }
```

### Supabase Auth ayarı (panelden)
- Authentication → Providers → Email: **açık**. "Confirm email" açık.
- Email Templates → **"Confirm signup"** ve **"Magic Link"** şablonlarına kod ekle (ilk giriş onay şablonunu kullanır): `Giriş kodun: {{ .Token }}`. Uygulama bağlantı değil 6 haneli kod kullanır. Metinler: `supabase/templates/`.
- Kayıt izin listesi (migrasyonlar `db push` ile yüklendikten sonra):
  1. Authentication → Hooks → **Before User Created** → Postgres fonksiyonu `private.hook_before_user_created` → etkinleştir.
  2. SQL Editor'de iki e-postayı ekle (küçük harfle): `insert into private.signup_allowlist (email) values ('...'), ('...');`
  - Yeni kayıtlar açık kalır; listede olmayan e-posta 403 alır.

### Paket yükleme (F1-05, kendin çalıştır)

1. **Üretim migrasyonu:** `npx supabase db push`. Ajan önce onayını ister. `packs` tablosunu ve `packs`, `pack-audio` kovalarını oluşturur.
2. **Gizli anahtar:** Supabase → Project Settings → API Keys → **Secret keys** → yeni anahtar (ad: `content-upload`). Anahtarı yalnızca parola yöneticine kaydet, sohbete yazma. Bu anahtar servis rolüyle çalışır.
3. **Yükleme** (PowerShell, `content/tools` klasöründe). Anahtar yalnızca bu pencerenin ortamında kalır, dosyaya ve geçmişe yazılmaz:

   ```powershell
   $env:SUPABASE_URL = "https://<ref>.supabase.co"
   $secure = Read-Host -AsSecureString "secret key"
   $env:SUPABASE_SECRET_KEY = [System.Net.NetworkCredential]::new("", $secure).Password
   uv run --no-sync dilbaz-content upload --publish
   Remove-Item Env:SUPABASE_SECRET_KEY
   ```

   - `--no-sync`: ortam hazır, `uv` yeniden kurmaya çalışmasın.
   - `--publish` verilmezse paketler taslak kalır ve uygulama yalnızca yayımlananları görür.
   - 3.629 ses dosyası (~24 MB) ve 2 paket yüklenir. Yerel denemede 26 sn sürdü. Yarıda kalırsa komutu tekrar çalıştır; yüklü sesler atlanır.
4. **Doğrulama:**
   - Table Editor → `packs`: `en@1` ve `tr-en@1` satırları `published`.
   - Storage → `packs` ve `pack-audio` kovaları dolu.

**Ajana bırakma (2026-09-30'da kullanılan yol):** Supabase CLI'da oturum açıksa (`supabase login`, F0-10) 2. ve 3. adımları ajan yapabilir. Onayınla anahtarı `supabase projects api-keys --reveal` ile alır ve yalnızca yükleme komutunun ortamına verir. Değer ekrana, loga, dosyaya ya da sohbete yazılmaz; senin anahtar oluşturman gerekmez. Doğrulamayı salt okunur SQL ile ajan yapar.

## 2. Windows'a araç kurulumu

| Araç | Sürüm | Kurulum |
|---|---|---|
| Git | güncel | `winget install Git.Git` |
| Flutter SDK | 3.47.x (stable; 2026-09-26: 3.47.5) | docs.flutter.dev → Windows kurulumu (zip ya da VS Code Flutter eklentisi). `flutter` PATH'te olmalı. Güncelleme: `flutter upgrade`. |
| Android Studio | güncel stable | `winget install Google.AndroidStudio` → SDK Manager: Android SDK Platform 36 ve 37, Build-Tools, Command-line Tools, Platform-Tools, Emulator. Sonra `flutter doctor --android-licenses`. Komut satırından: cmdline-tools 23 ile `sdkmanager` yerini `android sdk install platforms/android-36 build-tools/36.0.0 ndk/28.2.13676358 platform-tools emulator` komutuna bıraktı (`sdkmanager.bat` `;` içeren adları cmd'de böler). Kullanım verisini kapatmak için `android --no-metrics …`. |
| JDK | 17+ | Android Studio'nun gömülü JDK'sı yeterli |
| WSL 2 | güncel | **Önce:** yönetici PowerShell'de `wsl --install --no-distribution`, sonra **yeniden başlat** (Windows özelliği açar; sistem ayarı, kendin yaparsın). Docker Desktop için şart. |
| Docker Desktop | güncel | `winget install Docker.DockerDesktop` (WSL 2 ile). İlk açılışta sözleşmeyi kabul et. Yerel Supabase için gerekli. |
| Node.js | 20+ | `winget install OpenJS.NodeJS.LTS` (`npx supabase` için) |
| Supabase CLI | kök `package.json`'da sabit (2026-09-26: 2.118.0) | Proje kökünde `npm install` → `npx supabase …` sabitlenmiş sürümü kullanır. CI aynı sürümü kurar. |
| Deno | 2.x | `winget install DenoLand.Deno` (fonksiyon testleri ve eval) |
| Python | 3.12+ (sende 3.14 var) | Mevcut. `uv`: `winget install astral-sh.uv` |
| Visual Studio | 2022 veya 2026 | **Yalnızca Faz 3 (Windows derlemesi):** "Desktop development with C++" iş yükü |

### Windows Geliştirici Modu (kendin aç)
Flutter eklentileri sembolik bağ ister. **Ayarlar → Sistem → Geliştiriciler için → Geliştirici Modu: Açık.** Bu bir sistem güvenlik ayarıdır; ajan değiştirmez. **Faz 0'dan itibaren gerekir:** uygulamada `windows/` klasörü ve eklentiler olduğu için Geliştirici Modu kapalıyken `flutter pub get` sembolik bağ hatası verir.

### Telefon (Android)
- Ayarlar → Telefon hakkında → Yapım numarasına 7 kez dokun → Geliştirici seçenekleri → **USB hata ayıklama** açık.
- USB ile bağla. `flutter devices` telefonu göstermeli.
- Sevgilinin telefonuna kurulum: imzalı APK dosyası gönderilir, "bilinmeyen kaynaklardan yükleme" izni verilir. Rehber F1-24'te hazırlanır.

## 3. Doğrulama

Aşağıdaki komutların hepsi hatasız çalışmalı:

```bash
flutter doctor -v          # Android toolchain ✓ (Windows için Visual Studio ✓ Faz 3'te)
docker info
npx supabase --version
deno --version
uv --version
node --version
```

## 4. Kim ne yapar?

| İş | Sen | Ajan |
|---|---|---|
| Hesap açma, ödeme/limit, anahtar oluşturma | ✓ | — |
| Anahtarları secrets'a yazma | ✓ (komutu sen çalıştırırsın) | Komutu hazırlar |
| Geliştirici Modu, sistem ayarları | ✓ | — |
| Araç kurulumu | ✓ (ya da ajana onay verirsin) | Komutları hazırlar, doğrular |
| Kod, test, migrasyon, içerik üretimi | Onaylarsın (faz sonları, ücretli işlemler) | ✓ |
| Üretime migrasyon (`db push`), paket yükleme, web yayını | Onay verirsin | ✓ |
| İçerik örneklem incelemesi, ASR veri seti kaydı, günlük kullanım | ✓ | Araçları hazırlar |

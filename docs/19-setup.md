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
| 3 | **Google AI Studio (Gemini)** | aistudio.google.com → Google hesabıyla giriş → **Get API key** → **Create API key**. **Faturalandırma ekleme:** ücretsiz katmanda kalmalı. Kotalar AI Studio'nun kullanım sayfasında görünür (`gemini-3.1-flash-lite`, `gemini-3.5-flash`). | F1-15'ten önce |
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

Aynı `supabase/functions/.env` dosyası yerel geliştirmede (`npx supabase functions serve`) ve LLM eval'inde (`cd evals && deno run -A --env-file=../supabase/functions/.env run.ts --route answer_check`) de kullanılır. Bu dosya git dışıdır.

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
- Sevgilinin telefonuna kurulum: imzalı APK dosyası gönderilir, "bilinmeyen kaynaklardan yükleme" izni verilir. Rehber: §5.
- **Asıl uygulamanın kimliğiyle (`com.dilbaz.dilbaz_app`) telefona `flutter run`, `flutter install` ya da `flutter test` yapılmaz.** Flutter kurulum başarısız olunca (ör. imza farkı) eski uygulamayı kaldırıp yeniden kurar; cihazdaki veri gider. Geliştirme derlemeleri telefona her zaman `.local` ile kurulur (aşağıda).
- **Yerel yığına karşı deneme (F1-21):** Telefondaki uygulamaya dokunmadan, yanına ayrı bir kopya kurulur ("Dilbaz.local"; kendi kimliği ve verisi):
  ```bash
  cd app && DILBAZ_APP_ID_SUFFIX=.local flutter build apk --debug --dart-define-from-file=env/local.json
  adb install -r build/app/outputs/flutter-apk/app-debug.apk
  adb reverse tcp:54321 tcp:54321
  ```
  - `adb reverse`, telefonun `127.0.0.1:54321` adresini bilgisayardaki yerel Supabase'e bağlar. Giriş kodu yerel Mailpit'e düşer (`http://127.0.0.1:54324`).
  - Yerel test e-postası önce yerel veritabanında `private.signup_allowlist`'e eklenir. Paketler yerel yığına `dilbaz-content upload` ile yerel anahtarla yüklenir.
- **Uçtan uca testler (F1-24, `15` §4):** `app/integration_test/` ekranları, motoru ve cihazın SQLite'ını gerçek haliyle çalıştırır. Sunucu, LLM, ses, izinler ve bildirimler sahtedir; telefonda sistem penceresi açılmaz, bildirim kurulmaz.
  ```bash
  cd app && DILBAZ_APP_ID_SUFFIX=.local flutter test integration_test -d <cihaz> --no-uninstall
  ```
  - **`--no-uninstall` şart.** `flutter test`, test bitince kaldıracağı paketi derlemeden önce diskteki son APK'dan okur. Son derleme son eksizse asıl uygulamayı verisiyle kaldırabilir.
  - Telefonun ekranı açık ve kilitsiz olmalı. Test "Dilbaz.local"ı açıp kendi ilerletir (~1 dk); bu sırada telefona dokunulmaz.
  - Telefonsuz hızlı deneme (aynı senaryolar, ekransız): `flutter test integration_test -d flutter-tester`.

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

## 5. Sürüm APK ve iki telefona kurulum (F1-24)

Uygulama Play Store'a konmaz. İki telefona, **yükleme anahtarıyla imzalı** tek bir APK dosyası kurulur. Güncellemeler aynı anahtarla imzalanır ve eskisinin üstüne kurulur.

### 5.1 Yükleme anahtarı (bir kez, kendin yap)

1. Anahtarı oluştur (PowerShell). Parolayı sen belirlersin; sohbete yazma:

   ```powershell
   keytool -genkey -v -keystore $env:USERPROFILE\dilbaz-upload.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```

   - `keytool` bulunmazsa: `& "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" …`
   - İsim ve kurum soruları için gerçek bilgi gerekmez (ör. `Dilbaz`).
2. `app/android/key.properties` dosyasını bir düzenleyiciyle oluştur. Ters bölüler çift yazılır:

   ```properties
   storePassword=<parola>
   keyPassword=<parola>
   keyAlias=upload
   storeFile=C:\\Users\\<kullanıcı>\\dilbaz-upload.jks
   ```

3. **Yedekle:** `dilbaz-upload.jks` dosyasını ve parolayı parola yöneticine ve bir USB belleğe koy.
   - Anahtar kaybolursa uygulama güncellenemez. Tek yol kaldırıp yeniden kurmaktır ve cihazdaki veri gider. Sunucudaki kopya senkron açıksa kalır (F1-21).
   - Anahtar dosyası da `key.properties` de git dışıdır (`.gitignore`).

`key.properties` yoksa sürüm derlemesi hata ayıklama anahtarıyla imzalanır (`flutter run --release` çalışsın diye). Böyle bir APK dağıtılmaz; 5.2'deki imza denetimi bunu yakalar.

### 5.2 Derleme ve imza denetimi (ajan ya da sen)

```bash
cd app && flutter build apk --release --dart-define-from-file=env/prod.json
```

- Çıktı: `app/build/app/outputs/flutter-apk/app-release.apk`.
- Derleme sürerken aynı projede başka `flutter` komutu (test, analyze, run) çalıştırılmaz. O komutlar eklenti kayıt dosyasını geliştirme eklentileriyle yeniden yazar ve sürüm derlemesi `integration_test` paketini bulamadığı için düşer.
- İmzayı denetle:

  ```powershell
  & "$env:LOCALAPPDATA\Android\Sdk\build-tools\36.0.0\apksigner.bat" verify --print-certs app\build\app\outputs\flutter-apk\app-release.apk
  keytool -list -v -keystore $env:USERPROFILE\dilbaz-upload.jks -alias upload
  ```

  İki çıktıdaki SHA-256 aynı olmalı. `CN=Android Debug` görünürse `key.properties` okunmamıştır; APK dağıtılmaz.
- Her yeni sürümde `app/pubspec.yaml` içindeki `version` artırılır (`0.1.0+1` → `0.1.1+2`). Android, sayısı küçük ya da eşit olan sürümü güncelleme olarak kabul etmez.

### 5.3 Senin telefonun

- Telefonda şu an bilgisayardan kurulmuş, hata ayıklama anahtarıyla imzalı eski Dilbaz var. İmza farklı olduğu için yeni APK onun üstüne kurulmaz.
- **İlk kez:** eski uygulama kaldırılır (veri silme; ajan önce onay ister). Profil ve kurs sunucudan geri gelir. Kartlar, denemeler ve seviye testi sonucu, senkron üretimde açılmadan önce yalnızca telefondaydı (F1-21 migrasyonu `db push` bekliyor); onlar gelmez ve seviye testi yeniden önerilir.
- Kurulum:
  - USB ile: `adb install -r app/build/app/outputs/flutter-apk/app-release.apk` (`adb install -r`, imza farkında veriyi silmeden durur).
  - Ya da dosyayı telefona gönderip açarak (5.4'teki gibi).
- Sonraki güncellemeler eskisinin üstüne kurulur; **kaldırılmaz**.
- "Dilbaz.local" geliştirme kopyasıdır. Ayrı bir uygulamadır ve istenirse kaldırılır: `adb uninstall com.dilbaz.dilbaz_app.local`.

### 5.4 Sevgilinin telefonu

1. E-postası Supabase'de kayıt izin listesinde olmalı (§1, "Kayıt izin listesi").
2. APK dosyasını gönder: Quick Share, Google Drive ya da WhatsApp'ta **belge olarak**.
3. Telefonda dosyaya dokun. "Bu kaynaktan yüklemeye izin ver" sorulursa izin ver. Bu, telefonun sahibinin verdiği bir sistem iznidir; yalnızca o uygulama (ör. Dosyalarım, Chrome) için açılır.
4. Play Protect "tanınmayan uygulama" uyarısı gösterebilir: **Ayrıntılar → Yine de yükle.** Uyarı, Play'den gelmeyen her uygulamada çıkar.
5. Uygulamayı aç: e-posta → kod → karşılama akışı. Birlikte çalışmak için karşılamadaki ekip adımında senin verdiğin davet kodu girilir (ya da sonra Birlikte sekmesinden).
6. Bildirim ve mikrofon izinlerini uygulama gerektiğinde sorar; vermek telefonun sahibinin kararıdır.

### 5.5 Güncelleme

1. `version` artırılır ve 5.2'deki gibi derlenip imza denetlenir.
2. Dosya iki telefona da 5.3 / 5.4'teki gibi gönderilip eskisinin üstüne kurulur. Veri yerinde kalır.

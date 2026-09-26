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
| 2 | **Supabase** | Hesap aç → yeni proje: ad `dilbaz`, bölge **Central EU (Frankfurt)**. Güçlü bir veritabanı parolası belirle ve parola yöneticine kaydet. Project URL ve **publishable key**'i not et. | Faz 0 (F0-10) |
| 3 | **Anthropic** | console.anthropic.com → API anahtarı. **Aylık harcama limiti koy** (öneri: $50). | Faz 0 |
| 4 | **Deepgram** | Hesap aç ($200 başlangıç kredisi) → API anahtarı. | Faz 0 |
| 5 | **Azure** | Azure hesabı → "Speech" kaynağı, bölge **West Europe**, fiyatlandırma katmanı **F0 (ücretsiz)**. Anahtar ve bölgeyi not et. | Faz 0 |
| 6 | **Vercel** | Web sürümü için proje. | Faz 6 |

### Anahtarları ayarlama (kendin çalıştır)

```bash
# Proje klasöründe, Supabase CLI ile (bir kez)
npx supabase login
npx supabase link --project-ref <PROJE_REF>

# Sunucu tarafı gizli anahtarlar (uygulamaya asla girmez)
npx supabase secrets set ANTHROPIC_API_KEY=... DEEPGRAM_API_KEY=... AZURE_SPEECH_KEY=... AZURE_SPEECH_REGION=westeurope
```

Yerel geliştirme için aynı anahtarları `supabase/functions/.env` dosyasına yaz. Bu dosya git dışıdır.

Uygulama yapılandırması `app/env/prod.json` dosyasındadır (git dışı; yalnızca herkese açık bilgiler):

```json
{ "SUPABASE_URL": "https://<ref>.supabase.co", "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_..." }
```

### Supabase Auth ayarı (panelden)
- Authentication → Providers → Email: **açık**. "Confirm email" açık.
- Email Templates → "Magic Link" şablonuna kod ekle: `Kodun: {{ .Token }}`. Uygulama bağlantı değil 6 haneli kod kullanır.
- Authentication → Settings: yeni kayıtları kapat. İki kullanıcıyı panelden davet et ya da izin listesini kullan (ajan ayarlamayı gösterir).

## 2. Windows'a araç kurulumu

| Araç | Sürüm | Kurulum |
|---|---|---|
| Git | güncel | `winget install Git.Git` |
| Flutter SDK | 3.47.x (stable) | docs.flutter.dev → Windows kurulumu (zip ya da VS Code Flutter eklentisi). `flutter` PATH'te olmalı. |
| Android Studio | güncel stable | `winget install Google.AndroidStudio` → SDK Manager: Android SDK Platform 36, Build-Tools, Command-line Tools, Platform-Tools, Emulator. Sonra `flutter doctor --android-licenses`. |
| JDK | 17+ | Android Studio'nun gömülü JDK'sı yeterli |
| Docker Desktop | güncel | `winget install Docker.DockerDesktop` (WSL 2 ile). Yerel Supabase için gerekli. |
| Node.js | 20+ | `winget install OpenJS.NodeJS.LTS` (`npx supabase` için) |
| Supabase CLI | güncel | `npx supabase` (kurulum gerekmez) ya da Scoop: `scoop bucket add supabase https://github.com/supabase/scoop-bucket.git` → `scoop install supabase` |
| Deno | 2.x | `winget install DenoLand.Deno` (fonksiyon testleri ve eval) |
| Python | 3.12+ (sende 3.14 var) | Mevcut. `uv`: `winget install astral-sh.uv` |
| Visual Studio | 2022 veya 2026 | **Yalnızca Faz 3 (Windows derlemesi):** "Desktop development with C++" iş yükü |

### Windows Geliştirici Modu (kendin aç)
Flutter eklentileri sembolik bağ ister. **Ayarlar → Sistem → Geliştiriciler için → Geliştirici Modu: Açık.** Bu bir sistem güvenlik ayarıdır; ajan değiştirmez.

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

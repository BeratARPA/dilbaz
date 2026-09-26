# ADR-0006 — Ses sağlayıcıları

- **Durum:** Kabul edildi, **Faz 2 karşılaştırma testiyle kesinleşecek** (2026-09-26). **ADR-0009 ile kısmen değiştirildi:** Azure kullanılmıyor (kart gerekiyor). İngilizce ASR Deepgram kayıt kredisiyle; Türkçe ASR ve dinamik TTS cihaz üstü; paket sesleri Kokoro ile çevrimdışı; telaffuz kararı Faz 2 başında.

## Bağlam
Öğrenci konuşmasının transkripti kelimesi kelimesine olmalı. Araştırmalar Whisper'ın öğrenci hatalarını ve duraksamalarını "düzelttiğini" gösteriyor (`08` §2). Ayrıca telaffuz değerlendirmesi, Türkçe konuşma tanıma ve çok sesli TTS gerekiyor.

## Karar (başlangıç)
- **İngilizce öğrenci ASR:** Deepgram Nova-3, `filler_words=true`, kelime zamanları.
- **Telaffuz:** Azure Pronunciation Assessment, referans metinli REST, ≤ 30 sn, WAV 16 kHz.
- **Türkçe ASR ve TTS:** Azure AI Speech (tr-TR; nöral sesler).
- Tüm sağlayıcılar sunucuda, adaptör arayüzleri arkasındadır (`08` §3.3).

## Kesinleştirme
Faz 2'de (F2-01) kendi kayıtlarımızla karşılaştırma testi yapılır.
- **Adaylar:** Deepgram, AssemblyAI, Azure, OpenAI `gpt-transcribe`, `whisper-1`.
- **Birincil ölçüt:** hata koruma oranı ≥ %90.
- Sonuç bu dosyaya eklenir.

## Sonuçlar
- İki ses sağlayıcısı (Deepgram + Azure) + Anthropic: üç anahtar.
- Maliyet düşük: Deepgram kredisi ve Azure ücretsiz katman (`08` §10).
- Telaffuz değerlendirmesinde IPA ses adları ve prozodi yalnızca `en-US` yerel ayarında var. Ölçüt aksan değil, anlaşılırlıktır.

## Karşılaştırma testi sonuçları
_(Faz 2'de doldurulacak)_

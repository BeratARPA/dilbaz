# 20 — Sözlük

## Öğrenme bilimi ve dil edinimi

| Terim | Açıklama |
|---|---|
| **Hafızadan çağırma** (retrieval practice) | Bilgiyi tekrar görmek yerine hafızadan çıkarmaya çalışmak. Kalıcılığı artırır. |
| **Aralıklı tekrar** (spacing) | Çalışmayı zamana yaymak. Toplu çalışmadan daha kalıcıdır. |
| **FSRS** | Free Spaced Repetition Scheduler. Kartın ne zaman tekrar edileceğini hafıza modeline göre hesaplayan açık kaynak algoritma. |
| **Stabilite (S)** | FSRS'te hatırlama olasılığının %90'a düşmesi için geçmesi gereken gün sayısı. Büyüdükçe bilgi kalıcılaşır. |
| **Zorluk (D)** | FSRS'te kartın zorluk değeri (1–10) |
| **Hatırlama olasılığı (R)** (retrievability) | Belirli bir anda doğru hatırlama olasılığı |
| **Lapse** | Hatırlanan bir kartın unutulması (Again) |
| **İstenen zorluklar** (desirable difficulties) | O an zor gelen ama kalıcılığı artıran koşullar: çağırma, aralık, karıştırma |
| **Performans ≠ öğrenme** | Çalışma sırasındaki başarı, kalıcı öğrenmenin güvenilir göstergesi değildir |
| **TAP** (transfer-appropriate processing) | Neyi, nasıl pratik edersen onda gelişirsin |
| **Beceri edinimi** (skill acquisition) | Bildirimsel → işlemsel → otomatik bilgi aşamaları |
| **Dört kol** (four strands) | Nation: anlam odaklı girdi, anlam odaklı çıktı, dil odaklı çalışma, akıcılık |
| **Anlaşılır girdi / kapsama** | Metindeki bilinen kelime oranı. Öğrenme için ≥ %95, rahat anlama için ≥ %98. |
| **i+1** | Bilinenin bir adım ötesi: tek yeni öğe, geri kalanı bilinen |
| **Lemma / kelime ailesi** | Sözlük biçimi (go ← went). Kelime ailesi: türevlerle birlikte (happy, happiness). |
| **Kalıp** (chunk) | Birlikte ezberlenen ve kullanılan kelime grubu ("the problem is that…") |
| **Çıktı hipotezi** | Konuşmaya/yazmaya çalışmanın bilinmeyeni fark ettirmesi (Swain) |
| **İpucu merdiveni** | H0 durum → H1 hata türü → H2 yer → H3 kural → H4 cevap |
| **Uzmanlığın tersine dönme etkisi** | Yeni başlayana yardım eden rehberliğin ileri öğrenciye zarar vermesi |
| **İskele** (scaffold) | Geçici yardım: kelime taşları, Türkçe açıklama, yavaş ses… Seviyeyle azalır. |
| **Karıştırma** (interleaving) | Benzer/karışan öğeleri karışık sırada çalışmak |
| **L1 aktarımı** | Anadilin ikinci dildeki hatalara etkisi |
| **HVPT** | Çok sesli algı eğitimi: ses çiftlerini farklı konuşmacılardan dinleyip ayırt etme |
| **Minimal çift** | Tek bir sesle ayrılan kelime çifti (ship/sheep) |
| **Gölgeleme** (shadowing) | Duyduğunu hemen ardından tekrarlama |
| **4/3/2** | Aynı konuyu 4, 3, 2 dakikada anlatarak akıcılık geliştirme |
| **Aracılık** (mediation) | Okuduğunu/duyduğunu başkasına aktarma, açıklama (CEFR) |
| **Telafi stratejisi** | Bilmediği kelimenin etrafından dolaşma ("the thing you use to…") |
| **Öz belirleme kuramı** (SDT) | Motivasyon için özerklik, yetkinlik, bağlılık |
| **Uygulama niyeti** | "X olunca Y yaparım" planı |

## Ölçüm

| Terim | Açıklama |
|---|---|
| **CEFR** | Avrupa Ortak Dil Çerçevesi: A1–C2 seviyeleri, can-do tanımları |
| **Can-do** | "… yapabilir" biçimindeki yeterlik tanımı |
| **X_Lex** | Evet/hayır kelime boyutu testi (uydurma kelimelerle tahmin düzeltmesi) |
| **CAF** | Karmaşıklık, doğruluk, akıcılık: konuşma performansının üç boyutu |
| **EFC** | Hatasız cümlecik oranı (doğruluk ölçümü) |
| **MLR** | Ortalama akış uzunluğu: iki duraklama arasındaki kelime sayısı |
| **AS-birimi** | Konuşma çözümlemesi için sözce birimi (bağımsız cümlecik + bağlı öğeler) |
| **MTLD** | Metin uzunluğuna dayanıklı sözcük çeşitliliği ölçümü |
| **WER** | Kelime hata oranı (dikte ve ASR değerlendirmesi) |
| **Kanıt düzeyi** | new → learning → recallable → durable → transferred |

## Teknik

| Terim | Açıklama |
|---|---|
| **ASR / STT** | Konuşmayı yazıya çevirme |
| **TTS** | Metni seslendirme |
| **Telaffuz değerlendirmesi** | Referans metne göre ses/kelime doğruluğu puanlaması |
| **Kelimesi kelimesine transkript** (verbatim) | Hataları ve dolgu sözcüklerini düzeltmeden yazıya dökme |
| **LLM / rota** | Büyük dil modeli / Dilbaz'da tanımlı tek bir LLM görevi (ör. `answer_check`) |
| **Yapılandırılmış çıktı** | LLM'in şemaya uygun JSON döndürmesi |
| **Effort** | Claude'da düşünme derinliği ve token harcaması ayarı |
| **Prompt önbelleği** | Sabit prompt önekinin önbelleğe alınıp ucuz okunması |
| **Batch API** | Asenkron, %50 indirimli toplu LLM istekleri |
| **Eval** | LLM rotalarının altın vaka setiyle ölçülmesi |
| **RLS** | Postgres satır düzeyi güvenlik: her kullanıcı yalnızca kendi satırlarını görür |
| **Edge Function** | Supabase'in sunucu fonksiyonları (Deno/TypeScript) |
| **pgTAP** | Postgres için test çatısı |
| **drift** | Flutter için tipli SQLite kitaplığı |
| **Riverpod** | Flutter durum yönetimi kitaplığı |
| **Outbox** | Gönderilmeyi bekleyen yerel değişiklik kuyruğu |
| **UUIDv7** | Zamana göre sıralı benzersiz kimlik |
| **LWW** | Son yazan kazanır (çakışma çözümü) |
| **Olay günlüğü** (event log) | Değiştirilemez kayıtlar. Durum bunlardan hesaplanır. |
| **Dil paketi** | Bir dile ya da dil çiftine ait tüm veri (versiyonlu SQLite) |
| **Sentetik dil (`zz`)** | Motorun dilden bağımsızlığını test eden anlamsız dil |
| **ADR** | Mimari karar kaydı |

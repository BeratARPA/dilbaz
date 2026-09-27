# en@1 taşıyıcı cümleleri: QA raporu

Tarih: 2026-09-27 · Görev: F1-03 (S3–S4) · Çıktı: `content/packs/en/items/sentences.jsonl`

## Özet

| | |
|---|---|
| Cümle | 588 (Tatoeba 560, kendi 28) |
| Seviye | A0 42 · A1 411 · A2 135 |
| Ortalama uzunluk | 5.4 kelime (en uzun 9) |
| Taşıyıcısı olan anlam | 600/600 |
| Küratörlükle değişen seçim | 373 anlam (28 kendi cümle) |
| Bağımsız doğrulama, 1. tur | 587 cümle, 523 kabul |
| Bağımsız doğrulama, 2.–3. tur (yeni cümleler) | 69 cümle, 65 kabul |
| Paketteki doğrulanmış cümle | 588/588 |
| Düzeltilecek Türkçe çeviri (S5) | 65/560 Tatoeba çevirisi |
| Engelleyici sorun (S4) | 0 |

## Süreç

1. **S3 adayları:** Tatoeba'nın Türkçe çevirili 654 bin İngilizce cümlesi spaCy ile analiz edildi. Seviye, gramer ve paket dışı yapı filtresinden geçen en iyi 3 aday her anlam için listelendi (`10` §4.3).
2. **S4 küratörlük:** 600 anlamın otomatik seçimi tek tek incelendi. Deyimler, yanlış anlamlar, karamsar ton ve tekrar eden kalıplar değiştirildi (`curation/en/sentences.yaml`). Aynı lemmanın iki anlamı (right, too, free, letter) yalnızca elle seçildi.
3. **Bağımsız doğrulama (`10` §5.2):** Üretim gerekçelerini görmeyen ayrı ajan oturumları her cümleyi puanladı: doğallık (1–5), dilbilgisi, belirsizlik, hedef anlamın doğru kullanımı, uygunluk ve Türkçe çevirinin geri çeviriyle doğruluğu. Kabul: doğallık ≥ 4, dilbilgisi doğru, belirsizlik yok, hedef anlam doğru, uygun.
4. **Düzeltme:** Reddedilenlerin yerine yeni cümleler seçildi ve yeni turlarda yine bağımsız olarak doğrulandı (2. tur 65 cümle, 3. tur 4 cümle). Kararlar `curation/en/sentences.validation.jsonl` dosyasında; S4, kabul edilmiş kaydı olmayan cümleyi raporlar.
5. **Türkçe:** Yanlış çeviri İngilizce cümleyi reddetmez; doğrulamanın önerdiği düzeltme (`turkish_fix`) S5'te kullanılır.

## 1. turda ret nedenleri

64 cümle reddedildi (bir cümlenin birden çok nedeni olabilir):

- hedef anlam dışı kullanım: 27
- doğallık 3: 25
- belirsiz: 22
- uygunsuz: 2

Örnekler: "Nice to meet you, too." (meet = tanışmak, açıklama buluşmak diyor), "Let's start from the top." (deyim), "Let's go have a drink." (içki anlamı), "He has a great body." (uygunsuz). `wish` ve `need` açıklamaları da bu sırada düzeltildi.

Bir istisna kayıtlı: "Can I have the check, please?" belirsiz bulundu, çünkü Türkçedeki "çek" yanlış arkadaş. İngilizce cümle doğru ve öğretilmesi gereken tam da bu ayrım olduğu için tutuldu; çeviri S5'te "Hesabı alabilir miyim?" olur.

## Gramer dağılımı

En sık kodlar: `gp.pronouns.subject` 269, `gp.be.present` 165, `gp.articles.the` 160, `gp.articles.a_an` 127, `gp.nouns.plural` 84, `gp.present_simple.affirmative` 76, `gp.demonstratives` 68, `gp.possessive.adjectives` 64.

Cümlesi olmayan gramer noktaları: `gp.age`, `gp.possessive.s`, `gp.comparatives`, `gp.present_simple_vs_continuous`. Bunlar S7 metinlerinde ve gramer noktalarının kendi örneklerinde çalışılır.

## Bilinen sınırlar

- Gramer etiketleyicisi kural tabanlı; emin olmadığında kod vermez. Kaçırdığı yapılar elle ve bağımsız doğrulamada yakalandı.
- Tatoeba çevirilerinin bir kısmı kelimesi kelimesine ya da hatalı; S5 bunları düzeltir.
- Doğrulama bir dil modeli tarafından yapıldı. Aşağıdaki 20 örnek kullanıcıların kontrolü içindir (`10` §1.3).

## 👤 20 örnek (rastgele, tohum 2026)

Her satır için: cümle doğal mı, hedef kelime o anlamda mı, Türkçe doğru mu?

| # | Seviye | Cümle | Hedef | Türkçe |
|---|---|---|---|---|
| 1 | A0 | I'm good at games. | **game** (an activity with rules that you play for fun) | Ben oyunlarda iyiyim. |
| 2 | A0 | I'm sure you're right. | **sure** (certain, with no doubt) | Haklı olduğundan eminim. |
| 3 | A0 | I'm a little early. | **early** (before the usual or expected time) | Ben biraz erken geldim. |
| 4 | A1 | What's the matter? | **matter** (a problem or subject (What's the matter?)) | Sorun nedir? |
| 5 | A1 | The movie was too long. | **movie** (a film) | Film çok uzundu. |
| 6 | A1 | The house is too cold. | **cold** (having a low temperature) | Ev çok soğuk. |
| 7 | A1 | You can ride with me. | **ride** (to travel on a bike or a horse, or in a vehicle) | Benimle binebilirsin. |
| 8 | A1 | What does this note mean? | **note** (a short written message) | Bu not ne anlama geliyor? |
| 9 | A1 | Does that answer the question? | **answer** (to reply to a question or a call) | Bu, soruyu yanıtlıyor mu? *(düzeltilmiş)* |
| 10 | A1 | I don't have that information. | **information** (facts about something) | O bilgi bende yok. *(düzeltilmiş)* |
| 11 | A1 | Draw a line on the paper. | **line** (a long thin mark) | Kağıdın üzerine bir çizgi çizin. |
| 12 | A1 | I've got a party tonight. | **tonight** (this evening or night) | Bu gece bir partim var. |
| 13 | A1 | I don't think that's true. | **true** (correct, based on facts) | Onun doğru olduğunu sanmıyorum. |
| 14 | A1 | This box is light. | **light** (not heavy) | Bu kutu hafif. |
| 15 | A1 | Do you often drink milk? | **drink** (to take liquid into your mouth and swallow it) | Sık sık süt içiyor musun? |
| 16 | A2 | It is ten degrees below zero now. | **degree** (a unit for measuring temperature (20 degrees)) | Şimdi sıcaklık sıfırın altında on derece. |
| 17 | A2 | Thank you for your time and effort. | **effort** (hard work to do something) | Zamanınız ve çabanız için teşekkür ederim. |
| 18 | A2 | I'm going to the center of town. | **center** (the middle of something; a building for an activity) | Şehir merkezine gidiyorum. |
| 19 | A2 | My brother lives in a small village. | **village** (a very small town in the countryside) | Erkek kardeşim küçük bir köyde yaşıyor. |
| 20 | A2 | What are you going to do next? | **next** (after this, then) | Daha sonra ne yapacaksın? |

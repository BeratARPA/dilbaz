# ADR-0010 — Küçük hatada hedefi motor belirler

- **Durum:** Kabul edildi (2026-10-09).
- **Kullanıcı kararı:** "Küçük hata kararında 'hedef doğru mu' bilgisini LLM yerine motor hesaplasın."
- **İlgili:** I-04, I-11, I-17; `03` §0.2 ve §0.5; `07` §4.1 ve §8.

## Bağlam

- `minor_error` kararında cevabın kart için sayılıp sayılmadığı `target_ok`'a bağlıdır (`03` §0.2). Hata hedefteyse cevap yanlış sayılır; değilse doğru. Kanıt (I-04) ve FSRS puanı buna göre işler.
- `answer_check` eval'i (2026-10-08/09, `evals/results/`) LLM'in bu alanda güvenilmez olduğunu gösterdi:
  - **`@1`:** Anlamı değiştiren ya da dilbilgisi kartının yapısını bozan hataları `minor_error` saydı.
  - **`@2`:** O hataları düzeltti. Ama kelime kartında hedef dışındaki küçük hatada `target_ok=false` demeye başladı; hedefi doğru söyleyen öğrenci kaldı (I-17).
  - **`@3`:** Katı karar doğruluğunda eşiği geçti (%93,7). Bu kez hatası hedefin içinde olan küçük hataları `target_ok=true` saydı; örneğin be kartında "this tea very hot" geçti.
  - Öğrenciye yansıyan geçti/kaldı uyumu üç sürümde de ~%84'te kaldı. İstem bir yöne itildikçe `target_ok` öbür yöne kaydı.
- Motorun deterministik denetleyicisi bu bilgiyi zaten hesaplıyor (`03` §0.5 adım 4). Cevabı, hedefi söyleyen en yakın doğru cevapla kelime kelime hizalıyor ve farkların hedef kısma değip değmediğine bakıyor. Hedef kısım hedef öğenin lemmalarıyla bulunuyor. Lemma yoksa (dilbilgisi kartı) cümlenin tamamı hedef sayılıyor.

## Karar

- LLM `minor_error` dediğinde `target_ok`'u motor belirler: `AnswerChecker.targetIntact` ve `Evaluation.settled`. Hedef kelimelerin hepsi cevapta doğru biçimde ve yerindeyse doğru, değilse yanlış. Dilbilgisi kartında küçük hata kalır sayılır, çünkü hedef yapının kendisidir.
- Öteki kararlar LLM'den geldiği gibi kalır. `wrong`, `off_target` ve `unintelligible` zaten `target_ok=false` taşır. `acceptable_variant`'ta hedefsiz cevabı LLM'in `target_ok`'u ve listeler belirler.
- **LLM'in rolü:** kararın türü (doğru, varyant, küçük hata, yanlış, başka şey, emin değil), hata etiketleri ve ipucu merdiveni. Bu ayrım I-11 ile örtüşür: kart için sayılma kuralı deterministiktir.
- **Sonradan gelen karar:** LLM'e ulaşılamayınca ya da cevap itiraz edilince istek saklanır. Motorun hedef hükmü de cevap anında, cevap anahtarı elimizdeyken hesaplanıp yanına konur: denemenin `llm.target_intact` alanı ve itirazın `target_intact` alanı (`13`). Geç gelen `minor_error` bu değerle yerleşir. Bu alandan önce saklanmış cevaplarda LLM'in değeri kalır.

## Sonuçlar

- **Benzetim:** `@3`'ün 285 kararı motorun hedef hükmüyle yerleşince öğrenciye yansıyan uyum %84,2'den %96,5'e çıkıyor. Kalan 10 farkın 5'i sertlik, 5'i hoşgörü yönünde; hepsi LLM'in karar türünden geliyor, sertlik artmıyor.
- **Altın set testi** (`answer_check_golden_test.dart`, CI): Motorun hedef hükmü, altın setin yalnızca `minor_error` dediği 49 vakanın 48'inde altın `target_ok` ile aynı. Tek fark tartışmalı bir vaka: "What time does it close?" için "what time it closes". Eşik %5.
- `answer_check@3`'ün istemindeki `target_ok` yönergesi kalır ama küçük hatada belirleyici değildir. İstem değişikliği gerekmez, yeni eval gerekmez.
- Eval'in katı karar doğruluğu, öğrenciye yansıyan sonucu tek başına göstermez. `07` §8'e öğrenciye yansıyan uyum ölçütü not edildi.

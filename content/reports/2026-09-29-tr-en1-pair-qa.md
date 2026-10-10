# tr-en@1 çift paketi: QA raporu

Tarih: 2026-09-29 · Görev: F1-04 (S5) · Çıktı: `content/packs/tr-en/`

## Özet

| | |
|---|---|
| Karşılık | 600 anlam (229'unda kullanım notu), 120 kalıp, 40 gramer noktası |
| Cümle istemi | 588: Tatoeba 364, küratörlük 166, doğrulama düzeltmesi 58 |
| Varyant (hedefi söyleyen doğru cevap) | Cümle: 482 kartta 1.206 · Kalıp: 81 kartta 153 |
| Alternatif (hedefsiz doğru cevap) | Cümle: 78 kartta 100 · Kalıp: 74 kartta 174 |
| İstemle gösterilen bağlam | 32 kart |
| H3 kural notu | 40 |
| Karşıtlık notu | 34 |
| Hata etiketi | 45: gramer 29, kelime 6, telaffuz 7, algı 2, pragmatik 1 |
| Engelleyici sorun (`pair`) | 0 |

## Süreç

1. **Yazım:** Türkçe karşılıklar, istemler, varyantlar, kural notları, karşıtlık notları ve hata kataloğu bir Claude Code oturumunda yazıldı (`curation/tr-en/`, ADR-0009).
2. **Deterministik kontroller (`10` §6.1):**
   - Her öğenin karşılığı var.
   - Varyant hedef kelimeyi içeriyor, alternatif içermiyor.
   - Aynı istemi paylaşan kartlar birbirinin cevabını kabul ediyor.
   - H3 notu hiçbir kartın cevabını ya da hedef biçimini vermiyor.
3. **Bağımsız inceleme:** Yazan oturumdan ayrı beş ajan oturumu içeriği yazım gerekçelerini görmeden inceledi. Bir oturum anlamları, üçü cümleleri, biri kalıpları, gramer notlarını, karşıtlıkları ve etiketleri aldı. Öneriler tek tek değerlendirildi. Doğru olanlar uygulandı, bazıları alternatife çevrildi, İngilizce kelimeli ipucu önerileri alınmadı.

## İnceleme bulguları

| Alan | Bulgu | Uygulanan |
|---|---|---|
| Cümle istemleri (588) | 3 Türkçe hatası; 75 istem hedef kelimeye götürmüyor; 3 yanlış varyant; 595 eksik varyant önerisi | 3 düzeltme; 31 istem yeniden yazıldı ya da bağlam aldı; eş anlamlı cevaplar alternatif oldu; 3 varyant silindi; önerilen varyantların hepsi (hedef kontrolünden geçen) |
| Anlam karşılıkları (600) | 7 yanlış ya da eksik karşılık; 10 yanlış not; 35 not önerisi | Hepsi |
| Kalıplar (120) | 1 Türkçe hatası, 1 bağlam; 225 eksik cevap önerisi | Hepsi; cevaplar varyant ya da alternatif olarak sınıflandı |
| Gramer (40) | 23 noktada açıklama ya da H3 düzeltmesi | Hepsi |
| Karşıtlık (29) | 7 not düzeltmesi, 5 yeni çift | Hepsi |
| Hata etiketleri (40) | 17 düzeltme, 5 yeni etiket | Hepsi |

Örnekler:
- **Yanlış not:**
  - check (isim) notu "banka çeki anlamına gelmez" diyordu; ABD İngilizcesinde gelir.
  - date notu "I have a date with the doctor" hatasına yol açıyordu.
  - tell notu "say the truth" hatasını besliyordu.
- **Yanlış karşılık:** fine için "idare eder" (so-so demek), guy için "çocuk" (kid ile çakışıyordu).
- **H3 sızıntısı:** Bazı notlar kartın hedef biçimini veriyordu. "go → went", "I went to see a show today." kartında fiili veriyordu. children, people, the best, works, goes da böyleydi. Yeni kontrol bu biçimleri yakalıyor.
- **Hedefe götürmeyen istem:** "Yaptıklarım için" what I did'e, "Doktor olmak isterim" be'ye, "Saatim" hem watch hem clock'a gidiyordu.
- **Olgu hatası:** gp.age açıklaması Türkçede yaşın have ile söylendiğini ima ediyordu. "Did you ever go to London?" Amerikan İngilizcesinde doğru olduğu halde hata örneğiydi.

## Kararlar

- **Hedefsiz doğru cevap (kullanıcı kararı):** Türkçede tek kelimeyle karşılanan eş anlamlıları istem ayıramaz (hediye: present/gift). Öğrenci eş anlamlıyı söylerse cevap yanlış sayılmaz. Ama hedefin kanıtı da sayılmaz ve istem hedef için yeniden sorulur. Bu cevaplar pakette `alternatives` listesindedir, LLM'siz de tanınır. Kural `01` P9/I-17 ve `03` §0.2–0.3'e yazıldı. Motor tarafı F1-07'de yapılacak.
- **Normalizasyon eklemeleri:**
  - "He's got" ile "He has got" eşleşir. 's ve 'd, got ve been önünde has ve had olarak açılır.
  - "$30" ile "thirty dollars" eşleşir.
  - "programmes" ile "programs", "Goodnight" ile "good night", "Türkiye" ile "Turkey" eşleşir.
- **Varyant kontrolü:**
  - Hedef kelime S1 sözlüğünün biçimleriyle de aranır ("good at singing").
  - Tireli kelimenin parçası sayılmaz.
- **S4'e dönüş:**
  - ride anlamının taşıyıcısı "Can you ride a bike?" oldu. 4. turda bağımsız olarak doğrulandı.
  - Gramer etiketleyicisinde iki düzeltme yapıldı: olumsuz emir ve zaman edatı. Cümleler değişmedi, yalnızca gramer kodları değişti.

## Bilinen sınırlar

- İnceleme bir dil modeli tarafından yapıldı. Türkçe istemler kullanıcıya görünen metinlerdir. Aşağıdaki örnekler isteğe bağlı bir göz atma içindir.
- Tatoeba çevirilerinin yazımı olduğu gibi bırakıldı (dükkan, kağıt). Kendi metinlerimiz TDK yazımını izliyor (dükkân, dâhil).
- Varyantlar geniş, ama tam değil. Listede olmayan doğru cevabı LLM kabul eder ve kişisel varyant olarak ekler. LLM yoksa hizalama devreye girer (`03` §0.5).
- "My name is …" gibi boşluklu kalıpların değerlendirmesi (sondaki ad) motor işidir (F1-07).

## İsteğe bağlı örnekler (rastgele 12 cümle kartı, tohum 2026)

| # | İstem | Referans | Varyantlar | Alternatifler |
|---|---|---|---|---|
| 1 | Sende bir kopyası var mı? | Do you have a copy? | Have you got a copy?; Do you have a copy of it?; Have you got a copy of it? | — |
| 2 | Sık sık süt içer misin? | Do you often drink milk? | Do you drink milk often? | — |
| 3 | Güçlü olduğunu düşünüyor musun? | Do you think you're strong? | Do you think that you're strong? | — |
| 4 | Saçım kızıl değil. | I don't have red hair. | My hair isn't red. | — |
| 5 | Ben de bu rengi severim. | I like this color, too. | I also like this color.; I like this color as well.; I love this color, too. | — |
| 6 | Yeni şeyler öğrenmeyi seviyorum. | I love learning new things. | I love to learn new things.; I like learning new things.; I like to learn new things. | — |
| 7 | Artık ödemeye hazırım. | I'm ready to pay now. | Now I'm ready to pay. | — |
| 8 | Yapacak ödevim var. | I've got homework to do. | I have homework to do.; I have some homework to do.; I've got some homework to do. | — |
| 9 | Senin kazanmanı istiyorum. | I want you to win. | — | — |
| 10 | Ağabeyim müzik sever. | My big brother likes music. | My older brother likes music.; My elder brother likes music.; My big brother loves music.; My older brother loves music. | — |
| 11 | Kağıda düz bir çizgi çekti. | She drew a straight line on the paper. | He drew a straight line on the paper. | — |
| 12 | En sevdiğin müzik grubu hangisi? | What's your favorite music group? | What's your favorite band?; Which is your favorite music group?; Which is your favorite band? | — |

Alternatif örnekleri: "Here's a gift for you." (present), "Where can I buy a ticket?" (get), "My pleasure." (You're welcome), "Hi." (Hello).

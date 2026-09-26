# 01 — Pedagoji: Öğrenme Bilimi Spesifikasyonu

Bu doküman Dilbaz'ın "neden böyle çalıştığını" tanımlar. Kod, içerik ve arayüzdeki her karar buradaki ilkelere ve **değişmez kurallara (I-01 … I-18)** uymak zorundadır. Kaynakların tam künyesi `references.md` içindedir.

---

## 1. Öğrenme nedir?

**Tanım:** Öğrenme, bir bilgiyi ya da beceriyi **aradan zaman geçtikten sonra**, **yardım almadan**, gerektiğinde **yeni bir bağlamda** ve **yeterli hızda** doğru kullanabilmektir.

Bu tanımdan dört test çıkar. Dilbaz bir şeye "öğrenildi" demeden önce bunlara bakar:

| Test | Soru | Dilbaz'daki karşılığı |
|---|---|---|
| Gecikme | Günler/haftalar sonra hâlâ yapabiliyor mu? | FSRS stabilitesi, gecikmeli başarılı tekrar |
| Yardımsızlık | İpucu, çeviri, seçenek olmadan yapabiliyor mu? | İpucusuz doğru deneme |
| Aktarım | Çalıştığı bağlam dışında kullanabiliyor mu? | Serbest konuşma/yazıda hatasız kullanım |
| Hız | Konuşma hızında yapabiliyor mu? | Cevap gecikmesi, konuşma akıcılık ölçümleri |

### Performans ≠ öğrenme

Çalışma sırasındaki performans, kalıcı öğrenmenin kötü bir göstergesidir (Soderstrom & Bjork, 2015). Tekrar okumak, cevabı hemen görmek, aynı şeyi arka arkaya yapmak **o an** iyi hissettirir ama az kalıcılık üretir. Hafızadan çağırmak, aralık vermek, karıştırmak ise o an zor gelir ama daha kalıcıdır ("istenen zorluklar", Bjork, 1994).

Sonuç: Dilbaz öğrencinin o anki rahatlığını değil, **gecikmeli ve yardımsız başarısını** optimize eder. Öğrenciler kendi öğrenmelerini sistematik olarak yanlış değerlendirir (Bjork, Dunlosky & Kornell, 2013); bu yüzden Dilbaz **öz değerlendirmeye değil performansa** dayanır (örneğin FSRS puanını öğrenci değil, sistem cevabından hesaplar).

---

## 2. İlkeler

Her ilke: **ne diyor → kanıt → Dilbaz'da nasıl uygulanır → ilgili kurallar.**

### P1 — Hafızadan çağırma (retrieval practice)

- **Ne diyor:** Bilgiyi tekrar görmek yerine hafızadan çıkarmaya çalışmak, uzun vadeli hatırlamayı güçlü biçimde artırır.
- **Kanıt:** Roediger & Karpicke (2006): tekrar test edilen grup, bir hafta sonra tekrar çalışan gruptan belirgin şekilde daha iyi hatırladı; öğrenciler ise tersini tahmin etti. Dunlosky vd. (2013): uygulamalı test ve aralıklı çalışma "yüksek fayda", tekrar okuma ve altını çizme "düşük fayda".
- **Uygulama:** Her kart ve alıştırma bir üretim ya da çağırma denemesiyle başlar. "Bak ve geç" türü etkinlik yok. İlk tanıtım ekranı bile tanıtımdan hemen sonra bir çağırma denemesiyle biter.
- **Kurallar:** I-01, I-05.

### P2 — Aralıklı tekrar (spacing) ve FSRS

- **Ne diyor:** Aynı toplam sürede, çalışmayı zamana yaymak toplu çalışmaktan daha kalıcıdır. En iyi aralık, hedeflenen hatırlama süresi uzadıkça uzar.
- **Kanıt:** Cepeda vd. (2006) geniş meta-analiz; Cepeda vd. (2008) optimal aralık ile hatırlama süresi ilişkisi; Kim & Webb (2022) ikinci dil öğreniminde aralıklı çalışmanın gecikmeli testlerde belirgin üstünlüğü.
- **Uygulama:** Tekrar zamanlarını **FSRS** belirler (Ye vd., 2022; açık kaynak benchmark'ta SM-2'den belirgin daha iyi tahmin). Varsayılan hedef hatırlama olasılığı **%90**. Yeterli tekrar verisi birikince (bkz. `04-learner-model.md`) FSRS parametreleri **kişiye özel optimize edilir**. Takvim bazlı sabit tekrar (ör. "Cumartesi kelime tekrarı") yoktur.
- **Kurallar:** I-07, I-08.

### P3 — Neyi pratik edersen onda gelişirsin (transfer-appropriate processing)

- **Ne diyor:** Bellek performansı, öğrenme sırasındaki işlem ile test sırasındaki işlem ne kadar benzerse o kadar iyidir.
- **Kanıt:** Morris, Bransford & Franks (1977). Kelime öğreniminde yön etkisi: İngilizce→Türkçe çalışmak tanımayı, Türkçe→İngilizce çalışmak üretimi daha çok geliştirir (Webb, 2009).
- **Uygulama:** Kullanıcıların hedefi konuşmak olduğu için kartlarda **varsayılan cevap biçimi sesli üretimdir** (Türkçe anlam → İngilizce söyle). Yazılı üretim ikinci seçenektir. Tanıma (çoktan seçmeli, eşleştirme) yalnızca dinleme/okuma için gereken alıcı bilgi ve A0 başlangıcı içindir; üretim kanıtı sayılmaz.
- **Kurallar:** I-05.

### P4 — Dil bir konu değil, bir beceridir (skill acquisition)

- **Ne diyor:** Beceri üç aşamada gelişir: **bildirimsel bilgi** ("kuralı biliyorum") → **işlemsel bilgi** ("yavaşça uygulayabiliyorum") → **otomatiklik** ("düşünmeden, hızlı ve doğru").
- **Kanıt:** DeKeyser (2007, 2015) Skill Acquisition Theory. Otomatikleşme ancak çok sayıda, anlamlı ve giderek hızlanan kullanımla gelir.
- **Uygulama:** Her yapı için akış: kısa açık açıklama → kontrollü üretim → serbest üretim → zaman baskılı üretim (4/3/2, konuşma görevi). Cevap gecikmesi (latency) loglanır ve otomatiklik göstergesi olarak kullanılır.
- **Kurallar:** I-03, I-05.

### P5 — Dört kol dengesi (Nation'ın four strands çerçevesi)

- **Ne diyor:** İyi dengelenmiş bir dil programında zaman kabaca dört eşit kola ayrılır:
  1. **Anlam odaklı girdi** (`input`): anlamaya odaklı dinleme ve okuma.
  2. **Anlam odaklı çıktı** (`output`): bir şey anlatmak için konuşma ve yazma.
  3. **Dil odaklı çalışma** (`language`): kelime, gramer, telaffuz üzerine bilinçli çalışma.
  4. **Akıcılık gelişimi** (`fluency`): zaten bilinen malzemeyi hızlı kullanma.
- **Kanıt:** Nation (2007); Nation & Newton (2009).
- **Uygulama:** Her etkinlik bir kola etiketlenir (`03-activities.md`). Planlayıcı dengeyi **günlük değil haftalık** kurar ve seviyeye göre küçük ayarlar yapar (`05-session-planner.md`). Dizi izlemek gibi uygulama dışı girdi de "medya günlüğü" ile girdi koluna sayılabilir, ama 30 dakikalık bütçeye dahil değildir.

### P6 — Anlaşılır girdi ve kelime kapsaması

- **Ne diyor:** Bir metinden öğrenebilmek için içindeki kelimelerin büyük çoğunluğunu bilmek gerekir: en az **%95**, rahat anlama için **%98**. Rastlantısal kelime öğrenimi çok sayıda karşılaşma gerektirir.
- **Kanıt:** Hu & Nation (2000); Laufer & Ravenhorst-Kalovski (2010); Nation (2006) (roman/film için 8–9 bin kelime ailesi); Uchihara, Webb & Yanagisawa (2019) karşılaşma sıklığı meta-analizi.
- **Uygulama:** Her metin ve ses için lemma listesi paketle birlikte gelir. Uygulama, **kişiye özel kapsama oranını** hesaplar (öğrencinin bildiği lemmalar ÷ metindeki lemmalar). %95'in altındaki metin önerilmez. %95–98 arasındaysa bilinmeyen ilk birkaç kelime önceden öğretilir. Akıcılık okumaları için %98+ şartı aranır.
- **Kurallar:** I-06.

### P7 — Çıktı ve "boşluğu fark etme"

- **Ne diyor:** Konuşmaya/yazmaya çalışmak, öğrencinin söylemek istediği ile söyleyebildiği arasındaki boşluğu fark etmesini sağlar. Bu fark ediş öğrenmeyi tetikler.
- **Kanıt:** Swain (1985, 1995) çıktı hipotezi.
- **Uygulama:** "Söyleyemediklerim" defteri bu anı yakalar. Takılınan her cümle kişisel bir karta dönüşür. Konuşma görevlerinden sonra en önemli 3 düzeltme tekrar üretilir.

### P8 — Açık öğretim işe yarar, ama tek başına yetmez

- **Ne diyor:** Kuralı açıkça öğretmek, örtük öğretimden daha etkilidir. Ancak kuralı bilmek otomatik kullanım getirmez.
- **Kanıt:** Norris & Ortega (2000); Spada & Tomita (2010) meta-analizleri.
- **Uygulama:** Gramer öğeleri kısa bir açıklama ve örnekle tanıtılır (A seviyelerinde Türkçe), hemen ardından kontrollü üretim, sonra serbest üretim gelir. Açıklama asla tek başına bir "ders" olarak bırakılmaz.

### P9 — Geri bildirim: önce deneme, ipucu merdiveni, adım düzeyi

- **Ne diyor:**
  - Yanlış da olsa önce denemek, ardından doğruyu görmek öğrenmeyi artırır (Kornell, Hays & Bjork, 2009).
  - Öğrenciyi kendi hatasını düzeltmeye iten ipuçları, doğrusunu doğrudan söylemekten çoğu zaman daha etkilidir (Lyster & Saito, 2010).
  - Adım adım geri bildirim veren sistemler insan öğretmene çok yaklaşır. Yalnızca son cevaba doğru/yanlış diyen sistemler çok geride kalır (VanLehn, 2011).
  - Cevabı veren yapay zekâ pratikte performansı artırıp gerçek öğrenmeyi azaltabilir. İpucu veren sürüm bu zararı önler (Bastani vd., 2025).
- **Uygulama — İpucu merdiveni (H0–H4):**

  | Seviye | Öğrenci ne görür | Örnek ("I have problem with my key") |
  |---|---|---|
  | H0 | Sadece durum: doğru / neredeyse / tekrar dene | "Neredeyse!" |
  | H1 | Hata türü | "Bir kelime eksik." |
  | H2 | Hatanın yeri | "'problem' kelimesinden önce." |
  | H3 | Kural/açıklama | "Tekil sayılabilir isimden önce a/an gerekir." |
  | H4 | Doğru cevap | "I have a problem with my key." |

  Merdiven tek bir LLM çağrısıyla üretilir, istemci adım adım açar. H4 ancak son adımda ya da kullanıcı açıkça "göster" derse görünür. Akıcılık ve konuşma görevlerinde geri bildirim **görev bitince** verilir (araya girilmez) ve en fazla 3 düzeltmeyle sınırlıdır.
- **Kurallar:** I-01, I-02, I-11, I-17.

### P10 — Doğru zorluk (~%80–85 başarı)

- **Ne diyor:** En etkili öğretmenler, alıştırmalarda yaklaşık %80 başarı oranı sağlar (Rosenshine, 2012). Çok kolay iş sıkar, çok zor iş bunaltır (akış kavramı, Csikszentmihalyi, 1990).
- **Uygulama:** Planlayıcı, son 7 günün ipucusuz doğru oranını izler. Oran %90'ın üstündeyse zorluğu artırır (daha az iskele, yeni yapılar), %70'in altındaysa azaltır (daha çok tekrar, daha basit görev). FSRS'in %90 hedef hatırlaması aynı mantıkla uyumludur.

### P11 — Doğru yöntem seviyeye göre değişir (uzmanlığın tersine dönme etkisi)

- **Ne diyor:** Yeni başlayana yardım eden ayrıntılı rehberlik, ilerlemiş öğrenciye yük olur ve öğrenmesini yavaşlatır. Tersine, rehbersiz serbest ortam yeni başlayanı boğar.
- **Kanıt:** Kalyuga vd. (2003); Kirschner, Sweller & Clark (2006).
- **Uygulama:** İskele türleri (kelime taşları, Türkçe açıklama, yavaş ses, ipucu yoğunluğu, çoktan seçmeli seçenekler) seviyeye bağlı açılıp kapanır. Ayrıntı: `02-curriculum.md` §3.
- **Kurallar:** I-09.

### P12 — Karıştırarak çalışma (interleaving)

- **Ne diyor:** Birbirine benzeyen, karıştırılan öğeleri karışık sırada çalışmak, ayırt etmeyi ve uzun vadeli hatırlamayı güçlendirir.
- **Kanıt:** Kornell & Bjork (2008); ikinci dil gramerinde Nakata & Suzuki (2019).
- **Uygulama:** `contrasts_with` bağıyla işaretli öğeler (say/tell, house/home, Past Simple/Present Perfect, a/the) ilk öğrenmeden sonra karışık setlerde çalıştırılır.
- **Kurallar:** I-10.

### P13 — Sıklık önceliği

- **Ne diyor:** En sık 2000–3000 kelime ailesi günlük konuşmanın büyük kısmını (%90–95 civarı) karşılar. En yüksek getiri önce sık kelimelerdedir.
- **Kanıt:** Nation (2006, 2013); Milton (2010) CEFR seviyesi–kelime sayısı ilişkisi.
- **Uygulama:** Müfredat haritasındaki sıralama önce önkoşullara, sonra **sıklık sırasına**, sonra kişisel ilgiye (Söyleyemediklerim, iş alanı) göre yapılır. Nadir kelimeler (ör. "formalism") A–B seviyelerinde öğretilmez.

### P14 — Kalıplar (chunks) ve cümle birimi

- **Ne diyor:** Akıcı konuşmanın büyük kısmı hazır kalıplardan oluşur. Kelime tek başına değil, kullanımıyla (eşdizimler, yapı) öğrenilir.
- **Kanıt:** Pawley & Syder (1983); Wray (2002); Nation (2013) kelime bilgisinin boyutları (biçim, anlam, kullanım).
- **Uygulama:** Temel öğrenme birimi **cümle ve kalıptır**. Kelime (`word_sense`) öğeleri bile bağlam cümlesiyle çalışılır. Türkçesi aynı olan kelimeler (say/tell = söylemek) karşıtlık olarak modellenir.

### P15 — Anadilin etkisi (L1 transfer)

- **Ne diyor:** Öğrencinin anadili, hangi hataları yapacağını büyük ölçüde öngörür.
- **Kanıt:** Odlin (1989); Swan & Smith (2001), Türkçe konuşanlar bölümü.
- **Uygulama:** Dil çifti paketi (tr→en), Türkçe konuşanların tipik hatalarını **kapalı bir hata etiketi listesi** olarak tanımlar (a/the, he/she/it, 3. tekil -s, kelime sırası, Present Perfect, edatlar, "var" → there is/have, soru kurma; telaffuzda /θ ð/, w/v, ünlü uzunluğu, sondaki ötümlü ünsüzün ötümsüzleşmesi, başta ünsüz kümesine ünlü ekleme). Bu liste ilk günden kişiselleştirme sağlar: sistem hatayı adlandırabilir, planlayıcı haftalık odak seçebilir.

### P16 — Akıcılık gelişimi

- **Ne diyor:** Tanıdık malzemeyle, artan zaman baskısı altında tekrarlanan konuşma akıcılığı artırır.
- **Kanıt:** Arevart & Nation (1991), 4/3/2 tekniği; De Jong & Perfetti (2011): 4/3/2 akıcılığı ve işlemselleşmeyi artırdı.
- **Uygulama:** 4/3/2 etkinliği (aynı konu 4, 3, 2 dakika). Yalnızca bilinen malzemeyle yapılır (yeni kelime yok). Tur tur dakikadaki kelime sayısı gösterilir.

### P17 — Dinleme: algı, ayırt etme, altyazı

- **Ne diyor:**
  - Ses çiftlerini farklı konuşmacılardan dinleyip ayırt etme alıştırması (HVPT) ses algısını ve telaffuzu geliştirir (Logan, Lively & Pisoni, 1991; Thomson, 2018).
  - Aynı dilde altyazı (İngilizce ses + İngilizce altyazı), dinlemeyi ve kelime öğrenmeyi destekler (Montero Perez vd., 2013).
  - Telaffuzda öncelik "anlaşılırlık"tır, yerli gibi konuşmak değil (Levis, 2005; Jenkins, 2000).
- **Uygulama:** Minimal çift ayırt etme (birden çok ses), dikte, gölgeleme. Dizi izlerken İngilizce altyazı önerisi. Telaffuz hedefleri anlaşılırlığa göre önceliklendirilir (`02-curriculum.md` §5).

### P18 — Motivasyon: iş gibi hissettirmemek

- **Ne diyor:**
  - İnsan bir işe **özerklik** (seçim bende), **yetkinlik** (ilerlediğimi görüyorum) ve **bağlılık** (birlikte yapıyoruz) hissettiğinde gönüllü devam eder (Ryan & Deci, 2000).
  - Önceden vaat edilen ödüller içten gelen motivasyonu zayıflatabilir. Yetkinlik bilgisi veren geri bildirim güçlendirir (Deci, Koestner & Ryan, 1999).
  - Tek bir günü atlamak alışkanlık oluşumunu bozmaz (Lally vd., 2010).
  - "X olunca Y yaparım" planları hedefe ulaşmayı belirgin şekilde artırır (Gollwitzer & Sheeran, 2006).
- **Uygulama:** Kota, günlük seri, "kaçırıldı" etiketi, kırmızı uyarı ve puan/rozet ekonomisi yoktur. Bunların yerine şunlar vardır:
  - Haftalık hedef
  - Her gün 2–3 seçenek arasından seçim
  - Kendi sesinden ilerleme ("3 ay önceki sen")
  - Çiftin ortak hedefi
  - Kullanıcının seçtiği bir alışkanlık çıpası ve o saatte tek bir davet bildirimi

  Ayrıntı: `09-ux-motivation.md`.
- **Kurallar:** I-12, I-13, I-14.

### P19 — Birlikte öğrenme

- **Ne diyor:** Öğrencilerin kendi aralarında konuşması öğrenmeye katkı sağlar. Ancak konuşurken dikkat anlama gittiği için birbirlerinin dil hatalarını nadiren fark edip düzeltirler.
- **Kanıt:** Philp, Adams & Iwashita (2014); Sato & Ballinger (2016).
- **Uygulama:** Çift görevleri (sohbet kartları, iki telefonla bilgi boşluğu) kaydedilir. Düzeltme işini partner değil **uygulama** yapar, görev bittikten sonra, her kişiye ayrı.

### P20 — Öğrenmeyi öğretmek (üst biliş)

- **Ne diyor:** Öğrenciler etkili stratejileri (test etme, aralık) küçümser ve verimsiz olanları (tekrar okuma) tercih eder (Bjork, Dunlosky & Kornell, 2013). Bu inançlar öğretilebilir.
- **Uygulama:** Haftada bir, 1 dakikalık "Öğrenme bilimi notu": o haftanın deneyimine bağlı kısa bir açıklama. Örneğin: "Bu hafta ipucu kullandığın kartlar, cevabını hemen gördüklerinden daha iyi hatırlandı. Nedeni şu…". Uygulama her tasarım kararının "neden"ini açıklayabilir (Ayarlar → "Neden böyle?").

### P21 — Yapay zekâ korkulukları

- **Ne diyor:** Yapay zekâ öğretmen, iyi tasarlandığında büyük kazanım sağlayabilir (Kestin vd., 2025; De Simone vd., 2025). Cevabı veren bir asistan ise öğrenmeyi azaltabilir (Bastani vd., 2025).
- **Uygulama:**
  - LLM yalnızca tanımlı rotalarda, yapılandırılmış JSON ile çalışır.
  - Öğrenci denemeden cevap vermez.
  - Hata etiketlerini kapalı listeden seçer.
  - Emin değilse "belirsiz" döner.
  - Değerlendirme bir eval setiyle sürekli ölçülür.

  Ayrıntı: `07-ai-tutor.md`.
- **Kurallar:** I-11.

---

## 3. Değişmez kurallar (I-01 … I-18)

Bu kurallar kod incelemesinde ve testlerde kontrol edilir. Bir kuralı esnetmek gerekiyorsa önce bu dosyada gerekçesiyle değiştirilir, sonra kod değişir.

| Kod | Kural |
|---|---|
| **I-01** | **Önce deneme.** Hiçbir etkinlik, öğrenci cevap denemeden ya da açıkça "bilmiyorum" demeden doğru cevabı göstermez. İstisnalar: yeni öğenin ilk tanıtım ekranı ve kullanıcının kendisinin istediği Söyleyemediklerim önerisi. |
| **I-02** | **İpucu merdiveni.** Yanlış/eksik cevapta H1→H3 ipuçları önce gelir. H4 (cevap) en son ya da kullanıcı isteyince açılır. Akıcılık/konuşma görevlerinde geri bildirim görev bitince verilir ve en fazla 3 düzeltmeyle sınırlıdır. |
| **I-03** | **Her deneme loglanır.** Her deneme `attempts` tablosuna değiştirilemez bir kayıt olarak yazılır. Kart durumları bu kayıtlardan yeniden hesaplanabilir. |
| **I-04** | **Kanıta dayalı ilerleme.** "Hatırlanıyor / kalıcı / aktarıldı" etiketleri yalnızca `04-learner-model.md` kurallarıyla verilir. Uydurma yüzde gösterilmez. Belirsizlik aralık ve güven düzeyiyle gösterilir. |
| **I-05** | **Pratik = hedef.** Konuşma hedefi için varsayılan cevap biçimi sesli üretimdir. Tanıma alıştırmaları üretim kanıtı sayılmaz. |
| **I-06** | **Anlaşılır girdi.** Kişisel kelime kapsaması %95'in altındaki okuma/dinleme metni önerilmez. %95–98 arasındaysa önce bilinmeyen kelimeler öğretilir. Akıcılık okuması için %98+ gerekir. |
| **I-07** | **Tekrar yükü korunur.** Yeni öğe sayısı, öngörülen günlük tekrar süresini tavanın (varsayılan 10 dk) altında tutacak şekilde sınırlanır. |
| **I-08** | **Aralığı hafıza belirler.** Tekrar zamanlarını FSRS belirler. Takvim bazlı sabit tekrar yoktur. |
| **I-09** | **Rehberlik seviyeyle azalır.** İskeleler seviye tablosuna göre açılır/kapanır. C seviyelerinde varsayılan olarak kapalıdır, kullanıcı açabilir. |
| **I-10** | **Karışık çalışma.** `contrasts_with` bağlı öğeler ilk öğrenmeden sonra karışık setlerde çalıştırılır. |
| **I-11** | **Yapay zekâ düşünmeyi devralmaz.** LLM öğrenci denemeden cevap üretmez ve öğrencinin cümlesini onun yerine tamamlamaz. Hata etiketlerini kapalı listeden seçer, emin değilse `uncertain` döner. |
| **I-12** | **Suçluluk yok.** "Kaçırıldı", kırmızı uyarı, seri kaybı ve günlük kota yoktur. Haftalık hedef vardır; bir günün atlanması hiçbir şeyi sıfırlamaz. |
| **I-13** | **Zaman bütçesi.** Planlayıcı kullanıcının günlük bütçesini (varsayılan 30 dk) aşan öneri yapmaz. Bütçe dolunca "bugünlük yeter" der. Kullanıcı devam edebilir ama bunun için ekstra ödül verilmez. |
| **I-14** | **Özerklik.** Planlayıcı önerir, kullanıcı seçer (en az 2 seçenek). Zorunlu etkinlik yoktur; aylık test dahil her şey davettir. |
| **I-15** | **Dilden bağımsız motor.** `dilbaz_engine` içinde dile özgü kelime, kural, liste ya da metin yoktur. Hepsi paketlerden gelir. |
| **I-16** | **Doğrulanmış içerik.** Pakete giren her öğe otomatik kontrollerden geçer ve kaynağı/lisansı kayıtlıdır. Kullanıcı hatalı içeriği bildirebilir. |
| **I-17** | **Adil değerlendirme.** Doğru cevabın geçerli varyantları (başka ifade, kısaltma, eş anlamlı) kabul edilir. Referans cümleye birebir uyma zorlanmaz. |
| **I-18** | **Ses verisi mahremiyeti.** Kayıtlar yalnızca sahibine açıktır. Partner yalnızca özet bilgileri görür (`14-security-privacy.md`). |

---

## 4. Kaçınılacaklar (anti-desenler)

| Anti-desen | Neden zararlı | Yerine |
|---|---|---|
| Kelime = tek Türkçe karşılık | Farkları (say/tell) saklayamaz | Cümle/kalıp + karşıtlık bağları |
| Cevabı hemen göstermek | Çağırma olmaz | İpucu merdiveni |
| Öğrencinin "biliyorum" demesine güvenmek | Tanıdıklık yanılsaması | Performanstan otomatik puan |
| Günlük seri, kota, "kaçırıldı" | Kontrol hissi, motivasyon kaybı | Haftalık hedef, seçim |
| Seviyesiz "otantik" içerik (A2'de haber) | Anlaşılmayan girdi öğretmez | Kapsama ≥ %95 kuralı |
| Tüm hataları düzeltmek | Bilişsel yük, cesaret kırar | En önemli 3 düzeltme, tekrar eden hatalara odak |
| Tanımayı üretim sanmak | Pratik ≠ hedef | Sesli üretim varsayılanı |
| Aynı gün 10 doğru = öğrendi | Performans ≠ öğrenme | Gecikmeli, yardımsız kanıt |
| Beceri başına uydurma yüzde | Sahte kesinlik | Kanıt sayıları + güven aralığı |
| Takvime bağlı sabit tekrar | Hafızaya duyarsız | FSRS |

---

## 5. Deneyle çözülecek açık sorular

Bu sorular `16-experiments.md`'deki uygulama içi deneylerle yanıtlanacak:

1. Sesli üretim mi, yazılı üretim mi daha kalıcı? (Aynı öğrencide, öğe düzeyinde rastgele atama.)
2. İpucu merdiveni mi, doğrudan düzeltme mi? (Kalıcılık ve süre maliyeti.)
3. Karşıtlık setlerinde karışık mı, bloklu mu?
4. Dizi bölümü öncesinde bilinmeyen kelimeleri önceden öğretmek, izleme sonrası hatırlamayı artırıyor mu?
5. Kişiye özel FSRS parametreleri, varsayılana göre tekrar yükünü azaltıyor mu?

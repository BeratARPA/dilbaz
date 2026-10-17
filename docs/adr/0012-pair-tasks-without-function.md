# ADR-0012 — İkili görev: içerik pakette, oturum RPC ile

- **Durum:** Kabul edildi (2026-10-17).
- **İlgili:** ADR-0002, ADR-0003, ADR-0007; I-15, I-16, I-18; `03` A15, `12` §7 (`pair` fonksiyonu), `13` §2.5.

## Bağlam

- Plan (`12` §7, `13` §2.5): `pair` Edge Function'ı (`create`, `join`, `submit`) rol yüklerini yalnızca ilgili katılımcıya verecekti; `pair_roles` tablosunda her katılımcı yalnızca kendi rolünü görecekti; Realtime özel kanal `pair:{id}`.
- Görevlerin içeriği (rollerin bilgisi, cevap anahtarı) diğer içerik gibi dil paketlerindedir (ADR-0008, I-16). Fonksiyonlarda paket yoktur. Fonksiyonun rol dağıtması için içeriği ayrıca fonksiyon koduna üretmek gerekirdi; paket zaten cihazdadır.
- Rol bilgisini sunucudan saklamak, iki partner arasında bir hileyi önlemek içindir. Birlikte öğrenen iki kişi için bu tehdit gerçek değildir; "diğer rolü görmemek" bir arayüz kuralıdır.
- `03` A15'teki görev türleri resimlidir (resmi tarif etmek, iki resmin farkları). Paketlerde resim yoktur; resim üretmek ve lisanslamak ayrı bir iştir.

## Karar

- **İçerik:** Bilgi boşluğu görevleri hedef pakette `pair_info_gap` görevleridir: iki rolün İngilizce bilgi satırları, seçenekler ve cevap anahtarı. Çift paketinde Türkçe başlık, görev ve rol yönergeleri. Diğer görevler gibi bağımsız kontrolden geçer (I-16).
- **Resim yerine metin kartları:** İlk sürümde üç tür: *kim/hangisi* (bir rol tarif eder, öbürü dört seçenekten seçer), *plan* (bir rolde tarife, öbüründe kısıtlar; seçen rol seçer), *farklar* (iki rolün altışar satırı; her rol kendi listesinde farklı olanları işaretler).
- **Oturum:** `pair_sessions` tablosu (katılımcılar okur) ve SECURITY DEFINER RPC'ler: `pair_start` (ekip arkadaşını davet eder, rolleri atar), `pair_join`, `pair_answer` (yalnızca çağıranın cevabı), `pair_cancel`. İstemci tabloya doğrudan yazmaz. Değişiklikler Realtime ile iki telefona gelir (`stream`). `pair_roles` tablosu ve `pair` fonksiyonu yoktur.
- **Başarı:** Cevap anahtarı paketten gelir; iki cevap gelince motor (`InfoGapCheck`) deterministik olarak hesaplar. İki telefon aynı sonucu bulur; sonuç `pair_answer`'da saklanmaz, her telefon kendi oturum kaydına yazar.
- **Kişisel geri bildirim:** Her telefon yalnızca kendi sahibinin bas-konuş kayıtlarını yazıya döker (I-18). Görev sonunda dökümler `speaking_annotate` ile işaretlenir; motor en önemli 2 düzeltmeyi seçer (`pickCorrections`, `count: 2`). Ses saklanmaz.

## Sonuçlar

- Yeni fonksiyon ve dağıtım yok; görev eklemek yalnızca içerik işidir.
- Bir partner, isterse cihazındaki paketten öbür rolün bilgisini okuyabilir. Kabul edilen bir sınırdır.
- Resimli görevler (resmi tarif et, resim farkları) sonraki bir içerik görevine kaldı.
- `12` §7 ve `13` §2.5 bu karara göre güncellendi.

# Dilbaz

Bir dili sıfırdan ileri seviyeye **gerçekten** öğreten, öğrenme bilimine dayalı kişisel öğrenme sistemi. İlk dil çifti: Türkçe konuşanlar için İngilizce.

- **Durum:** Faz 0 (temel kurulum) sürüyor (2026-09-26). Güncel durum: [docs/17-roadmap.md](docs/17-roadmap.md).
- **Platformlar:** Android (öncelik), Windows, web. Tek kod tabanı: Flutter.
- **Temel fikir:** Ders değil, öğrenme kanıtı. Önce dene, sonra gör. Az ama her gün. İlerlemeni kendi sesinden duy.

## Nereden başlamalı?

| Ne istiyorsun? | Dosya |
|---|---|
| Projenin ne olduğunu anlamak | [docs/00-overview.md](docs/00-overview.md) |
| "Öğrenme nedir, neden böyle?" | [docs/01-pedagogy.md](docs/01-pedagogy.md) |
| Ne zaman ne yapılacak | [docs/17-roadmap.md](docs/17-roadmap.md) |
| Kurulum, hesaplar, anahtarlar (senin yapacakların) | [docs/19-setup.md](docs/19-setup.md) |
| Claude Code'un çalışma kuralları | [CLAUDE.md](CLAUDE.md) |

## Kodlamayı başlatmak

1. Bu klasörü Claude Code'da proje klasörü olarak aç.
2. [prompts/kickoff.md](prompts/kickoff.md) içindeki promptu yapıştır.
3. Sonraki oturumlarda [prompts/continue.md](prompts/continue.md), faz sonlarında [prompts/phase-review.md](prompts/phase-review.md).

## Doküman haritası

`docs/00-overview.md` §7'de tüm dokümanların listesi ve ne zaman okunacağı var. Mimari kararlar: `docs/adr/`.

## Lisans

- **Kod:** [MIT](LICENSE).
- **İçerik verisi** (`content/` altındaki paketler ve küratörlük dosyaları): açık lisanslı kaynaklardan türetilir. Her kaynağın lisansı ve atfı [`content/sources.yaml`](content/sources.yaml) dosyasında kayıtlıdır (Tatoeba CC BY 2.0 FR, NGSL ve Octanove CC BY-SA 4.0, Wiktionary/Wiktextract CC BY-SA 4.0, CMUdict BSD-2-Clause, CEFR-J atıfla serbest). CC BY-SA kaynak içeren paketler CC BY-SA 4.0 ile dağıtılır; ayrıntı: [`docs/10-content-pipeline.md`](docs/10-content-pipeline.md) §2.

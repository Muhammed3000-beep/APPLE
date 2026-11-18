# Pre-Apple I Prototype & Woz Monitor (1975)

Apple'ın 1976'da piyasaya sürdüğü ilk bilgisayar olan **Apple I**'den bile daha eski bir dönemi; Steve Wozniak'ın 1975 yılında Homebrew Computer Club günlerinde MOS 6502 işlemcisi üzerinde geliştirdiği **256 baytlık Woz Monitor** ve prototip sistemini tarayıcı üzerinde simüle eden tek dosyalık web uygulamasıdır.

## GitHub Pages ile Yayınlama
1. GitHub'da yeni bir repository oluşturun (örneğin: `apple-woz-monitor-1975`).
2. Bu arşivdeki `index.html` ve `README.md` dosyalarını deponuza yükleyin.
3. Depo ayarlarından **Settings > Pages** bölümüne girin.
4. **Source** kısmından `Deploy from a branch` seçeneğini ve `main` dalını seçip kaydedin.
5. Birkaç saniye içinde siteniz canlı olarak yayına alınacaktır.

## Temel Komutlar
- `FF00` : Belirtilen hex bellek adresini okur.
- `FF00.FF1F` : İki adres arasındaki bellek dökümünü (Hex Dump) verir.
- `0200: A9 42` : Belirtilen adrese makine kodu (hex baytları) yazar.
- `0300.0345A` : Bellek içeriğini ASCII metin olarak okur.
- `E000R` : Integer BASIC yorumlayıcısını başlatır.
- `?` : Yardım menüsünü gösterir.

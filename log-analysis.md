# Erişim logu analizi

Sunucu internete açıldıktan sonra erişim loglarında biriken trafiğin incelenmesi. Amaç, dışarı açılan bir servisin pratikte ne tür isteklerle karşılaştığını somut olarak görmek.

## Gözlem penceresi

| | |
| --- | --- |
| Süre | ~6 saat |
| Toplam istek | 339 |
| Benzersiz kaynak adres | 137 |
| Ortalama | ~59 istek/saat |

Site hiçbir yerde duyurulmadı, hiçbir siteden bağlantı verilmedi. Gelen trafiğin tamamı kendiliğinden keşif.

## Nasıl bulundu

**Certificate Transparency.** Let's Encrypt verdiği her sertifikayı herkese açık bir log'a yazar. Bazı tarama servisleri bu log'u anlık izleyip yeni alan adlarını dakikalar içinde ziyaret eder. Loglarda `GenomeCrawlerd` (Nokia) ve `Infrawatch` imzaları bu tür araştırma tarayıcılarına ait.

**IP aralığı taraması.** 404 dönen isteklerin 21'i kök dizine (`/`) yapılmıştı — bunlar alan adını değil doğrudan IP adresini deneyen taramalar.

## Aranan yollar

En çok 404 dönen istekler:

```
29  /favicon.ico
21  /
 6  /robots.txt
 4  /SDK/webLanguage
 2  /wp-login.php
 1  //xmlrpc.php?rsd
 1  //wp/wp-includes/wlwmanifest.xml
 1  /wp-json/batch/v1
 1  /wp-content/debug.log
 ...
```

`wlwmanifest.xml` dosyası dokuz farklı yol varyantında denenmişti: `/wp/`, `/wp1/`, `/wp2/`, `/wordpress/`, `/website/`, `/test/`, `/sito/`, `/web/`. Bu, WordPress kurulumunun hangi alt dizinde olduğunu bulmaya çalışan bir parmak izi çıkarma denemesi.

## Üç farklı tarama türü

Gelen trafik tek tip değildi; en az üç ayrı amaç ayırt edilebiliyor.

**1. CMS zafiyet taraması.** WordPress dosyalarını arayan istekler. Amaç, bilinen açığı olan bir sürüm bulmak.

**2. Ağ cihazı arayüzü taraması.** `/SDK/webLanguage` yolu, bazı ağ cihazlarının ve appliance'ların yönetim arayüzüne ait bir imza. Varsayılan parolayla açık bırakılmış cihazlar aranıyor.

**3. Phishing kit taraması.** Tek bir kaynaktan gelen bir istek dizisi şu dosyaları aradı: `twint_ch.js`, `raif_ch.js`, `lkk_ch.js`, `qrcode_twint.js`, `assets/js/auth.js`. Bunlar İsviçre bankacılık sistemlerine ait dosya adları (Twint bir ödeme uygulaması, Raiffeisen bir banka). Bu bir zafiyet taraması değil: ele geçirilmiş sunucularda barındırılan dolandırıcılık sayfalarını bulmaya çalışan bir tarayıcı.

Üçüncüsü beklenmedikti ve en öğretici olanı oldu — internete açık bir sunucunun maruz kaldığı trafik yalnızca "açık ara" aramakla sınırlı değil.

## Analizde kullanılan komutlar

nginx varsayılan olarak *combined* formatta log yazar; alanlar boşlukla ayrıldığı için `awk` yeterli.

```bash
# toplam istek
wc -l /var/log/nginx/access.log

# benzersiz kaynak adres sayısı
awk '{print $1}' /var/log/nginx/access.log | sort -u | wc -l

# en çok istek yapan adresler
awk '{print $1}' /var/log/nginx/access.log | sort | uniq -c | sort -rn | head -15

# 404 dönen yollar
awk '$9==404 {print $7}' /var/log/nginx/access.log | sort | uniq -c | sort -rn | head -20

# istemci imzaları
awk -F'"' '{print $6}' /var/log/nginx/access.log | sort | uniq -c | sort -rn | head -15
```

## fail2ban sonuçları

İlk ölçümde `nginx-botsearch` jail'i sıfır gösterdi. Sebebi bir yapılandırma hatasıydı ve ayrıca belgelendi (`troubleshooting.md`, bölüm 6): jail `error.log` okuyordu, ancak 404 dönüşleri yalnızca `access.log` dosyasına yazılıyordu.

`access.log` okuyan özel filtre yazıldıktan sonra mevcut log üzerinde test edildi ve 23 eşleşme buldu. Jail yalnızca yeni satırları izlediği için geçmiş denemelere ban uygulanmadı.

## Sitede ortaya çıkan eksikler

Log analizi, saldırı tespiti dışında iki pratik eksiği de gösterdi:

- `/favicon.ico` 29 kez 404 döndü. Bunlar bot değil, gerçek tarayıcılardı — sekmede ikon görünmüyordu. SVG ikon sayfaya `data:` URI olarak gömülerek çözüldü.
- `/robots.txt` 6 kez istendi ve yoktu. Dosya eklendi.

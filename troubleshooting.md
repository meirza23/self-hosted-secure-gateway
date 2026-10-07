# Karşılaşılan sorunlar

Proje boyunca karşılaştığım sorunlar ve nasıl teşhis ettiğim. Çoğu, yapılandırmanın doğru olduğu halde beklenen sonucu vermediği durumlardı.

---

## 1. CGNAT: dışarıdan erişim neden mümkün olmayabilir

**Belirti.** Port yönlendirme kuralı doğru yazılmasına rağmen dışarıdan erişim yok, hata mesajı da yok.

**Teşhis.** `canyouseeme.org` üzerinden yapılan testin sonucu belirleyici oldu:

- `Connection refused` → paket hedefe ulaşıyor ama reddediliyor (dinleyen servis yok)
- `Connection timed out` → paket hedefe **hiç ulaşmıyor**

İkincisi geldiğinde sorunun sunucuda değil yolda olduğu anlaşılır. Kontrol yöntemi:

```bash
# modem arayüzündeki WAN IP ile dış IP karşılaştırılır
# farklıysa (özellikle 100.64.x.x–100.127.x.x aralığı) CGNAT vardır
```

**Arka plan.** CGNAT'ta operatör tek bir public IP'yi çok sayıda aboneye paylaştırır. İçeriden dışarı çıkış sorunsuz çalışır çünkü bağlantıyı abone başlatır ve çeviri tablosunda kaydı oluşur. Dışarıdan gelen bağlantıda ise böyle bir kayıt yoktur; operatörün cihazı paketi hangi aboneye vereceğini bilemez ve düşürür. Modemdeki yönlendirme kuralı doğru olsa bile trafik modeme hiç ulaşmaz.

**Çözüm.** Operatörden routable (CGNAT dışı) IP talep etmek. Kritik olan adresin "statik" olması değil, dışarıdan ulaşılabilir olmasıdır — dinamik ama public bir adres de iş görür, yalnızca DNS kaydının güncellenmesi gerekir.

---

## 2. ISS'nin engellediği port

**Belirti.** CGNAT elendikten sonra bile 8080 portunda `Connection timed out`.

**Teşhis.** Modem WAN IP'si ile dış IP aynıydı, yani gerçek public IP vardı. Yönlendirme kuralı listede aktif görünüyordu. Geriye ISS'nin port engellemesi ihtimali kaldı.

**Çözüm.** Port 8888'e geçildi ve erişim sağlandı. Değişiklik üç yerde birden yapılmalı: web sunucusu, işletim sistemi güvenlik duvarı, modem kuralı.

**Not.** Ev aboneliklerinde 80 ve 443 inbound trafiği de sık engellenir. Bu kurulumda engellenmemişti; engellenseydi Let's Encrypt doğrulaması HTTP-01 yerine DNS-01 yöntemiyle yapılabilirdi (DNS sağlayıcısının API anahtarıyla, 80 portuna hiç ihtiyaç duymadan).

---

## 3. Hairpin NAT: iç ağdan yapılan testler yanıltıcı

**Belirti.** Kurulum dışarıdan çalışıyor ama kendi Wi-Fi ağından public IP'ye erişilemiyor.

**Açıklama.** Hairpin NAT (NAT loopback), iç ağdaki bir cihazın kendi public IP'sine bağlanıp tekrar iç ağa yönlendirilmesidir. Birçok ev modemi bunu desteklemez. Destek yoksa çalışan bir kurulum bile içeriden erişilemez görünür.

**Sonuç.** Dışarıdan erişim testleri mutlaka farklı bir ağdan yapılmalı — mobil veri veya harici bir test servisi.

---

## 4. DHCP havuzunun tüm aralığı kaplaması

**Belirti.** Sunucuya sabit yerel adres verilecek ama modemin DHCP havuzu 2–254 arasını kapsıyor; havuz dışından adres seçmek mümkün değil.

**Risk.** Havuz içinden manuel adres seçilirse modem bunu bilmez. Kiralama süresi dolduğunda aynı adresi başka bir cihaza verebilir ve iki cihaz çakışır.

**Çözüm.** Havuzun bitiş değeri 200'e çekildi, üstü manuel kullanıma ayrıldı. Alternatif olarak DHCP reservation (MAC adresine sabit IP bağlama) da kullanılabilirdi; bu daha temiz bir yöntemdir çünkü modem adresin kime ait olduğunu bilir.

---

## 5. cloud-init'in SSH ayarını ezmesi

**Belirti.** `/etc/ssh/sshd_config` dosyasında `PasswordAuthentication no` yazılı, servis yeniden başlatıldı, ancak parola ile giriş çalışmaya devam ediyor.

**Teşhis.** Dosyaya bakmak yerine **gerçekte uygulanan** değer sorgulandı:

```bash
sudo sshd -T | grep -i passwordauthentication
# passwordauthentication yes
```

Çıktı `yes` olduğuna göre ayar başka bir yerden eziliyordu. Kaynak arandı:

```bash
ls -la /etc/ssh/sshd_config.d/
sudo grep -r PasswordAuthentication /etc/ssh/sshd_config.d/
# /etc/ssh/sshd_config.d/50-cloud-init.conf:PasswordAuthentication yes
```

**Açıklama.** Ubuntu 24.04, `sshd_config.d` altındaki dosyaları ana yapılandırmadan **sonra** okur ve bunlar üzerine yazar. cloud-init kurulum sırasında oraya kendi dosyasını bırakmıştı.

**Çözüm.** İlgili dosyadaki satır düzeltildi. Doğrulama dosyayı okuyarak değil, davranışı test ederek yapıldı:

```bash
ssh -o PubkeyAuthentication=no kullanici@sunucu
# Permission denied (publickey)
```

**Çıkarım.** Yapılandırma dosyasının içeriği ile servisin gerçekte uyguladığı değer farklı olabilir. `sshd -T` gibi "efektif yapılandırmayı göster" komutları bu yüzden değerli.

---

## 6. fail2ban'in nginx jail'i hiçbir şey yakalamıyor

**Belirti.** Erişim loglarında onlarca WordPress tarama denemesi var ama `nginx-botsearch` jail'i sıfır gösteriyor.

**Teşhis.** Jail'in hangi dosyayı okuduğuna bakıldı: `/var/log/nginx/error.log`. Ancak site yapılandırmasındaki `try_files $uri $uri/ =404` dahili bir dönüş üretiyor ve nginx bunu hata olarak kaydetmiyor. Yani tarama denemeleri `access.log` dosyasında 404 olarak duruyor, `error.log` dosyasına hiç düşmüyor.

**Çözüm.** `access.log` okuyan özel bir filtre yazıldı (`config/nginx-noscript.conf`). Bilinen zafiyet yollarını (`wp-`, `xmlrpc`, `phpmyadmin`, `.env`, `.git` vb.) 404 veya 403 durum koduyla birlikte arıyor.

Filtre uygulanmadan önce mevcut log üzerinde test edildi:

```bash
sudo fail2ban-regex /var/log/nginx/access.log /etc/fail2ban/filter.d/nginx-noscript.conf
# Lines: 353 lines, 0 ignored, 23 matched, 330 missed
```

Eşik 2 deneme, ban süresi 24 saat olarak ayarlandı. Statik bir sitede bu yolları arayan bir isteğin meşru olma ihtimali yok.

**Ek not.** nginx jail'lerinde `backend = polling` kullanıldı. SSH jail'i `systemd` backend'i kullanıyor çünkü Ubuntu 24.04 SSH loglarını journal'a yazıyor; nginx ise dosyaya yazıyor ve aynı ayar orada çalışmıyor.

---

## 7. OCSP stapling artık çalışmıyor

**Belirti.** TLS sertleştirmesi için `ssl_stapling on` eklendiğinde nginx uyarı veriyor:

```
"ssl_stapling" ignored, no OCSP responder URL in the certificate
```

**Teşhis.** Sertifikanın içeriği kontrol edildi; OCSP adresi gerçekten yoktu. Bunun yerine CRL dağıtım noktası vardı:

```bash
echo | openssl s_client -connect metopal.site:443 2>/dev/null \
  | openssl x509 -noout -text | grep -A2 "CRL Distribution"
```

**Açıklama.** Yapılandırma hatası değil. Let's Encrypt OCSP desteğini sonlandırdı: 7 Mayıs 2025'te sertifikalardan OCSP adresleri kaldırıldı, 6 Ağustos 2025'te sunucular tamamen kapatıldı. Gerekçeleri gizlilik ve altyapı sadeliği — OCSP sorgusunda sertifika otoritesi, hangi ziyaretçinin hangi siteye bağlandığını anlık olarak görebiliyordu. İptal bilgisi artık yalnızca CRL üzerinden sağlanıyor.

**Çözüm.** Stapling satırları kaldırıldı. SSL Labs notunu etkilemedi.

**Ayrıca.** Protokol, şifre takımı ve oturum ayarları certbot'un `options-ssl-nginx.conf` dosyasından geliyor (Mozilla intermediate profili). Bu dosya elle düzenlenmemeli; düzenlenirse certbot gelecekteki güvenlik güncellemelerini otomatik uygulayamıyor.

---

## 8. CAA kaydı beklenenden geniş

**Belirti.** Yalnızca Let's Encrypt'e izin veren bir CAA kaydı eklendi, ancak sorgu on satır döndürdü:

```bash
dig +short metopal.site CAA
# 0 issue "letsencrypt.org"
# 0 issue "digicert.com; cansignhttpexchanges=yes"
# 0 issue "pki.goog; cansignhttpexchanges=yes"
# 0 issue "ssl.com"
# 0 issue "comodoca.com"
# ... ve issuewild karşılıkları
```

**Açıklama.** Diğer kayıtları Cloudflare otomatik ekliyor. Proxy açıldığında kendi edge sertifikalarını bu otoritelerden alabildiği için hepsini önden izinli tutuyor.

**Sonuç.** Politika "yalnızca Let's Encrypt" değil, "şu beş otoriteden biri" anlamına geliyor. Hiç CAA olmamasından iyi ama hedeflenen sıkılıkta değil. Kayıtlar olduğu gibi bırakıldı: listedeki otoriteler denetimli kuruluşlar ve temizlik, ileride proxy açılmak istendiğinde Universal SSL sertifikasının alınmasını engelleyebilirdi.

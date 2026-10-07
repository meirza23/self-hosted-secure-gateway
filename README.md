# Self-Hosted Secure Gateway

Bir web sitesini evdeki bir sunucudan, uçtan uca kendi kurduğum altyapı üzerinden internete açtım. Amaç çalışan bir site yayınlamak değil, bir servisi dışarı açarken gereken bütün katmanları kurmak ve her birinin ne işe yaradığını anlamaktı: adresleme, NAT, sertifika yönetimi, erişim denetimi ve log analizi.

Site `metopal.site` adresinde, Ubuntu Server üzerinde nginx ile sunuluyor. Sertifika Let's Encrypt'ten, SSL Labs notu **A+**.

---

## Mimari

```
                     ┌─────────── istek ───────────┐
                     │                             ▼
  [Tarayıcı] ──▶ [DNS: A kaydı] ──▶ [Modem · DNAT] ──▶ [Ubuntu VM]
                                     :443 → iç adres      UFW · nginx · TLS
                     ▲                                        │
                     └─────────── cevap ──────────────────────┘
```

| Katman | Bileşen | Görevi |
| --- | --- | --- |
| İsim çözümleme | Cloudflare DNS, A kaydı | Alan adını public IP'ye bağlar |
| Sınır | ZTE modem, port yönlendirme | Gelen 80/443 trafiğini iç sunucuya çevirir (DNAT) |
| Ağ | VMware bridged adaptör | Sanal makineyi yerel ağda bağımsız bir cihaz yapar |
| Erişim denetimi | UFW | Varsayılan reddet; yalnızca 22 (yerel), 80, 443 |
| Servis | nginx | İstekleri karşılar, statik içeriği sunar |
| Şifreleme | certbot + Let's Encrypt | TLS sertifikası, otomatik yenileme |
| Saldırı önleme | fail2ban, 5 jail | Tekrarlayan denemeleri otomatik banlar |

---

## Neden bu tercihler

**nginx, Caddy değil.** Caddy sertifikayı kendi alıp yenilediği için daha hızlı sonuç verir. nginx'te certbot ayrı kurulur, birkaç adım fazladır. Buna rağmen nginx seçildi: sektör standardı, iş ilanlarında adı geçiyor ve öğrenilen şeyin doğrudan karşılığı var.

**Sunucu ayrı bir sanal makinede.** Ana makineye kurmak daha kolaydı ama internete açılan yüzeyi kişisel sistemden ayırmak gerekiyordu. Dual boot da düşünüldü ve elendi: Ubuntu açıkken Windows kapalı kalacağı için test döngüsü yavaşlar.

**Bridged ağ modu.** NAT modunda sanal makine VMware'in iç ağında kalır ve modem ona doğrudan ulaşamaz. Bridged'de yerel ağdan kendi adresini alır, modem açısından fiziksel bir cihazdan farksızdır.

**Sertleştirme, dışarı açmadan önce.** Plandaki sıra bilinçli olarak değiştirildi: UFW, SSH anahtarı ve fail2ban, nginx ve sertifikadan önce kuruldu. Dışarı açılan bir sunucu ilk dakikadan itibaren taranır; savunmanın o an hazır olması gerekir.

**Cloudflare proxy kapalı.** Açık olsaydı DDoS koruması ve önbellekleme gelirdi, ama trafik Cloudflare üzerinden aktığı için kendi NAT yapılandırması test edilemez ve erişim loglarında ziyaretçiler yerine Cloudflare adresleri görünürdü. Projenin ölçüm yeteneği bozulurdu.

---

## Kurulum

### Sunucu ve ağ

Ubuntu Server 24.04, VMware'de bridged adaptörle. DHCP havuzu modem üzerinde daraltıldı ve havuz dışından sabit adres verildi — yönlendirme kuralının hedefi değişmemeli.

cloud-init'in ağ yapılandırmasına müdahalesi kapatıldı; aksi halde her açılışta netplan dosyasını kendi şablonundan yeniden üretip DHCP'ye döndürüyor:

```bash
echo 'network: {config: disabled}' | sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
```

Netplan yapılandırması `config/netplan.yaml` dosyasında.

### Sertleştirme

```bash
# güvenlik duvarı — önce izin, sonra etkinleştir
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from 192.168.1.0/24 to any port 22 proto tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

Sıra önemli: ters yapılırsa varsayılan reddet politikası devreye girdiği anda açık SSH oturumu kopar.

SSH için ed25519 anahtar çifti üretildi, açık anahtar `authorized_keys` dosyasına eklendi, parola girişi kapatıldı. Doğrulama açıkça test edildi:

```bash
ssh -o PubkeyAuthentication=no kullanici@sunucu
# Permission denied (publickey)
```

fail2ban yapılandırması `config/jail.local`, özel nginx filtresi `config/nginx-noscript.conf`.

### nginx ve sertifika

Site yapılandırması `config/nginx-site.conf`, hız sınırı bölgesi `config/limits.conf` dosyasında.

```bash
sudo certbot --nginx -d metopal.site -d www.metopal.site
```

certbot `/.well-known/acme-challenge/` altına rastgele bir dosya koyuyor, Let's Encrypt bunu 80 portundan okuyarak alan adının sahipliğini doğruluyor. Port 80'in açık olması bu yüzden şart.

---

## Sonuçlar

**SSL Labs: A+.** Sertifika ve protokol desteği 100/100, anahtar değişimi ve şifre gücü 90/100 (ECDSA P-256 için beklenen değer). Yalnızca TLS 1.2 ve 1.3 açık, ileri gizlilik her şifre takımında mevcut, bilinen zafiyetlerin tamamı olumsuz.

**Güvenlik başlıkları:** HSTS, CSP, X-Frame-Options, X-Content-Type-Options, Referrer-Policy, Permissions-Policy. `server_tokens off` ile sürüm bilgisi gizli.

**Gözlemlenen trafik:** İlk altı saatte 339 istek, 137 farklı kaynak adres. Ayrıntılar `docs/log-analysis.md` dosyasında.

---

## Bilinen sınırlar

**DMZ yok.** Sunucu, ev ağının diğer cihazlarıyla aynı segmentte. Kurumsal bir kurulumda web sunucusu ayrı bir arayüzde (DMZ) tutulur ve oradan iç ağa geçiş kapatılır — böylece sunucu ele geçirilse bile saldırgan iç ağa ulaşamaz. Ev modemi segment oluşturamadığı için bu yapılamadı. Riski azaltmak adına sunucu sürekli açık tutulmuyor.

**İzleme harici değil.** Uptime Kuma planlanmıştı ancak kurulmadı: izleme aracının izlediği sistemle aynı makinede çalışması bir körlük yaratıyor — makine kapandığında izleme de kapanıyor. Anlamlı olması için harici bir konumda çalışması gerekirdi.

**CAA politikası hedeflendiği kadar dar değil.** Cloudflare kendi edge sertifikaları için birkaç otoriteyi otomatik izinli tutuyor. Ayrıntı `docs/troubleshooting.md` dosyasında.

---

## Dosyalar

```
docs/troubleshooting.md   karşılaşılan sorunlar ve teşhis süreçleri
docs/log-analysis.md      erişim logu bulguları
config/                   yapılandırma dosyaları (adresler maskelenmiş)
screenshots/              doğrulama çıktıları
```

Yapılandırma dosyalarında public IP maskelenmiştir.

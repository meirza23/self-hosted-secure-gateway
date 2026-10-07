#!/usr/bin/env bash
# Güvenlik duvarı kuralları.
#
# Sıra önemli: önce izinler yazılır, sonra etkinleştirilir. Ters
# yapılırsa varsayılan reddet politikası devreye girdiği anda açık
# SSH oturumu kopar.

set -euo pipefail

# varsayılan: gelen reddet, giden izin ver
# (durum bilgili çalışır — kendi başlattığın bağlantıların cevabı
#  "gelen trafik" sayılmaz)
sudo ufw default deny incoming
sudo ufw default allow outgoing

# SSH yalnızca yerel ağdan.
# Modemde 22 zaten yönlendirilmiyor; bu ikinci bir katman.
sudo ufw allow from 192.168.1.0/24 to any port 22 proto tcp

# web trafiği herkese açık
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

sudo ufw enable
sudo ufw status verbose

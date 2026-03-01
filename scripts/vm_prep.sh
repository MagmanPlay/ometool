#!/usr/bin/env bash
# ================================================================
# 🔧 Ubuntu 24.04 VM Deployment Preparation Script
# ================================================================

# Принудительное выполнение от root
if [ "$EUID" -ne 0 ]; then
    echo -e "\n🚫 Скрипт должен выполняться с правами root. Используйте:\n\n  sudo bash $0\n"
    exit 1
fi

clear
echo -e "=============================================="
echo -e "🚀 VM Preparation Script for Ubuntu 24.04"
echo -e "==============================================\n"

# Обновление системы
echo -e "🔄 Обновление системы и установленных пакетов...\n"
apt update -y && apt upgrade -y && apt autoremove -y && apt clean
echo -e "\n✅ Система обновлена.\n"

# Установка UFW и certbot
echo -e "🧱 Установка и настройка UFW + iptables + fail2ban + certbot...\n"
apt install -y ufw iptables certbot fail2ban
systemctl enable fail2ban

# Настройка базовых правил UFW
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 443/tcp
echo -e "✅ Базовые правила UFW установлены.\n"

# Активация UFW
ufw --force enable
echo -e "\n✅ Firewall активирован.\n"

# Настройка DNS-over-TLS через systemd-resolved
echo -e "🔐 Настройка зашифрованных DNS (DNS-over-TLS)...\n"

mkdir -p /etc/systemd/resolved.conf.d

cat <<EOF >/etc/systemd/resolved.conf.d/dot.conf
[Resolve]
DNS=1.1.1.1#cloudflare-dns.com 8.8.8.8#dns.google
FallbackDNS=1.0.0.1#cloudflare-dns.com 8.8.4.4#dns.google
DNSOverTLS=yes
DNSSEC=yes
EOF

systemctl restart systemd-resolved
echo -e "✅ DNS-over-TLS настроен (Cloudflare + Google).\n"

# Включение TCP BBR
echo -e "🏎️  Включение алгоритма TCP BBR для ускорения сети...\n"
cat <<EOF >/etc/sysctl.d/99-bbr.conf
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
sysctl --system > /dev/null 2>&1
echo -e "✅ TCP BBR успешно активирован.\n"

# Настройка автоматического обновления (cron)
echo -e "⏰ Настройка автообновления и перезагрузки (каждые 15 дней в 03:00)...\n"
# Удаляем предыдущее правило автообновления, если скрипт запускается повторно, чтобы избежать дублей
crontab -l 2>/dev/null | grep -v "apt-get update" | crontab -
# Добавляем новую cron-задачу
(crontab -l 2>/dev/null; echo "0 3 */15 * * DEBIAN_FRONTEND=noninteractive apt-get update && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y && DEBIAN_FRONTEND=noninteractive apt-get autoremove -y && /sbin/reboot") | crontab -
echo -e "✅ Crontab настроен.\n"

# Отключение лишних сервисов
echo -e "🧹 Отключаем ненужные сервисы...\n"

systemctl disable --now cloud-init 2>/dev/null
apt purge -y qemu-guest-agent 2>/dev/null
systemctl disable --now serial-getty@ttyS0.service 2>/dev/null
systemctl mask serial-getty@ttyS0.service 2>/dev/null
echo -e "✅ Лишние сервисы отключены.\n"

# Финальное резюме
clear
echo -e "=============================================="
echo -e "✅  Подготовка VM завершена успешно!"
echo -e "=============================================="
echo -e "📡 Активные правила UFW:"
ufw status numbered
echo -e "\n🔒 DNS-over-TLS: Cloudflare + Google"
echo -e "🏎️  Network: TCP BBR активирован"
echo -e "🔄 Автообновление: Раз в 15 дней в 03:00 (с перезагрузкой)"
echo -e "==============================================\n"

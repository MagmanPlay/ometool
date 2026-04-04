#!/usr/bin/env bash
# ================================================================
# 🌐 Установка и настройка DNSTT + UDPGW (Туннелирование)
# ================================================================

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

echo -e "\n${CYAN}${BOLD}🌐 Запуск мастера настройки DNSTT Tunnel...${NC}\n"

# ================= Интерактивный ввод =================
echo -e "${YELLOW}📝 Шаг 0: Настройка параметров туннеля${NC}"

# Запрос домена (с проверкой на пустоту и принудительным чтением с клавиатуры)
while true; do
    read -p "👉 Введите ваш домен (NS запись должна указывать на IP сервера): " DOMAIN </dev/tty
    if [ -n "$DOMAIN" ]; then
        break
    else
        echo -e "${RED}❌ Домен не может быть пустым. Попробуйте еще раз.${NC}"
    fi
done

# Запрос пользователя (с принудительным чтением с клавиатуры)
read -p "👉 Введите имя пользователя для VPN [по умолчанию: dnstt]: " INPUT_USER </dev/tty
VPN_USER=${INPUT_USER:-dnstt}

echo -e "\n${GREEN}✅ Принято! Домен: ${DOMAIN}, Пользователь: ${VPN_USER}${NC}\n"
# =====================================================

echo -e "${CYAN}>>> [1/8] Обновление системы и установка зависимостей...${NC}"
apt-get update -qq
apt-get install -y golang git wget nano iptables cmake build-essential unzip -qq

echo -e "${CYAN}>>> [2/8] Освобождение 53 порта (отключение systemd-resolved)...${NC}"
systemctl stop systemd-resolved 2>/dev/null
systemctl disable systemd-resolved 2>/dev/null
rm -f /etc/resolv.conf
echo "nameserver 8.8.8.8" > /etc/resolv.conf
echo "nameserver 1.1.1.1" >> /etc/resolv.conf

echo -e "${CYAN}>>> [3/8] Сборка DNSTT Server...${NC}"
rm -rf /root/go
rm -f /usr/local/bin/dnstt-server
go install www.bamsoftware.com/git/dnstt.git/dnstt-server@latest
mv ~/go/bin/dnstt-server /usr/local/bin/
chmod +x /usr/local/bin/dnstt-server

echo -e "${CYAN}>>> [4/8] Сборка и установка UDPGW (BadVPN)...${NC}"
wget -qO badvpn.zip https://github.com/ambrop72/badvpn/archive/master.zip
unzip -q badvpn.zip
cd badvpn-master
mkdir build && cd build
cmake .. -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1 > /dev/null 2>&1
make > /dev/null 2>&1
cp udpgw/badvpn-udpgw /usr/local/bin/
chmod +x /usr/local/bin/badvpn-udpgw
cd ../..
rm -rf badvpn-master badvpn.zip

echo -e "${CYAN}>>> [5/8] Настройка SSH-пользователя ${BOLD}$VPN_USER${NC}..."
userdel -f $VPN_USER 2>/dev/null
useradd -M -s /usr/sbin/nologin $VPN_USER
USER_PASS=$(openssl rand -base64 12)
echo "$VPN_USER:$USER_PASS" | chpasswd

# Очистка старых записей Match User, если скрипт запускается повторно
sed -i "/Match User $VPN_USER/,\$d" /etc/ssh/sshd_config
cat <<EOT >> /etc/ssh/sshd_config

Match User $VPN_USER
    AllowTcpForwarding yes
    X11Forwarding no
    AllowAgentForwarding no
    PermitTTY no
    ForceCommand /usr/sbin/nologin
EOT
systemctl restart ssh

echo -e "${CYAN}>>> [6/8] Генерация ключей DNSTT...${NC}"
rm -rf /root/dnstt-keys
mkdir -p /root/dnstt-keys
cd /root/dnstt-keys
/usr/local/bin/dnstt-server -gen-key -privkey-file server.key -pubkey-file server.pub
PUBKEY=$(cat server.pub)

echo -e "${CYAN}>>> [7/8] Определение порта SSH...${NC}"
SSH_PORT=$(sshd -T | grep "^port " | awk '{print $2}' | head -n 1)
SSH_PORT=${SSH_PORT:-22}
echo -e "${GREEN}SSH работает на порту: $SSH_PORT. Используем его для туннеля.${NC}"

echo -e "${CYAN}>>> [8/8] Создание и запуск systemd-сервисов (DNSTT + UDPGW)...${NC}"

# UDPGW сервис
cat <<EOF > /etc/systemd/system/udpgw.service
[Unit]
Description=BadVPN UDP Gateway (Port 7300)
After=network.target

[Service]
ExecStart=/usr/local/bin/badvpn-udpgw --listen-addr 127.0.0.1:7300 --max-clients 1000
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

# DNSTT сервис
cat <<EOF > /etc/systemd/system/dnstt.service
[Unit]
Description=DNSTT Server (Port 53)
After=network.target

[Service]
ExecStart=/usr/local/bin/dnstt-server -udp :53 -privkey-file /root/dnstt-keys/server.key $DOMAIN 127.0.0.1:$SSH_PORT
Restart=always
User=root
WorkingDirectory=/root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now udpgw > /dev/null 2>&1
systemctl enable --now dnstt > /dev/null 2>&1

echo -e "\n${YELLOW}===============================================${NC}"
echo -e "${YELLOW}${BOLD}     🎉 DNSTT + UDPGW УСПЕШНО УСТАНОВЛЕНЫ      ${NC}"
echo -e "${YELLOW}===============================================${NC}"
echo -e "🌐 ${BOLD}Домен:${NC}            $DOMAIN"
echo -e "🔑 ${BOLD}Публичный ключ:${NC}   ${GREEN}$PUBKEY${NC}"
echo -e "👤 ${BOLD}Пользователь SSH:${NC} ${GREEN}$VPN_USER${NC}"
echo -e "🔒 ${BOLD}Пароль SSH:${NC}       ${RED}$USER_PASS${NC}  <-- ОБЯЗАТЕЛЬНО СОХРАНИТЕ!"
echo -e "🔌 ${BOLD}Порт UDPGW:${NC}       7300 (Укажите в клиенте на вашем устройстве)"
echo -e "${YELLOW}===============================================${NC}"
echo -e "\n${BOLD}Статус сервисов:${NC}"
systemctl status dnstt --no-pager | grep Active
systemctl status udpgw --no-pager | grep Active
echo -e ""

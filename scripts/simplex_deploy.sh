#!/usr/bin/env bash
# ================================================================
# 💬 OMETOOL - Развертывание приватного узла SimpleX Chat
# ================================================================

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

echo -e "\n${CYAN}${BOLD}💬 Запуск мастера установки SimpleX Relay (Text, Files, Calls)...${NC}\n"

# ================= Интерактивный ввод =================
echo -e "${YELLOW}📝 Шаг 1: Базовая настройка сервера${NC}"

# Запрос домена или IP
while true; do
    read -p "👉 Введите домен или IP-адрес этого сервера: " DOMAIN </dev/tty
    if [ -n "$DOMAIN" ]; then
        break
    else
        echo -e "${RED}❌ Это поле не может быть пустым.${NC}"
    fi
done

# Настройка SSL
echo -e "\n${BOLD}Как поступим с SSL сертификатами?${NC}"
echo -e "  [1] Сгенерировать надежные самоподписанные (Рекомендуется для изолированных сетей)"
echo -e "  [2] Указать путь к существующим (например, от Let's Encrypt)"
read -p "👉 Ваш выбор: " SSL_MODE </dev/tty

CERT_PATH="/etc/simplex/cert.pem"
KEY_PATH="/etc/simplex/key.pem"

if [ "$SSL_MODE" == "2" ]; then
    read -p "👉 Укажите полный путь к сертификату (cert.pem / fullchain.pem): " CUSTOM_CERT </dev/tty
    read -p "👉 Укажите полный путь к ключу (key.pem / privkey.pem): " CUSTOM_KEY </dev/tty
fi

# Настройка WebRTC (Звонки)
echo -e "\n${BOLD}Настройка сервера звонков (WebRTC TURN):${NC}"
read -p "👉 Придумайте логин для TURN сервера [по умолчанию: simplex]: " TURN_USER </dev/tty
TURN_USER=${TURN_USER:-simplex}
TURN_PASS=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9')
echo -e "${GREEN}✅ Пароль для TURN сгенерирован автоматически.${NC}\n"

# =====================================================

echo -e "${CYAN}>>> [1/7] Установка зависимостей (coturn, openssl, jq, curl)...${NC}"
DEBIAN_FRONTEND=noninteractive apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y coturn openssl jq curl wget -qq

echo -e "${CYAN}>>> [2/7] Подготовка директорий и сертификатов...${NC}"
mkdir -p /etc/simplex
mkdir -p /var/opt/simplex/xftp # Папка для временного хранения файлов

if [ "$SSL_MODE" == "2" ] && [ -f "$CUSTOM_CERT" ] && [ -f "$CUSTOM_KEY" ]; then
    cp "$CUSTOM_CERT" "$CERT_PATH"
    cp "$CUSTOM_KEY" "$KEY_PATH"
    echo -e "  ${GREEN}Скопированы пользовательские сертификаты.${NC}"
else
    echo -e "  ${YELLOW}Генерация самоподписанных SSL сертификатов...${NC}"
    openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 \
        -subj "/C=US/ST=Denial/L=Springfield/O=Dis/CN=$DOMAIN" \
        -keyout "$KEY_PATH" -out "$CERT_PATH" > /dev/null 2>&1
    echo -e "  ${GREEN}Сертификаты успешно сгенерированы.${NC}"
fi

# Получаем отпечаток сертификата для формирования готовых ссылок (SHA256)
CERT_FINGERPRINT=$(openssl x509 -in "$CERT_PATH" -noout -fingerprint -sha256 | sed 's/SHA256 Fingerprint=//' | sed 's/://g' | awk '{print tolower($0)}')

echo -e "${CYAN}>>> [3/7] Скачивание и установка SMP Server (Сообщения)...${NC}"
# Умный парсинг последней версии для Ubuntu 22.04/24.04 (x86_64)
SMP_URL=$(curl -s https://api.github.com/repos/simplex-chat/simplexmq/releases/latest | jq -r '.assets[] | select(.name | contains("smp-server-ubuntu-22_04-x86_64")) | .browser_download_url')
wget -qO /usr/local/bin/smp-server "$SMP_URL"
chmod +x /usr/local/bin/smp-server

echo -e "${CYAN}>>> [4/7] Скачивание и установка XFTP Server (Файлы)...${NC}"
XFTP_URL=$(curl -s https://api.github.com/repos/simplex-chat/simplexmq/releases/latest | jq -r '.assets[] | select(.name | contains("xftp-server-ubuntu-22_04-x86_64")) | .browser_download_url')
wget -qO /usr/local/bin/xftp-server "$XFTP_URL"
chmod +x /usr/local/bin/xftp-server

echo -e "${CYAN}>>> [5/7] Настройка Coturn (Сервер Звонков)...${NC}"
cat <<EOF > /etc/turnserver.conf
listening-port=3478
tls-listening-port=5349
fingerprint
lt-cred-mech
user=$TURN_USER:$TURN_PASS
realm=$DOMAIN
cert=$CERT_PATH
pkey=$KEY_PATH
total-quota=100
stale-nonce=600
no-stdout-log
EOF

sed -i 's/#TURNSERVER_ENABLED=1/TURNSERVER_ENABLED=1/' /etc/default/coturn 2>/dev/null

echo -e "${CYAN}>>> [6/7] Настройка брандмауэра (Открытие портов)...${NC}"
if command -v ufw >/dev/null 2>&1; then
    # Открываем порты и скрываем стандартный вывод UFW
    ufw allow 5223/tcp comment 'SimpleX SMP' > /dev/null 2>&1
    ufw allow 5224/tcp comment 'SimpleX XFTP' > /dev/null 2>&1
    ufw allow 3478/tcp comment 'Coturn STUN/TURN' > /dev/null 2>&1
    ufw allow 3478/udp comment 'Coturn STUN/TURN' > /dev/null 2>&1
    ufw allow 5349/tcp comment 'Coturn STUN/TURN TLS' > /dev/null 2>&1
    ufw allow 5349/udp comment 'Coturn STUN/TURN TLS' > /dev/null 2>&1
    ufw allow 49152:65535/udp comment 'Coturn Relay Ports' > /dev/null 2>&1
    echo -e "  ${GREEN}Автоматически открыты порты: 5223, 5224, 3478, 5349, 49152-65535${NC}"
else
    echo -e "  ${YELLOW}UFW не установлен, пропуск настройки брандмауэра.${NC}"
fi

echo -e "${CYAN}>>> [7/7] Создание и запуск Systemd сервисов...${NC}"

# Сервис SMP
cat <<EOF > /etc/systemd/system/smp-server.service
[Unit]
Description=SimpleX SMP Server (Messaging)
After=network.target

[Service]
ExecStart=/usr/local/bin/smp-server -l 0.0.0.0:5223 -c $CERT_PATH -k $KEY_PATH
Restart=always
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# Сервис XFTP
cat <<EOF > /etc/systemd/system/xftp-server.service
[Unit]
Description=SimpleX XFTP Server (Files)
After=network.target

[Service]
ExecStart=/usr/local/bin/xftp-server -l 0.0.0.0:5224 -c $CERT_PATH -k $KEY_PATH -d /var/opt/simplex/xftp
Restart=always
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now smp-server > /dev/null 2>&1
systemctl enable --now xftp-server > /dev/null 2>&1
systemctl enable --now coturn > /dev/null 2>&1
systemctl restart coturn > /dev/null 2>&1

# ФИНАЛ - Вывод данных для подключения
clear
echo -e "${YELLOW}===================================================================${NC}"
echo -e "${YELLOW}${BOLD} 🚀 ВАШ НЕУЯЗВИМЫЙ УЗЕЛ SIMPLEX УСПЕШНО РАЗВЕРНУТ 🚀 ${NC}"
echo -e "${YELLOW}===================================================================${NC}"
echo -e "Просто скопируйте эти ссылки и вставьте в приложение SimpleX Chat!\n"

echo -e "${BOLD}💬 1. Сервер Сообщений (SMP):${NC}"
echo -e "🔗 Ссылка: ${GREEN}smp://$CERT_FINGERPRINT@$DOMAIN:5223${NC}\n"

echo -e "${BOLD}📁 2. Сервер Файлов (XFTP):${NC}"
echo -e "🔗 Ссылка: ${GREEN}xftp://$CERT_FINGERPRINT@$DOMAIN:5224${NC}\n"

echo -e "${BOLD}📞 3. Сервер Звонков (WebRTC / TURN):${NC}"
echo -e "В настройках SimpleX Chat добавьте любую из ссылок в раздел 'WebRTC ICE servers':"
echo -e "🔗 TURN (Обычный): ${GREEN}turn:$TURN_USER:$TURN_PASS@$DOMAIN:3478${NC}"
echo -e "🔗 TURN (по TLS):  ${GREEN}turns:$TURN_USER:$TURN_PASS@$DOMAIN:5349${NC}"
echo -e "${YELLOW}===================================================================${NC}"
echo -e "\n${BOLD}Открытые порты в UFW:${NC}"
echo -e "  - ${CYAN}TCP:${NC} 5223, 5224, 3478, 5349"
echo -e "  - ${CYAN}UDP:${NC} 3478, 5349, 49152-65535 (Для передачи голоса/видео)"
echo -e "\n${BOLD}Статус запущенных служб:${NC}"
systemctl status smp-server --no-pager | grep Active
systemctl status xftp-server --no-pager | grep Active
systemctl status coturn --no-pager | grep Active
echo -e ""

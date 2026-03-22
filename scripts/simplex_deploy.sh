#!/usr/bin/env bash
# ================================================================
# 💬 OMETOOL - Развертывание приватного узла SimpleX Chat
# ================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

echo -e "\n${CYAN}${BOLD}💬 Управление приватным узлом SimpleX Relay...${NC}\n"

echo -e "${BOLD}Выберите действие:${NC}"
echo -e "  ${GREEN}[1]${NC} 🚀 Полная установка (Text, Files, Calls)"
echo -e "  ${RED}[2]${NC} 🗑️ Полное удаление (Очистка сервера от всех следов)"
echo -e "  ${CYAN}[0]${NC} 🚪 Выход"
echo ""

read -p "👉 Ваш выбор: " SIMPLEX_MODE </dev/tty

case $SIMPLEX_MODE in
    1)
        # ================= ИНТЕРАКТИВНЫЙ ВВОД =================
        echo -e "\n${YELLOW}📝 Шаг 1: Базовая настройка сервера${NC}"

        while true; do
            read -p "👉 Введите домен или IP-адрес этого сервера: " DOMAIN </dev/tty
            if [ -n "$DOMAIN" ]; then
                break
            else
                echo -e "${RED}❌ Это поле не может быть пустым.${NC}"
            fi
        done

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

        echo -e "\n${BOLD}Настройка сервера звонков (WebRTC TURN):${NC}"
        read -p "👉 Придумайте логин для TURN сервера [по умолчанию: simplex]: " TURN_USER </dev/tty
        TURN_USER=${TURN_USER:-simplex}
        TURN_PASS=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9')
        echo -e "${GREEN}✅ Пароль для TURN сгенерирован автоматически.${NC}\n"

        # ================= УСТАНОВКА =================
        echo -e "${CYAN}>>> [1/7] Установка зависимостей...${NC}"
        DEBIAN_FRONTEND=noninteractive apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -y coturn openssl curl wget jq libgmp10 -qq

        echo -e "${CYAN}>>> [2/7] Подготовка директорий и сертификатов...${NC}"
        mkdir -p /etc/simplex
        mkdir -p /var/opt/simplex/xftp

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

        CERT_FINGERPRINT=$(openssl x509 -in "$CERT_PATH" -noout -fingerprint -sha256 | awk -F'=' '{print $2}' | tr -d ':' | tr 'A-Z' 'a-z')

        echo -e "${CYAN}>>> [3/7] Умный поиск и скачивание SMP Server...${NC}"
        ARCH=$(uname -m)
        API_JSON=$(curl -s https://api.github.com/repos/simplex-chat/simplexmq/releases/latest)
        
        # Динамический поиск ссылки (сначала ищем с ubuntu, если нет - берем любую Linux сборку)
        SMP_URL=$(echo "$API_JSON" | grep -oP '"browser_download_url": "\K[^"]*smp-server-[^"]*'"$ARCH"'[^"]*"' | grep -i "ubuntu" | head -n 1)
        if [ -z "$SMP_URL" ]; then
            SMP_URL=$(echo "$API_JSON" | grep -oP '"browser_download_url": "\K[^"]*smp-server-[^"]*'"$ARCH"'[^"]*"' | head -n 1)
        fi

        if [ -z "$SMP_URL" ]; then
            echo -e "${RED}❌ Ошибка: Не удалось найти ссылку на SMP сервер в GitHub API!${NC}"
            exit 1
        fi
        
        wget -qO /usr/local/bin/smp-server "$SMP_URL"
        
        # ЖЕСТКАЯ ПРОВЕРКА: Это бинарник или HTML-ошибка 404?
        if ! head -c 4 /usr/local/bin/smp-server | grep -q "ELF"; then
            echo -e "${RED}❌ Ошибка: Скачанный файл SMP не является программой! Возможно, GitHub изменил ссылки.${NC}"
            exit 1
        fi
        chmod +x /usr/local/bin/smp-server
        echo -e "  ${GREEN}SMP Server успешно скачан и проверен.${NC}"

        echo -e "${CYAN}>>> [4/7] Умный поиск и скачивание XFTP Server...${NC}"
        XFTP_URL=$(echo "$API_JSON" | grep -oP '"browser_download_url": "\K[^"]*xftp-server-[^"]*'"$ARCH"'[^"]*"' | grep -i "ubuntu" | head -n 1)
        if [ -z "$XFTP_URL" ]; then
            XFTP_URL=$(echo "$API_JSON" | grep -oP '"browser_download_url": "\K[^"]*xftp-server-[^"]*'"$ARCH"'[^"]*"' | head -n 1)
        fi
        
        wget -qO /usr/local/bin/xftp-server "$XFTP_URL"
        
        if ! head -c 4 /usr/local/bin/xftp-server | grep -q "ELF"; then
            echo -e "${RED}❌ Ошибка: Скачанный файл XFTP не является программой!${NC}"
            exit 1
        fi
        chmod +x /usr/local/bin/xftp-server
        echo -e "  ${GREEN}XFTP Server успешно скачан и проверен.${NC}"

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
            ufw allow 5223/tcp comment 'SimpleX SMP' > /dev/null 2>&1
            ufw allow 5224/tcp comment 'SimpleX XFTP' > /dev/null 2>&1
            ufw allow 3478/tcp comment 'Coturn STUN/TURN' > /dev/null 2>&1
            ufw allow 3478/udp comment 'Coturn STUN/TURN' > /dev/null 2>&1
            ufw allow 5349/tcp comment 'Coturn STUN/TURN TLS' > /dev/null 2>&1
            ufw allow 5349/udp comment 'Coturn STUN/TURN TLS' > /dev/null 2>&1
            ufw allow 49152:65535/udp comment 'Coturn Relay Ports' > /dev/null 2>&1
            echo -e "  ${GREEN}Автоматически открыты порты UFW: 5223, 5224, 3478, 5349, 49152-65535${NC}"
        else
            echo -e "  ${YELLOW}UFW не установлен, пропуск настройки брандмауэра.${NC}"
        fi

        echo -e "${CYAN}>>> [7/7] Создание и запуск Systemd сервисов...${NC}"
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

        sleep 2

        # ФИНАЛ
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
        echo -e "  - ${CYAN}UDP:${NC} 3478, 5349, 49152-65535"
        echo -e "\n${BOLD}Статус запущенных служб:${NC}"
        systemctl status smp-server --no-pager | grep Active
        systemctl status xftp-server --no-pager | grep Active
        systemctl status coturn --no-pager | grep Active
        echo -e ""
        ;;

    2)
        # ================= ОЧИСТКА =================
        echo -e "\n${RED}${BOLD}🗑️ Запуск полного удаления SimpleX Relay...${NC}"
        read -p "👉 Вы уверены, что хотите удалить все данные, сертификаты и службы? [y/N]: " confirm </dev/tty
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo -e "Отмена очистки."
            exit 0
        fi

        echo -e "${CYAN}>>> [1/5] Остановка и удаление systemd служб...${NC}"
        systemctl stop smp-server xftp-server coturn 2>/dev/null
        systemctl disable smp-server xftp-server coturn 2>/dev/null
        rm -f /etc/systemd/system/smp-server.service
        rm -f /etc/systemd/system/xftp-server.service
        systemctl daemon-reload

        echo -e "${CYAN}>>> [2/5] Удаление исполняемых файлов...${NC}"
        rm -f /usr/local/bin/smp-server
        rm -f /usr/local/bin/xftp-server

        echo -e "${CYAN}>>> [3/5] Удаление конфигураций, сертификатов и данных XFTP...${NC}"
        rm -rf /etc/simplex
        rm -rf /var/opt/simplex
        apt-get purge -y coturn >/dev/null 2>&1
        apt-get autoremove -y >/dev/null 2>&1
        rm -f /etc/turnserver.conf

        echo -e "${CYAN}>>> [4/5] Удаление правил брандмауэра (UFW)...${NC}"
        if command -v ufw >/dev/null 2>&1; then
            ufw delete allow 5223/tcp > /dev/null 2>&1
            ufw delete allow 5224/tcp > /dev/null 2>&1
            ufw delete allow 3478/tcp > /dev/null 2>&1
            ufw delete allow 3478/udp > /dev/null 2>&1
            ufw delete allow 5349/tcp > /dev/null 2>&1
            ufw delete allow 5349/udp > /dev/null 2>&1
            ufw delete allow 49152:65535/udp > /dev/null 2>&1
        fi

        echo -e "\n${YELLOW}===============================================${NC}"
        echo -e "${GREEN}${BOLD} ✅ СЕРВЕР SIMPLEX ПОЛНОСТЬЮ УДАЛЕН И ОЧИЩЕН   ${NC}"
        echo -e "${YELLOW}===============================================${NC}\n"
        ;;

    0)
        echo -e "Выход."
        exit 0
        ;;
    *)
        echo -e "${RED}Неверный выбор.${NC}"
        exit 1
        ;;
esac

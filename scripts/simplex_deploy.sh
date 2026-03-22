#!/usr/bin/env bash
# ================================================================
# 💬 OMETOOL - Развертывание приватного узла SimpleX Chat (DOCKER)
# ================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

echo -e "\n${CYAN}${BOLD}💬 Управление приватным узлом SimpleX Relay (Docker)...${NC}\n"

if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Ошибка: Docker не установлен!${NC}"
    echo -e "Для установки SimpleX этим методом необходим Docker."
    echo -e "Пожалуйста, выйдите в главное меню OMETOOL и выполните пункт [2] (Установка Docker.io)."
    exit 1
fi

echo -e "${BOLD}Выберите действие:${NC}"
echo -e "  ${GREEN}[1]${NC} 🚀 Полная установка (Text, Files, Calls) через Docker"
echo -e "  ${RED}[2]${NC} 🗑️ Полное удаление (Очистка контейнеров и сервера)"
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
        echo -e "${CYAN}>>> [1/6] Установка системных зависимостей (coturn, openssl)...${NC}"
        DEBIAN_FRONTEND=noninteractive apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -y coturn openssl curl -qq

        echo -e "${CYAN}>>> [2/6] Подготовка директорий и генерация SSL сертификатов...${NC}"
        mkdir -p /etc/simplex/smp/config
        mkdir -p /etc/simplex/smp/logs
        mkdir -p /etc/simplex/xftp/config
        mkdir -p /etc/simplex/xftp/logs
        mkdir -p /etc/simplex/xftp/files
        mkdir -p /etc/simplex/certs

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

        # Подготавливаем сертификаты строго под требования Docker-контейнера
        cp "$CERT_PATH" "/etc/simplex/certs/${DOMAIN}.crt"
        cp "$KEY_PATH" "/etc/simplex/certs/${DOMAIN}.key"

        # SMP (5223) — ОБЯЗАТЕЛЬНО
        cp "$CERT_PATH" "/etc/simplex/certs/${DOMAIN}:5223.crt"
        cp "$KEY_PATH" "/etc/simplex/certs/${DOMAIN}:5223.key"

        # XFTP (5224)
        cp "$CERT_PATH" "/etc/simplex/certs/${DOMAIN}:5224.crt"
        cp "$KEY_PATH" "/etc/simplex/certs/${DOMAIN}:5224.key"
        
        # Даем полные права папкам, чтобы Docker-пользователь мог в них писать и читать
        chmod -R 777 /etc/simplex

        CERT_FINGERPRINT=$(openssl x509 -in "$CERT_PATH" -outform der | sha256sum | awk '{print $1}' | xxd -r -p | base64 | tr '+/' '-_' | tr -d '=')

        echo -e "${CYAN}>>> [3/6] Запуск Docker-контейнера SMP Server (Сообщения)...${NC}"
        docker rm -f simplex-smp 2>/dev/null
        docker run -d --name simplex-smp --restart always \
            -e "ADDR=$DOMAIN" \
            -p 5223:443 \
            -v /etc/simplex/smp/config:/etc/opt/simplex \
            -v /etc/simplex/smp/logs:/var/opt/simplex \
            -v /etc/simplex/certs:/certificates \
            simplexchat/smp-server:latest > /dev/null

        echo -e "${CYAN}>>> [4/6] Запуск Docker-контейнера XFTP Server (Файлы)...${NC}"
        docker rm -f simplex-xftp 2>/dev/null
        docker run -d --name simplex-xftp --restart always \
            -e "ADDR=$DOMAIN:5224" \
            -e "QUOTA=100gb" \
            -p 5224:443 \
            -v /etc/simplex/xftp/config:/etc/opt/simplex-xftp \
            -v /etc/simplex/xftp/logs:/var/opt/simplex-xftp \
            -v /etc/simplex/xftp/files:/srv/xftp \
            -v /etc/simplex/certs:/certificates \
            simplexchat/xftp-server:latest > /dev/null

        # Ожидаем пару секунд, чтобы убедиться, что контейнеры не упали
        sleep 4
        
        echo -e "${CYAN}>>> [5/6] Настройка Coturn (Сервер Звонков)...${NC}"
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
        systemctl daemon-reload
        systemctl enable --now coturn > /dev/null 2>&1
        systemctl restart coturn > /dev/null 2>&1

        echo -e "${CYAN}>>> [6/6] Настройка брандмауэра (Открытие портов)...${NC}"
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
        echo -e "\n${BOLD}Открытые порты (Не забудьте открыть их в облачном Firewall, если он есть!):${NC}"
        echo -e "  - ${CYAN}TCP:${NC} 5223, 5224, 3478, 5349"
        echo -e "  - ${CYAN}UDP:${NC} 3478, 5349, 49152-65535"
        
        echo -e "\n${BOLD}Статус запущенных Docker-контейнеров:${NC}"
        docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep simplex
        
        # АВТОМАТИЧЕСКАЯ ДИАГНОСТИКА XFTP
        XFTP_STATUS=$(docker inspect -f '{{.State.Status}}' simplex-xftp 2>/dev/null)
        if [ "$XFTP_STATUS" != "running" ]; then
            echo -e "\n${RED}${BOLD}⚠️ ВНИМАНИЕ: XFTP сервер не запустился! Вот логи ошибки:${NC}"
            docker logs simplex-xftp --tail 20
        fi
        
        echo -e "\n${BOLD}Статус сервера звонков (Coturn):${NC}"
        systemctl status coturn --no-pager | grep Active
        echo -e ""
        ;;

    2)
        # ================= ОЧИСТКА =================
        echo -e "\n${RED}${BOLD}🗑️ Запуск полного удаления SimpleX Relay...${NC}"
        read -p "👉 Вы уверены, что хотите удалить все данные, сертификаты и контейнеры? [y/N]: " confirm </dev/tty
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo -e "Отмена очистки."
            exit 0
        fi

        echo -e "${CYAN}>>> [1/4] Остановка и удаление Docker контейнеров...${NC}"
        docker rm -f simplex-smp simplex-xftp 2>/dev/null

        echo -e "${CYAN}>>> [2/4] Удаление файлов, конфигураций и базы данных...${NC}"
        rm -rf /etc/simplex
        apt-get purge -y coturn >/dev/null 2>&1
        apt-get autoremove -y >/dev/null 2>&1
        rm -f /etc/turnserver.conf

        echo -e "${CYAN}>>> [3/4] Остановка системных служб (если были установлены ранее)...${NC}"
        systemctl stop smp-server xftp-server 2>/dev/null
        systemctl disable smp-server xftp-server 2>/dev/null
        rm -f /etc/systemd/system/smp-server.service
        rm -f /etc/systemd/system/xftp-server.service
        systemctl daemon-reload

        echo -e "${CYAN}>>> [4/4] Удаление правил брандмауэра (UFW)...${NC}"
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

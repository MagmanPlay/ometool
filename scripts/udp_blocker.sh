#!/usr/bin/env bash
# ================================================================
# 🛡️ OMETOOL - Ультимативный блокировщик UDP (Анти-Торрент)
# ================================================================

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

echo -e "\n${CYAN}${BOLD}🛡️ Запуск модуля управления UDP трафиком...${NC}\n"

echo -e "${BOLD}Выберите действие:${NC}"
echo -e "  ${RED}[1]${NC} 🚫 Заблокировать UDP (Оставить только DNS/NTP и исключения)"
echo -e "  ${GREEN}[2]${NC} 🟢 Снять блокировку (Вернуть все как было)"
echo -e "  ${CYAN}[0]${NC} 🚪 Выход"
echo ""

read -p "👉 Ваш выбор: " UDP_MODE </dev/tty

case $UDP_MODE in
    1)
        clear
        echo -e "${RED}${BOLD}⚠️ ВНИМАНИЕ: БЛОКИРОВКА UDP — ЭТО ЖЕСТКАЯ МЕРА!${NC}"
        echo -e "Многие хостеры блокируют серверы за торренты. Так как Xray не может"
        echo -e "отловить обфусцированный uTP-трафик, блокировка UDP на уровне ядра — лучший выход.\n"
        
        echo -e "${BOLD}Минусы и риски:${NC}"
        echo -e "❌ ${YELLOW}Не будет работать HTTP/3 (QUIC)${NC} - сайты будут открываться по HTTP/2 (чуть медленнее)."
        echo -e "❌ ${YELLOW}Голосовые чаты (Discord/Zoom)${NC} и WebRTC перейдут на резервный TCP."
        echo -e "❌ ${YELLOW}Сетевые игры${NC} через ваш VPN перестанут работать.\n"
        
        echo -e "${BOLD}Что продолжит работать:${NC}"
        echo -e "✅ Системные DNS (порт 53) и синхронизация времени NTP (порт 123)."
        echo -e "✅ Весь TCP трафик (Web, Xray Reality, Telegram, Видео).\n"

        read -p "👉 Вы уверены, что хотите заблокировать UDP? [y/N]: " confirm </dev/tty
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo -e "Отмена."
            exit 0
        fi

        echo -e "\n${CYAN}💡 Если вы используете WireGuard или OpenVPN, их порты нужно оставить открытыми.${NC}"
        read -p "👉 Введите UDP порты для ИСКЛЮЧЕНИЯ через запятую (например: 51820,1194) или нажмите Enter: " CUSTOM_PORTS </dev/tty

        echo -e "\n${CYAN}>>> [1/4] Установка утилит сохранения iptables...${NC}"
        DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent netfilter-persistent > /dev/null 2>&1

        echo -e "${CYAN}>>> [2/4] Очистка старых правил OMETOOL (если были)...${NC}"
        # Безопасное удаление, чтобы не плодить дубли
        for cmd in iptables ip6tables; do
            $cmd -D OUTPUT -p udp ! -o lo -j OMETOOL_UDP_BLOCK 2>/dev/null
            $cmd -D FORWARD -p udp -j OMETOOL_UDP_BLOCK 2>/dev/null
            $cmd -F OMETOOL_UDP_BLOCK 2>/dev/null
            $cmd -X OMETOOL_UDP_BLOCK 2>/dev/null
        done

        echo -e "${CYAN}>>> [3/4] Создание непробиваемой цепочки правил...${NC}"
        for cmd in iptables ip6tables; do
            # Создаем кастомную цепочку
            $cmd -N OMETOOL_UDP_BLOCK
            
            # Перенаправляем весь исходящий и транзитный UDP (кроме локального lo) в нашу цепочку
            $cmd -I OUTPUT -p udp ! -o lo -j OMETOOL_UDP_BLOCK
            $cmd -I FORWARD -p udp -j OMETOOL_UDP_BLOCK
            
            # РАЗРЕШАЕМ критичные порты
            $cmd -A OMETOOL_UDP_BLOCK -p udp --dport 53 -j ACCEPT   # DNS
            $cmd -A OMETOOL_UDP_BLOCK -p udp --dport 123 -j ACCEPT  # NTP
            
            # РАЗРЕШАЕМ порты пользователя
            if [ -n "$CUSTOM_PORTS" ]; then
                IFS=',' read -ra PORT_ARRAY <<< "$CUSTOM_PORTS"
                for port in "${PORT_ARRAY[@]}"; do
                    port=$(echo "$port" | xargs) # убираем пробелы
                    if [[ "$port" =~ ^[0-9]+$ ]]; then
                        $cmd -A OMETOOL_UDP_BLOCK -p udp --sport $port -j ACCEPT
                        $cmd -A OMETOOL_UDP_BLOCK -p udp --dport $port -j ACCEPT
                    fi
                done
            fi
            
            # ОТКЛОНЯЕМ весь остальной UDP
            if [ "$cmd" == "iptables" ]; then
                $cmd -A OMETOOL_UDP_BLOCK -j REJECT --reject-with icmp-port-unreachable
            else
                $cmd -A OMETOOL_UDP_BLOCK -j REJECT --reject-with icmp6-port-unreachable
            fi
        done

        echo -e "${CYAN}>>> [4/4] Сохранение правил (для работы после перезагрузки)...${NC}"
        netfilter-persistent save > /dev/null 2>&1

        echo -e "\n${YELLOW}===============================================${NC}"
        echo -e "${YELLOW}${BOLD}   🚫 UDP ТРАФИК УСПЕШНО ЗАБЛОКИРОВАН!         ${NC}"
        echo -e "${YELLOW}===============================================${NC}"
        echo -e "Теперь торренты не смогут установить соединение."
        echo -e "Связь сервера с внешним миром ограничена TCP, DNS и NTP."
        if [ -n "$CUSTOM_PORTS" ]; then
            echo -e "Открытые исключения: ${GREEN}${CUSTOM_PORTS}${NC}"
        fi
        echo -e "${YELLOW}===============================================${NC}\n"
        ;;

    2)
        echo -e "\n${GREEN}🟢 Снятие блокировки UDP...${NC}"
        
        for cmd in iptables ip6tables; do
            # Удаляем перенаправления
            $cmd -D OUTPUT -p udp ! -o lo -j OMETOOL_UDP_BLOCK 2>/dev/null
            $cmd -D FORWARD -p udp -j OMETOOL_UDP_BLOCK 2>/dev/null
            # Очищаем и удаляем саму цепочку
            $cmd -F OMETOOL_UDP_BLOCK 2>/dev/null
            $cmd -X OMETOOL_UDP_BLOCK 2>/dev/null
        done

        # Сохраняем чистые правила
        if command -v netfilter-persistent &> /dev/null; then
            netfilter-persistent save > /dev/null 2>&1
        fi

        echo -e "\n${YELLOW}===============================================${NC}"
        echo -e "${GREEN}${BOLD}   ✅ БЛОКИРОВКА СНЯТА. UDP СНОВА РАБОТАЕТ!    ${NC}"
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

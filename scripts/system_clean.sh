#!/usr/bin/env bash
# ================================================================
# 🧹 OMETOOL - Умная очистка системы (Smart System Cleaner)
# ================================================================

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

# Функция получения свободного места (в % и ГБ)
get_disk_usage() {
    df -h / | awk 'NR==2 {print $3 " / " $2 " (" $5 " занято)"}'
}

# Функция перевода байтов в читаемый формат (для точного подсчета)
get_avail_kb() {
    df / | awk 'NR==2 {print $4}'
}

echo -e "\n${CYAN}${BOLD}🧹 Модуль очистки системы инициализирован...${NC}\n"
echo -e "📊 Состояние диска до очистки: ${YELLOW}$(get_disk_usage)${NC}\n"

echo -e "${BOLD}Выберите режим очистки:${NC}"
echo -e "  ${GREEN}[1]${NC} 🌱 Легкая (Базовая) - Безопасное удаление старых кэшей и пакетов (Рекомендуется)"
echo -e "  ${RED}[2]${NC} 🔥 Жесткая (Интерактивная) - Глубокий поиск мусора, логов и старых данных"
echo -e "  ${CYAN}[0]${NC} 🚪 Выход"
echo ""
read -p "👉 Ваш выбор: " CLEAN_MODE

SPACE_BEFORE=$(get_avail_kb)

case $CLEAN_MODE in
    1)
        echo -e "\n${GREEN}🌱 Запуск легкой очистки...${NC}"
        
        echo -e "📦 Очистка кэша APT и старых зависимостей..."
        apt-get autoremove -y > /dev/null 2>&1
        apt-get clean > /dev/null 2>&1
        
        echo -e "📓 Очистка старых системных журналов (оставляем за 7 дней)..."
        journalctl --vacuum-time=7d > /dev/null 2>&1
        
        echo -e "🗑️ Очистка временных файлов пользователя..."
        rm -rf /root/.cache/* 2>/dev/null
        
        echo -e "${GREEN}✅ Легкая очистка завершена!${NC}"
        ;;
        
    2)
        echo -e "\n${RED}${BOLD}🔥 Запуск ЖЕСТКОЙ очистки. Будьте внимательны!${NC}\n"
        
        # 1. APT Cache
        APT_SIZE=$(du -sh /var/cache/apt 2>/dev/null | awk '{print $1}')
        echo -e "${CYAN}📦 Кэш пакетов (APT) занимает: ${YELLOW}$APT_SIZE${NC}"
        read -p "   Удалить кэш загруженных пакетов и сироты? [y/N]: " ans
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            apt-get autoremove --purge -y > /dev/null 2>&1
            apt-get clean > /dev/null 2>&1
            echo -e "   ${GREEN}Удалено.${NC}"
        fi
        
        # 2. Systemd Journal
        JOURNAL_SIZE=$(du -sh /var/log/journal 2>/dev/null | awk '{print $1}')
        if [ -n "$JOURNAL_SIZE" ]; then
            echo -e "\n${CYAN}📓 Системный журнал (systemd) занимает: ${YELLOW}$JOURNAL_SIZE${NC}"
            read -p "   Сжать журнал до минимума (оставить 10MB)? [y/N]: " ans
            if [[ "$ans" =~ ^[Yy]$ ]]; then
                journalctl --vacuum-size=10M > /dev/null 2>&1
                echo -e "   ${GREEN}Журнал сжат.${NC}"
            fi
        fi

        # 3. Old Logs
        OLD_LOGS=$(find /var/log -type f \( -name "*.gz" -o -name "*.1" \) -exec du -ch {} + 2>/dev/null | grep total$ | awk '{print $1}')
        if [ -n "$OLD_LOGS" ]; then
            echo -e "\n${CYAN}📄 Старые архивированные логи (*.gz, *.1) занимают: ${YELLOW}$OLD_LOGS${NC}"
            read -p "   Удалить старые логи? [y/N]: " ans
            if [[ "$ans" =~ ^[Yy]$ ]]; then
                find /var/log -type f \( -name "*.gz" -o -name "*.1" \) -delete
                echo -e "   ${GREEN}Старые логи удалены.${NC}"
            fi
        fi

        # 4. Crash Reports
        CRASH_SIZE=$(du -sh /var/crash 2>/dev/null | awk '{print $1}')
        if [ "$CRASH_SIZE" != "0" ] && [ -n "$CRASH_SIZE" ]; then
            echo -e "\n${CYAN}💥 Отчеты об ошибках системы занимают: ${YELLOW}$CRASH_SIZE${NC}"
            read -p "   Удалить отчеты о крашах? [y/N]: " ans
            if [[ "$ans" =~ ^[Yy]$ ]]; then
                rm -rf /var/crash/*
                echo -e "   ${GREEN}Отчеты удалены.${NC}"
            fi
        fi

        # 5. Docker (если установлен)
        if command -v docker &> /dev/null; then
            DOCKER_SIZE=$(docker system df | awk '/Images/ {print $4}')
            echo -e "\n${CYAN}🐳 Docker обнаружен. Данные (образы, контейнеры) занимают: ${YELLOW}$DOCKER_SIZE${NC}"
            echo -e "   ${RED}ВНИМАНИЕ:${NC} Это удалит все ОСТАНОВЛЕННЫЕ контейнеры, неиспользуемые сети и образы (dangling)!"
            read -p "   Выполнить безопасную очистку Docker? [y/N]: " ans
            if [[ "$ans" =~ ^[Yy]$ ]]; then
                docker system prune -f > /dev/null 2>&1
                echo -e "   ${GREEN}Docker очищен.${NC}"
            fi
        fi
        
        # 6. Очистка текущих пухлых логов без удаления файла (truncate)
        echo -e "\n${CYAN}🧹 Очистка активных логов (syslog, auth.log и т.д.)...${NC}"
        read -p "   Обнулить текущие большие логи (безопасно)? [y/N]: " ans
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            find /var/log -type f -name "*.log" -exec truncate -s 0 {} \;
            truncate -s 0 /var/log/syslog 2>/dev/null
            truncate -s 0 /var/log/messages 2>/dev/null
            echo -e "   ${GREEN}Логи обнулены.${NC}"
        fi

        echo -e "\n${GREEN}🔥 Жесткая очистка завершена!${NC}"
        ;;
        
    0)
        echo -e "Отмена."
        exit 0
        ;;
    *)
        echo -e "${RED}Неверный выбор.${NC}"
        exit 1
        ;;
esac

# Подсчет освобожденного места
SPACE_AFTER=$(get_avail_kb)
FREED_KB=$((SPACE_AFTER - SPACE_BEFORE))

# Конвертация в Мегабайты для красивого вывода
if [ $FREED_KB -gt 0 ]; then
    FREED_MB=$((FREED_KB / 1024))
    echo -e "\n=============================================="
    echo -e "🎉 ${BOLD}ОТЧЕТ ОБ ОЧИСТКЕ${NC}"
    echo -e "=============================================="
    echo -e "Освобождено места: ${GREEN}${BOLD}+${FREED_MB} MB${NC}"
    echo -e "Состояние диска:   ${CYAN}$(get_disk_usage)${NC}"
    echo -e "==============================================\n"
else
    echo -e "\n${YELLOW}Мусора не найдено. Система уже чиста!${NC}"
    echo -e "Состояние диска: ${CYAN}$(get_disk_usage)${NC}\n"
fi

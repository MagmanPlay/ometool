#!/usr/bin/env bash
# ================================================================
# ⚙️ OMETOOL - Интеллектуальное управление Swap (Файл подкачки)
# ================================================================

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

echo -e "\n${CYAN}${BOLD}⚙️ Запуск модуля управления Swap-файлом...${NC}\n"

# ================= Функции аналитики =================
get_ram_mb() {
    free -m | awk '/^Mem:/{print $2}'
}

get_free_disk_mb() {
    df -m / | awk 'NR==2 {print $4}'
}

get_cpu_cores() {
    nproc
}

# ================= Интерактивное меню =================
echo -e "${BOLD}Выберите режим создания Swap:${NC}"
echo -e "  ${GREEN}[1]${NC} 🧠 Умный (Автоматический расчет на основе железа сервера)"
echo -e "  ${MAGENTA}[2]${NC} 🛠️ Ручной (Самостоятельно указать объем в ГБ)"
echo -e "  ${CYAN}[0]${NC} 🚪 Выход"
echo ""

read -p "👉 Ваш выбор: " SWAP_MODE </dev/tty

case $SWAP_MODE in
    1)
        echo -e "\n${YELLOW}🔍 Анализ оборудования сервера...${NC}"
        
        RAM_MB=$(get_ram_mb)
        DISK_MB=$(get_free_disk_mb)
        CORES=$(get_cpu_cores)
        
        echo -e "  💻 ${BOLD}Процессор:${NC}       $CORES ядер"
        echo -e "  🧠 ${BOLD}Оперативная память:${NC} $RAM_MB MB"
        echo -e "  💾 ${BOLD}Свободно на диске:${NC}  $DISK_MB MB"

        # Умная логика расчета
        if [ "$RAM_MB" -le 2048 ]; then
            # Для <= 2GB ОЗУ: Swap = ОЗУ * 2
            CALC_SWAP=$((RAM_MB * 2))
        elif [ "$RAM_MB" -le 8192 ]; then
            # Для 2-8GB ОЗУ: Swap = ОЗУ
            CALC_SWAP=$RAM_MB
        else
            # Для > 8GB ОЗУ: Swap = 4GB (обычно этого достаточно для серверов)
            CALC_SWAP=4096
        fi

        # Проверка, чтобы Swap не занял больше 25% свободного места
        MAX_ALLOWED=$((DISK_MB / 4))
        if [ "$CALC_SWAP" -gt "$MAX_ALLOWED" ]; then
            echo -e "  ${RED}⚠️ Диск заполнен! Уменьшаем размер подкачки для безопасности.${NC}"
            CALC_SWAP=$MAX_ALLOWED
        fi

        SWAP_GB=$(awk "BEGIN {printf \"%.1f\", $CALC_SWAP/1024}")
        
        echo -e "\n${GREEN}💡 Рекомендуемый размер Swap: ${BOLD}${CALC_SWAP} MB (~${SWAP_GB} GB)${NC}"
        read -p "👉 Применить эти настройки? [Y/n]: " ans </dev/tty
        if [[ "$ans" =~ ^[Nn]$ ]]; then
            echo -e "Отмена."
            exit 0
        fi
        FINAL_SWAP_MB=$CALC_SWAP
        ;;
        
    2)
        echo -e "\n${MAGENTA}🛠️ Ручной режим${NC}"
        while true; do
            read -p "👉 Введите желаемый размер Swap в Гигабайтах (например: 2): " INPUT_GB </dev/tty
            if [[ "$INPUT_GB" =~ ^[0-9]+$ ]] && [ "$INPUT_GB" -gt 0 ]; then
                FINAL_SWAP_MB=$((INPUT_GB * 1024))
                break
            else
                echo -e "${RED}❌ Пожалуйста, введите целое число больше нуля.${NC}"
            fi
        done
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

# ================= Выполнение установки =================
SWAP_FILE="/swapfile"

echo -e "\n${CYAN}>>> [1/5] Проверка старого файла подкачки...${NC}"
if swapon --show | grep -q "$SWAP_FILE"; then
    echo -e "  ${YELLOW}Обнаружен активный Swap. Отключаем и удаляем...${NC}"
    swapoff "$SWAP_FILE"
    rm -f "$SWAP_FILE"
fi

echo -e "${CYAN}>>> [2/5] Выделение места на диске (${FINAL_SWAP_MB} MB)...${NC}"
# Используем fallocate (быстро), если ФС не поддерживает - фоллбэк на dd (медленно, но надежно)
if ! fallocate -l "${FINAL_SWAP_MB}M" "$SWAP_FILE" 2>/dev/null; then
    echo -e "  ${YELLOW}fallocate не сработал. Используем dd (это займет время)...${NC}"
    dd if=/dev/zero of="$SWAP_FILE" bs=1M count="$FINAL_SWAP_MB" status=progress
fi

echo -e "${CYAN}>>> [3/5] Настройка прав доступа и форматирование...${NC}"
chmod 600 "$SWAP_FILE"
mkswap "$SWAP_FILE" > /dev/null 2>&1

echo -e "${CYAN}>>> [4/5] Активация и сохранение в fstab (Постоянный Swap)...${NC}"
swapon "$SWAP_FILE"
# Удаляем старую запись, если была, и добавляем новую
sed -i '\#/swapfile#d' /etc/fstab
echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab

echo -e "${CYAN}>>> [5/5] Применение серверных оптимизаций ядра...${NC}"
# Настройка swappiness (10 вместо 60) - использовать Swap только в крайнем случае
# Настройка vfs_cache_pressure (50 вместо 100) - дольше хранить кэш ФС в ОЗУ
cat <<EOF > /etc/sysctl.d/99-swap-optimize.conf
vm.swappiness=10
vm.vfs_cache_pressure=50
EOF
sysctl --system > /dev/null 2>&1

# ФИНАЛ
echo -e "\n${YELLOW}===============================================${NC}"
echo -e "${YELLOW}${BOLD}     🎉 SWAP УСПЕШНО НАСТРОЕН И ОПТИМИЗИРОВАН  ${NC}"
echo -e "${YELLOW}===============================================${NC}"
echo -e "💾 ${BOLD}Текущий Swap:${NC}"
swapon --show
echo -e "\n🔧 ${BOLD}Оптимизации:${NC}"
echo -e "  vm.swappiness = $(sysctl -n vm.swappiness) ${GREEN}(Оптимально для сервера)${NC}"
echo -e "  vm.vfs_cache_pressure = $(sysctl -n vm.vfs_cache_pressure)"
echo -e "${YELLOW}===============================================${NC}\n"

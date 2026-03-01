#!/usr/bin/env bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color (сброс цвета)
BOLD='\033[1m'

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}🚫 Ошибка: Скрипт должен выполняться с правами root.${NC}"
  echo -e "Используйте: ${YELLOW}sudo bash $0${NC}"
  exit 1
fi

draw_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "  ██████╗ ███╗   ███╗███████╗████████╗ ██████╗ ██████╗ ██╗     "
    echo " ██╔═══██╗████╗ ████║██╔════╝╚══██╔══╝██╔═══██╗██╔══██╗██║     "
    echo " ██║   ██║██╔████╔██║█████╗     ██║   ██║   ██║██║  ██║██║     "
    echo " ██║   ██║██║╚██╔╝██║██╔══╝     ██║   ██║   ██║██║  ██║██║     "
    echo " ╚██████╔╝██║ ╚═╝ ██║███████╗   ██║   ╚██████╔╝██████╔╝███████╗"
    echo "  ╚═════╝ ╚═╝     ╚═╝╚══════╝   ╚═╝    ╚═════╝ ╚═════╝ ╚══════╝"
    echo "==============================================================="
    echo "       🚀 POWERFUL SERVER MULTI TOOL SCRIPT 🚀                 "
    echo "==============================================================="
    echo -e "${NC}"
}

run_remote_script() {
    local script_name="$1"
    local script_url="$2"

    echo -e "\n${YELLOW}▶ Запускаю сценарий: ${BOLD}${GREEN}${script_name}${NC}...\n"
    
    if curl -sSL "$script_url" | bash; then
        echo -e "\n${GREEN}✅ Сценарий '${script_name}' успешно выполнен!${NC}"
    else
        echo -e "\n${RED}❌ Ошибка при выполнении сценария '${script_name}'.${NC}"
        echo -e "Проверьте ссылку на GitHub или наличие интернета."
    fi
    
    echo -e "\nНажмите ${YELLOW}Enter${NC}, чтобы вернуться в главное меню..."
    read -r
}

# ================================================================
# 🔄 Основной цикл меню
# ================================================================
while true; do
    draw_banner
    echo -e "${BOLD}Выберите нужное действие:${NC}\n"
    
    echo -e "  ${MAGENTA}1.${NC} Базовая подготовка VM на Ubuntu 24.04 (Firewall, DNS, BBR, Cron)"
    echo -e "  ${MAGENTA}2.${NC} Установка Docker.io (Оптимизировано для Ubuntu 24.04)"
    echo -e "  ${MAGENTA}3.${NC} Деплой DNSTT (Туннелирование)"
    echo -e "  ${MAGENTA}0.${NC} Выход из меню\n"
    
    read -p "👉 Ваш выбор: " choice

    case $choice in
        1)
            run_remote_script "Базовая подготовка VM" "https://raw.githubusercontent.com/MagmanPlay/ometool/main/scripts/vm_prep.sh"
            ;;
        2)
            run_remote_script "Установка Docker.io" "https://raw.githubusercontent.com/MagmanPlay/ometool/main/scripts/install_dockerio.sh"
            ;;
        3)
            run_remote_script "Деплой DNSTT" "https://raw.githubusercontent.com/MagmanPlay/ometool/main/scripts/deploy_dnstt.sh"
            ;;
        0)
            echo -e "\n${GREEN}👋 Завершение работы. Удачи!${NC}\n"
            exit 0
            ;;
        *)
            echo -e "\n${RED}⚠️ Неверный выбор! Пожалуйста, укажите цифру из меню.${NC}"
            sleep 2
            ;;
    esac
done

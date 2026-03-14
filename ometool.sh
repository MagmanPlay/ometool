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
    local tmp_script="/tmp/ometool_temp_module.sh"

    echo -e "\n${YELLOW}▶ Загружаю модуль: ${BOLD}${GREEN}${script_name}${NC}...\n"
    
    if curl -sSL "$script_url" -o "$tmp_script"; then
        
        bash "$tmp_script"
        
        if [ $? -eq 0 ]; then
            echo -e "\n${GREEN}✅ Модуль '${script_name}' успешно выполнен!${NC}"
        else
            echo -e "\n${RED}⚠️ Выполнение '${script_name}' завершено с ошибкой или прервано.${NC}"
        fi
        
        rm -f "$tmp_script"
    else
        echo -e "\n${RED}❌ Ошибка: Не удалось скачать модуль. Проверьте ссылку или интернет.${NC}"
    fi
    
    echo -e "\nНажмите ${YELLOW}Enter${NC}, чтобы вернуться в главное меню..."
    read -r </dev/tty
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
    echo -e "  ${MAGENTA}4.${NC} Очистка системы (Light / Hard)"
    echo -e "  ${MAGENTA}5.${NC} Деплой Python-бота (Авто venv + systemd)"
    echo -e "  ${MAGENTA}6.${NC} Настройка Swap-файла (Smart/Manual)"
    echo -e "  ${MAGENTA}0.${NC} Выход из меню\n"
    
    # Добавлен /dev/tty для жесткой привязки к клавиатуре
    read -p "👉 Ваш выбор: " choice </dev/tty

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
        4)
            run_remote_script "Очистка системы" "https://raw.githubusercontent.com/MagmanPlay/ometool/main/scripts/system_clean.sh" 
            ;;
        5)
            run_remote_script "Деплой Python-бота" "https://raw.githubusercontent.com/MagmanPlay/ometool/main/scripts/python_bot_deploy.sh"
            ;;              
        6)
            run_remote_script "Настройка Swap" "https://raw.githubusercontent.com/MagmanPlay/ometool/main/scripts/swap_manager.sh"
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

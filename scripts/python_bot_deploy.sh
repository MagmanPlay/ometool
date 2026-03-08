#!/usr/bin/env bash
# ================================================================
# 🐍 OMETOOL - Умный деплой Python скриптов/ботов в systemd
# ================================================================

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

echo -e "\n${CYAN}${BOLD}🐍 Запуск мастера деплоя Python-ботов...${NC}\n"

# ================= Интерактивный ввод =================
echo -e "${YELLOW}📝 Шаг 1: Настройка параметров сервиса${NC}"

# Запрос имени сервиса
while true; do
    read -p "👉 Введите имя сервиса (например, my_tg_bot): " SERVICE_NAME </dev/tty
    if [[ "$SERVICE_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        break
    else
        echo -e "${RED}❌ Недопустимое имя. Используйте только латинские буквы, цифры, '_' и '-'.${NC}"
    fi
done

# Запрос пути к файлу
while true; do
    read -p "👉 Введите полный путь к вашему .py файлу (например, /root/mybot/bot.py): " SCRIPT_PATH </dev/tty
    if [ -f "$SCRIPT_PATH" ]; then
        break
    else
        echo -e "${RED}❌ Файл не найден! Убедитесь, что вы указали правильный абсолютный путь.${NC}"
    fi
done

# Извлекаем директорию скрипта из полного пути
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")
VENV_PATH="$SCRIPT_DIR/venv"
EXEC_PYTHON="$VENV_PATH/bin/python"

echo -e "\n${GREEN}✅ Принято! Сервис: ${SERVICE_NAME}, Путь: ${SCRIPT_PATH}${NC}\n"
# =====================================================

echo -e "${CYAN}>>> [1/5] Установка системных зависимостей Python (venv, pip)...${NC}"
apt-get update -qq
apt-get install -y python3-venv python3-pip python3-dev -qq

echo -e "${CYAN}>>> [2/5] Создание виртуального окружения (venv)...${NC}"
if [ ! -d "$VENV_PATH" ]; then
    python3 -m venv "$VENV_PATH"
    echo -e "${GREEN}  vENV успешно создан в $VENV_PATH${NC}"
else
    echo -e "${YELLOW}  vENV уже существует, пропускаем создание.${NC}"
fi

echo -e "${CYAN}>>> [3/5] Установка зависимостей Python...${NC}"
if [ -f "$SCRIPT_DIR/requirements.txt" ]; then
    echo -e "  Найден requirements.txt. Устанавливаем пакеты..."
    "$EXEC_PYTHON" -m pip install -r "$SCRIPT_DIR/requirements.txt" -q
    echo -e "${GREEN}  Зависимости установлены!${NC}"
else
    echo -e "${YELLOW}  Файл requirements.txt не найден. Пропускаем установку пакетов.${NC}"
    echo -e "  ${BOLD}Совет:${NC} Убедитесь, что вашему боту не нужны сторонние библиотеки, или установите их вручную."
fi

echo -e "${CYAN}>>> [4/5] Создание systemd сервиса...${NC}"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=Python Bot Service ($SERVICE_NAME)
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$SCRIPT_DIR
ExecStart=$EXEC_PYTHON $SCRIPT_PATH
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

echo -e "${GREEN}  Файл сервиса создан: $SERVICE_FILE${NC}"

echo -e "${CYAN}>>> [5/5] Запуск и добавление в автозагрузку...${NC}"
systemctl daemon-reload
systemctl enable --now "$SERVICE_NAME" > /dev/null 2>&1

# ФИНАЛ
echo -e "\n${YELLOW}===============================================${NC}"
echo -e "${YELLOW}${BOLD}     🎉 PYTHON БОТ УСПЕШНО ЗАПУЩЕН!            ${NC}"
echo -e "${YELLOW}===============================================${NC}"
echo -e "🤖 ${BOLD}Имя сервиса:${NC}     $SERVICE_NAME"
echo -e "📂 ${BOLD}Рабочая папка:${NC}   $SCRIPT_DIR"
echo -e "🐍 ${BOLD}Окружение:${NC}       $VENV_PATH"
echo -e "${YELLOW}===============================================${NC}"
echo -e "\n${BOLD}Полезные команды для управления:${NC}"
echo -e "🟢 Статус:          ${GREEN}systemctl status $SERVICE_NAME${NC}"
echo -e "🔄 Перезапуск:      ${CYAN}systemctl restart $SERVICE_NAME${NC}"
echo -e "🛑 Остановка:       ${RED}systemctl stop $SERVICE_NAME${NC}"
echo -e "📜 Чтение логов:    ${MAGENTA}journalctl -u $SERVICE_NAME -f${NC}\n"

echo -e "${BOLD}Текущий статус:${NC}"
systemctl status "$SERVICE_NAME" --no-pager | grep Active
echo -e ""

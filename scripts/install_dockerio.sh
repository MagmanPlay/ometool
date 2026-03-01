#!/usr/bin/env bash
# ================================================================
# 🐳 Установка Docker.io и Docker Compose (Native Ubuntu Method)
# ================================================================

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

echo -e "\n${CYAN}${BOLD}🚀 Начинаем установку Docker.io и Docker Compose...${NC}\n"

# 1. Очистка системы от других версий
echo -e "${YELLOW}🧹 Шаг 1: Удаление возможных конфликтующих пакетов Docker-CE...${NC}"
apt purge -y docker-ce docker-ce-cli docker-buildx-plugin docker-compose-plugin 2>/dev/null
apt autoremove -y 2>/dev/null
echo -e "${GREEN}✅ Очистка завершена.${NC}\n"

# 2. Установка из репозиториев Ubuntu
echo -e "${YELLOW}📦 Шаг 2: Обновление списка пакетов и установка docker.io...${NC}"
apt update -y
apt install -y docker.io docker-compose-v2
echo -e "${GREEN}✅ Пакеты успешно установлены.${NC}\n"

# 3. Настройка сервиса
echo -e "${YELLOW}⚙️ Шаг 3: Добавление Docker в автозагрузку и запуск...${NC}"
systemctl enable --now docker
echo -e "${GREEN}✅ Сервис Docker активирован.${NC}\n"

# 4. Финальная проверка работоспособности
echo -e "${CYAN}${BOLD}🔍 Шаг 4: Проверка статуса установки...${NC}"

# Проверяем наличие команды и активность демона systemd
if command -v docker &> /dev/null && systemctl is-active --quiet docker; then
    DOCKER_VER=$(docker --version)
    COMPOSE_VER=$(docker compose version)
    
    echo -e "\n=============================================="
    echo -e "${GREEN}🎉 Установка успешно завершена!${NC}"
    echo -e "=============================================="
    echo -e "🐳 ${BOLD}Docker:${NC}  $DOCKER_VER"
    echo -e "🐙 ${BOLD}Compose:${NC} $COMPOSE_VER"
    echo -e "🟢 ${BOLD}Статус:${NC}  Активен и работает"
    echo -e "==============================================\n"
else
    echo -e "\n${RED}❌ Ошибка: Docker установлен некорректно или сервис не запустился.${NC}"
    echo -e "Для диагностики выполните команду: ${YELLOW}systemctl status docker${NC}\n"
fi

#!/bin/bash
# ==============================================================================
#                 NOVADAYZ SHOP - Ubuntu Auto-Installer Script
# ==============================================================================
# OS Support: Ubuntu 20.04 / 22.04 / 24.04 (LTS)
# Runs as: root
# ==============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}==============================================================================${NC}"
echo -e "${BLUE}                   NOVADAYZ SHOP AUTO-INSTALLER SCRIPT                        ${NC}"
echo -e "${BLUE}==============================================================================${NC}"

# 1. Root & OS check
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Ошибка: Этот скрипт должен быть запущен от имени суперпользователя (root).${NC}"
  echo -e "Используйте: sudo $0"
  exit 1
fi

if [ -f /etc/os-release ]; then
  . /etc/os-release
  if [ "$ID" != "ubuntu" ]; then
    echo -e "${YELLOW}Предупреждение: Этот скрипт официально поддерживает только Ubuntu.${NC}"
    read -p "Вы действительно хотите продолжить? (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
      exit 1
    fi
  fi
else
  echo -e "${RED}Ошибка: Не удалось определить операционную систему.${NC}"
  exit 1
fi

# 2. Interactive user inputs
echo -e "\n${YELLOW}>>> Настройка конфигурации проекта...${NC}"
read -p "Введите имя домена (например, novadayz.ru) или оставьте пустым для IP: " DOMAIN
read -p "Введите ваш Steam Web API Key (можно получить на https://steamcommunity.com/dev/apikey): " STEAM_KEY
read -p "Введите секретный ключ для мода DayZ (DayZ Server API Key): " DAYZ_KEY
read -p "Введите репозиторий GitHub в формате 'owner/repo' (например: Behemiron/NovaDayzStore): " GIT_REPO

USE_SSH="true"
GIT_TOKEN=""

if [ -n "$GIT_REPO" ]; then
  read -p "Использовать SSH Deploy Key для авторизации в GitHub? (Рекомендуется) (Y/n): " auth_choice
  if [[ "$auth_choice" =~ ^[Nn]$ ]]; then
    USE_SSH="false"
    read -p "Введите ваш GitHub Personal Access Token (PAT): " GIT_TOKEN
  else
    USE_SSH="true"
    # Ensure root SSH directory exists
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    
    # Generate SSH Key if it does not exist
    SSH_KEY_FILE="/root/.ssh/id_ed25519_novadayz"
    if [ ! -f "$SSH_KEY_FILE" ]; then
      echo -e "${YELLOW}>>> Генерация SSH Deploy Key...${NC}"
      ssh-keygen -t ed25519 -f "$SSH_KEY_FILE" -N "" -q
      chmod 600 "$SSH_KEY_FILE"
      chmod 644 "${SSH_KEY_FILE}.pub"
    fi
    
    echo -e "\n${GREEN}==============================================================================${NC}"
    echo -e "${GREEN}  ВАШ SSH DEPLOY KEY (СКОПИРУЙТЕ СТРОКУ НИЖЕ И ДОБАВЬТЕ В НАСТРОЙКИ GITHUB):     ${NC}"
    echo -e "${GREEN}==============================================================================${NC}"
    cat "${SSH_KEY_FILE}.pub"
    echo -e "${GREEN}==============================================================================${NC}"
    echo -e "  Инструкция:"
    echo -e "  1. Откройте ваш GitHub-репозиторий -> Settings -> Deploy keys -> Add deploy key"
    echo -e "  2. Вставьте скопированный ключ в поле Key"
    echo -e "  3. Назовите ключ (например, VPS Deploy Key)"
    echo -e "  4. Нажмите Add key"
    echo -e "${GREEN}==============================================================================${NC}"
    
    read -p "После того как добавите ключ на GitHub, нажмите ENTER для продолжения установки..." dummy
  fi
fi

# Generate random secure passwords for DB and JWT
DB_PASS=$(openssl rand -hex 16)
JWT_SECRET=$(openssl rand -hex 32)
JWT_REFRESH_SECRET=$(openssl rand -hex 32)

echo -e "\n${YELLOW}>>> Установка необходимых пакетов...${NC}"
apt-get update -y
apt-get upgrade -y
apt-get install -y curl git build-essential openssl nginx certbot python3-certbot-nginx

# 3. Install Node.js 20 LTS
if ! command -v node &> /dev/null; then
  echo -e "${YELLOW}>>> Установка Node.js 20...${NC}"
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs
fi
echo -e "${GREEN}Node.js версия: $(node -v)${NC}"
echo -e "${GREEN}npm версия: $(npm -v)${NC}"

# 4. Install PM2
if ! command -v pm2 &> /dev/null; then
  echo -e "${YELLOW}>>> Установка PM2...${NC}"
  npm install -y -g pm2
fi

# 5. Install MySQL Server
if ! command -v mysql &> /dev/null; then
  echo -e "${YELLOW}>>> Установка MySQL Server...${NC}"
  apt-get install -y mysql-server
  systemctl start mysql
  systemctl enable mysql
fi

# Configure MySQL Database & User
echo -e "${YELLOW}>>> Настройка базы данных MySQL...${NC}"
mysql -e "CREATE DATABASE IF NOT EXISTS novadayz CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -e "CREATE USER IF NOT EXISTS 'novadayz'@'localhost' IDENTIFIED BY '${DB_PASS}';"
mysql -e "GRANT ALL PRIVILEGES ON novadayz.* TO 'novadayz'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

# 6. Setup Directory Structure
APP_DIR="/var/www/novadayz"
echo -e "${YELLOW}>>> Подготовка директорий в $APP_DIR...${NC}"

# If running installer inside the source codebase directory, copy local files
if [ -d "./backend" ] && [ -d "./frontend" ]; then
  echo -e "Копирование файлов проекта из текущего расположения..."
  mkdir -p $APP_DIR
  cp -r ./backend $APP_DIR/
  cp -r ./frontend $APP_DIR/
  if [ -f "./package.json" ]; then
    cp ./package.json $APP_DIR/
  fi
  if [ -f "./package-lock.json" ]; then
    cp ./package-lock.json $APP_DIR/
  fi
  if [ -f "./.gitignore" ]; then
    cp ./.gitignore $APP_DIR/
  fi
else
  # Fresh installation - clone from GitHub repo
  echo -e "Клонирование репозитория с GitHub..."
  rm -rf $APP_DIR
  if [ "$USE_SSH" = "true" ]; then
    GIT_SSH_COMMAND="ssh -i /root/.ssh/id_ed25519_novadayz -o StrictHostKeyChecking=no" git clone git@github.com:${GIT_REPO}.git $APP_DIR
    cd $APP_DIR
    git config core.sshCommand "ssh -i /root/.ssh/id_ed25519_novadayz -o StrictHostKeyChecking=no"
  else
    git clone https://${GIT_TOKEN}@github.com/${GIT_REPO}.git $APP_DIR
  fi
fi

# 7. Generate Configuration files
echo -e "${YELLOW}>>> Генерация конфигурационных файлов .env...${NC}"

# Backend config
cat > $APP_DIR/backend/.env << ENVEOF
NODE_ENV=production
PORT=3001
FRONTEND_URL=http://${DOMAIN:-localhost}
DATABASE_URL=mysql://novadayz:${DB_PASS}@localhost:3306/novadayz
REDIS_URL=redis://localhost:6379
JWT_SECRET=${JWT_SECRET}
JWT_REFRESH_SECRET=${JWT_REFRESH_SECRET}
JWT_ACCESS_EXPIRY=15m
JWT_REFRESH_EXPIRY=7d
STEAM_API_KEY=${STEAM_KEY}
DAYZ_SERVER_API_KEY=${DAYZ_KEY}
ENVEOF

# Frontend config
cat > $APP_DIR/frontend/.env.local << ENVEOF
NEXT_PUBLIC_BACKEND_URL=http://${DOMAIN:-localhost}/api
NEXT_PUBLIC_API_URL=http://${DOMAIN:-localhost}/api
ENVEOF

# Write DB credentials so the updater can read it if needed
cat > $APP_DIR/.db_creds << CREDSEOF
DB_USER=novadayz
DB_PASS=${DB_PASS}
DB_NAME=novadayz
CREDSEOF

# 8. Build Backend
echo -e "${YELLOW}>>> Сборка бэкенда...${NC}"
cd $APP_DIR/backend
npm install --production=false
npx prisma generate
npx prisma db push --accept-data-loss
npm run build

# Save default settings values to DB for domain and github
mysql -u novadayz -p${DB_PASS} novadayz -e "
INSERT INTO SystemSetting (\`key\`, \`value\`) VALUES
('system.domain', '${DOMAIN}'),
('system.ssl_mode', 'http'),
('github.token', '${GIT_TOKEN}'),
('github.repo', '${GIT_REPO}')
ON DUPLICATE KEY UPDATE \`value\` = VALUES(\`value\`);"

# 9. Build Frontend
echo -e "${YELLOW}>>> Сборка фронтенда...${NC}"
cd $APP_DIR/frontend
npm install
NEXT_PUBLIC_BACKEND_URL="http://${DOMAIN:-localhost}/api" npm run build

# 10. Configure Nginx Virtual Host
echo -e "${YELLOW}>>> Настройка веб-сервера Nginx...${NC}"
cat > /etc/nginx/sites-available/novadayz << NGINXEOF
server {
    listen 80;
    server_name ${DOMAIN:-_};

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_cache_bypass \$http_upgrade;
    }

    location /api/ {
        proxy_pass http://localhost:3001/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_cache_bypass \$http_upgrade;
    }

    location /_next/static/ {
        proxy_pass http://localhost:3000/_next/static/;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
NGINXEOF

ln -sf /etc/nginx/sites-available/novadayz /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default || true
nginx -t
systemctl reload nginx

# 11. Run Services with PM2
echo -e "${YELLOW}>>> Запуск приложений под PM2...${NC}"
pm2 delete novadayz-backend 2>/dev/null || true
pm2 delete novadayz-frontend 2>/dev/null || true

cd $APP_DIR/backend
pm2 start dist/main.js --name novadayz-backend --env production

cd $APP_DIR/frontend
pm2 start npm --name novadayz-frontend -- start -- -p 3000

pm2 save
pm2 startup systemd -u root --hp /root || true

# 12. Let's Encrypt SSL automation
if [ -n "$DOMAIN" ] && [ "$DOMAIN" != "localhost" ]; then
  echo -e "${YELLOW}>>> Запрос SSL сертификата Let's Encrypt для $DOMAIN...${NC}"
  certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email admin@$DOMAIN --redirect || echo -e "${RED}Предупреждение: Не удалось выпустить SSL. Возможно, домен не направлен на этот IP.${NC}"
fi

echo -e "\n${GREEN}==============================================================================${NC}"
echo -e "${GREEN}             УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА!                                     ${NC}"
echo -e "${GREEN}==============================================================================${NC}"
echo -e "  Сайт доступен по адресу: http://${DOMAIN:-Ваш_IP_Сервера}"
echo -e "  Бэкенд API:              http://${DOMAIN:-Ваш_IP_Сервера}/api"
echo -e "  Пароль к базе данных:    ${DB_PASS} (Сохранен в $APP_DIR/.db_creds)"
echo -e "${GREEN}==============================================================================${NC}"

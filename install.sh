#!/bin/bash
# ==============================================================================
#                 NOVADAYZ SHOP - Ubuntu Auto-Installer Script
# ==============================================================================
# OS Support: Ubuntu 20.04 / 22.04 / 24.04 (LTS)
# Runs as: root (will configure and run applications under novadayz system user)
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
read -p "Репозиторий GitHub (по умолчанию Behemiron/NovaDayzStore): " GIT_REPO
GIT_REPO=${GIT_REPO:-Behemiron/NovaDayzStore}

USE_SSH="true"
GIT_TOKEN=""

# 3. Create non-privileged system user "novadayz"
if ! id "novadayz" &>/dev/null; then
  echo -e "${YELLOW}>>> Создание системного пользователя novadayz...${NC}"
  useradd -r -m -U -d /home/novadayz -s /bin/bash novadayz
fi

if [ -n "$GIT_REPO" ]; then
  read -p "Использовать SSH Deploy Key для авторизации в GitHub? (Рекомендуется) (Y/n): " auth_choice
  if [[ "$auth_choice" =~ ^[Nn]$ ]]; then
    USE_SSH="false"
    read -p "Введите ваш GitHub Personal Access Token (PAT): " GIT_TOKEN
  else
    USE_SSH="true"
    # Ensure novadayz SSH directory exists
    mkdir -p /home/novadayz/.ssh
    chmod 700 /home/novadayz/.ssh
    
    # Generate SSH Key if it does not exist
    SSH_KEY_FILE="/home/novadayz/.ssh/id_ed25519_novadayz"
    if [ ! -f "$SSH_KEY_FILE" ]; then
      echo -e "${YELLOW}>>> Генерация SSH Deploy Key...${NC}"
      ssh-keygen -t ed25519 -f "$SSH_KEY_FILE" -N "" -q
      chmod 600 "$SSH_KEY_FILE"
      chmod 644 "${SSH_KEY_FILE}.pub"
    fi
    chown -R novadayz:novadayz /home/novadayz/.ssh
    
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
apt-get install -y curl git build-essential openssl nginx certbot python3-certbot-nginx sudo

# Configure sudoers for passwordless Nginx/Certbot reload by novadayz user
echo -e "${YELLOW}>>> Настройка прав sudo для пользователя novadayz...${NC}"
echo "novadayz ALL=(ALL) NOPASSWD: /usr/sbin/nginx, /usr/bin/systemctl reload nginx, /usr/bin/certbot" > /etc/sudoers.d/novadayz
chmod 440 /etc/sudoers.d/novadayz

# 4. Install Node.js 20 LTS
if ! command -v node &> /dev/null; then
  echo -e "${YELLOW}>>> Установка Node.js 20...${NC}"
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs
fi
echo -e "${GREEN}Node.js версия: $(node -v)${NC}"
echo -e "${GREEN}npm версия: $(npm -v)${NC}"

# 5. Install PM2
if ! command -v pm2 &> /dev/null; then
  echo -e "${YELLOW}>>> Установка PM2...${NC}"
  npm install -y -g pm2
fi

# 6. Install MySQL Server
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

# 7. Setup Directory Structure
APP_DIR="/var/www/novadayz"
echo -e "${YELLOW}>>> Подготовка директорий в $APP_DIR...${NC}"

# Fresh installation - clone from GitHub repo
echo -e "Клонирование репозитория с GitHub..."
rm -rf $APP_DIR
mkdir -p $APP_DIR
chown novadayz:novadayz $APP_DIR

if [ "$USE_SSH" = "true" ]; then
  sudo -u novadayz GIT_SSH_COMMAND="ssh -i /home/novadayz/.ssh/id_ed25519_novadayz -o StrictHostKeyChecking=no" git clone git@github.com:${GIT_REPO}.git $APP_DIR
  cd $APP_DIR
  sudo -u novadayz git config core.sshCommand "ssh -i /home/novadayz/.ssh/id_ed25519_novadayz -o StrictHostKeyChecking=no"
else
  sudo -u novadayz git clone https://${GIT_TOKEN}@github.com/${GIT_REPO}.git $APP_DIR
fi

# 8. Generate Configuration files
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

# Set ownership of all files to novadayz user
chown -R novadayz:novadayz $APP_DIR

# 9. Build Backend
echo -e "${YELLOW}>>> Сборка бэкенда...${NC}"
cd $APP_DIR/backend
sudo -u novadayz npm install --production=false
sudo -u novadayz npx prisma generate
sudo -u novadayz npx prisma db push --accept-data-loss
sudo -u novadayz npm run build

# Save default settings values to DB for domain and github
mysql -u novadayz -p${DB_PASS} novadayz -e "
INSERT INTO SystemSetting (\`key\`, \`value\`) VALUES
('system.domain', '${DOMAIN}'),
('system.ssl_mode', 'http'),
('github.token', '${GIT_TOKEN}'),
('github.repo', '${GIT_REPO}')
ON DUPLICATE KEY UPDATE \`value\` = VALUES(\`value\`);"

# 10. Build Frontend
echo -e "${YELLOW}>>> Сборка фронтенда...${NC}"
cd $APP_DIR/frontend
sudo -u novadayz npm install --production=false
sudo -u novadayz NEXT_PUBLIC_BACKEND_URL="http://${DOMAIN:-localhost}/api" npm run build

# 11. Configure Nginx Virtual Host
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

# Enable Nginx configs and assign ownership to novadayz user
touch /etc/nginx/sites-available/novadayz
chown novadayz:novadayz /etc/nginx/sites-available/novadayz
mkdir -p /etc/nginx/ssl
chown -R novadayz:novadayz /etc/nginx/ssl

ln -sf /etc/nginx/sites-available/novadayz /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default || true
nginx -t
systemctl reload nginx

# 12. Run Services with PM2 under novadayz user
echo -e "${YELLOW}>>> Запуск приложений под PM2...${NC}"
sudo -u novadayz pm2 delete novadayz-backend 2>/dev/null || true
sudo -u novadayz pm2 delete novadayz-frontend 2>/dev/null || true

cd $APP_DIR/backend
sudo -u novadayz pm2 start dist/main.js --name novadayz-backend --env production

cd $APP_DIR/frontend
sudo -u novadayz pm2 start npm --name novadayz-frontend -- start -- -p 3000

sudo -u novadayz pm2 save
env PATH=$PATH:/usr/bin pm2 startup systemd -u novadayz --hp /home/novadayz || true

# 13. Let's Encrypt SSL automation
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

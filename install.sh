#!/bin/bash
# ==============================================================================
#                 NOVADAYZ SHOP - Ubuntu Auto-Installer Script
# ==============================================================================
# OS Support: Ubuntu 20.04 / 22.04 / 24.04 (LTS)
# Lead Architect & Developer: Behemiron (Discord: behemiron_777777)
# Runs as: root (configures isolated unprivileged system user per project)
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
    read -p "Вы действительно хотите продолжить? (y/N): " confirm < /dev/tty || true
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

read -p "Введите уникальное имя проекта/владельца (например, yavol, dayz_pvp) [по умолчанию: shop]: " INPUT_PROJECT_NAME < /dev/tty || true
INPUT_PROJECT_NAME=$(echo "$INPUT_PROJECT_NAME" | tr -cd 'a-zA-Z0-9_' | tr '[:upper:]' '[:lower:]')
INPUT_PROJECT_NAME=${INPUT_PROJECT_NAME:-shop}

# Dynamically derived secure names for isolation
SYS_USER="${INPUT_PROJECT_NAME}_novadayz"
SYS_HOME="/home/${SYS_USER}"
APP_DIR="/var/www/${SYS_USER}"
DB_NAME="${INPUT_PROJECT_NAME}_db"
DB_USER="${SYS_USER}"
PM2_BACKEND="${INPUT_PROJECT_NAME}-backend"
PM2_FRONTEND="${INPUT_PROJECT_NAME}-frontend"
NGINX_CONF="${SYS_USER}"

echo -e "${GREEN}Изолированный пользователь Linux: ${SYS_USER}${NC}"
echo -e "${GREEN}Директория установки проекта:     ${APP_DIR}${NC}"
echo -e "${GREEN}База данных MySQL:                ${DB_NAME}${NC}"

read -p "Введите имя домена (например, novadayz.ru) или оставьте пустым для IP: " DOMAIN < /dev/tty || true
DOMAIN=$(echo "$DOMAIN" | tr -d '\r')

if [ -z "$DOMAIN" ]; then
  echo -e "${YELLOW}Домен не указан. Автоматическое определение внешнего IP-адреса сервера...${NC}"
  DOMAIN=$(curl -s --max-time 5 https://api.ipify.org || echo "")
  DOMAIN=$(echo "$DOMAIN" | tr -d '\r')
  if [ -z "$DOMAIN" ]; then
    DOMAIN="localhost"
  fi
  echo -e "${GREEN}Используется IP-адрес: $DOMAIN${NC}"
fi

read -p "Введите ваш Steam Web API Key (можно получить на https://steamcommunity.com/dev/apikey): " STEAM_KEY < /dev/tty || true
STEAM_KEY=$(echo "$STEAM_KEY" | tr -d '\r')

read -p "Введите секретный ключ для мода DayZ (DayZ Server API Key): " DAYZ_KEY < /dev/tty || true
DAYZ_KEY=$(echo "$DAYZ_KEY" | tr -d '\r')

read -p "Репозиторий GitHub (по умолчанию Behemiron/NovaDayzStore): " GIT_REPO < /dev/tty || true
GIT_REPO=$(echo "$GIT_REPO" | tr -d '\r')
GIT_REPO=${GIT_REPO:-Behemiron/NovaDayzStore}

USE_SSH="true"
GIT_TOKEN=""

# 3. Create non-privileged isolated system user
if ! id "$SYS_USER" &>/dev/null; then
  echo -e "${YELLOW}>>> Создание изолированного системного пользователя ${SYS_USER}...${NC}"
  useradd -r -m -U -d "$SYS_HOME" -s /bin/bash "$SYS_USER"
fi

if [ -n "$GIT_REPO" ]; then
  read -p "Использовать SSH Deploy Key для авторизации в GitHub? (Рекомендуется) (Y/n): " auth_choice < /dev/tty || true
  if [[ "$auth_choice" =~ ^[Nn]$ ]]; then
    USE_SSH="false"
    read -p "Введите ваш GitHub Personal Access Token (PAT): " GIT_TOKEN < /dev/tty || true
  else
    USE_SSH="true"
    # Ensure project user SSH directory exists
    mkdir -p "${SYS_HOME}/.ssh"
    chmod 700 "${SYS_HOME}/.ssh"
    
    # Generate SSH Key if it does not exist
    SSH_KEY_FILE="${SYS_HOME}/.ssh/id_ed25519_${INPUT_PROJECT_NAME}"
    if [ ! -f "$SSH_KEY_FILE" ]; then
      echo -e "${YELLOW}>>> Генерация уникального SSH Deploy Key (${SSH_KEY_FILE})...${NC}"
      ssh-keygen -t ed25519 -f "$SSH_KEY_FILE" -N "" -q
      chmod 600 "$SSH_KEY_FILE"
      chmod 644 "${SSH_KEY_FILE}.pub"
    fi
    chown -R "${SYS_USER}:${SYS_USER}" "${SYS_HOME}/.ssh"
    
    echo -e "\n${GREEN}==============================================================================${NC}"
    echo -e "${GREEN}  YOUR LICENSE DEPLOY KEY (COPY THE PUBLIC KEY BELOW):                        ${NC}"
    echo -e "${GREEN}==============================================================================${NC}"
    cat "${SSH_KEY_FILE}.pub"
    echo -e "${GREEN}==============================================================================${NC}"
    echo -e "  LICENSE ACTIVATION INSTRUCTIONS:"
    echo -e "  1. Copy the full public key string above."
    echo -e "  2. Send this key directly to Behemiron via Discord: behemiron_777777"
    echo -e "  3. Wait for Behemiron to confirm that your license key has been added to repository."
    echo -e "  4. Once confirmed by Behemiron, press ENTER below to proceed with installation."
    echo -e "${GREEN}==============================================================================${NC}"
    
    read -p "After Behemiron confirms key activation, press ENTER to continue installation..." dummy < /dev/tty || true
  fi
fi

# Generate random secure passwords for DB and JWT
DB_PASS=$(openssl rand -hex 16)
JWT_SECRET=$(openssl rand -hex 32)
JWT_REFRESH_SECRET=$(openssl rand -hex 32)

echo -e "\n${YELLOW}>>> Установка необходимых пакетов...${NC}"
apt-get update -y
apt-get upgrade -y
apt-get install -y curl git build-essential openssl nginx certbot python3-certbot-nginx sudo redis-server

# Configure sudoers for passwordless Nginx/Certbot reload by isolated system user
echo -e "${YELLOW}>>> Настройка прав sudo для пользователя ${SYS_USER}...${NC}"
echo "${SYS_USER} ALL=(ALL) NOPASSWD: /usr/sbin/nginx, /usr/bin/systemctl reload nginx, /usr/bin/certbot" > "/etc/sudoers.d/${SYS_USER}"
chmod 440 "/etc/sudoers.d/${SYS_USER}"

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

# Enable and start Redis
echo -e "${YELLOW}>>> Настройка Redis Server...${NC}"
systemctl start redis-server
systemctl enable redis-server

# 6. Install MySQL Server
if ! command -v mysql &> /dev/null; then
  echo -e "${YELLOW}>>> Установка MySQL Server...${NC}"
  apt-get install -y mysql-server
  systemctl start mysql
  systemctl enable mysql
fi

# Configure MySQL Database & User
echo -e "${YELLOW}>>> Настройка базы данных MySQL (${DB_NAME})...${NC}"
mysql -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
mysql -e "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

# 7. Setup Directory Structure
echo -e "${YELLOW}>>> Подготовка изолированной директории в ${APP_DIR}...${NC}"

# Fresh installation - clone from GitHub repo
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR"
chown "${SYS_USER}:${SYS_USER}" "$APP_DIR"

if [ "$USE_SSH" = "true" ]; then
  sudo -u "$SYS_USER" GIT_SSH_COMMAND="ssh -i ${SSH_KEY_FILE} -o StrictHostKeyChecking=no" git clone "git@github.com:${GIT_REPO}.git" "$APP_DIR"
  cd "$APP_DIR"
  sudo -u "$SYS_USER" git config core.sshCommand "ssh -i ${SSH_KEY_FILE} -o StrictHostKeyChecking=no"
else
  sudo -u "$SYS_USER" git clone "https://${GIT_TOKEN}@github.com/${GIT_REPO}.git" "$APP_DIR"
fi

# 8. Generate Configuration files
echo -e "${YELLOW}>>> Генерация конфигурационных файлов .env...${NC}"

# Backend config
cat > "$APP_DIR/backend/.env" << ENVEOF
NODE_ENV=production
PORT=3001
APP_DIR=${APP_DIR}
SYSTEM_USER=${SYS_USER}
PM2_BACKEND_NAME=${PM2_BACKEND}
PM2_FRONTEND_NAME=${PM2_FRONTEND}
FRONTEND_URL=http://${DOMAIN:-localhost}
DATABASE_URL=mysql://${DB_USER}:${DB_PASS}@localhost:3306/${DB_NAME}
REDIS_URL=redis://localhost:6379
JWT_SECRET=${JWT_SECRET}
JWT_REFRESH_SECRET=${JWT_REFRESH_SECRET}
JWT_ACCESS_EXPIRY=15m
JWT_REFRESH_EXPIRY=7d
STEAM_API_KEY=${STEAM_KEY}
DAYZ_SERVER_API_KEY=${DAYZ_KEY}
ENVEOF

# Frontend config
cat > "$APP_DIR/frontend/.env.local" << ENVEOF
NEXT_PUBLIC_BACKEND_URL=http://${DOMAIN:-localhost}/api
NEXT_PUBLIC_API_URL=http://${DOMAIN:-localhost}/api
ENVEOF

# Write DB credentials so the updater can read it if needed
cat > "$APP_DIR/.db_creds" << CREDSEOF
DB_USER=${DB_USER}
DB_PASS=${DB_PASS}
DB_NAME=${DB_NAME}
CREDSEOF

# Set ownership of all files to project system user
chown -R "${SYS_USER}:${SYS_USER}" "$APP_DIR"

# 9. Build Backend
echo -e "${YELLOW}>>> Сборка бэкенда...${NC}"
cd "$APP_DIR/backend"
sudo -u "$SYS_USER" npm install --production=false
sudo -u "$SYS_USER" npx prisma generate
sudo -u "$SYS_USER" npx prisma db push --accept-data-loss
sudo -u "$SYS_USER" npm run build

# Save default settings values to DB for domain and github
mysql -u "$DB_USER" -p"${DB_PASS}" "${DB_NAME}" -e "
INSERT INTO SystemSetting (\`key\`, \`value\`) VALUES
('system.domain', '${DOMAIN}'),
('system.ssl_mode', 'http'),
('github.token', '${GIT_TOKEN}'),
('github.repo', '${GIT_REPO}')
ON DUPLICATE KEY UPDATE \`value\` = VALUES(\`value\`);"

# 10. Build Frontend
echo -e "${YELLOW}>>> Сборка фронтенда...${NC}"
cd "$APP_DIR/frontend"
sudo -u "$SYS_USER" npm install --production=false
sudo -u "$SYS_USER" NEXT_PUBLIC_BACKEND_URL="http://${DOMAIN:-localhost}/api" npm run build

# 11. Configure Nginx Virtual Host
echo -e "${YELLOW}>>> Настройка веб-сервера Nginx...${NC}"
cat > "/etc/nginx/sites-available/${NGINX_CONF}" << NGINXEOF
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
        add_header Cache-Control "no-cache, no-store, must-revalidate";
        add_header Pragma "no-cache";
        add_header Expires "0";
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

# Enable Nginx configs and assign ownership to system user
touch "/etc/nginx/sites-available/${NGINX_CONF}"
chown "${SYS_USER}:${SYS_USER}" "/etc/nginx/sites-available/${NGINX_CONF}"
mkdir -p /etc/nginx/ssl
chown -R "${SYS_USER}:${SYS_USER}" /etc/nginx/ssl

ln -sf "/etc/nginx/sites-available/${NGINX_CONF}" /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default || true
nginx -t
systemctl reload nginx

# 12. Run Services with PM2 under isolated user
echo -e "${YELLOW}>>> Запуск приложений под PM2 (пользователь ${SYS_USER})...${NC}"
sudo -u "$SYS_USER" pm2 delete "$PM2_BACKEND" 2>/dev/null || true
sudo -u "$SYS_USER" pm2 delete "$PM2_FRONTEND" 2>/dev/null || true

cd "$APP_DIR/backend"
sudo -u "$SYS_USER" pm2 start dist/main.js --name "$PM2_BACKEND" --env production

cd "$APP_DIR/frontend"
sudo -u "$SYS_USER" pm2 start npm --name "$PM2_FRONTEND" -- start -- -p 3000

sudo -u "$SYS_USER" pm2 save
env PATH=$PATH:/usr/bin pm2 startup systemd -u "$SYS_USER" --hp "$SYS_HOME" || true

# 13. Let's Encrypt SSL automation
if [ -n "$DOMAIN" ] && [ "$DOMAIN" != "localhost" ]; then
  echo -e "${YELLOW}>>> Запрос SSL сертификата Let's Encrypt для $DOMAIN...${NC}"
  certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email admin@$DOMAIN --redirect || echo -e "${RED}Предупреждение: Не удалось выпустить SSL. Возможно, домен не направлен на этот IP.${NC}"
fi

# 14. Firewall Security Configuration (UFW)
echo -e "${YELLOW}>>> Настройка брандмауэра UFW (Автоматическая защита портов)...${NC}"
if command -v ufw &> /dev/null || apt-get install -y ufw; then
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow 22/tcp      # SSH доступ для администратора
  ufw allow 80/tcp      # HTTP Web доступ
  ufw allow 443/tcp     # HTTPS Web доступ (SSL)
  ufw deny 3306/tcp     # Закрытие порта MySQL от внешних атак
  ufw deny 5432/tcp     # Закрытие порта PostgreSQL от внешних атак
  ufw deny 6379/tcp     # Закрытие порта Redis
  ufw deny 3000/tcp     # Блокировка прямого обращения к Next.js в обход Nginx
  ufw deny 3001/tcp     # Блокировка прямого обращения к Nest.js API в обход Nginx
  ufw --force enable
  echo -e "${GREEN}Брандмауэр UFW успешно включен! Внешний доступ к БД (3306), Redis (6379) и API (3001) надежно закрыт.${NC}"
fi

echo -e "\n${GREEN}==============================================================================${NC}"
echo -e "${GREEN}             УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА!                                     ${NC}"
echo -e "${GREEN}==============================================================================${NC}"
echo -e "  Проект / Пользователь:   ${SYS_USER}"
echo -e "  Директория установки:    ${APP_DIR}"
echo -e "  Сайт доступен по адресу: http://${DOMAIN:-Ваш_IP_Сервера}"
echo -e "  Бэкенд API:              http://${DOMAIN:-Ваш_IP_Сервера}/api"
echo -e "  Пароль к базе данных:    ${DB_PASS} (Сохранен в ${APP_DIR}/.db_creds)"
echo -e "${GREEN}==============================================================================${NC}"

# Самоудаление скрипта после успешного завершения
rm -- "$0" 2>/dev/null || true

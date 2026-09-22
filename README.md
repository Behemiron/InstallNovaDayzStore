# Behemiron Store — Automated Server Deployment

Production-ready automated installation script for deploying **Behemiron Store** web platforms (NovaDayZ, PaPaDayz, Survive Rust, and custom gaming shops) on **Ubuntu 20.04 / 22.04 / 24.04 LTS**.

Designed & Maintained by **Behemiron** (Discord: `behemiron_777777`).

---

## Architecture & Security Breakdown

This installer configures a hardened, non-root Linux environment following production security standards:

1. **System User Isolation**: Automatically creates a dedicated non-privileged system user `${name}_behemiron` (`/home/${name}_behemiron`) and runs all Node.js / PM2 / Next.js application processes strictly under this unprivileged user.
2. **Automated UFW Firewall Security**:
   - **Allowed Public Ports**: `80` (HTTP), `443` (HTTPS), `22` (SSH).
   - **Blocked External Ports**: `3306` (MySQL), `5432` (PostgreSQL), `6379` (Redis), `3000` (Next.js Direct), `3001` (NestJS API Direct).
   - Database and application services bind locally to `127.0.0.1` and are reverse-proxied exclusively through Nginx.
3. **Database Isolation**: Installs MySQL Server and creates a dedicated database `${name}_db` with auto-generated 32-character high-entropy credentials.
4. **Nginx Reverse Proxy & SSL**: Configures virtual host routing for API `/api` and frontend `/`, with automated Let's Encrypt TLS certificate issuance via Certbot.
5. **Zero-Downtime Process Management**: Integrates PM2 with systemd auto-restart policies upon VPS reboot.
6. **Direct IP Drop (Anti-Bot return 444) & /tmp Execution Hardening**:
   - Drops all direct raw IP and port scanner attacks (bypassing Cloudflare or DNS) with Nginx `return 444` (instant TCP drop without response).
   - Mounts `/tmp` and `/var/tmp` with `noexec, nosuid, nodev` flags to block execution of web shells, miners, and binary payloads.
   - Activates `fail2ban` for automated port scan and brute-force mitigation at firewall level.
   - Creates isolated user temp directories to guarantee 100% build stability for Node.js and APT.

---

## Prerequisites

Before executing the installer:

1. A fresh **Ubuntu LTS (20.04 / 22.04 / 24.04)** server instance with SSH `root` access.
2. A valid domain name with its **DNS A Record** pointing to your VPS public IP (e.g., `shop.yourserver.com`).
3. Your **Steam Web API Key** (obtainable from [Steam Developer Portal](https://steamcommunity.com/dev/apikey)).

---

## Quick One-Line Launch

Connect to your VPS via SSH as `root` and run:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Behemiron/InstallNovaDayzStore/main/install.sh)"
```

Alternatively:
```bash
curl -sSL https://raw.githubusercontent.com/Behemiron/InstallNovaDayzStore/main/install.sh | sudo bash
```

---

## Step-by-Step Installation Prompt Walkthrough

During installation, the script will prompt you for configuration parameters:

### Step 1: Unique Project & System User Name
- **Prompt**: `Введите уникальное имя проекта/владельца (например, yavol, dayz_pvp) [по умолчанию: shop]:`
- **Action**: Enter your custom project identifier (e.g., `yavol`).
- **Security Hardening**: The installer dynamically generates a unique isolated Linux system user `${name}_behemiron` (e.g., `yavol_behemiron`), isolates its home directory `/home/yavol_behemiron`, installs application code in `/var/www/yavol_behemiron`, and provisions a dedicated database `${name}_db`.

### Step 2: Domain Configuration
- **Prompt**: `Введите имя домена (например, myshop.ru) или оставьте пустым для IP:`
- **Action**: Type your domain name (e.g. `shop.yourserver.com`) without `http://` or `https://`.
- **Note**: If you do not have a domain yet, press `ENTER`. The script will automatically detect your public VPS IP address and configure the web store to run directly on the IP.

### Step 3: Steam Web API Key
- **Prompt**: `Введите ваш Steam Web API Key:`
- **Action**: Paste your 32-character Steam Developer API Key. This key is required for Steam OpenID authentication and retrieving player avatars/names.

### Step 4: Server Secret API Key
- **Prompt**: `Введите секретный ключ для мода сервера (Server API Key):`
- **Action**: Enter any strong secret string (e.g., `my_secret_server_key_98765`). This exact key will be configured in your server mod's config to secure in-game delivery requests.

### Step 5: Repository Selection
- **Prompt**: `Репозиторий GitHub (например, Behemiron/NovaDayZStore или Behemiron/PaPaDayz) [по умолчанию: Behemiron/NovaDayZStore]:`
- **Action**: Enter your licensed product repository, or press `ENTER` to accept the default repository.

### Step 6: Authorization Mode
- **Prompt**: `Использовать SSH Deploy Key для авторизации в GitHub? (Рекомендуется) (Y/n):`
- **Action**: Press `ENTER` or type `y`. The script will generate a dedicated SSH key pair.

### Step 7: License Key Generation & Activation (Instant)
- The installer displays your generated SSH Public Deploy Key on screen:
  ```text
  ==============================================================================
    YOUR SSH DEPLOY KEY (СКОПИРУЙТЕ ПУБЛИЧНЫЙ КЛЮЧ НИЖЕ):                        
  ==============================================================================
  ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... behemiron@server
  ==============================================================================
  ```
- **Action Steps**:
  1. Copy the full `ssh-ed25519 ...` public key line printed in your console.
  2. Paste it in your client dashboard at **https://behemiron.tech** in the «Привязать Deploy Key» field for instant automatic repository activation, OR send it to **Behemiron** via Discord: `behemiron_777777`.
  3. Once added, return to your server console and press `ENTER` to resume execution.

---

## Post-Installation Automated Sequence

After pressing `ENTER`, the installer autonomously handles the rest of the deployment:

1. Installs Node.js 20 LTS, MySQL, Redis, Nginx, Certbot, PM2, and UFW Firewall.
2. Clones the repository codebase into your custom isolated project directory `/var/www/${project_user}` (e.g., `/var/www/yavol_behemiron`).
3. Auto-generates production `.env` configuration files with random DB passwords and JWT secrets.
4. Compiles the NestJS backend API (`npm run build`).
5. Compiles the Next.js frontend web application (`npm run build`).
6. Configures Nginx virtual host proxying and automatically issues SSL via Certbot.
7. Enables UFW Firewall rules blocking external access to database ports (`3306`, `5432`, `6379`, `3000`, `3001`).
8. Launches background services under PM2 and saves startup policies.

---

## Server Management Commands

Replace `<project_user>` (e.g., `yavol_behemiron`) and `<project_name>` (e.g., `yavol`) with the custom project identifier chosen during setup:

```bash
# View active application process status
sudo -u <project_user> pm2 status

# View live application logs
sudo -u <project_user> pm2 logs <project_name>-backend
sudo -u <project_user> pm2 logs <project_name>-frontend

# Restart application services
sudo -u <project_user> pm2 restart <project_name>-backend
sudo -u <project_user> pm2 restart <project_name>-frontend

# Check active UFW firewall rules & blocked ports
sudo ufw status verbose
```

---

## Developer Support & Inquiries

For license activations, technical support, or custom mod integrations:

- **Lead Architect & Developer**: Behemiron
- **Discord**: `behemiron_777777`
- **License Hub**: https://behemiron.tech
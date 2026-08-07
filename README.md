# NovaDayZ Store — Automated Server Deployment

Production-ready automated installation script for deploying the **NovaDayZ Store** web platform on **Ubuntu 20.04 / 22.04 / 24.04 LTS**.

Designed & Maintained by **Behemiron** (Discord: `behemiron_777777`).

---

## Architecture & Security Breakdown

This installer configures a hardened, non-root Linux environment following production security standards:

1. **System User Isolation**: Automatically creates a non-privileged `novadayz` system user (`/home/novadayz`) and runs all Node.js / PM2 / Next.js application processes strictly under this unprivileged user.
2. **Automated UFW Firewall Security**:
   - **Allowed Public Ports**: `80` (HTTP), `443` (HTTPS), `22` (SSH).
   - **Blocked External Ports**: `3306` (MySQL), `5432` (PostgreSQL), `6379` (Redis), `3000` (Next.js Direct), `3001` (NestJS API Direct).
   - Database and application services bind locally to `127.0.0.1` and are reverse-proxied exclusively through Nginx.
3. **Database Isolation**: Installs MySQL Server and creates a dedicated database `novadayz` with auto-generated 32-character high-entropy credentials.
4. **Nginx Reverse Proxy & SSL**: Configures virtual host routing for API `/api` and frontend `/`, with automated Let's Encrypt TLS certificate issuance via Certbot.
5. **Zero-Downtime Process Management**: Integrates PM2 with systemd auto-restart policies upon VPS reboot.

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
curl -sSL https://raw.githubusercontent.com/Behemiron/InstallNovaDayzStore/main/install.sh | sudo bash
```

---

## Step-by-Step Installation Prompt Walkthrough

During installation, the script will prompt you for configuration parameters. Below is the complete step-by-step breakdown:

### Step 1: System User Creation
- The script automatically checks for the `novadayz` system user. If it does not exist, it creates the isolated user account `/home/novadayz` with restricted permissions.

### Step 2: Domain Configuration
- **Prompt**: `Введите имя домена (например, novadayz.ru) или оставьте пустым для IP:`
- **Action**: Type your domain name (e.g. `shop.yourserver.com`) without `http://` or `https://`.
- **Note**: If you do not have a domain yet, press `ENTER`. The script will automatically detect your public VPS IP address and configure the web store to run directly on the IP.

### Step 3: Steam Web API Key
- **Prompt**: `Введите ваш Steam Web API Key:`
- **Action**: Paste your 32-character Steam Developer API Key. This key is required for Steam OpenID authentication and retrieving player avatars/names.

### Step 4: DayZ Server Secret API Key
- **Prompt**: `Введите секретный ключ для мода DayZ (DayZ Server API Key):`
- **Action**: Enter any strong secret string (e.g., `my_secret_dayz_key_98765`). This exact key will be configured in your server mod's `$profile:\NovaDayZStore\config.json` to secure in-game delivery requests.

### Step 5: Repository Selection
- **Prompt**: `Репозиторий GitHub (по умолчанию Behemiron/NovaDayzStore):`
- **Action**: Press `ENTER` to accept the default official private repository (`Behemiron/NovaDayzStore`).

### Step 6: Authorization Mode
- **Prompt**: `Использовать SSH Deploy Key для авторизации в GitHub? (Рекомендуется) (Y/n):`
- **Action**: Press `ENTER` or type `y`. The script will generate a dedicated SSH key pair under `/home/novadayz/.ssh/id_ed25519_novadayz`.

### Step 7: License Key Generation & Activation (Crucial)
- The installer displays your generated SSH Public Deploy Key on screen:
  ```text
  ==============================================================================
    YOUR LICENSE DEPLOY KEY (COPY THE PUBLIC KEY BELOW):                        
  ==============================================================================
  ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... novadayz@server
  ==============================================================================
  ```
- **Action Steps**:
  1. Copy the full `ssh-ed25519 ...` public key line printed in your console.
  2. Send this public key to **Behemiron** via Discord: `behemiron_777777`.
  3. Wait for **Behemiron** to confirm that your license key has been activated for repository access.
  4. Once confirmed by Behemiron, return to your server console and press `ENTER` to resume execution.

---

## Post-Installation Automated Sequence

After pressing `ENTER`, the installer autonomously handles the rest of the deployment:

1. Installs Node.js 20 LTS, MySQL, Redis, Nginx, Certbot, PM2, and UFW Firewall.
2. Clones the repository codebase into `/var/www/novadayz`.
3. Auto-generates production `.env` configuration files with random DB passwords and JWT secrets.
4. Compiles the NestJS backend API (`npm run build`).
5. Compiles the Next.js frontend web application (`npm run build`).
6. Configures Nginx virtual host proxying and automatically issues SSL via Certbot.
7. Enables UFW Firewall rules blocking external access to database ports (`3306`, `5432`, `6379`, `3000`, `3001`).
8. Launches background services under PM2 and saves startup policies.

---

## Server Management Commands

```bash
# View active application process status
sudo -u novadayz pm2 status

# View live application logs
sudo -u novadayz pm2 logs novadayz-backend
sudo -u novadayz pm2 logs novadayz-frontend

# Restart application services
sudo -u novadayz pm2 restart novadayz-backend
sudo -u novadayz pm2 restart novadayz-frontend

# Check active UFW firewall rules & blocked ports
sudo ufw status verbose
```

---

## Developer Support & Inquiries

For license activations, technical support, or custom DayZ mod integrations:

- **Lead Architect & Developer**: Behemiron
- **Discord**: `behemiron_777777`

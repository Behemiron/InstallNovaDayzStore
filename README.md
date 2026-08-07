# NovaDayZ Store — Automated Server Deployment

Production-ready automated installation script for deploying the **NovaDayZ Store** web platform on **Ubuntu 20.04 / 22.04 / 24.04 LTS**.

Designed and maintained by **Behemiron**.

---

## Architecture & Security Breakdown

This installer configures a hardened, non-root Linux environment following production security standards:

1. **Isolated System User**: Runs all Node.js services under a dedicated non-privileged `novadayz` user account.
2. **Automated UFW Firewall Hardening**:
   - **Allowed Ports**: `80` (HTTP), `443` (HTTPS), `22` (SSH).
   - **Blocked Ports**: `3306` (MySQL), `5432` (PostgreSQL), `6379` (Redis), `3000` (Next.js Direct), `3001` (NestJS API Direct).
   - All internal services communicate exclusively via local sockets (`127.0.0.1`) and reverse-proxied through Nginx.
3. **Database Security**: Provisions MySQL with auto-generated 32-character high-entropy credentials.
4. **Nginx Reverse Proxy**: Pre-configured HTTP/2 proxying with automated Let's Encrypt TLS certificate provisioning via Certbot.
5. **Process Manager (PM2)**: Configures systemd auto-restart policies for zero-downtime execution.

---

## Prerequisites

Before executing the installer:

1. A clean **Ubuntu LTS (20.04 / 22.04 / 24.04)** instance with root access.
2. A valid domain name pointing its **A Record** to your server IP (e.g., `shop.yourserver.com`).
3. Your **Steam Web API Key** (obtainable via [Steam Developer Portal](https://steamcommunity.com/dev/apikey)).

---

## One-Line Automated Installation

Connect to your VPS via SSH as `root` and execute:

```bash
curl -sSL https://raw.githubusercontent.com/Behemiron/InstallNovaDayzStore/main/install.sh | sudo bash
```

---

## Interactive Step Walkthrough

1. **Domain Name**: Enter your domain (e.g. `shop.yourserver.com`). If testing on bare IP, press `ENTER`.
2. **Steam API Key**: Provide your Steam Developer Web API Key.
3. **DayZ Server API Key**: Set your secret key used to authenticate requests between your DayZ server mod and backend.
4. **GitHub Repository**: Press `ENTER` to accept default (`Behemiron/NovaDayzStore`).
5. **License Key Activation**:
   - The script generates a unique Ed25519 Deploy Key (License Key).
   - Copy the printed public key string.
   - Send the key directly to **Behemiron** via Discord: `behemiron_777777`.
   - Wait for **Behemiron** to confirm that your key has been activated for repository access.
   - Once confirmed by Behemiron, return to your server terminal and press `ENTER` to proceed with automated setup.

---

## Service Management Commands

```bash
# Check status of running backend and frontend services
sudo -u novadayz pm2 status

# View live backend application logs
sudo -u novadayz pm2 logs novadayz-backend

# Restart backend or frontend
sudo -u novadayz pm2 restart novadayz-backend
sudo -u novadayz pm2 restart novadayz-frontend

# Inspect active firewall rules
sudo ufw status verbose
```

---

## Developer Support & Inquiries

For technical support, custom DayZ mod integrations, or server setup inquiries:

- **Lead Architect**: Behemiron
- **Discord**: `behemiron_777777`

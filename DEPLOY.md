# Deployment Guide

Complete guide for deploying Pixel Raiders to different targets using the unified deployment system.

## Quick Start

All deployment configuration is managed in your main `.env` file. Update the values there to change deploy targets.

### Yarn Commands

```bash
# PortMaster
yarn deploy              # Deploy to PortMaster (dev API)
yarn deploy:prod         # Deploy to PortMaster (production API)

# Linux
yarn deploy:linux        # Deploy to Linux target (dev API)
yarn deploy:linux:prod   # Deploy to Linux target (production API)

# Windows
yarn deploy:windows      # Deploy to Windows target (dev API)
yarn deploy:windows:prod # Deploy to Windows target (production API)
```

## Configuration (.env)

Edit your `.env` file to configure deployment targets:

```bash
# Dev API Configuration
DEV_API_URL=http://10.0.0.197:3000
DEV_RELAY_HOST=10.0.0.197
DEV_RELAY_PORT=12346

# Linux Deploy Target
LINUX_TARGET_HOST=imac.local
LINUX_TARGET_USER=alsinas
LINUX_DEPLOY_PATH=~/Desktop/PIXELRAIDERS-linux

# Windows Deploy Target
WINDOWS_TARGET_HOST=192.168.1.100
WINDOWS_TARGET_USER=YourUsername
WINDOWS_DEPLOY_PATH=C:/Users/YourUsername/Desktop/PIXELRAIDERS-win64

# PortMaster Deploy Target
PORTMASTER_TARGET_HOST=10.0.0.94
PORTMASTER_TARGET_USER=spruce
PORTMASTER_TARGET_PASS=happygaming
PORTMASTER_DEPLOY_PATH=/mnt/sdcard/Roms/PORTS
```

## Windows SSH Setup

To deploy to Windows, you need to enable SSH on the target machine.

### 1. Install OpenSSH Server (Windows 10/11)

Open PowerShell as Administrator and run:

```powershell
# Install OpenSSH Server
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

# Start the service
Start-Service sshd

# Set it to start automatically
Set-Service -Name sshd -StartupType 'Automatic'

# Confirm the firewall rule is configured
Get-NetFirewallRule -Name *ssh*
```

### 2. Get Windows IP Address

On the Windows machine, open Command Prompt and run:

```cmd
ipconfig
```

Look for "IPv4 Address" under your active network adapter. Update `WINDOWS_TARGET_HOST` in `.env` with this IP.

### 3. Test SSH Connection

From your Mac, test the connection:

```bash
ssh YourUsername@192.168.1.100
```

Replace `YourUsername` with your Windows username and `192.168.1.100` with your Windows IP.

### 4. Set Up SSH Keys (Optional but Recommended)

For passwordless deployment:

```bash
# On your Mac, generate SSH key if you don't have one
ssh-keygen -t rsa -b 4096

# Copy your public key to Windows
ssh-copy-id YourUsername@192.168.1.100
```

On Windows, if `ssh-copy-id` doesn't work, manually add your public key:

1. Create `C:\Users\YourUsername\.ssh\authorized_keys`
2. Copy contents of `~/.ssh/id_rsa.pub` from Mac into that file

### 5. Update .env

Update your `.env` file with the correct Windows configuration:

```bash
WINDOWS_TARGET_HOST=192.168.1.100  # Your Windows IP
WINDOWS_TARGET_USER=YourUsername   # Your Windows username
WINDOWS_DEPLOY_PATH=C:/Users/YourUsername/Desktop/PIXELRAIDERS-win64
```

## Troubleshooting

### SSH Connection Failed

**Linux/Mac:**
- Ensure SSH is enabled: `System Preferences > Sharing > Remote Login`
- Check firewall settings
- Verify hostname resolves: `ping imac.local`

**Windows:**
- Ensure OpenSSH Server is running: `Get-Service sshd`
- Check firewall allows SSH (port 22)
- Try IP address instead of hostname

**PortMaster:**
- Ensure device is powered on
- Check network connectivity
- Verify IP address is correct

### Deployment Path Issues

**Windows:**
- Use forward slashes in paths: `C:/Users/...` not `C:\Users\...`
- Ensure user has write permissions to the target directory

**Linux/Mac:**
- Use `~` for home directory or full absolute paths
- Check directory permissions

### Build Fails

- Ensure you have all required tools installed
- Check that `.env` file exists and is properly formatted
- Try cleaning build cache: `yarn dist:clean`

## Direct Script Usage

If you prefer not to use yarn:

```bash
# PortMaster
./build/portmaster/deploy.sh
./build/portmaster/deploy.sh --prod

# Linux  
./build/desktop/deploy-linux.sh
./build/desktop/deploy-linux.sh --prod

# Windows
./build/desktop/deploy-windows.sh
./build/desktop/deploy-windows.sh --prod
```

## What Gets Deployed

### Linux
- `PIXELRAIDERS.love` - Game package
- `PIXELRAIDERS.sh` - Launcher script
- `love.AppImage` or `PIXELRAIDERS.AppImage` - LÖVE runtime

### Windows
- `PIXELRAIDERS.exe` - Game executable
- All required DLL files
- `love-license.txt`

### PortMaster
- `PIXELRAIDERS.sh` - Launcher script
- `PIXELRAIDERS/` folder containing:
  - `PIXELRAIDERS.love` - Game package
  - `PIXELRAIDERS.gptk` - Controller mapping
  - `port.json` - PortMaster metadata

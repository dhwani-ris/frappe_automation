# 🚀 Frappe Setup Wizard

A streamlined bash script for setting up Frappe Framework with automated bench creation, site deployment, and production configuration.

## ✨ Features

- **Complete System Setup**: Automated installation of all dependencies
- **Smart Environment Detection**: Separate configurations for development and production
- **Automated Theme Installation**: Installs [Frappe Desk Theme](https://github.com/dhwani-ris/frappe_desk_theme) automatically
- **Custom App Creation**: Built-in support for creating and deploying custom Frappe apps
- **Production Ready**: Full production setup with Supervisor, Nginx, SSL, and proper file permissions
- **Assets 404 Fix**: Resolves common assets serving issues in production
- **Git Integration**: Automatic Git repository setup for custom apps

## 📋 Prerequisites

- **OS**: Ubuntu 20.04+ / Debian 11+
- **User**: Non-root user with sudo privileges
- **Memory**: Minimum 2GB RAM (4GB+ recommended for production)
- **Storage**: At least 10GB free space

## 🚀 Quick Start

### 1. Download and Setup

```bash
# Make executable
chmod +x frappe_enhanced_setup.sh

# Run the script
./frappe_enhanced_setup.sh
```

### 2. Setup Workflow

#### Option 1: Complete Setup
```
1) Complete Setup (System Dependencies + MySQL + SSH/Git)
```
This installs:
- System packages (Python, Node.js, MariaDB, Redis, etc.)
- wkhtmltopdf for PDF generation
- MySQL/MariaDB with secure configuration
- SSH keys for Git repositories
- Python virtual environment with frappe-bench

#### Option 2: Create Bench
```
2) Create Bench
```
- Creates a new Frappe bench with specified version
- Default version: `version-15`
- Customizable bench name

#### Option 3: Create Site
```
3) Create Site
```
- Creates a new Frappe site
- Installs Frappe Desk Theme automatically
- Optional custom app creation with Git integration
- Choose between Development or Production environment

## 🛠️ Detailed Setup Guide

### Complete System Setup

The script automatically installs these dependencies:

**System Packages:**
- Python 3.8+ with dev tools
- Node.js 18+ and Yarn
- MariaDB server and client
- Redis server
- Nginx web server
- Supervisor process manager
- Let's Encrypt certbot
- wkhtmltopdf for PDF generation

**Python Packages:**
- frappe-bench
- Required Python libraries

### Environment Configurations

#### Development Environment
```bash
# Features:
- Local development server
- Debug mode enabled
- No SSL/production optimizations
- Direct bench commands

# Usage:
bench start                    # Start development server
bench --site sitename serve    # Serve specific site
```

#### Production Environment
```bash
# Features:
- Supervisor process management
- Nginx reverse proxy
- SSL certificate (Let's Encrypt)
- Optimized file permissions
- Assets caching and compression
- Security headers
```

## 📁 Directory Structure

```
~/frappe_portable/
├── venv/                     # Python virtual environment
├── your-bench-name/
│   ├── apps/                 # Frappe applications
│   │   ├── frappe/           # Core Frappe framework
│   │   ├── frappe_desk_theme/ # Automated theme installation
│   │   └── your-custom-app/   # Your custom applications
│   ├── sites/                # Site configurations
│   │   ├── assets/           # Static assets (CSS, JS, images)
│   │   └── your-site/        # Individual site data
│   └── config/               # Nginx and Supervisor configs
```

## 🔧 Configuration Details

### MySQL Configuration
- Automated secure installation
- Root password setup
- Database user creation for each site
- Proper charset and collation settings

### Nginx Configuration
```nginx
# Assets serving with proper caching
location /assets {
    alias /path/to/bench/sites/assets;
    expires 1y;
    add_header Cache-Control "public, immutable";
    access_log off;
}

# Security headers
add_header X-Frame-Options "SAMEORIGIN";
add_header X-Content-Type-Options "nosniff";
```

### File Permissions
```bash
# Proper ownership
chown -R user:www-data sites/
chmod -R 755 sites/
find sites/ -type f -exec chmod 644 {} \;
```

## 🎨 Automatic Features

### Frappe Desk Theme
- **Repository**: https://github.com/dhwani-ris/frappe_desk_theme
- **Installation**: Automatic after site creation
- **Features**: Enhanced UI/UX for Frappe

### Custom App Creation
1. **App Generation**: Uses `bench new-app` command
2. **Installation**: Automatically installs on the created site
3. **Git Integration**: 
   - Initializes Git repository
   - Creates initial commit
   - Pushes to remote repository (if provided)

## 🔒 SSL Certificate Setup

### Automatic Let's Encrypt
```bash
# Requirements:
1. Domain pointing to server IP
2. Ports 80 and 443 open
3. Valid DNS resolution

# The script automatically:
- Validates domain DNS
- Installs SSL certificate
- Configures HTTPS redirects
- Updates Nginx configuration
```

## 🐛 Troubleshooting

### Common Issues

#### 1. Assets 404 Error
```bash
# The script automatically fixes this by:
- Setting correct nginx alias path
- Proper file permissions
- Building assets after installation
```

#### 2. MySQL Connection Issues
```bash
# Ensure MySQL is running
sudo systemctl status mariadb

# Reset MySQL password if needed
sudo mysql_secure_installation
```

#### 3. Permission Denied Errors
```bash
# Fix file permissions
sudo chown -R $USER:www-data ~/frappe_portable/
chmod -R 755 ~/frappe_portable/
```

#### 4. Nginx Configuration Error
```bash
# Test nginx config
sudo nginx -t

# Check error logs
sudo tail -f /var/log/nginx/error.log
```

#### 5. Too Many Redirects (SSL Issue)
```bash
# Check site configuration
bench --site sitename set-config force_https 1

# Clear cache
bench clear-cache
bench clear-website-cache
```

### Log Locations
```bash
# Nginx logs
/var/log/nginx/access.log
/var/log/nginx/error.log

# Supervisor logs
/var/log/supervisor/

# Frappe logs
~/frappe_portable/bench-name/logs/
```

## 📚 Useful Commands

### Bench Management
```bash
# Activate virtual environment
source ~/frappe_portable/venv/bin/activate

# Navigate to bench
cd ~/frappe_portable/your-bench-name

# Site operations
bench new-site sitename
bench drop-site sitename
bench backup --site sitename
bench restore backup_file --site sitename

# App operations
bench get-app app_repo_url
bench install-app appname --site sitename
bench uninstall-app appname --site sitename

# Updates
bench update --reset
bench migrate

# Production management
sudo supervisorctl restart all
sudo systemctl reload nginx
```

### Development Commands
```bash
# Start development server
bench start

# Enable developer mode
bench set-config developer_mode 1
bench clear-cache

# Watch for changes
bench watch
```

## 🔧 Advanced Configuration

### Custom Domain Setup
```bash
# Add custom domain
bench setup add-domain --site sitename custom-domain.com

# Update site config
bench config dns_multitenant on
```

### Backup Automation
```bash
# Setup automated backups
bench setup backup-cron --site sitename
```

### Performance Optimization
```bash
# Enable production optimizations
bench setup production
bench config set-common-config enable_scheduler 1
```

## 🤝 Contributing

Feel free to submit issues and enhancement requests!

## 📄 License

This script is provided as-is under the MIT License.

---

**Powered by Dhwani RIS**

#!/bin/bash

set -e

cecho() { echo -e "\e[1;32m$1\e[0m"; }
cwarning() { echo -e "\e[1;33m$1\e[0m"; }
cerror() { echo -e "\e[1;31m$1\e[0m"; }

FRAPPE_HOME="$HOME/frappe_portable"
VENV_DIR="$FRAPPE_HOME/venv"
DEFAULT_FRAPPE_VERSION="version-15"
DESK_THEME_REPO="https://github.com/dhwani-ris/frappe_desk_theme"

trap 'cerror "\n❌ Error on line $LINENO. Exiting." && exit 1' ERR

prepare_env() {
  mkdir -p "$FRAPPE_HOME"
  cd "$FRAPPE_HOME"
}

complete_setup() {
  cecho "🛠️ Starting Complete System Setup..."

  # Install system dependencies
  SYSTEM_PACKAGES=(
    curl git python3-dev python3-pip python3-setuptools python3-venv
    libffi-dev build-essential redis-server supervisor libmysqlclient-dev
    mariadb-server mariadb-client python3-mysqldb pkg-config default-libmysqlclient-dev 
    gcc nginx certbot python3-certbot-nginx wkhtmltopdf
  )

  for pkg in "${SYSTEM_PACKAGES[@]}"; do
    if dpkg -s "$pkg" &> /dev/null; then
      echo "✅ $pkg already installed"
    else
      echo "📦 Installing $pkg..."
      sudo apt install -y "$pkg"
    fi
  done

  # Install Node.js
  if command -v node &> /dev/null; then
    NODE_VERSION=$(node -v | cut -d. -f1 | sed 's/v//')
    if [[ "$NODE_VERSION" -lt 18 ]]; then
      cecho "🔁 Upgrading Node.js..."
      curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
      sudo apt install -y nodejs
    else
      echo "✅ Node.js $(node -v) already installed"
    fi
  else
    cecho "📦 Installing Node.js..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
    sudo apt install -y nodejs
  fi

  # Install Yarn
  if ! command -v yarn &> /dev/null; then
    cecho "📦 Installing Yarn..."
    sudo corepack enable
    sudo corepack prepare yarn@stable --activate
  fi

  # Setup MySQL
  setup_mysql

  # Setup SSH and Git
  setup_ssh_git

  # Setup Python Virtual Environment
  setup_venv

  cecho "✅ Complete setup finished!"
}

setup_mysql() {
  cecho "🗄️ Setting up MySQL/MariaDB..."
  
  sudo systemctl start mariadb
  sudo systemctl enable mariadb

  if ! sudo mysql -u root -e "SELECT 1;" &> /dev/null; then
    cecho "🔐 Running MySQL secure installation..."
    sudo mysql_secure_installation
  else
    cecho "✅ MySQL already configured"
  fi
}

setup_ssh_git() {
  cecho "🔑 Setting up SSH and Git..."
  
  # SSH setup
  if [[ ! -f "$HOME/.ssh/id_rsa" ]]; then
    ssh-keygen -t rsa -b 4096 -f "$HOME/.ssh/id_rsa" -N ""
    cecho "🔑 Your public SSH key:"
    cat "$HOME/.ssh/id_rsa.pub"
    echo
    cwarning "Please add this key to your Git provider if needed"
  fi

  # Git config
  if ! git config --global user.name &> /dev/null; then
    read -p "Enter your Git username: " GIT_USERNAME
    read -p "Enter your Git email: " GIT_EMAIL
    git config --global user.name "$GIT_USERNAME"
    git config --global user.email "$GIT_EMAIL"
  fi
}

setup_venv() {
  cecho "🐍 Setting up Python Virtual Environment..."

  if [[ ! -d "$VENV_DIR" ]]; then
    python3 -m venv "$VENV_DIR"
  fi

  source "$VENV_DIR/bin/activate"
  pip install --upgrade pip wheel frappe-bench
}

create_bench() {
  cecho "🏗️ Creating Frappe Bench..."
  
  read -p "📁 Enter bench name: " BENCH_NAME
  if [[ -z "$BENCH_NAME" ]]; then
    cerror "❌ Bench name cannot be empty"
    return
  fi

  read -p "🌿 Enter Frappe version [${DEFAULT_FRAPPE_VERSION}]: " FRAPPE_VERSION
  FRAPPE_VERSION=${FRAPPE_VERSION:-$DEFAULT_FRAPPE_VERSION}

  if [[ -d "$FRAPPE_HOME/$BENCH_NAME" ]]; then
    cwarning "⚠️ Bench '$BENCH_NAME' already exists!"
    read -p "Continue anyway? (y/n): " CONTINUE
    [[ "$CONTINUE" != "y" ]] && return
  fi

  cd "$FRAPPE_HOME"
  bench init --frappe-branch "$FRAPPE_VERSION" "$BENCH_NAME"
  cecho "✅ Bench '$BENCH_NAME' created successfully!"
}

create_site() {
  cecho "🌐 Creating Frappe Site..."
  
  read -p "📁 Enter bench name: " BENCH_NAME
  if [[ ! -d "$FRAPPE_HOME/$BENCH_NAME" ]]; then
    cerror "❗ Bench '$BENCH_NAME' not found!"
    return
  fi

  cd "$FRAPPE_HOME/$BENCH_NAME"
  
  read -p "🌐 Enter site name (e.g., site1.local or yourdomain.com): " SITE_NAME
  if [[ -z "$SITE_NAME" ]]; then
    cerror "❌ Site name cannot be empty"
    return
  fi

  # MySQL credentials
  read -p "MySQL root username [root]: " DB_ROOT_USER
  DB_ROOT_USER=${DB_ROOT_USER:-root}
  read -s -p "MySQL root password: " DB_ROOT_PASSWORD
  echo
  read -s -p "Site administrator password: " ADMIN_PASSWORD
  echo

  # Create site
  cecho "🚧 Creating site: $SITE_NAME"
  bench new-site "$SITE_NAME" --db-root-username "$DB_ROOT_USER" --db-root-password "$DB_ROOT_PASSWORD" --admin-password "$ADMIN_PASSWORD"

  # Install desk theme
  cecho "🎨 Installing Frappe Desk Theme..."
  bench get-app "$DESK_THEME_REPO"
  bench --site "$SITE_NAME" install-app frappe_desk_theme

  # Ask for custom app
  read -p "🛠️ Create custom app? (y/n): " CREATE_APP
  if [[ "$CREATE_APP" == "y" ]]; then
    read -p "📝 Enter app name: " APP_NAME
    if [[ -n "$APP_NAME" ]]; then
      bench new-app "$APP_NAME"
      bench --site "$SITE_NAME" install-app "$APP_NAME"
      
      read -p "🔗 Enter Git repo URL for initial commit (optional): " REPO_URL
      if [[ -n "$REPO_URL" ]]; then
        cd "apps/$APP_NAME"
        git add .
        git commit -m "Initial commit"
        git remote add origin "$REPO_URL"
        git push -u origin main
        cd "../.."
      fi
    fi
  fi

  # Ask for environment setup
  echo
  cecho "🚀 Environment Setup:"
  echo "1) Development"
  echo "2) Production"
  read -p "Choose environment [1-2]: " ENV_CHOICE

  case "$ENV_CHOICE" in
    1)
      setup_development "$SITE_NAME"
      ;;
    2)
      setup_production "$BENCH_NAME" "$SITE_NAME"
      ;;
    *)
      cwarning "No environment setup selected"
      ;;
  esac

  cecho "✅ Site '$SITE_NAME' created successfully!"
}

setup_development() {
  local site_name="$1"
  cecho "🛠️ Setting up Development Environment..."
  
  cecho "Development server commands:"
  echo "  bench start                    # Start all services"
  echo "  bench --site $site_name serve  # Serve specific site"
  echo
  
  read -p "🚀 Start development server now? (y/n): " START_DEV
  if [[ "$START_DEV" == "y" ]]; then
    bench start
  fi
}

setup_production() {
  local bench_name="$1"
  local site_name="$2"
  
  cecho "🏭 Setting up Production Environment..."
  
  # Setup supervisor
  cecho "⚙️ Setting up Supervisor..."
  bench setup supervisor --user "$USER"
  sudo ln -sf "$PWD/config/supervisor.conf" "/etc/supervisor/conf.d/${bench_name}.conf"
  sudo supervisorctl reread
  sudo supervisorctl update

  # Setup nginx
  cecho "🌐 Setting up Nginx..."
  bench setup nginx
  
  # Fix assets path and permissions
  cecho "🔧 Configuring assets and permissions..."
  
  # Update nginx config for proper assets serving
  sed -i "s|location /assets {[^}]*}|location /assets {\n    alias $PWD/sites/assets;\n    try_files \$uri \$uri/ =404;\n    expires 1y;\n    add_header Cache-Control \"public, immutable\";\n    access_log off;\n}|" config/nginx.conf
  
  # Fix access_log format issue - remove 'main' if present
  sed -i 's|access_log  /var/log/nginx/access.log main;|access_log  /var/log/nginx/access.log;|' config/nginx.conf
  
  # Set proper file permissions
  sudo chown -R "$USER:$USER" "$PWD/sites/assets"
  sudo chmod -R 755 "$PWD/sites/assets"
  find "$PWD/sites/assets" -type f -exec chmod 644 {} \;
  
  # Create assets directory if it doesn't exist
  mkdir -p "$PWD/sites/assets"
  
  # Generate assets
  bench build --app frappe
  bench --site $site_name clear-cache
  bench --site $site_name clear-website-cache

  sudo ln -sf "$PWD/config/nginx.conf" "/etc/nginx/conf.d/${bench_name}.conf"

  # Test nginx config
  if sudo nginx -t; then
    sudo systemctl reload nginx
    cecho "✅ Nginx configured successfully"
  else
    cerror "❌ Nginx configuration error"
    return
  fi

  # Setup SSL
  read -p "🔐 Setup SSL certificate? (y/n): " SETUP_SSL
  if [[ "$SETUP_SSL" == "y" ]]; then
    read -p "🌐 Enter domain name: " DOMAIN
    if [[ -n "$DOMAIN" ]]; then
      # Check if domain resolves
      if host "$DOMAIN" &> /dev/null; then
        cecho "🔒 Setting up SSL certificate for $DOMAIN..."
        sudo certbot --nginx -d "$DOMAIN"
        
        # Update site config for HTTPS
        bench config dns_multitenant on
        bench setup add-domain --site "$site_name" "$DOMAIN"
        
        cecho "✅ SSL certificate configured!"
      else
        cwarning "⚠️ Domain $DOMAIN does not resolve. Please configure DNS first."
      fi
    fi
  fi

  # Final permissions fix
  sudo chown -R "$USER:www-data" "$PWD/sites"
  sudo chmod -R 755 "$PWD/sites"

  cecho "🎉 Production environment setup complete!"
  echo
  cecho "📋 Production URLs:"
  echo "  HTTP:  http://$site_name"
  [[ -n "$DOMAIN" ]] && echo "  HTTPS: https://$DOMAIN"
  echo
  cecho "🔧 Management commands:"
  echo "  sudo supervisorctl restart all    # Restart services"
  echo "  sudo systemctl reload nginx      # Reload nginx"
  echo "  bench migrate                     # Run migrations"
}

main_menu() {
  while true; do
    cecho "\n==================================================="
    cecho "🚀 Frappe Setup Wizard"
    cecho "==================================================="
    echo "1) Complete Setup (System Dependencies + MySQL + SSH/Git)"
    echo "2) Create Bench"
    echo "3) Create Site"
    echo "4) Exit"
    read -p "Choose option [1-4]: " CHOICE

    case "$CHOICE" in
      1)
        complete_setup
        ;;
      2)
        create_bench
        ;;
      3)
        create_site
        ;;
      4)
        echo
        cecho "👋 Thanks for using Frappe Setup Wizard!"
        exit 0
        ;;
      *)
        cerror "❗ Invalid option. Please try again."
        ;;
    esac
  done
}

# === EXECUTION START ===
cecho "🚀 Frappe Setup Wizard"

# Check if not running as root
if [[ $EUID -eq 0 ]]; then
   cerror "❌ Don't run this script as root"
   exit 1
fi

# Activate virtual environment if exists
if [[ -z "$VIRTUAL_ENV" ]] && [[ -d "$VENV_DIR" ]]; then
    source "$VENV_DIR/bin/activate"
fi

prepare_env
main_menu

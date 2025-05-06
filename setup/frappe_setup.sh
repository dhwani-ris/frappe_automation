#!/bin/bash

set -e

cecho() { echo -e "\e[1;32m$1\e[0m"; }

FRAPPE_HOME="$HOME/frappe_portable"
VENV_DIR="$FRAPPE_HOME/venv"
DEFAULT_BENCH_DIR="frappe-bench"
MGRANT_BENCH_DIR="mgrant-bench"
DEFAULT_FRAPPE_VERSION="version-15"

trap 'echo -e "\e[1;31m\n❌ Error on line $LINENO. Exiting.\e[0m" && exit 1' ERR

prepare_env() {
  mkdir -p "$FRAPPE_HOME"
  cd "$FRAPPE_HOME"
}

install_deps() {
  cecho "🛠️ Checking and installing dependencies..."

  SYSTEM_PACKAGES=(
    curl git python3-dev python3-pip python3-setuptools python3-venv
    libffi-dev build-essential redis-server supervisor libmysqlclient-dev
    mariadb-server mariadb-client python3-mysqldb pkg-config default-libmysqlclient-dev gcc nginx certbot python3-certbot-nginx
  )

  for pkg in "${SYSTEM_PACKAGES[@]}"; do
    if dpkg -s "$pkg" &> /dev/null; then
      echo "✅ $pkg already installed"
    else
      echo "📦 Installing $pkg..."
      sudo apt install -y "$pkg"
    fi
  done

  if command -v node &> /dev/null; then
    NODE_VERSION=$(node -v | cut -d. -f1 | sed 's/v//')
    if [[ "$NODE_VERSION" -lt 18 ]]; then
      cecho "🔁 Node.js version < 18, upgrading..."
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

  if command -v yarn &> /dev/null; then
    echo "✅ Yarn $(yarn --version) already installed"
  else
    cecho "📦 Installing Yarn via Corepack..."
    sudo corepack enable
    sudo corepack prepare yarn@stable --activate
  fi
}

setup_venv() {
  cecho "🐍 Setting up Python Virtual Environment..."

  if [[ -d "$VENV_DIR" ]]; then
    cecho "✅ Virtual environment already exists. Skipping creation."
  else
    python3 -m venv "$VENV_DIR"
  fi

  source "$VENV_DIR/bin/activate"

  pip show pip &> /dev/null || python -m ensurepip
  pip show wheel &> /dev/null || pip install wheel
  pip show frappe-bench &> /dev/null || pip install frappe-bench
}

init_bench() {
  read -p "📁 Enter bench directory name: " BENCH_DIR
  BENCH_DIR=${BENCH_DIR:-$DEFAULT_BENCH_DIR}
  
  read -p "🌿 Enter Frappe version [${DEFAULT_FRAPPE_VERSION}]: " FRAPPE_VERSION
  FRAPPE_VERSION=${FRAPPE_VERSION:-$DEFAULT_FRAPPE_VERSION}

  cecho "🚧 Initializing Bench: $BENCH_DIR with $FRAPPE_VERSION"
  bench init --frappe-branch "$FRAPPE_VERSION" "$BENCH_DIR"
  cd "$BENCH_DIR"

  read -p "➕ Do you want to install additional apps now? (y/n): " GET_APP_CHOICE
  [[ "$GET_APP_CHOICE" == "y" ]] && install_apps
}

setup_site() {
  read -p "📁 Enter bench directory name: " BENCH_DIR
  BENCH_DIR=${BENCH_DIR:-$DEFAULT_BENCH_DIR}
  
  if [[ ! -d "$FRAPPE_HOME/$BENCH_DIR" ]]; then
    cecho "❗ Bench directory '$BENCH_DIR' not found!"
    read -p "Do you want to create it now? (y/n): " CREATE_BENCH
    if [[ "$CREATE_BENCH" == "y" ]]; then
      init_bench "$BENCH_DIR"
    else
      return
    fi
  fi

  cd "$FRAPPE_HOME/$BENCH_DIR" || exit
  read -p "🌐 Enter site name (e.g., site1.local): " SITE_NAME
  bench new-site "$SITE_NAME"
}

install_apps() {
  while true; do
    read -p "➕ Do you want to install another app? If yes, enter Git/Bitbucket repo URL (or type 'done' to skip): " APP_URL
    [[ "$APP_URL" == "done" ]] && break

    read -p "🌿 Enter branch to use [${DEFAULT_FRAPPE_VERSION}]: " APP_BRANCH
    APP_BRANCH=${APP_BRANCH:-$DEFAULT_FRAPPE_VERSION}

    APP_NAME=$(basename "$APP_URL" .git)

    read -p "➡️ Fetch app '$APP_NAME' from branch '$APP_BRANCH'? (y/n): " CONFIRM_GET
    [[ "$CONFIRM_GET" != "y" ]] && continue

    bench get-app --branch "$APP_BRANCH" "$APP_URL"

    read -p "📍 Install '$APP_NAME' on which site?: " APP_SITE
    read -p "✅ Proceed to install '$APP_NAME' on '$APP_SITE'? (y/n): " CONFIRM_INSTALL
    [[ "$CONFIRM_INSTALL" != "y" ]] && continue

    bench --site "$APP_SITE" install-app "$APP_NAME"
    echo "✔️ $APP_NAME installed successfully on $APP_SITE"
  done
}

setup_production() {
  cecho "\nProduction Setup Options:"
  echo "1) Setup All (Supervisor + Nginx + SSL)"
  echo "2) Setup SSL Only"
  read -p "Choose an option [1-2]: " PROD_CHOICE

  read -p "📁 Enter the bench directory to configure for production: " PROD_BENCH
  if [[ ! -d "$FRAPPE_HOME/$PROD_BENCH" ]]; then
    cecho "❗ Bench directory '$PROD_BENCH' not found!"
    return
  fi

  cd "$FRAPPE_HOME/$PROD_BENCH" || return

  case "$PROD_CHOICE" in
    1)
      cecho "🔧 Setting up Supervisor and Nginx for $PROD_BENCH..."
      
      # Setup Supervisor
      if [[ -f "config/supervisor.conf" ]]; then
        read -p "supervisor.conf already exists and this will overwrite it. Do you want to continue? [y/N]: " OVERWRITE
        [[ "$OVERWRITE" != "y" ]] && return
      fi
      bench setup supervisor --user "$USER"
      sudo ln -sf "$PWD/config/supervisor.conf" /etc/supervisor/conf.d/${PROD_BENCH}.conf

      # Setup Nginx
      if [[ -f "config/nginx.conf" ]]; then
        read -p "nginx.conf already exists and this will overwrite it. Do you want to continue? [y/N]: " OVERWRITE
        [[ "$OVERWRITE" != "y" ]] && return
      fi
      bench setup nginx

      # Replace nginx.conf with updated asset location block and access log config
      sed -i 's|location /assets {[^}]*}|location /assets {\n    alias /home/frappe/frappe-bench/sites/assets;\n    try_files $uri $uri/ =404;\n    allow all;\n    add_header X-Debug-Path $request_filename;\n    add_header Cache-Control \"max-age=31536000\";\n}|' config/nginx.conf
      sed -i 's|access_log  /var/log/nginx/access.log main;|access_log  /var/log/nginx/access.log;|' config/nginx.conf

      sudo ln -sf "$PWD/config/nginx.conf" /etc/nginx/conf.d/${PROD_BENCH}.conf

      sudo supervisorctl reread
      sudo supervisorctl update
      sudo systemctl reload nginx

      echo "ℹ️  Note: Ensure your domain is mapped correctly to this server's public IP address."
      ;;
    2)
      echo "ℹ️  Skipping Supervisor and Nginx setup..."
      ;;
    *)
      cecho "❗ Invalid option selected"
      return
      ;;
  esac

  # SSL Setup (common for both options)
  read -p "🌐 Do you want to configure SSL with certbot for a site? (y/n): " SSL_CHOICE
  if [[ "$SSL_CHOICE" == "y" ]]; then
    read -p "🔐 Enter the domain name configured in nginx: " DOMAIN
    cecho "🔍 Checking domain mapping..."
    if ! host "$DOMAIN" &> /dev/null; then
      cecho "❌ Error: Could not resolve IP for domain $DOMAIN"
      cecho "Please ensure your domain's DNS records are properly configured."
      return
    fi
    sudo certbot --nginx -d "$DOMAIN"
  fi
}

setup_ssh() {
  cecho "🔑 Setting up SSH for private repositories..."
  
  # Check if SSH key already exists
  if [[ -f "$HOME/.ssh/id_rsa" ]]; then
    read -p "SSH key already exists. Do you want to overwrite? (y/n): " OVERWRITE
    if [[ "$OVERWRITE" != "y" ]]; then
      echo "Skipping SSH key generation..."
      return
    fi
  fi

  # Generate SSH key
  ssh-keygen -t rsa -b 4096 -f "$HOME/.ssh/id_rsa" -N ""
  
  # Display public key
  cecho "Your public SSH key:"
  cat "$HOME/.ssh/id_rsa.pub"
  echo -e "\nPlease add this key to your Git provider (GitHub/GitLab/Bitbucket)"
}

setup_git_config() {
  cecho "⚙️ Setting up Git configuration..."
  
  # Check if git config exists
  if git config --global user.name &> /dev/null; then
    read -p "Git global config exists. Do you want to overwrite? (y/n): " OVERWRITE
    if [[ "$OVERWRITE" != "y" ]]; then
      echo "Skipping Git config..."
      return
    fi
  fi

  # Get user input for Git config
  read -p "Enter your Git username: " GIT_USERNAME
  read -p "Enter your Git email: " GIT_EMAIL

  # Set global Git config
  git config --global user.name "$GIT_USERNAME"
  git config --global user.email "$GIT_EMAIL"

  # Set bench-specific Git config if in a bench directory
  if [[ -d ".git" ]]; then
    read -p "Do you want to set bench-specific Git config? (y/n): " BENCH_CONFIG
    if [[ "$BENCH_CONFIG" == "y" ]]; then
      read -p "Enter bench-specific Git username (press Enter to skip): " BENCH_USERNAME
      read -p "Enter bench-specific Git email (press Enter to skip): " BENCH_EMAIL
      
      [[ -n "$BENCH_USERNAME" ]] && git config user.name "$BENCH_USERNAME"
      [[ -n "$BENCH_EMAIL" ]] && git config user.email "$BENCH_EMAIL"
    fi
  fi

  cecho "✅ Git configuration completed"
}

main_menu() {
  while true; do
    cecho "\n==================================================="
    cecho "🔧 Welcome to Frappe Setup Wizard"
    cecho "==================================================="
    echo "1) Setup SSH and Git Configuration"
    echo "2) Setup Site"
    echo "3) Setup Default Frappe Bench"
    echo "4) Setup mGrant Bench"
    echo "5) Setup mGrant Site"
    echo "6) Only Get App"
    echo "7) Setup Production (Supervisor + Nginx + SSL)"
    echo "8) Exit"
    read -p "Choose an option [1-8]: " CHOICE

    case "$CHOICE" in
      1)
        setup_ssh
        setup_git_config
        ;;
      2)
        setup_site
        ;;
      3)
        init_bench "$DEFAULT_BENCH_DIR"
        ;;
      4)
        init_bench "$MGRANT_BENCH_DIR"
        ;;
      5)
        cd "$FRAPPE_HOME/$MGRANT_BENCH_DIR" || { 
          cecho "❗ mGrant bench directory not found!"
          read -p "Do you want to create it now? (y/n): " CREATE_MGRANT
          if [[ "$CREATE_MGRANT" == "y" ]]; then
            init_bench "$MGRANT_BENCH_DIR"
          else
            continue
          fi
        }
        setup_site
        ;;
      6)
        read -p "📁 Enter the bench directory to install apps into: " TARGET_BENCH
        if [[ ! -d "$FRAPPE_HOME/$TARGET_BENCH" ]]; then
          cecho "❗ Bench directory '$TARGET_BENCH' not found!"
          continue
        fi
        cd "$FRAPPE_HOME/$TARGET_BENCH" || continue
        install_apps
        ;;
      7)
        setup_production
        ;;
      8)
        echo -e "\n\e[1;34m───────────────────────────────────────────────"
        echo -e "  🔷 Powered by Dhwani RIS"
        echo -e "  👨‍💻 Made with ❤️ by Ankit Jangir"
        echo -e "  💡 Inspired by Amresh Yadav"
        echo -e "───────────────────────────────────────────────\e[0m"
        exit 0
        ;;
      *)
        echo "❗ Invalid option. Please try again."
        ;;
    esac
  done
}

# === EXECUTION START ===
prepare_env
install_deps
setup_venv
main_menu
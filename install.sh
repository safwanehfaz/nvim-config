#!/bin/bash
set -e

# --- [ Configuration ] ---
REPO_URL="https://raw.githubusercontent.com/safwanehfaz/nvim-config/main/nvim_version.txt"
CONFIG_REPO="https://github.com/safwanehfaz/nvim-config.git"
ARCH=$(uname -m)

# --- [ Pre-flight Checks ] ---

check_internet() {
    echo "Checking internet connection..."
    if ! curl -s --head --request GET https://www.github.com > /dev/null; then
        echo "Error: No internet connection."
        exit 1
    fi
}

validate_sudo() {
    echo "Requesting sudo privileges for installation..."
    sudo -v
    # Keep sudo alive in background
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
}

# --- [ Logic Functions ] ---

setup_config() {
    if [ -d "$HOME/.config/nvim" ]; then
        cd "$HOME/.config/nvim"
        
        # Check if there are any local changes (uncommitted or untracked)
        if [ -d ".git" ]; then
            CHANGES=$(git status --porcelain)
            if [ -z "$CHANGES" ]; then
                echo "No local changes detected in config. Skipping backup..."
                # Just pull the latest if no changes
                git pull origin main || true
                return 0
            fi
        fi
        
        # If changes exist or not a git repo, proceed with backup
        read -p "Local changes detected in config. Backup and install new? (y/n): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            local timestamp=$(date +%Y%m%d_%H%M%S)
            mv "$HOME/.config/nvim" "$HOME/.config/nvim_backup_$timestamp"
            echo "Backup created: nvim_backup_$timestamp"
            git clone "$CONFIG_REPO" "$HOME/.config/nvim"
        fi
    else
        # Fresh install
        git clone "$CONFIG_REPO" "$HOME/.config/nvim"
    fi
}

get_download_link() {
    local choice=$1
    if [ "$ARCH" = "x86_64" ]; then
        [ "$choice" = "appimage" ] && echo "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.appimage"
        [ "$choice" = "tarball" ] && echo "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz"
    elif [ "$ARCH" = "aarch64" ]; then
        [ "$choice" = "appimage" ] && echo "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-arm64.appimage"
        [ "$choice" = "tarball" ] && echo "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-arm64.tar.gz"
    fi
}

check_dependencies() {
    local deps=("curl" "tar" "git")
    local missing=()
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then missing+=("$dep"); fi
    done
    if [ "$WISHED_VERSION" = "appimage" ]; then
        if ! dpkg -s libfuse2t64 &> /dev/null && ! dpkg -s libfuse2 &> /dev/null; then missing+=("libfuse2t64"); fi
    fi
    [ ${#missing[@]} -ne 0 ] && sudo apt update && sudo apt install -y "${missing[@]}"
}

clean_old_installations() {
    local paths=("/usr/bin/nvim" "/usr/local/bin/nvim" "/opt/nvim")
    for path in "${paths[@]}"; do
        if [ -e "$path" ]; then
            read -p "Found $path. Remove it? (y/n): " confirm
            [[ "$confirm" =~ ^[Yy]$ ]] && sudo rm -rf "$path"
        fi
    done
}

check_wished_version() {
    local attempt=1
    while [ $attempt -le 3 ]; do
        read -p "Install as Tarball [T] or AppImage [A]? " input
        case "${input,,}" in
            t) WISHED_VERSION="tarball"; return 0 ;;
            a) WISHED_VERSION="appimage"; return 0 ;;
            *) echo "Invalid input ($attempt/3)"; ((attempt++)) ;;
        esac
    done
    exit 1
}

# --- [ Execution Flow ] ---

check_internet
validate_sudo

LATEST_VERSION=$(curl -s "$REPO_URL")
if command -v nvim &> /dev/null; then
    CURRENT_VERSION=$(nvim --version | head -n 1 | grep -o 'v[0-9.]*')
else
    CURRENT_VERSION="none"
fi

echo "Latest: $LATEST_VERSION | Current: $CURRENT_VERSION"

if [ "$CURRENT_VERSION" != "$LATEST_VERSION" ]; then
    check_wished_version
    check_dependencies
    clean_old_installations
    
    LINK=$(get_download_link "$WISHED_VERSION")
    echo "Downloading Neovim..."
    curl -LO "$LINK"

    if [ "$WISHED_VERSION" = "appimage" ]; then
        chmod +x nvim-linux-*.appimage
        sudo mv nvim-linux-*.appimage /usr/local/bin/nvim
    else
        tar -xzf nvim-linux-*.tar.gz
        sudo rm -rf /opt/nvim && sudo mv nvim-linux-* /opt/nvim
        sudo ln -sf /opt/nvim/bin/nvim /usr/local/bin/nvim
    fi
fi

setup_config
echo "Operation completed successfully!"
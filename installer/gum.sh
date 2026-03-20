#!/usr/bin/env bash
# installer/gum.sh — Detect and install gum (minimum version 0.14)
# Bash 3.2+ compatible

GUM_MIN_MAJOR=0
GUM_MIN_MINOR=14

# gum_detect — returns 0 if gum >= 0.14 is installed, 1 otherwise
gum_detect() {
  if ! command -v gum >/dev/null 2>&1; then
    return 1
  fi

  local version_output
  version_output=$(gum --version 2>/dev/null || echo "")
  # Expected format: "gum version 0.14.0 (...)"
  local version_str
  version_str=$(echo "$version_output" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)

  if [ -z "$version_str" ]; then
    return 1
  fi

  local major minor
  major=$(echo "$version_str" | cut -d. -f1)
  minor=$(echo "$version_str" | cut -d. -f2)

  if [ "$major" -gt "$GUM_MIN_MAJOR" ]; then
    return 0
  elif [ "$major" -eq "$GUM_MIN_MAJOR" ] && [ "$minor" -ge "$GUM_MIN_MINOR" ]; then
    return 0
  else
    return 1
  fi
}

# gum_install — offers to install gum via brew, apt, or binary download
gum_install() {
  echo ""
  echo "gum >= 0.${GUM_MIN_MINOR} is required for this installer."
  echo ""
  echo "Installation options:"

  local install_method=""

  if command -v brew >/dev/null 2>&1; then
    echo "  1) Homebrew:  brew install charmbracelet/tap/gum"
    install_method="brew"
  fi

  if command -v apt-get >/dev/null 2>&1; then
    echo "  2) apt (Debian/Ubuntu)"
    if [ -z "$install_method" ]; then
      install_method="apt"
    fi
  fi

  echo "  3) Download binary from GitHub releases"
  if [ -z "$install_method" ]; then
    install_method="binary"
  fi

  echo ""
  printf "Install gum now? [y/N] "
  read -r confirm
  if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "Skipping gum installation."
    return 1
  fi

  # Try brew first, then apt, then binary
  if command -v brew >/dev/null 2>&1; then
    echo "Installing via Homebrew..."
    brew install charmbracelet/tap/gum
    return $?
  elif command -v apt-get >/dev/null 2>&1; then
    echo "Installing via apt..."
    # Add charm repo
    if command -v gpg >/dev/null 2>&1 && command -v curl >/dev/null 2>&1; then
      curl -fsSL https://repo.charm.sh/apt/gpg.key | gpg --dearmor -o /usr/share/keyrings/charm.gpg 2>/dev/null || true
      echo "deb [signed-by=/usr/share/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | \
        tee /etc/apt/sources.list.d/charm.list >/dev/null 2>&1 || true
      apt-get update -qq >/dev/null 2>&1 || true
      apt-get install -y gum 2>/dev/null
      return $?
    fi
  fi

  # Binary download fallback
  echo "Downloading gum binary from GitHub releases..."
  local os arch download_url tmpdir
  os=$(uname -s | tr '[:upper:]' '[:lower:]')
  arch=$(uname -m)
  case "$arch" in
    x86_64)  arch="x86_64" ;;
    aarch64|arm64) arch="arm64" ;;
    *)
      echo "Unsupported architecture: $arch"
      return 1
      ;;
  esac

  local version="0.14.5"
  local os_cap
  os_cap=$(echo "$os" | sed 's/./\u&/') 2>/dev/null || os_cap=$(echo "$os" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')

  download_url="https://github.com/charmbracelet/gum/releases/download/v${version}/gum_${version}_${os_cap}_${arch}.tar.gz"

  tmpdir=$(mktemp -d)
  if curl -fsSL "$download_url" -o "${tmpdir}/gum.tar.gz" 2>/dev/null; then
    tar -xzf "${tmpdir}/gum.tar.gz" -C "$tmpdir" 2>/dev/null
    local gum_bin
    gum_bin=$(find "$tmpdir" -name "gum" -type f | head -1)
    if [ -n "$gum_bin" ]; then
      local install_dir="/usr/local/bin"
      if [ ! -w "$install_dir" ]; then
        install_dir="$HOME/.local/bin"
        mkdir -p "$install_dir"
      fi
      cp "$gum_bin" "${install_dir}/gum"
      chmod +x "${install_dir}/gum"
      rm -rf "$tmpdir"
      echo "gum installed to ${install_dir}/gum"
      return 0
    fi
  fi
  rm -rf "$tmpdir"
  echo "Binary download failed."
  return 1
}

# gum_ensure — ensures gum is available, exits if it can't be installed
gum_ensure() {
  if gum_detect; then
    return 0
  fi

  if gum_install; then
    if gum_detect; then
      return 0
    fi
  fi

  echo "ERROR: gum >= 0.${GUM_MIN_MINOR} is required but could not be installed."
  echo "Please install it manually: https://github.com/charmbracelet/gum#installation"
  exit 1
}

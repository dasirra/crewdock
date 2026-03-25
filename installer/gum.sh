#!/usr/bin/env bash
# installer/gum.sh — Detect and install gum (minimum version 0.14)
# Bash 3.2+ compatible

GUM_MIN_MAJOR=0
GUM_MIN_MINOR=14

# Pinned release — update SHA256 values when bumping version
GUM_PINNED_VERSION="0.17.0"
# SHA256 checksums from https://github.com/charmbracelet/gum/releases/download/v0.17.0/checksums.txt
GUM_SHA256_LINUX_X86_64="69ee169bd6387331928864e94d47ed01ef649fbfe875baed1bbf27b5377a6fdb"
GUM_SHA256_LINUX_ARM64="b0b9ed95cbf7c8b7073f17b9591811f5c001e33c7cfd066ca83ce8a07c576f9c"
GUM_SHA256_DARWIN_ARM64="e2a4b8596efa05821d8c58d0c1afbcd7ad1699ba69c689cc3ff23a4a99c8b237"
GUM_SHA256_DARWIN_X86_64="cd66576aeebe6cd19c771863c7e8d696e0e1d5387d1e7075666baa67c2052e53"

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

  # Binary download — pinned version with SHA256 verification
  echo "Downloading gum v${GUM_PINNED_VERSION} binary from GitHub releases..."
  local os arch download_url expected_sha256 tmpdir
  os=$(uname -s | tr '[:upper:]' '[:lower:]')
  arch=$(uname -m)

  local os_cap
  os_cap=$(echo "$os" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')

  case "${os}/${arch}" in
    linux/x86_64)       arch="x86_64"; expected_sha256="${GUM_SHA256_LINUX_X86_64}" ;;
    linux/aarch64|\
    linux/arm64)        arch="arm64";  expected_sha256="${GUM_SHA256_LINUX_ARM64}" ;;
    darwin/arm64)       arch="arm64";  expected_sha256="${GUM_SHA256_DARWIN_ARM64}" ;;
    darwin/x86_64)      arch="x86_64"; expected_sha256="${GUM_SHA256_DARWIN_X86_64}" ;;
    *)
      echo "Unsupported platform: ${os}/${arch}"
      return 1
      ;;
  esac

  download_url="https://github.com/charmbracelet/gum/releases/download/v${GUM_PINNED_VERSION}/gum_${GUM_PINNED_VERSION}_${os_cap}_${arch}.tar.gz"

  tmpdir=$(mktemp -d)
  if curl -fsSL "$download_url" -o "${tmpdir}/gum.tar.gz" 2>/dev/null; then
    # Verify SHA256 checksum before extracting
    local actual_sha256
    if command -v sha256sum >/dev/null 2>&1; then
      actual_sha256=$(sha256sum "${tmpdir}/gum.tar.gz" | cut -d' ' -f1)
    elif command -v shasum >/dev/null 2>&1; then
      actual_sha256=$(shasum -a 256 "${tmpdir}/gum.tar.gz" | cut -d' ' -f1)
    else
      echo "ERROR: No sha256sum or shasum found; cannot verify download."
      rm -rf "$tmpdir"
      return 1
    fi
    if [ "$actual_sha256" != "$expected_sha256" ]; then
      echo "ERROR: SHA256 mismatch for gum download."
      echo "  Expected: ${expected_sha256}"
      echo "  Got:      ${actual_sha256}"
      rm -rf "$tmpdir"
      return 1
    fi

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

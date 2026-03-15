#!/bin/bash -e
# ─────────────────────────────────────────────────────────────────────────────
# install-tools.sh — Install all security tools for the Osmedeus AI scanner
#
# This script is COPY'd into the Docker image and RUN during build.
# It is idempotent: safe to run multiple times without side effects.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Helpers ──────────────────────────────────────────────────────────────────

log()  { printf '\n\033[1;34m[+] %s\033[0m\n' "$*"; }
ok()   { printf '    \033[0;32m✓ %s\033[0m\n' "$*"; }
skip() { printf '    \033[0;33m⊘ %s (already installed)\033[0m\n' "$*"; }

command_exists() { command -v "$1" &>/dev/null; }

# ── Go tools ─────────────────────────────────────────────────────────────────

GO_TOOLS=(
    "github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"
    "github.com/projectdiscovery/httpx/cmd/httpx@latest"
    "github.com/projectdiscovery/dnsx/cmd/dnsx@latest"
    "github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest"
    "github.com/projectdiscovery/naabu/v2/cmd/naabu@latest"
    "github.com/owasp-amass/amass/v4/...@master"
    "github.com/ffuf/ffuf/v2@latest"
    "github.com/tomnomnom/waybackurls@latest"
    "github.com/tomnomnom/httprobe@latest"
    "github.com/lc/gau/v2/cmd/gau@latest"
)

install_go_tools() {
    log "Installing Go-based security tools"

    if ! command_exists go; then
        echo "ERROR: go is not installed — cannot install Go tools" >&2
        exit 1
    fi

    for pkg in "${GO_TOOLS[@]}"; do
        # Derive binary name from the package path (last path segment before @)
        bin_name=$(echo "$pkg" | sed 's/@.*//' | awk -F/ '{print $NF}')

        # amass package path ends with "..." — fix the name
        [[ "$bin_name" == "..." ]] && bin_name="amass"

        if command_exists "$bin_name"; then
            skip "$bin_name"
        else
            printf '    Installing %s … ' "$bin_name"
            go install "$pkg" 2>&1 | tail -1 || true
            ok "$bin_name"
        fi
    done
}

# ── Apt packages ─────────────────────────────────────────────────────────────

APT_PACKAGES=(
    # Scanning / recon
    nmap masscan whatweb nikto sqlmap testssl.sh
    # Headless browser
    chromium
    # Python
    python3 python3-pip python3-venv
    # DNS & network utilities
    dnsutils whois curl wget
    # Development / build
    libpcap-dev git jq ca-certificates
)

install_apt_packages() {
    log "Installing apt packages"

    apt-get update -qq

    local to_install=()
    for pkg in "${APT_PACKAGES[@]}"; do
        if dpkg -s "$pkg" &>/dev/null; then
            skip "$pkg"
        else
            to_install+=("$pkg")
        fi
    done

    if [[ ${#to_install[@]} -gt 0 ]]; then
        # Retry up to 3 times for transient network failures (chromium is large)
        for attempt in 1 2 3; do
            if apt-get install -y --no-install-recommends "${to_install[@]}"; then
                break
            else
                echo "    Attempt $attempt failed, retrying …"
                apt-get update -qq
            fi
        done
        ok "apt packages installed"
    fi

    rm -rf /var/lib/apt/lists/*

    # Ensure python symlink exists
    ln -sf /usr/bin/python3 /usr/bin/python 2>/dev/null || true
}

# ── Pip packages ─────────────────────────────────────────────────────────────

PIP_PACKAGES=(
    sslyze
)

install_pip_packages() {
    log "Installing pip packages"

    for pkg in "${PIP_PACKAGES[@]}"; do
        if python3 -m pip show "$pkg" &>/dev/null 2>&1; then
            skip "$pkg"
        else
            python3 -m pip install --no-cache-dir --break-system-packages "$pkg"
            ok "$pkg"
        fi
    done
}

# ── Main ─────────────────────────────────────────────────────────────────────

main() {
    log "Osmedeus AI scanner — security tool installer"
    echo "    Running as $(whoami) on $(uname -s)/$(uname -m)"

    install_apt_packages
    install_go_tools
    install_pip_packages

    log "All tools installed successfully ✓"
}

main "$@"

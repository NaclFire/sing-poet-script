#!/usr/bin/env bash

set -e
trap 'echo -e "\033[31m[ERROR]\033[0m Failed at line $LINENO"; exit 1' ERR

################################
# BASIC INFO
################################

REPO="NaclFire/sing-poet"
INSTALL_PATH="/usr/local/bin"
CONFIG_DIR="/etc/sing-poet"
SERVICE_NAME="sing-poet"

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

info(){ echo -e "${GREEN}[INFO]${PLAIN} $1"; }
warn(){ echo -e "${YELLOW}[WARN]${PLAIN} $1"; }
err(){ echo -e "${RED}[ERROR]${PLAIN} $1"; exit 1; }

################################
# SYSTEM CHECK
################################

check_root(){
    if [ "$(id -u)" != "0" ]; then
        err "Please run as root"
    fi
}

detect_os(){
    [ -f /etc/os-release ] || err "Unsupported OS"

    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID

    info "OS: $OS $VERSION"
}

install_base(){
    info "Installing dependencies..."

    case "$OS" in
        ubuntu|debian)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update --allow-releaseinfo-change -y
            apt-get install -y curl tar gzip ca-certificates
        ;;
        centos|rocky|almalinux|rhel)
            yum makecache -y || dnf makecache -y
            yum install -y curl tar gzip || \
            dnf install -y curl tar gzip
        ;;
        *)
            err "Unsupported system: $OS"
        ;;
    esac
}

check_systemd(){
    command -v systemctl >/dev/null || err "systemd not found"
}

prepare_env(){
    check_root
    detect_os
    install_base
    check_systemd
}

################################
# ARCH
################################

detect_arch(){

    ARCH=$(uname -m)

    case "$ARCH" in
        x86_64|amd64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        armv7*) ARCH="armv7" ;;
        *) err "Unsupported arch: $ARCH" ;;
    esac

    info "Architecture: $ARCH"
}

################################
# DOWNLOAD RELEASE
################################

get_download_url(){

    info "Fetching latest release..."

    # Get latest tag from GitHub API (similar to XrayR install script)
    TAG=$(curl -Ls "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

    if [ -z "$TAG" ]; then
        err "Failed to detect release version, may be out of GitHub API limit, please try again later"
    fi

    info "Latest release tag: $TAG"

    # Build download URL based on architecture
    case "$ARCH" in
        amd64)
            URL="https://github.com/${REPO}/releases/download/${TAG}/sing-poet-amd64.tar.gz"
            ;;
        arm64)
            URL="https://github.com/${REPO}/releases/download/${TAG}/sing-poet-arm64.tar.gz"
            ;;
        armv7)
            URL="https://github.com/${REPO}/releases/download/${TAG}/sing-poet-armv7.tar.gz"
            ;;
        *)
            err "Unsupported architecture: $ARCH"
            ;;
    esac

    info "Download URL: $URL"
}

download_binary(){

    TMP=$(mktemp -d)
    FILE="$TMP/$(basename "$URL")"

    info "Downloading sing-poet..."
    curl -L --max-time 300 -o "$FILE" "$URL"

    info "Extracting..."
    tar -xf "$FILE" -C "$TMP"

    BIN=$(find "$TMP" -type f -name sing-poet)

    [ -z "$BIN" ] && err "Binary not found"

    install -m 755 "$BIN" ${INSTALL_PATH}/sing-poet

    rm -rf "$TMP"

    info "Binary installed"
}

################################
# CONFIG
################################

install_config(){

    mkdir -p "$CONFIG_DIR"

    CONFIG_REPO="NaclFire/sing-poet-script"
    API="https://api.github.com/repos/${CONFIG_REPO}/contents/config"

    info "Downloading configs..."

    FILES=$(curl -s --max-time 30 "$API" | grep download_url | cut -d '"' -f4)

    for url in $FILES; do
        name=$(basename "$url")

        if [ -f "${CONFIG_DIR}/${name}" ]; then
            warn "$name exists, skip"
            continue
        fi

        curl -L --max-time 30 -o "${CONFIG_DIR}/${name}" "$url"
    done
}

################################
# CONFIGURE
################################

configure(){

    NODETYPE="$1"
    APIHOST="$2"
    APIKEY="$3"
    NODEID="$4"

    [ -z "$NODETYPE" ] && err "Missing nodetype"
    [ -z "$APIHOST" ] && err "Missing apihost"
    [ -z "$APIKEY" ] && err "Missing apikey"
    [ -z "$NODEID" ] && err "Missing nodeid"

    NODETYPE_LOWER=$(echo "$NODETYPE" | tr '[:upper:]' '[:lower:]')

    SRC="${CONFIG_DIR}/server_${NODETYPE_LOWER}.json"
    DST="${CONFIG_DIR}/server.json"

    [ -f "$SRC" ] || err "Node template not found"

    cp -f "$SRC" "$DST"

    PANEL="${CONFIG_DIR}/panel.json"

    sed -i "s/vmess/${NODETYPE_LOWER}/g" "$PANEL"
    sed -i "s|http://localhost:8384|${APIHOST}|g" "$PANEL"
    sed -i "s/your-apikey/${APIKEY}/g" "$PANEL"
    sed -i "s/16/${NODEID}/g" "$PANEL"

    info "Configuration completed"
}

################################
# SERVICE
################################

create_service(){

cat >/etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=sing-poet Service
After=network.target

[Service]
Type=simple
ExecStart=${INSTALL_PATH}/sing-poet run -c ${CONFIG_DIR}/server.json -p ${CONFIG_DIR}/panel.json
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
}

################################
# COMMANDS
################################

install_service(){

    prepare_env
    detect_arch

    get_download_url
    download_binary
    install_config
    configure "$@"
    create_service

    systemctl enable ${SERVICE_NAME}
    # systemctl restart ${SERVICE_NAME}

    info "sing-poet installed successfully"
}

update_service(){

    prepare_env
    detect_arch
    get_download_url
    download_binary

    systemctl restart ${SERVICE_NAME}

    info "Updated successfully"
}

remove_service(){

    systemctl stop ${SERVICE_NAME} || true
    systemctl disable ${SERVICE_NAME} || true

    rm -f /etc/systemd/system/${SERVICE_NAME}.service
    rm -f ${INSTALL_PATH}/sing-poet

    systemctl daemon-reload

    info "Removed successfully"
}

################################
# CLI
################################

case "$1" in
install)
    shift
    install_service "$@"
    ;;
update)
    update_service
    ;;
uninstall)
    remove_service
    ;;
restart)
    systemctl restart ${SERVICE_NAME}
    ;;
status)
    systemctl status ${SERVICE_NAME}
    ;;
log)
    journalctl -u ${SERVICE_NAME} -f
    ;;
*)
echo "Usage:
  $0 install <nodetype> <apihost> <apikey> <nodeid>
  $0 update
  $0 uninstall
  $0 restart
  $0 status
  $0 log"
exit 1
;;
esac
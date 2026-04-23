#!/usr/bin/env bash

set -e

REPO="NaclFire/sing-poet"
INSTALL_PATH="/usr/local/bin"
SERVICE_NAME="sing-poet"

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

info() { echo -e "${GREEN}[INFO]${PLAIN} $1"; }
warn() { echo -e "${YELLOW}[WARN]${PLAIN} $1"; }
err()  { echo -e "${RED}[ERROR]${PLAIN} $1"; }

check_root() {
    [ "$EUID" -ne 0 ] && {
        err "Please run as root"
        exit 1
    }
}

detect_arch() {
    ARCH=$(uname -m)

    case "$ARCH" in
        x86_64|amd64)
            ARCH="amd64"
            ;;
        aarch64|arm64)
            ARCH="arm64"
            ;;
        armv7*)
            ARCH="armv7"
            ;;
        *)
            err "Unsupported arch: $ARCH"
            exit 1
            ;;
    esac

    info "Architecture: $ARCH"
}

get_download_url() {

    API="https://api.github.com/repos/${REPO}/releases/latest"

    info "Fetching latest release info..."

    JSON=$(curl -fsSL "$API")

    URL=$(echo "$JSON" \
        | grep browser_download_url \
        | grep linux \
        | grep "$ARCH" \
        | head -n1 \
        | cut -d '"' -f4)

    [ -z "$URL" ] && {
        err "No release found for arch $ARCH"
        exit 1
    }

    info "Download URL:"
    info "$URL"
}

download_binary() {
    TMP=$(mktemp -d)
    FILE="$TMP/$(basename "$URL")"

    info "Downloading $URL"
    curl -L -o "$FILE" "$URL"

    info "Extracting..."
    tar -xf "$FILE" -C "$TMP"

    BIN=$(find "$TMP" -type f -name "sing-poet")

    install -m 755 "$BIN" "${INSTALL_PATH}/sing-poet"

    rm -rf "$TMP"
}
install_config() {

    CONFIG_DIR="/etc/sing-poet"
    CONFIG_REPO="NaclFire/sing-poet-script"
    CONFIG_PATH="config"

    info "Preparing config directory..."

    mkdir -p "$CONFIG_DIR"

    API="https://api.github.com/repos/${CONFIG_REPO}/contents/${CONFIG_PATH}"

    info "Downloading default configs..."

    FILES=$(curl -s "$API" | grep download_url | cut -d '"' -f4)

    for url in $FILES; do
        name=$(basename "$url")

        # 不覆盖已有配置（非常重要）
        if [ -f "${CONFIG_DIR}/${name}" ]; then
            warn "$name exists, skip"
            continue
        fi

        info "Downloading $name"
        curl -L -o "${CONFIG_DIR}/${name}" "$url"
    done
}
create_service() {
cat >/etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=SING-POET Service
After=network.target nss-lookup.target
Wants=network.target

[Service]
Type=simple
ExecStart=${INSTALL_PATH}/sing-poet run -c /etc/sing-poet/server.json -p /etc/sing-poet/panel.json
Restart=on-failure
RestartSec=30s
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
}
configure_sing_poet() {

    CONFIG_DIR="/etc/sing-poet"

    NODETYPE_LOWER=$(echo "$NODETYPE" | tr '[:upper:]' '[:lower:]')

    SRC_SERVER="${CONFIG_DIR}/server_${NODETYPE_LOWER}.json"
    DST_SERVER="${CONFIG_DIR}/server.json"
    PANEL_FILE="${CONFIG_DIR}/panel.json"

    info "Configuring sing-poet..."

    # ===== 检查 server 模板 =====
    if [ ! -f "$SRC_SERVER" ]; then
        err "Node type config not found: $SRC_SERVER"
        exit 1
    fi

    # ===== 复制 server 配置 =====
    cp -f "$SRC_SERVER" "$DST_SERVER"

    info "Using node type: $NODETYPE"

    # ===== 修改 panel.json =====
    if [ ! -f "$PANEL_FILE" ]; then
        err "panel.json not found"
        exit 1
    fi

    sed -i "s/vmess/${NODETYPE_LOWER}/g" "$PANEL_FILE"
    sed -i "s|http://localhost:8384|${APIHOST}|g" "$PANEL_FILE"
    sed -i "s/your-apikey/${APIKEY}/g" "$PANEL_FILE"
    sed -i "s/16/${NODEID}/g" "$PANEL_FILE"

    info "Configuration completed."
}
install_service() {

    check_root
    detect_arch

    NODETYPE="$2"
    APIHOST="$3"
    APIKEY="$4"
    NODEID="$5"

    [ -z "$NODETYPE" ] && err "Missing nodetype"
    [ -z "$APIHOST" ] && err "Missing apihost"
    [ -z "$APIKEY" ] && err "Missing apikey"
    [ -z "$NODEID" ] && err "Missing nodeid"

    get_download_url
    download_binary
    install_config
    configure_sing_poet
    create_service

    systemctl enable ${SERVICE_NAME}
    systemctl restart ${SERVICE_NAME}

    info "sing-poet installed and started!"
}

update_service() {
    check_root
    detect_arch
    get_download_url
    download_binary

    systemctl restart ${SERVICE_NAME}

    info "sing-poet updated!"
}

remove_service() {
    check_root

    systemctl stop ${SERVICE_NAME} || true
    systemctl disable ${SERVICE_NAME} || true

    rm -f /etc/systemd/system/${SERVICE_NAME}.service
    rm -f ${INSTALL_PATH}/sing-poet

    systemctl daemon-reload

    info "sing-poet removed!"
}

case "$1" in
install)
    install_service
    ;;
update)
    update_service
    ;;
uninstall)
    remove_service
    ;;
*)
    echo "Usage:"
    echo "  $0 install <nodetype> <apihost> <apikey> <nodeid>"
    echo "  $0 update"
    echo "  $0 uninstall"
    exit 1
    ;;
esac
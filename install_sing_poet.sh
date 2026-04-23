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

    URL=$(curl -s "$API" \
      | jq -r ".assets[] | select(.name|test(\"linux.*${ARCH}\")) | .browser_download_url" \
      | head -n1)

    [ -z "$URL" ] && {
        err "No release found for arch $ARCH"
        exit 1
    }
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

install_service() {
    check_root
    detect_arch
    get_download_url
    download_binary
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
    echo "Usage: $0 {install|update|uninstall}"
    exit 1
    ;;
esac
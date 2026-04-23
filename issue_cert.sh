#!/bin/bash

set -e

read -p "请输入你的邮箱: " EMAIL
read -p "请输入你的域名 (例如 example.com): " DOMAIN

if [ -z "$EMAIL" ] || [ -z "$DOMAIN" ]; then
  echo "邮箱和域名不能为空"
  exit 1
fi

echo "=== 1. 安装 acme.sh ==="
curl https://get.acme.sh | sh

source ~/.bashrc || source ~/.zshrc

ACME="$HOME/.acme.sh/acme.sh"

echo "=== 2. 检查是否已注册 ACME 账号 ==="
if $ACME --list-account >/dev/null 2>&1; then
  echo "ACME 账号已存在，跳过注册"
else
  echo "注册 ACME 账号..."
  $ACME --register-account -m "$EMAIL"
fi

echo "=== 3. 申请证书（standalone） ==="
$ACME --issue -d "$DOMAIN" --standalone

echo "=== 4. 创建证书目录 ==="
mkdir -p /etc/sing-poet

echo "=== 5. 安装证书 ==="
$ACME --install-cert -d "$DOMAIN" \
  --key-file /etc/sing-poet/private.key \
  --fullchain-file /etc/sing-poet/cert.crt \
  --reloadcmd "echo 'cert renewed'"

echo "=== 6. 确保自动续期 ==="
$ACME --install-cronjob >/dev/null 2>&1 || true

echo "=== 完成 ==="
echo "证书路径："
echo "/etc/sing-poet/private.key"
echo "/etc/sing-poet/cert.crt"
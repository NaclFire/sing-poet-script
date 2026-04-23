#!/bin/bash

set -e

# 读取域名
read -p "请输入你的域名 (例如 example.com): " DOMAIN

if [ -z "$DOMAIN" ]; then
  echo "域名不能为空"
  exit 1
fi

echo "=== 1. 安装 acme.sh ==="
curl https://get.acme.sh | sh

source ~/.bashrc || source ~/.zshrc

echo "=== 2. 确保 acme.sh 已安装 ==="
~/.acme.sh/acme.sh --version

echo "=== 3. 申请证书（standalone 模式）==="
# standalone 模式需要 80 端口空闲，并且 root 权限
~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone

echo "=== 4. 创建证书目录 ==="
mkdir -p /etc/sing-poet

echo "=== 5. 安装证书 ==="
~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" \
  --key-file /etc/sing-poet/private.key \
  --fullchain-file /etc/sing-poet/cert.crt \
  --reloadcmd "echo 'cert renewed'"

echo "=== 6. 自动续期已由 acme.sh cron 管理 ==="
crontab -l | grep acme.sh || echo "⚠️ 如果没有看到 cron，运行：~/.acme.sh/acme.sh --install-cronjob"

echo "=== 完成 ==="
echo "证书路径："
echo "私钥: /etc/sing-poet/private.key"
echo "证书: /etc/sing-poet/cert.crt"
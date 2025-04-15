#!/bin/bash

set -euo pipefail

echo "====== 🚀 n8n + Traefik 自动部署开始 ======"

# 获取用户输入
read -p "🌐 请输入你的域名（例如 n8n.example.com）: " DOMAIN
read -p "📧 请输入你的邮箱（用于 Let's Encrypt 申请证书）: " EMAIL
read -p "👤 请输入用于登录 n8n 的用户名: " N8N_USER
read -p "🔒 请输入用于登录 n8n 的密码: " N8N_PASS

# 安装 Docker 和 Docker Compose（如未安装）
if ! command -v docker &> /dev/null; then
    echo "🔧 安装 Docker 中..."
    curl -fsSL https://get.docker.com | bash
fi

if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    echo "🔧 安装 Docker Compose..."
    apt-get update
    apt-get install -y docker-compose
fi

# 创建工作目录
mkdir -p ~/n8n-docker && cd ~/n8n-docker

# 创建 Traefik 配置文件夹
mkdir -p traefik

# 写入 Traefik 配置文件
cat <<EOF > traefik/traefik.yml
entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"

providers:
  docker:
    exposedByDefault: false

certificatesResolvers:
  letsencrypt:
    acme:
      email: "$EMAIL"
      storage: /letsencrypt/acme.json
      httpChallenge:
        entryPoint: web
EOF

# 创建 acme.json 并设权限
touch traefik/acme.json
chmod 600 traefik/acme.json

# 创建 n8n 数据目录并修复权限
mkdir -p n8n_data
chown -R 1000:1000 n8n_data
chmod -R 700 n8n_data

# 写入 Docker Compose 配置
cat <<EOF > docker-compose.yml
version: "3.7"

services:
  traefik:
    image: traefik:v2.9
    restart: always
    command:
      - "--api.insecure=true"
      - "--providers.docker=true"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge=true"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web"
      - "--certificatesresolvers.letsencrypt.acme.email=$EMAIL"
      - "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
      - "./traefik/traefik.yml:/traefik.yml:ro"
      - "./traefik/acme.json:/letsencrypt/acme.json"

  n8n:
    image: n8nio/n8n
    restart: always
    environment:
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=$N8N_USER
      - N8N_BASIC_AUTH_PASSWORD=$N8N_PASS
      - N8N_HOST=$DOMAIN
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - NODE_ENV=production
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.n8n.rule=Host(\`$DOMAIN\`)"
      - "traefik.http.routers.n8n.entrypoints=websecure"
      - "traefik.http.routers.n8n.tls.certresolver=letsencrypt"
    volumes:
      - ./n8n_data:/home/node/.n8n
EOF

# 启动服务
echo "🚀 启动 n8n 和 Traefik..."
docker-compose up -d

echo ""
echo "🎉 部署成功！请访问 👉 https://$DOMAIN"
echo "🔐 登录账号: $N8N_USER"
echo "🔑 登录密码: $N8N_PASS"
echo "📁 项目目录：~/n8n-docker"

#!/bin/bash
# F2BHub 在线安装脚本
# curl -sSL https://raw.githubusercontent.com/strobe111/Fail2ban/master/install.sh | bash

set -e

REPO="https://github.com/strobe111/Fail2ban.git"
INSTALL_DIR="/opt/F2BHub"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

echo -e "${CYAN}"
echo "======================================"
echo "   F2BHub 在线安装"
echo "======================================"
echo -e "${NC}"

if [ "$(id -u)" = "0" ]; then
    error "请勿以 root 运行，使用普通用户（脚本内会使用 sudo）"
fi

if [ -d "$INSTALL_DIR" ]; then
    info "$INSTALL_DIR 已存在，正在更新..."
    cd "$INSTALL_DIR"
    git pull
else
    info "克隆仓库到 $INSTALL_DIR ..."
    sudo mkdir -p "$INSTALL_DIR"
    sudo chown "$USER:$USER" "$INSTALL_DIR"
    git clone "$REPO" "$INSTALL_DIR"
fi

cd "$INSTALL_DIR"
chmod +x f2b.sh

info "安装完成！运行管理脚本..."
echo ""
exec ./f2b.sh
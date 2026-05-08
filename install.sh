#!/bin/bash
# F2BHub 一键安装脚本
# curl -sSL https://raw.githubusercontent.com/strobe111/Fail2ban/master/install.sh | bash

set -e

REPO="https://github.com/strobe111/Fail2ban.git"
INSTALL_DIR="/opt/F2BHub"
HUB_PORT=5001

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# Run command directly as root, or via sudo for non-root
as_root() { [ "$(id -u)" = "0" ] && "$@" || sudo "$@"; }

detect_os() {
    if [ -f /etc/debian_version ]; then
        echo "debian"
    elif [ -f /etc/redhat-release ]; then
        echo "rhel"
    else
        echo "unknown"
    fi
}

echo -e "${CYAN}"
echo "======================================"
echo "   F2BHub 一键安装"
echo "======================================"
echo -e "${NC}"

# -------------------------------------------------------
# 1. Detect environment
# -------------------------------------------------------
if [ "$(id -u)" = "0" ]; then
    SUDO=""
    RUN_USER="root"
    info "检测到 root 用户"
else
    SUDO="sudo"
    RUN_USER="$USER"
    info "检测到普通用户: $RUN_USER"
fi

OS=$(detect_os)
info "检测系统: $OS"
[ "$OS" = "unknown" ] && error "不支持的系统，仅支持 Debian/Ubuntu 和 RHEL/CentOS"

# -------------------------------------------------------
# 2. Install dependencies (including git)
# -------------------------------------------------------
info "安装系统依赖..."
if [ "$OS" = "debian" ]; then
    as_root apt-get update -qq
    as_root apt-get install -y -qq git python3 python3-venv python3-pip fail2ban
elif [ "$OS" = "rhel" ]; then
    as_root yum install -y -q git python3 python3-pip fail2ban
    as_root pip3 install --upgrade pip
fi

# -------------------------------------------------------
# 3. Start Fail2ban
# -------------------------------------------------------
info "启动 Fail2ban..."
as_root systemctl enable --now fail2ban
sleep 1
if as_root systemctl is-active --quiet fail2ban; then
    info "Fail2ban 已启动"
else
    warn "Fail2ban 启动失败，请检查: systemctl status fail2ban"
fi

# -------------------------------------------------------
# 4. Clone or update repo
# -------------------------------------------------------
if [ -d "$INSTALL_DIR" ]; then
    info "$INSTALL_DIR 已存在，正在更新..."
    cd "$INSTALL_DIR"
    git pull
else
    info "克隆仓库到 $INSTALL_DIR ..."
    as_root mkdir -p "$INSTALL_DIR"
    if [ -n "$SUDO" ]; then
        as_root chown "$USER:$USER" "$INSTALL_DIR"
    fi
    git clone "$REPO" "$INSTALL_DIR"
fi

cd "$INSTALL_DIR"

# -------------------------------------------------------
# 5. Setup venv and install Python deps
# -------------------------------------------------------
info "部署 F2BHub Web..."
python3 -m venv "$INSTALL_DIR/.venv"
"$INSTALL_DIR/.venv/bin/pip" install -q --upgrade pip
"$INSTALL_DIR/.venv/bin/pip" install -q -r "$INSTALL_DIR/requirements.txt"

"$INSTALL_DIR/.venv/bin/python3" -c "from app import create_app, db; app=create_app(); app.app_context().push(); db.create_all(); print('DB initialized')"
info "数据库已初始化"

# -------------------------------------------------------
# 6. Create systemd service
# -------------------------------------------------------
# Determine service user
if [ "$(id -u)" = "0" ]; then
    if ! id -u f2bhub &>/dev/null; then
        as_root useradd -r -s /usr/sbin/nologin f2bhub
    fi
    SERVICE_USER="f2bhub"
    as_root chown -R f2bhub:f2bhub "$INSTALL_DIR"
    as_root chown -R f2bhub:f2bhub "$INSTALL_DIR/.venv"
else
    SERVICE_USER="$USER"
fi

info "创建 F2BHub 服务..."
as_root tee /etc/systemd/system/f2bhub.service > /dev/null <<EOF
[Unit]
Description=F2BHub Web Dashboard
After=network.target

[Service]
Type=simple
User=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/.venv/bin/python3 $INSTALL_DIR/run.py
Restart=always
RestartSec=5
Environment=FLASK_ENV=production

[Install]
WantedBy=multi-user.target
EOF

as_root systemctl daemon-reload
as_root systemctl enable --now f2bhub
sleep 1
if as_root systemctl is-active --quiet f2bhub; then
    info "F2BHub 服务已启动"
else
    warn "F2BHub 服务启动失败，请检查: systemctl status f2bhub"
fi

# -------------------------------------------------------
# 7. Configure firewall
# -------------------------------------------------------
info "配置防火墙..."
if command -v ufw &>/dev/null; then
    as_root ufw allow $HUB_PORT/tcp &>/dev/null && info "UFW 已放行端口 $HUB_PORT" || warn "UFW 放行失败"
elif command -v firewall-cmd &>/dev/null; then
    as_root firewall-cmd --permanent --add-port=$HUB_PORT/tcp &>/dev/null && \
    as_root firewall-cmd --reload &>/dev/null && info "firewalld 已放行端口 $HUB_PORT" || warn "firewalld 放行失败"
else
    warn "未检测到防火墙，请手动放行端口 $HUB_PORT"
fi

# -------------------------------------------------------
# 8. Done
# -------------------------------------------------------
IP=$(hostname -I 2>/dev/null | awk '{print $1}')
[ -z "$IP" ] && IP="<服务器IP>"

echo ""
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}   F2BHub 安装完成！${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""
info "Web 面板: http://$IP:$HUB_PORT"
info "管理命令: $INSTALL_DIR/f2b.sh"
info "查看状态: systemctl status f2bhub"
echo ""
#!/bin/bash
set -e

# === F2BHub 管理脚本 ===
INSTALL_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV_DIR="$INSTALL_DIR/.venv"
HUB_PORT=5001
F2B_LOG="/var/log/fail2ban.log"
AGENT_SERVICE="f2bhub-agent"
HUB_SERVICE="f2bhub"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

detect_os() {
    if [ -f /etc/debian_version ]; then
        echo "debian"
    elif [ -f /etc/redhat-release ]; then
        echo "rhel"
    else
        echo "unknown"
    fi
}

pkg_install() {
    local os=$(detect_os)
    if [ "$os" = "debian" ]; then
        sudo apt-get update -qq && sudo apt-get install -y -qq "$@"
    elif [ "$os" = "rhel" ]; then
        sudo yum install -y -q "$@"
    else
        error "Unsupported OS. Only Debian/Ubuntu and RHEL/CentOS are supported."
    fi
}

# -------------------------------------------------------
# 1. Install F2BHub
# -------------------------------------------------------
install_f2bhub() {
    echo ""
    info "===== 安装 F2BHub ====="
    echo ""

    local os=$(detect_os)
    info "检测系统: $os"

    info "安装系统依赖..."
    if [ "$os" = "debian" ]; then
        pkg_install python3 python3-venv python3-pip fail2ban
    elif [ "$os" = "rhel" ]; then
        pkg_install python3 python3-pip fail2ban
        sudo pip3 install --upgrade pip
    fi

    info "启动 Fail2ban..."
    sudo systemctl enable --now fail2ban
    sleep 1
    if sudo systemctl is-active --quiet fail2ban; then
        info "Fail2ban 已启动"
    else
        warn "Fail2ban 启动失败，请检查: systemctl status fail2ban"
    fi

    info "部署 F2BHub Web..."
    python3 -m venv "$VENV_DIR"
    "$VENV_DIR/bin/pip" install -q --upgrade pip
    "$VENV_DIR/bin/pip" install -q -r "$INSTALL_DIR/requirements.txt"

    "$VENV_DIR/bin/python3" -c "from app import create_app, db; app=create_app(); app.app_context().push(); db.create_all(); print('DB initialized')"
    info "数据库已初始化"

    info "创建 F2BHub 服务..."
    sudo tee /etc/systemd/system/$HUB_SERVICE.service > /dev/null <<EOF
[Unit]
Description=F2BHub Web Dashboard
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$INSTALL_DIR
ExecStart=$VENV_DIR/bin/python3 $INSTALL_DIR/run.py
Restart=always
RestartSec=5
Environment=FLASK_ENV=production

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable --now $HUB_SERVICE
    sleep 1
    if sudo systemctl is-active --quiet $HUB_SERVICE; then
        info "F2BHub 服务已启动"
    else
        warn "F2BHub 服务启动失败，请检查: systemctl status $HUB_SERVICE"
    fi

    info "配置防火墙..."
    if command -v ufw &>/dev/null; then
        sudo ufw allow $HUB_PORT/tcp &>/dev/null && info "UFW 已放行端口 $HUB_PORT" || warn "UFW 放行失败"
    elif command -v firewall-cmd &>/dev/null; then
        sudo firewall-cmd --permanent --add-port=$HUB_PORT/tcp &>/dev/null && \
        sudo firewall-cmd --reload &>/dev/null && info "firewalld 已放行端口 $HUB_PORT" || warn "firewalld 放行失败"
    else
        warn "未检测到防火墙，请手动放行端口 $HUB_PORT"
    fi

    local ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    [ -z "$ip" ] && ip="<服务器IP>"
    echo ""
    info "===== 安装完成 ====="
    info "Web 面板: http://$ip:$HUB_PORT"
    info "CLI 查看: sudo fail2ban-client status"
    echo ""
}

# -------------------------------------------------------
# 2. Configure Fail2ban
# -------------------------------------------------------
configure_fail2ban() {
    echo ""
    info "===== 配置 Fail2ban ====="
    echo ""

    if ! command -v fail2ban-client &>/dev/null; then
        error "Fail2ban 未安装，请先执行选项 1"
    fi

    echo "选择要启用的 jail (空格分隔):"
    echo "  1) sshd        (SSH 登录保护)"
    echo "  2) nginx-http  (Nginx HTTP 认证)"
    echo "  3) nginx-botsearch (Nginx 恶意爬虫)"
    echo "  4) postfix     (Postfix 邮件)"
    echo "  5) dovecot     (Dovecot 邮件)"
    echo "  6) recidive    (Fail2ban 重复违规)"
    echo ""
    read -p "输入编号 (默认 1): " JAIL_INPUT
    JAIL_INPUT=${JAIL_INPUT:-1}

    JAILS=""
    for n in $JAIL_INPUT; do
        case $n in
            1) JAILS="$JAILS sshd" ;;
            2) JAILS="$JAILS nginx-http" ;;
            3) JAILS="$JAILS nginx-botsearch" ;;
            4) JAILS="$JAILS postfix" ;;
            5) JAILS="$JAILS dovecot" ;;
            6) JAILS="$JAILS recidive" ;;
            *) warn "忽略未知编号: $n" ;;
        esac
    done

    [ -z "$JAILS" ] && error "未选择任何 jail"

    echo ""
    read -p "bantime  (封禁时长，默认 10m): " BANTIME
    BANTIME=${BANTIME:-10m}
    read -p "findtime (检测窗口，默认 10m): " FINDTIME
    FINDTIME=${FINDTIME:-10m}
    read -p "maxretry (最大重试，默认 5):   " MAXRETRY
    MAXRETRY=${MAXRETRY:-5}

    local jail_file="/etc/fail2ban/jail.local"
    info "写入 $jail_file ..."

    sudo tee "$jail_file" > /dev/null <<EOF
[DEFAULT]
bantime  = $BANTIME
findtime = $FINDTIME
maxretry = $MAXRETRY
backend  = systemd
EOF

    for jail in $JAILS; do
        sudo tee -a "$jail_file" > /dev/null <<EOF

[$jail]
enabled  = true
EOF
    done

    info "重启 Fail2ban..."
    sudo systemctl restart fail2ban
    sleep 1

    echo ""
    info "===== 配置完成 ====="
    info "已启用: $JAILS"
    info "参数: bantime=$BANTIME findtime=$FINDTIME maxretry=$MAXRETRY"
    sudo fail2ban-client status
    echo ""
}

# -------------------------------------------------------
# 3. Generate Agent
# -------------------------------------------------------
generate_agent() {
    echo ""
    info "===== 生成 Fail2ban Agent ====="
    echo ""

    read -p "输入服务器名称 (默认 $(hostname)): " AGENT_HOSTNAME
    AGENT_HOSTNAME=${AGENT_HOSTNAME:-$(hostname)}

    read -p "是否使用本机 Fail2ban 配置？(Y/n): " USE_LOCAL
    USE_LOCAL=${USE_LOCAL,,}
    if [ "$USE_LOCAL" = "n" ]; then
        USE_LOCAL="n"
    else
        USE_LOCAL="y"
    fi

    if ! command -v openssl &>/dev/null; then
        pkg_install openssl
    fi
    API_KEY=$(openssl rand -hex 32)
    info "已生成 API Key"

    if [ -f "$INSTALL_DIR/config.py" ]; then
        sed -i "s/AGENT_API_KEY = .*/AGENT_API_KEY = \"$API_KEY\"/" "$INSTALL_DIR/config.py"
        info "API Key 已写入 F2BHub 配置"
    fi

    local agent_dir="$INSTALL_DIR/agent"
    local hub_url="http://127.0.0.1:$HUB_PORT"
    if [ "$USE_LOCAL" = "n" ]; then
        local ip=$(hostname -I 2>/dev/null | awk '{print $1}')
        [ -z "$ip" ] && ip="<F2BHub服务器IP>"
        hub_url="http://$ip:$HUB_PORT"
    fi

    cat > "$agent_dir/agent.conf" <<EOF
[agent]
hub_url = $hub_url
api_key = $API_KEY
heartbeat_interval = 60

[fail2ban]
log_path = $F2B_LOG
initial_lines = 0
EOF

    if [ "$USE_LOCAL" = "y" ]; then
        info "本机部署 Agent..."
        deploy_local_agent "$agent_dir" "$API_KEY" "$AGENT_HOSTNAME" "$hub_url"
    else
        info "生成远程安装命令..."
        generate_remote_command "$agent_dir" "$API_KEY" "$AGENT_HOSTNAME" "$hub_url"
    fi
}

deploy_local_agent() {
    local agent_dir="$1"
    local api_key="$2"
    local hostname="$3"
    local hub_url="$4"

    local agent_venv="$agent_dir/.venv"
    python3 -m venv "$agent_venv"
    "$agent_venv/bin/pip" install -q requests

    sudo tee /etc/systemd/system/$AGENT_SERVICE.service > /dev/null <<EOF
[Unit]
Description=F2BHub Agent - $hostname
After=network.target fail2ban.service

[Service]
Type=simple
User=$USER
WorkingDirectory=$agent_dir
ExecStart=$agent_venv/bin/python3 $agent_dir/f2b_agent.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable --now $AGENT_SERVICE
    sleep 2

    echo ""
    info "===== Agent 部署完成 ====="
    info "服务器名: $hostname"
    info "Hub: $hub_url"
    if sudo systemctl is-active --quiet $AGENT_SERVICE; then
        info "Agent 运行中"
    else
        warn "Agent 启动失败，请检查: systemctl status $AGENT_SERVICE"
    fi
    echo ""
}

generate_remote_command() {
    local agent_dir="$1"
    local api_key="$2"
    local hostname="$3"
    local hub_url="$4"

    local ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    [ -z "$ip" ] && ip="<F2BHub服务器IP>"

    sudo systemctl restart $HUB_SERVICE 2>/dev/null

    echo ""
    info "===== 远程安装命令 ====="
    echo ""
    echo -e "${CYAN}在远程服务器上执行以下命令一键安装 Fail2ban + Agent:${NC}"
    echo ""
    echo "  curl -sSL http://$ip:$HUB_PORT/api/agent/f2b_agent_install.sh | bash -s -- \\"
    echo "    --hub http://$ip:$HUB_PORT \\"
    echo "    --api-key $api_key \\"
    echo "    --hostname $hostname"
    echo ""
    info "或手动复制 agent/ 目录到远程服务器后运行 f2b_agent_install.sh"
    echo ""
}

# -------------------------------------------------------
# 4. Manage Agent
# -------------------------------------------------------
manage_agent() {
    echo ""
    info "===== 管理 Fail2ban Agent ====="
    echo ""

    if ! sudo systemctl list-unit-files $AGENT_SERVICE.service &>/dev/null; then
        warn "本机未部署 Agent"
    else
        echo "本机 Agent 状态:"
        sudo systemctl status $AGENT_SERVICE --no-pager 2>/dev/null || true
        echo ""
    fi

    if [ -f "$VENV_DIR/bin/python3" ]; then
        echo "已注册的 Agent:"
        "$VENV_DIR/bin/python3" -c "
from app import create_app, db
from app.models import Server
app = create_app()
with app.app_context():
    servers = Server.query.order_by(Server.hostname).all()
    if not servers:
        print('  (无)')
    for s in servers:
        status = '在线' if s.is_online else '离线'
        hb = s.last_heartbeat.strftime('%Y-%m-%d %H:%M') if s.last_heartbeat else '无'
        print(f'  {s.hostname:20s}  {s.ip or \"N/A\":15s}  {status}  心跳: {hb}')
" 2>/dev/null || warn "无法读取 Agent 列表"
    fi

    echo ""
    echo "操作:"
    echo "  1) 重启 Agent"
    echo "  2) 停止 Agent"
    echo "  3) 删除 Agent"
    echo "  0) 返回"
    echo ""
    read -p "选择: " AGENT_OP

    case $AGENT_OP in
        1)
            sudo systemctl restart $AGENT_SERVICE
            info "Agent 已重启"
            ;;
        2)
            sudo systemctl stop $AGENT_SERVICE
            info "Agent 已停止"
            ;;
        3)
            sudo systemctl stop $AGENT_SERVICE 2>/dev/null || true
            sudo systemctl disable $AGENT_SERVICE 2>/dev/null || true
            sudo rm -f /etc/systemd/system/$AGENT_SERVICE.service
            sudo systemctl daemon-reload
            info "Agent 已删除"
            ;;
        *)
            ;;
    esac
    echo ""
}

# -------------------------------------------------------
# 5. Update F2BHub
# -------------------------------------------------------
update_f2bhub() {
    echo ""
    info "===== 更新 F2BHub ====="
    echo ""

    if [ -d "$INSTALL_DIR/.git" ]; then
        info "拉取最新代码..."
        git -C "$INSTALL_DIR" pull
    else
        warn "非 git 仓库，跳过代码更新"
    fi

    info "更新依赖..."
    "$VENV_DIR/bin/pip" install -q --upgrade -r "$INSTALL_DIR/requirements.txt"

    info "重启 F2BHub..."
    sudo systemctl restart $HUB_SERVICE
    sleep 1
    if sudo systemctl is-active --quiet $HUB_SERVICE; then
        info "F2BHub 已更新并启动"
    else
        warn "F2BHub 启动失败，请检查: systemctl status $HUB_SERVICE"
    fi
    echo ""
}

# -------------------------------------------------------
# 6. Uninstall
# -------------------------------------------------------
uninstall() {
    echo ""
    warn "===== 卸载 F2BHub ====="
    echo ""
    read -p "确认卸载 F2BHub？(y/N): " CONFIRM
    CONFIRM=${CONFIRM,,}
    [ "$CONFIRM" != "y" ] && { info "已取消"; return; }

    info "停止服务..."
    sudo systemctl stop $HUB_SERVICE 2>/dev/null || true
    sudo systemctl stop $AGENT_SERVICE 2>/dev/null || true

    info "删除 systemd 服务..."
    sudo systemctl disable $HUB_SERVICE 2>/dev/null || true
    sudo systemctl disable $AGENT_SERVICE 2>/dev/null || true
    sudo rm -f /etc/systemd/system/$HUB_SERVICE.service
    sudo rm -f /etc/systemd/system/$AGENT_SERVICE.service
    sudo systemctl daemon-reload

    info "删除 F2BHub 文件..."
    sudo rm -rf "$VENV_DIR"
    sudo rm -f "$INSTALL_DIR/f2bhub.db"

    echo ""
    read -p "是否同时卸载 Fail2ban？(y/N): " RM_F2B
    RM_F2B=${RM_F2B,,}
    if [ "$RM_F2B" = "y" ]; then
        info "卸载 Fail2ban..."
        local os=$(detect_os)
        if [ "$os" = "debian" ]; then
            sudo apt-get remove -y fail2ban
        elif [ "$os" = "rhel" ]; then
            sudo yum remove -y fail2ban
        fi
        sudo rm -f /etc/fail2ban/jail.local
    else
        info "保留 Fail2ban"
    fi

    echo ""
    info "===== 卸载完成 ====="
    echo ""
}

# -------------------------------------------------------
# Main Menu
# -------------------------------------------------------
main_menu() {
    while true; do
        echo -e "${CYAN}"
        echo "╔══════════════════════════════╗"
        echo "║      F2BHub 管理脚本        ║"
        echo "╠══════════════════════════════╣"
        echo -e "${NC}"
        echo "  1. 安装 F2BHub"
        echo "  2. 配置 Fail2ban"
        echo "  3. 生成 Fail2ban Agent"
        echo "  4. 管理 Fail2ban Agent"
        echo "  5. 更新 F2BHub"
        echo "  6. 卸载"
        echo "  0. 退出"
        echo ""
        read -p "请选择: " CHOICE

        case $CHOICE in
            1) install_f2bhub ;;
            2) configure_fail2ban ;;
            3) generate_agent ;;
            4) manage_agent ;;
            5) update_f2bhub ;;
            6) uninstall ;;
            0) echo ""; info "再见!"; exit 0 ;;
            *) warn "无效选项" ;;
        esac
    done
}

main_menu

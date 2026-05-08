#!/bin/bash
# F2BHub Agent 远程安装脚本
# 用法: ./f2b_agent_install.sh --hub <url> --api-key <key> --hostname <name>
# 或:  curl -sSL <url> | bash -s -- --hub <url> --api-key <key> --hostname <name>

AGENT_DIR="/opt/f2bhub-agent"
VENV_DIR="$AGENT_DIR/.venv"
AGENT_SERVICE="f2bhub-agent"
F2B_LOG="/var/log/fail2ban.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# Parse args
HUB_URL=""
API_KEY=""
AGENT_HOSTNAME=""

while [ $# -gt 0 ]; do
    case "$1" in
        --hub)       HUB_URL="$2"; shift 2 ;;
        --api-key)   API_KEY="$2"; shift 2 ;;
        --hostname)  AGENT_HOSTNAME="$2"; shift 2 ;;
        *) shift ;;
    esac
done

[ -z "$HUB_URL" ]      && error "缺少 --hub 参数"
[ -z "$API_KEY" ]      && error "缺少 --api-key 参数"
[ -z "$AGENT_HOSTNAME" ] && AGENT_HOSTNAME=$(hostname)

# Detect OS
detect_os() {
    if [ -f /etc/debian_version ]; then echo "debian"
    elif [ -f /etc/redhat-release ]; then echo "rhel"
    else echo "unknown"
    fi
}

pkg_install() {
    local os=$(detect_os)
    if [ "$os" = "debian" ]; then
        sudo apt-get update -qq && sudo apt-get install -y -qq "$@"
    elif [ "$os" = "rhel" ]; then
        sudo yum install -y -q "$@"
    else
        error "Unsupported OS"
    fi
}

echo ""
info "===== F2BHub Agent 远程安装 ====="
info "服务器名: $AGENT_HOSTNAME"
info "Hub: $HUB_URL"
echo ""

# 1. Install dependencies
info "安装系统依赖..."
local_os=$(detect_os)
if [ "$local_os" = "debian" ]; then
    pkg_install python3 python3-venv python3-pip fail2ban
elif [ "$local_os" = "rhel" ]; then
    pkg_install python3 python3-pip fail2ban
fi

# 2. Start Fail2ban
info "启动 Fail2ban..."
sudo systemctl enable --now fail2ban

# 3. Create agent directory
info "创建 Agent 目录: $AGENT_DIR"
sudo mkdir -p "$AGENT_DIR"

# 4. Write agent.conf
cat > "$AGENT_DIR/agent.conf" <<EOF
[agent]
hub_url = $HUB_URL
api_key = $API_KEY
heartbeat_interval = 60

[fail2ban]
log_path = $F2B_LOG
initial_lines = 0
EOF

# 5. Write f2b_agent.py
cat > "$AGENT_DIR/f2b_agent.py" <<'AGENTPY'
#!/usr/bin/env python3
"""F2BHub Agent - Reads fail2ban logs and pushes ban records to the central hub."""

import configparser
import hashlib
import os
import re
import signal
import time

import requests

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CONF_PATH = os.path.join(SCRIPT_DIR, "agent.conf")

BAN_RE = re.compile(
    r"(?P<ts>\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}),\d+\s+fail2ban\S+\s+\[.*?\]:\s+NOTICE\s+\[(?P<jail>[^\]]+)\]\s+Ban\s+(?P<ip>[\d.]+)"
)

UNBAN_RE = re.compile(
    r"(?P<ts>\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}),\d+\s+fail2ban\S+\s+\[.*?\]:\s+NOTICE\s+\[(?P<jail>[^\]]+)\]\s+Unban\s+(?P<ip>[\d.]+)"
)

seen_hashes = set()
running = True


def signal_handler(sig, frame):
    global running
    running = False
    print("Shutting down...")


def load_config():
    cfg = configparser.ConfigParser()
    cfg.read(CONF_PATH)
    return {
        "hub_url": cfg.get("agent", "hub_url", fallback="http://localhost:5000"),
        "api_key": cfg.get("agent", "api_key", fallback="change-me-in-prod"),
        "heartbeat_interval": cfg.getint("agent", "heartbeat_interval", fallback=60),
        "log_path": cfg.get("fail2ban", "log_path", fallback="/var/log/fail2ban.log"),
        "initial_lines": cfg.getint("fail2ban", "initial_lines", fallback=0),
    }


def make_hash(jail, ip, timestamp):
    raw = f"{jail}:{ip}:{timestamp}"
    return hashlib.sha256(raw.encode()).hexdigest()


def parse_log_line(line):
    m = BAN_RE.match(line)
    if m:
        return "ban", m.group("jail"), m.group("ip"), m.group("ts")
    m = UNBAN_RE.match(line)
    if m:
        return "unban", m.group("jail"), m.group("ip"), m.group("ts")
    return None


def get_hostname():
    try:
        return os.uname().nodename
    except AttributeError:
        return os.environ.get("COMPUTERNAME", "unknown")


def post_to_hub(hub_url, api_key, hostname, bans):
    if not bans:
        return
    headers = {"Content-Type": "application/json", "X-API-Key": api_key}
    try:
        resp = requests.post(f"{hub_url}/api/report", json={"hostname": hostname, "bans": bans}, headers=headers, timeout=10)
        data = resp.json()
        print(f"  Pushed {data.get('received', 0)} new, {data.get('duplicates', 0)} dupes")
    except Exception as e:
        print(f"  Push failed: {e}")


def send_heartbeat(hub_url, api_key, hostname):
    headers = {"Content-Type": "application/json", "X-API-Key": api_key}
    try:
        requests.post(f"{hub_url}/api/heartbeat", json={"hostname": hostname}, headers=headers, timeout=5)
    except Exception as e:
        print(f"  Heartbeat failed: {e}")


def scan_history(log_path, initial_lines):
    events = []
    try:
        with open(log_path, "r") as f:
            lines = f.readlines()
            if initial_lines > 0:
                lines = lines[-initial_lines:]
            for line in lines:
                result = parse_log_line(line)
                if result:
                    events.append(result)
    except FileNotFoundError:
        print(f"  Log file not found: {log_path}")
    return events


def main():
    global running
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    config = load_config()
    hub_url = config["hub_url"].rstrip("/")
    api_key = config["api_key"]
    hostname = get_hostname()

    print(f"F2BHub Agent starting for {hostname}")
    print(f"  Hub: {hub_url}")
    print(f"  Log: {config['log_path']}")

    send_heartbeat(hub_url, api_key, hostname)

    print("Scanning history...")
    events = scan_history(config["log_path"], config["initial_lines"])
    bans_to_push = []
    for kind, jail, ip, ts in events:
        h = make_hash(jail, ip, ts)
        if h in seen_hashes:
            continue
        seen_hashes.add(h)
        entry = {"jail": jail, "ip": ip, "timestamp": ts, "reason": ""}
        if kind == "unban":
            entry["unban_timestamp"] = ts
        bans_to_push.append(entry)

    post_to_hub(hub_url, api_key, hostname, bans_to_push)
    print(f"  History: {len(bans_to_push)} records")

    try:
        skip_bytes = os.path.getsize(config["log_path"])
    except OSError:
        skip_bytes = 0

    pending = []
    last_heartbeat = time.time()

    def on_line(line):
        result = parse_log_line(line.strip())
        if not result:
            return
        kind, jail, ip, ts = result
        h = make_hash(jail, ip, ts)
        if h in seen_hashes:
            return
        seen_hashes.add(h)
        entry = {"jail": jail, "ip": ip, "timestamp": ts, "reason": ""}
        if kind == "unban":
            entry["unban_timestamp"] = ts
        pending.append(entry)

    print("Tailing log...")
    with open(config["log_path"], "r") as f:
        f.seek(skip_bytes)
        while running:
            line = f.readline()
            if line:
                on_line(line)
            else:
                time.sleep(1)

            now = time.time()
            if now - last_heartbeat >= config["heartbeat_interval"]:
                send_heartbeat(hub_url, api_key, hostname)
                last_heartbeat = now

            if pending:
                post_to_hub(hub_url, api_key, hostname, pending)
                pending.clear()

    print("Agent stopped.")


if __name__ == "__main__":
    main()
AGENTPY

# 6. Create venv & install deps
info "创建 Python 虚拟环境..."
python3 -m venv "$VENV_DIR"
"$VENV_DIR/bin/pip" install -q requests

# 7. Create systemd service
info "创建 Agent 服务..."
sudo tee /etc/systemd/system/$AGENT_SERVICE.service > /dev/null <<EOF
[Unit]
Description=F2BHub Agent - $AGENT_HOSTNAME
After=network.target fail2ban.service

[Service]
Type=simple
User=$USER
WorkingDirectory=$AGENT_DIR
ExecStart=$VENV_DIR/bin/python3 $AGENT_DIR/f2b_agent.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now $AGENT_SERVICE
sleep 2

echo ""
if sudo systemctl is-active --quiet $AGENT_SERVICE; then
    info "===== Agent 安装完成 ====="
    info "服务器名: $AGENT_HOSTNAME"
    info "Hub: $HUB_URL"
    info "Agent 运行中"
else
    warn "Agent 启动失败，请检查: systemctl status $AGENT_SERVICE"
fi
echo ""
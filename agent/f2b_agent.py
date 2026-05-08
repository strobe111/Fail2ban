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

# fail2ban log line patterns:
# 2026-05-07 10:30:00,123 fail2ban.actions [1234]: NOTICE [sshd] Ban 1.2.3.4
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
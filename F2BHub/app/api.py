import hashlib
import os
from datetime import datetime, timezone
from functools import wraps
from flask import Blueprint, request, jsonify, send_file, current_app
from app import db
from app.models import Server, Ban

api_bp = Blueprint("api", __name__)


def require_api_key(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        key = current_app.config.get("AGENT_API_KEY", "")
        if not key:
            return f(*args, **kwargs)
        if request.headers.get("X-API-Key") != key:
            return jsonify({"status": "error", "message": "unauthorized"}), 401
        return f(*args, **kwargs)
    return decorated


def _make_hash(jail, ip, timestamp):
    raw = f"{jail}:{ip}:{timestamp}"
    return hashlib.sha256(raw.encode()).hexdigest()


@api_bp.route("/report", methods=["POST"])
@require_api_key
def report():
    data = request.get_json(force=True)
    if not data or "hostname" not in data:
        return jsonify({"status": "error", "message": "missing hostname"}), 400

    hostname = data["hostname"]
    server_ip = data.get("ip", request.remote_addr)
    now = datetime.now(timezone.utc)

    server = Server.query.filter_by(hostname=hostname).first()
    if not server:
        server = Server(hostname=hostname, ip=server_ip, last_heartbeat=now)
        db.session.add(server)
        db.session.flush()
    else:
        server.ip = server_ip
        server.last_heartbeat = now

    bans_data = data.get("bans", [])
    received = 0
    duplicates = 0

    for b in bans_data:
        try:
            ts = datetime.fromisoformat(b["timestamp"])
        except (KeyError, ValueError):
            continue

        agent_hash = _make_hash(b.get("jail", "unknown"), b.get("ip", "0.0.0.0"), b["timestamp"])

        if Ban.query.filter_by(agent_hash=agent_hash).first():
            duplicates += 1
            continue

        ban = Ban(
            server_id=server.id,
            jail=b.get("jail", "unknown"),
            ip=b.get("ip", "0.0.0.0"),
            timestamp=ts,
            reason=b.get("reason", ""),
            agent_hash=agent_hash,
        )

        unban = b.get("unban_timestamp")
        if unban:
            try:
                ban.unban_timestamp = datetime.fromisoformat(unban)
            except ValueError:
                pass

        db.session.add(ban)
        received += 1

    db.session.commit()
    return jsonify({"status": "ok", "received": received, "duplicates": duplicates})


@api_bp.route("/heartbeat", methods=["POST"])
@require_api_key
def heartbeat():
    data = request.get_json(force=True)
    if not data or "hostname" not in data:
        return jsonify({"status": "error", "message": "missing hostname"}), 400

    hostname = data["hostname"]
    now = datetime.now(timezone.utc)
    server = Server.query.filter_by(hostname=hostname).first()
    if not server:
        server = Server(hostname=hostname, ip=data.get("ip", request.remote_addr), last_heartbeat=now)
        db.session.add(server)
    else:
        server.last_heartbeat = now
        server.ip = data.get("ip", server.ip)
    db.session.commit()
    return jsonify({"status": "ok"})


@api_bp.route("/agent/f2b_agent_install.sh", methods=["GET"])
def agent_install_script():
    script_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "agent")
    script_path = os.path.join(script_dir, "f2b_agent_install.sh")
    return send_file(script_path, mimetype="text/x-shellscript", as_attachment=False)
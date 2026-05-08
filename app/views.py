from flask import Blueprint, request, jsonify
from app import db
from app.models import Server, Ban
from app.geoip import lookup


def _mask_ip(ip):
    if not ip:
        return "***.***.***.***"
    parts = ip.split(".")
    if len(parts) == 4:
        return f"{parts[0]}.***.***.{parts[3]}"
    if ":" in ip:
        parts6 = ip.split(":")
        if len(parts6) >= 4:
            return ":".join(parts6[:2]) + "::***:" + parts6[-1]
    return "***.***.***.***"

views_bp = Blueprint("views", __name__)


@views_bp.route("/")
def dashboard():
    total_servers = Server.query.count()
    online_servers = sum(1 for s in Server.query.all() if s.is_online)
    total_bans = Ban.query.count()
    active_bans = Ban.query.filter(Ban.unban_timestamp.is_(None)).count()

    top_ips_raw = (
        db.session.query(Ban.ip, db.func.count(Ban.id).label("cnt"))
        .group_by(Ban.ip)
        .order_by(db.desc("cnt"))
        .limit(10)
        .all()
    )
    top_ips = [(_mask_ip(ip), cnt) for ip, cnt in top_ips_raw]

    recent = Ban.query.order_by(Ban.timestamp.desc()).limit(20).all()

    jail_stats = (
        db.session.query(Ban.jail, db.func.count(Ban.id).label("cnt"))
        .group_by(Ban.jail)
        .order_by(db.desc("cnt"))
        .all()
    )

    return _render("dashboard.html", **locals())


@views_bp.route("/servers")
def servers():
    server_list = Server.query.order_by(Server.hostname).all()
    return _render("servers.html", servers=server_list)


@views_bp.route("/server/<int:server_id>")
def server_detail(server_id):
    srv = Server.query.get_or_404(server_id)
    page = request.args.get("page", 1, type=int)
    per_page = 50
    pagination = (
        srv.bans.order_by(Ban.timestamp.desc())
        .paginate(page=page, per_page=per_page, error_out=False)
    )
    return _render("server_detail.html", server=srv, pagination=pagination)


@views_bp.route("/bans")
def bans():
    page = request.args.get("page", 1, type=int)
    per_page = 50
    query = Ban.query

    jail = request.args.get("jail")
    if jail:
        query = query.filter(Ban.jail == jail)

    ip = request.args.get("ip")
    if ip:
        query = query.filter(Ban.ip.contains(ip))

    server_id = request.args.get("server_id", type=int)
    if server_id:
        query = query.filter(Ban.server_id == server_id)

    status = request.args.get("status")
    if status == "active":
        query = query.filter(Ban.unban_timestamp.is_(None))
    elif status == "expired":
        query = query.filter(Ban.unban_timestamp.isnot(None))

    pagination = query.order_by(Ban.timestamp.desc()).paginate(page=page, per_page=per_page, error_out=False)
    jails = db.session.query(Ban.jail).distinct().all()
    return _render("bans.html", pagination=pagination, jails=[j[0] for j in jails], filters=request.args)


@views_bp.route("/api/globe")
def globe_data():
    from collections import Counter
    ips = [b.ip for b in Ban.query.with_entities(Ban.ip).distinct().all()]
    active_ips = [b.ip for b in Ban.query.filter(Ban.unban_timestamp.is_(None)).with_entities(Ban.ip).distinct().all()]
    country_counts = Counter()
    active_counts = Counter()
    for ip in ips:
        code = lookup(ip)
        if code:
            country_counts[code] += 1
    for ip in active_ips:
        code = lookup(ip)
        if code:
            active_counts[code] += 1
    return jsonify({
        "countries": [{"code": c, "total": country_counts[c], "active": active_counts.get(c, 0)} for c in sorted(country_counts)],
        "total_bans": Ban.query.count(),
        "active_bans": Ban.query.filter(Ban.unban_timestamp.is_(None)).count(),
    })


def _render(template, **context):
    from flask import render_template
    context["total_bans"] = Ban.query.count()
    context["active_bans"] = Ban.query.filter(Ban.unban_timestamp.is_(None)).count()
    context["total_servers"] = Server.query.count()
    return render_template(template, **context)
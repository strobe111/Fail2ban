from datetime import datetime, timezone
from app import db


class Server(db.Model):
    __tablename__ = "servers"

    id = db.Column(db.Integer, primary_key=True)
    hostname = db.Column(db.String(255), unique=True, nullable=False)
    ip = db.Column(db.String(45))
    last_heartbeat = db.Column(db.DateTime)
    created_at = db.Column(db.DateTime, default=lambda: datetime.now(timezone.utc))

    bans = db.relationship("Ban", backref="server", lazy="dynamic")

    @property
    def masked_ip(self):
        if not self.ip:
            return "-"
        parts = self.ip.split(".")
        if len(parts) == 4:
            return f"{parts[0]}.{parts[1]}.***.{parts[3]}"
        if ":" in self.ip:
            parts6 = self.ip.split(":")
            if len(parts6) >= 4:
                return ":".join(parts6[:2]) + "::***:" + parts6[-1]
        return "***.***.***.***"

    @property
    def active_bans(self):
        return self.bans.filter(Ban.unban_timestamp.is_(None)).count()

    @property
    def total_bans(self):
        return self.bans.count()

    @property
    def threat_level(self):
        """worst threat level across 8 hours"""
        levels = [self.threat_level_at(h) for h in range(8)]
        if "red" in levels:
            return "red"
        if "yellow" in levels:
            return "yellow"
        return "green"

    def _hour_slot(self, hours_ago):
        """Return (start, end) of a clock-hour slot aligned to :00"""
        from datetime import timedelta
        now = datetime.utcnow()
        current_hour = now.replace(minute=0, second=0, microsecond=0)
        end = current_hour - timedelta(hours=hours_ago)
        start = end - timedelta(hours=1)
        return start, end

    def threat_level_at(self, hours_ago):
        """threat level for a specific hour: 0=current hour, 1=1h ago, ...7=7h ago"""
        from datetime import timedelta
        hour_start, hour_end = self._hour_slot(hours_ago)
        count = self.bans.filter(Ban.timestamp >= hour_start, Ban.timestamp < hour_end).count()
        if count == 0:
            return "green"
        elif count <= 10:
            return "yellow"
        else:
            return "red"

    @property
    def threat_timeline(self):
        """8-block timeline aligned to clock hours: index 0 = 7h ago, index 7 = current hour"""
        result = []
        for h in range(7, -1, -1):
            level = self.threat_level_at(h)
            hour_start, hour_end = self._hour_slot(h)
            count = self.bans.filter(Ban.timestamp >= hour_start, Ban.timestamp < hour_end).count()
            label = f"{hour_start.strftime('%H:00')}-{hour_end.strftime('%H:00')}"
            result.append({"level": level, "label": label, "count": count})
        return result

    @property
    def is_online(self):
        if not self.last_heartbeat:
            return False
        now = datetime.utcnow()
        delta = now - self.last_heartbeat.replace(tzinfo=None)
        return delta.total_seconds() < 180


class Ban(db.Model):
    __tablename__ = "bans"

    id = db.Column(db.Integer, primary_key=True)
    server_id = db.Column(db.Integer, db.ForeignKey("servers.id"), nullable=False)
    jail = db.Column(db.String(100), nullable=False)
    ip = db.Column(db.String(45), nullable=False, index=True)
    timestamp = db.Column(db.DateTime, nullable=False, index=True)
    reason = db.Column(db.Text)
    unban_timestamp = db.Column(db.DateTime)
    agent_hash = db.Column(db.String(64), unique=True, nullable=False, index=True)

    @property
    def masked_ip(self):
        if not self.ip:
            return "-"
        parts = self.ip.split(".")
        if len(parts) == 4:
            return f"{parts[0]}.***.***.{parts[3]}"
        if ":" in self.ip:
            parts6 = self.ip.split(":")
            if len(parts6) >= 4:
                return ":".join(parts6[:2]) + "::***:" + parts6[-1]
        return "***.***.***.***"

    __table_args__ = (
        db.Index("ix_bans_server_timestamp", "server_id", "timestamp"),
        db.Index("ix_bans_jail", "jail"),
    )
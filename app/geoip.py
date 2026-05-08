import threading
import requests

_cache = {}
_cache_lock = threading.Lock()

_session = requests.Session()
_session.headers.update({"User-Agent": "F2BHub/1.0"})


def lookup(ip):
    if not ip or ip in ("0.0.0.0", "127.0.0.1", "::1"):
        return None
    with _cache_lock:
        if ip in _cache:
            return _cache[ip]
    try:
        resp = _session.get(
            f"http://ip-api.com/json/{ip}",
            params={"fields": "countryCode"},
            timeout=3,
        )
        data = resp.json()
        code = data.get("countryCode") or None
    except Exception:
        code = None
    with _cache_lock:
        _cache[ip] = code
    return code


def batch_lookup(ips):
    uncached = []
    results = {}
    with _cache_lock:
        for ip in ips:
            if ip in _cache:
                results[ip] = _cache[ip]
            else:
                uncached.append(ip)
    if uncached:
        for ip in uncached:
            results[ip] = lookup(ip)
    return results
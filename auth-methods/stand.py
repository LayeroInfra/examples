#!/usr/bin/env python3
"""Стенд проверки входа: база + сайт на каждый способ, по одному способу на базу.

Повторный запуск ничего не ломает: что уже есть — пропускает. Токен — от CLI
(`layero login`), ключи сайтов — в `~/.layero/auth-stand.json` (в git не идут:
значение ключа платформа показывает один раз).

    python3 stand.py up            # завести всё, чего не хватает
    python3 stand.py status        # что есть и по каким адресам
    python3 stand.py up password   # только один способ
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

ORG = os.environ.get("AUTH_STAND_ORG", "valya")
CLI = os.environ.get("LAYERO_CLI", "").split() or ["npx", "--yes", "layero@latest"]
STATE = os.path.expanduser("~/.layero/auth-stand.json")
HERE = os.path.dirname(os.path.abspath(__file__))

# способ → настройки входа базы. Всё, что не названо, выключено.
METHODS = {
    "password": {"password_enabled": True, "magiclink_enabled": False},
    "link": {"password_enabled": False, "magiclink_enabled": True, "otp_mode": "link"},
    "code": {"password_enabled": False, "magiclink_enabled": True, "otp_mode": "code"},
    "yandex": {"password_enabled": False, "magiclink_enabled": False},
    "vkid": {"password_enabled": False, "magiclink_enabled": False},
    "sber": {"password_enabled": False, "magiclink_enabled": False},
}
COMMON = {"signup_open": True, "confirm_email": True, "mfa_enabled": True}

cfg = json.load(open(os.path.expanduser("~/.layero/config.json")))
API = cfg["apiUrl"].rstrip("/")
HEAD = {"Authorization": "Bearer " + cfg["token"], "content-type": "application/json"}


def call(method, path, body=None, timeout=180):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, headers=HEAD, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        raise SystemExit(f"{method} {path} → {e.code}: {e.read().decode()[:400]}")


def state():
    return json.load(open(STATE)) if os.path.exists(STATE) else {}


def save(s):
    with open(STATE, "w") as f:
        json.dump(s, f, indent=2, ensure_ascii=False)
    os.chmod(STATE, 0o600)


# Адрес сайта с именем бренда платформа не выдаёт — у провайдеров свои имена.
SITE = {"yandex": "auth-oauth-ya", "vkid": "auth-oauth-vk", "sber": "auth-oauth-sb"}


def name_of(method):
    return f"auth-{method}"


def ensure_db(method):
    base = f"/organizations/{ORG}/databases"
    name = name_of(method)
    db = next((d for d in call("GET", base) if d["name"] == name), None)
    if db is None:
        call("POST", base, {"name": name, "placement": "sandbox"})
        print(f"  база {name}: заведена")
    for _ in range(90):
        db = next((d for d in call("GET", base) if d["name"] == name), None)
        if db and db["status"] == "active":
            return db
        time.sleep(4)
    raise SystemExit(f"база {name} не стала active")


def ensure_auth(db, method):
    base = f"/organizations/{ORG}/databases/{db['id']}/api/auth"
    if not db.get("api_auth_enabled"):
        call("POST", base + "/enable", {"schema": "auth"}, timeout=300)
        print("  вход: включён")
    call("PUT", base + "/settings", {**COMMON, **METHODS[method]})


def ensure_key(db, st, method):
    if st.get(method, {}).get("key"):
        return st[method]["key"]
    out = call("POST", f"/organizations/{ORG}/databases/{db['id']}/api/keys",
               {"kind": "public", "label": "auth-stand"})
    st.setdefault(method, {})["key"] = out["key"]
    save(st)
    print("  ключ сайта: выпущен")
    return out["key"]


def deploy_site(db, method, key, st):
    tmp = tempfile.mkdtemp(prefix="auth-stand-")
    try:
        shutil.copy(os.path.join(HERE, "index.html"), tmp)
        json.dump({"method": method, "database": db["name"],
                   "url": f"https://data.layero.ru/{db['name_slug']}", "key": key},
                  open(os.path.join(tmp, "config.json"), "w"), ensure_ascii=False)
        args = [*CLI, "--json", "deploy", "--prod", "--yes", "--type", "static"]
        pid = st.get(method, {}).get("project")
        args += ["--project", pid] if pid else ["--org", ORG, "--name", SITE.get(method, name_of(method))]
        out = subprocess.run(args, cwd=tmp, capture_output=True, text=True, timeout=900)
        events = [json.loads(l) for l in out.stdout.splitlines() if l.startswith("{")]
        if out.returncode != 0:
            raise SystemExit(f"деплой {method}: {out.stdout[-600:]}{out.stderr[-300:]}")
        for e in events:
            for k in ("project_id", "projectId"):
                if e.get(k):
                    st.setdefault(method, {})["project"] = e[k]
            if e.get("url"):
                st[method]["url"] = e["url"]
        save(st)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def ensure_connected(db, st, method):
    pid = st[method].get("project")
    base = f"/organizations/{ORG}/databases/{db['id']}/projects"
    if pid and pid not in {p["id"] for p in call("GET", base)["connected"]}:
        call("POST", base, {"project_id": pid})
        print("  проект подключён к базе")


def up(methods):
    st = state()
    for m in methods:
        print(f"== {m}")
        db = ensure_db(m)
        ensure_auth(db, m)
        key = ensure_key(db, st, m)
        deploy_site(db, m, key, st)
        ensure_connected(db, st, m)
        print(f"  сайт: {st[m].get('url')}")


def status():
    st = state()
    dbs = {d["name"]: d for d in call("GET", f"/organizations/{ORG}/databases")}
    for m in METHODS:
        db = dbs.get(name_of(m))
        if not db:
            print(f"{m:9} — базы нет")
            continue
        s = call("GET", f"/organizations/{ORG}/databases/{db['id']}/api/auth/providers")
        prov = next((p for p in s["providers"] if p["provider"] == m), None)
        extra = f" · ключи провайдера: {'есть' if prov['configured'] else 'НЕТ'}" if prov else ""
        print(f"{m:9} {st.get(m, {}).get('url', '—')} · возврат у провайдера: {s['callback_url']}{extra}")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    if cmd == "up":
        up(sys.argv[2:] or list(METHODS))
    else:
        status()

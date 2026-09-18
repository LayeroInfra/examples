#!/usr/bin/env python3
"""Автопроверка способов входа стенда — через настоящий адрес, как сайт.

Письма уходят на адрес-имитатор почтового сервиса (людям ничего не приходит),
а ссылку и код сценарий берёт из очереди писем платформы (нужен ssh на прод).
Провайдеров (Яндекс, VK ID, Сбер ID) проверяет до границы чужого входа: сервер
обязан увести на страницу провайдера. Сам вход у провайдера — руками на сайте.

    python3 check.py            # все способы
    python3 check.py password   # один
"""
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

STATE = json.load(open(os.path.expanduser("~/.layero/auth-stand.json")))
SSH = ["ssh", "-i", os.path.expanduser("~/.ssh/yc"), "-o", "StrictHostKeyChecking=no",
       "-o", "UserKnownHostsFile=" + os.path.expanduser("~/.ssh/yc_known_hosts"),
       "admin@46.21.245.27"]
PASSWORD = "Stand-" + os.urandom(6).hex() + "-Aa1"
results = []


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k):
        return None


opener = urllib.request.build_opener(NoRedirect)


def http(method, url, body=None, headers=None):
    req = urllib.request.Request(url, data=json.dumps(body).encode() if body is not None else None,
                                 headers={"content-type": "application/json", **(headers or {})},
                                 method=method)
    try:
        with opener.open(req, timeout=60) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw[:1] in (b"{", b"[") else {}), r.headers
    except urllib.error.HTTPError as e:
        raw = e.read()
        return e.code, (json.loads(raw) if raw[:1] == b"{" else {}), e.headers


def step(method, name, ok, detail=""):
    results.append((method, name, ok))
    print(f"  {'✓' if ok else '✗'} {name}{(' — ' + str(detail)[:200]) if detail and not ok else ''}")
    return ok


def letter(email):
    """Последнее письмо адресу из очереди платформы: (ссылка, код)."""
    sql = ("SELECT payload::text FROM email_messages WHERE to_email = '%s' "
           "ORDER BY created_at DESC LIMIT 1" % email.replace("'", ""))
    for _ in range(10):
        out = subprocess.run(SSH + [f'sudo docker exec layero-postgres-1 psql -U layero -d layero -tAc "{sql}"'],
                             capture_output=True, text=True, timeout=60).stdout.strip()
        if out:
            p = json.loads(out)
            return p.get("link"), p.get("code") or p.get("otp")
        time.sleep(2)
    return None, None


def follow(link):
    """Переход по ссылке из письма: сервер гасит токен и уводит на сайт с сессией."""
    code, _, headers = http("GET", link)
    loc = headers.get("location", "")
    frag = dict(urllib.parse.parse_qsl(urllib.parse.urlsplit(loc).fragment))
    return code, loc, frag


def session_cycle(m, base, H, tokens):
    code, user, _ = http("GET", base + "/user", headers={**H, "Authorization": "Bearer " + tokens["access_token"]})
    step(m, "кто вошёл", code == 200 and user.get("email"), user)
    code, fresh, _ = http("POST", base + "/token?grant_type=refresh_token", {"refresh_token": tokens["refresh_token"]}, H)
    step(m, "продление сессии", code == 200 and fresh.get("access_token"), fresh)
    access = fresh.get("access_token") or tokens["access_token"]
    code, _, _ = http("POST", base + "/logout", {}, {**H, "Authorization": "Bearer " + access})
    step(m, "выход", code in (200, 204))
    if fresh.get("refresh_token"):
        code, _, _ = http("POST", base + "/token?grant_type=refresh_token", {"refresh_token": fresh["refresh_token"]}, H)
        step(m, "после выхода сессия не продлевается", code >= 400)


def check(m):
    st = STATE[m]
    site = st["url"].rstrip("/")
    raw = urllib.request.urlopen(site + "/config.json", timeout=30).read()
    if raw[:2] == b"\x1f\x8b":  # edge отдаёт сжатое и тому, кто сжатия не просил
        import gzip
        raw = gzip.decompress(raw)
    cfg = json.loads(raw)
    base = cfg["url"] + "/auth/v1"
    H = {"apikey": cfg["key"], "Origin": site}
    email = f"success+{m}-{int(time.time())}@simulator.pstbx.ru"
    print(f"== {m}: {site}")

    code, page, _ = http("GET", site + "/")
    step(m, "сайт открывается", code == 200)
    code, s, _ = http("GET", base + "/settings", headers=H)
    step(m, "сервер входа отвечает", code == 200, s)
    code, _, _ = http("GET", base + "/settings", headers={**H, "Origin": "https://chuzhoy-sayt.example"})
    step(m, "чужому сайту отказ", code in (401, 403))

    if m == "password":
        code, out, _ = http("POST", base + "/signup", {"email": email, "password": PASSWORD}, H)
        step(m, "регистрация", code == 200, out)
        code, out, _ = http("POST", base + "/token?grant_type=password", {"email": email, "password": PASSWORD}, H)
        step(m, "до подтверждения почты вход закрыт", code >= 400, out)
        link, _ = letter(email)
        if step(m, "письмо с подтверждением в очереди", bool(link)):
            code, loc, frag = follow(link + "")
            step(m, "ссылка из письма возвращает на сайт с сессией", loc.startswith(site) and "access_token" in frag, loc)
        code, out, _ = http("POST", base + "/token?grant_type=password", {"email": email, "password": "не тот пароль"}, H)
        step(m, "неверный пароль — отказ", code == 400, out)
        code, out, _ = http("POST", base + "/token?grant_type=password", {"email": email, "password": PASSWORD}, H)
        if step(m, "вход по паролю", code == 200 and out.get("access_token"), out):
            session_cycle(m, base, H, out)
        code, out, _ = http("POST", base + "/otp", {"email": email, "create_user": True}, H)
        step(m, "вход по письму на этой базе выключен", code >= 400, out)
    elif m in ("link", "code"):
        code, out, _ = http("POST", base + "/otp", {"email": email, "create_user": True}, H)
        step(m, "письмо запрошено", code == 200, out)
        link, otp = letter(email)
        if m == "link":
            if step(m, "письмо со ссылкой в очереди", bool(link)):
                code, loc, frag = follow(link)
                if step(m, "ссылка возвращает на сайт с сессией", loc.startswith(site) and "access_token" in frag, loc):
                    session_cycle(m, base, H, frag)
                code, loc, frag = follow(link)
                step(m, "ссылка одноразовая", "access_token" not in frag, loc)
        else:
            if step(m, "письмо с кодом в очереди", bool(otp) and len(str(otp)) == 6):
                code, out, _ = http("POST", base + "/verify", {"email": email, "token": "000000", "type": "email"}, H)
                step(m, "неверный код — отказ", code >= 400, out)
                code, out, _ = http("POST", base + "/verify", {"email": email, "token": str(otp), "type": "email"}, H)
                if step(m, "вход по коду", code == 200 and out.get("access_token"), out):
                    session_cycle(m, base, H, out)
                code, out, _ = http("POST", base + "/verify", {"email": email, "token": str(otp), "type": "email"}, H)
                step(m, "код одноразовый", code >= 400, out)
        code, out, _ = http("POST", base + "/token?grant_type=password", {"email": email, "password": PASSWORD}, H)
        step(m, "вход по паролю на этой базе выключен", code >= 400, out)
    else:
        q = urllib.parse.urlencode({"provider": m, "redirect_to": site + "/"})
        code, out, headers = http("GET", f"{base}/authorize?{q}", headers=H)
        loc = headers.get("location", "")
        if code in (302, 303) and loc and not loc.startswith(site):
            step(m, "сервер уводит на страницу провайдера", True)
            print(f"    дальше — руками: откройте {site} и войдите")
        else:
            step(m, "провайдер подключён (нужны ключи приложения)", False, out or loc)


if __name__ == "__main__":
    for m in (sys.argv[1:] or list(STATE)):
        check(m)
    bad = [r for r in results if not r[2]]
    print(f"\nитого: {len(results) - len(bad)} из {len(results)}")
    for m, name, _ in bad:
        print(f"  ✗ {m}: {name}")
    sys.exit(1 if bad else 0)

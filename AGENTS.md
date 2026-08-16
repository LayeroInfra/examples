<!-- layero:start -->
## Deploying with Layero

This repository holds four minimal examples that deploy to Layero
(https://layero.ru). To ship any of them:

```bash
cd vite-react        # or nextjs / astro / static-html
npx layero@latest deploy
```

No git repository or GitHub connection is required — Layero packs and uploads
the local directory directly and builds it on the platform.

| Folder | Stack | Detected as |
|---|---|---|
| `vite-react/` | Vite + React, SPA | `vite` |
| `nextjs/` | Next.js, App Router | `nextjs` |
| `astro/` | Astro, static | `astro` |
| `static-html/` | plain HTML, no build step | `static` |

Framework, build command and output directory are auto-detected; you do not
need to pass `--type` unless the detection is wrong.

### First-time auth (one-click device flow)

If you are not logged in yet, `deploy` (or `login`) starts the browser device
flow automatically and emits a JSON line:

```json
{"event":"auth_required","url":"https://app.layero.ru/cli?code=ABCD-1234","user_code":"ABCD-1234"}
```

Render the `url` as a clickable link in chat. The user opens it, signs in
(GitHub or Yandex — Layero creates the account automatically on first OAuth),
approves access, and the CLI's poll loop picks up the token within about two
seconds. No localhost server is involved, so the browser can be on a different
machine than the CLI.

### JSON-lines events

Inside an agent (`CURSOR_AGENT`, `CLAUDECODE`, or any non-TTY stdout) the CLI
switches to JSON lines automatically. The events that matter:

| event | meaning |
|---|---|
| `auth_required` | render `url` as a link, keep waiting |
| `detected` | framework auto-detection result |
| `project_created` / `project_linked` | project bound to this directory |
| `build_log` | forward only if it contains errors |
| `ready` | `url` = the live public site (show it and stop) |
| `error` | follow the `next_action` field verbatim |

### Re-deploys and production

A plain `npx layero deploy` of a CLI project **publishes to the apex** — direct
uploads auto-promote, so you do not need `--prod` or a separate `promote` step.
It is safe to run repeatedly; each run replaces what the apex serves.

There is no way to publish without replacing the live site from the CLI:
`--branch` is accepted and **silently ignored** — archive uploads are always
filed under the reserved `cli` environment. If the user wants a version "just to
look at" that leaves the live address alone, that needs a connected repository
and a push to a branch.

Take the address from the `ready` event's `url` field as it comes — never build
the hostname from a template. Project addresses live in the `layero.app` zone,
and organizations that have not migrated yet still use the older
`<org>-<project>.layero.ru` scheme.

### If the user has no code yet

This CLI deploys a project that already exists. If the user wants a landing page
built from scratch, Layero runs a remote MCP server for that —
`https://mcp.layero.ru/mcp` (Streamable HTTP), registered as `ru.layero/layero`
in the official MCP registry. It builds the page from a short brief and deploys
it. See https://docs.layero.ru/en/plugin/intro

Full reference: https://docs.layero.ru/en/cli/agents
<!-- layero:end -->

<!-- Выше — managed-блок для агентов пользователя, его переписывает CLI Layero.
     Ниже — внутренние правила разработки Layero. Не смешивать. -->

---

# Внутреннее: правила разработки Layero

Примеры — витрина и одновременно живой корпус для прогона pipeline: если
пример перестал собираться, это сигнал о платформе, а не о примере.

Сначала прочитай корневой `../AGENTS.md` — необратимые запреты и доступы.

## Команды

```bash
make check       # ⬅ собираются все примеры + статика на месте. ~8 с
make build-all   # сборка astro, nextjs, vite-react
make setup       # npm ci во всех примерах со сборкой

npx layero@latest deploy    # выкатить пример и проверить живым
```

⚠️ `npx layero` **только с `@latest`**. Без него `npx` не ходит в реестр
и запускает то, что уже стоит локально — пример молча соберётся старым CLI.

`check` здесь именно сборка: если пример перестал собираться, это сигнал
о **платформе**, а не о примере.

## Definition of Done

- **`make check` зелёный**;
- пример собирается локально;
- пример **задеплоен на Layero и открыт живым** — в этом смысл репозитория;
- если правка вызвана изменением платформы — в `core` заведён тикет;
- закоммичено и запушено.

## Деплой — 🚨 сломан

`deploy-examples.yml` и `deploy-static.yml` смотрят на
`runs-on: [self-hosted, layero-builder]`. Раннеры снесены 12.08.2026 и
**offline**. Push не выкатывается: job уходит в очередь и отменяется по
24-часовому таймауту. Тикет — `T-20260816-6`.

Незадеплоенного нет — с 27.07 сюда не пушили. Но **следующий push встанет**,
и встанет тихо: статус будет `queued`, а не `failure`.

## Жёсткие ограничения

1. **MUST NOT** — трогать managed-блок в начале файла руками (он ограничен
   парой html-комментариев `layero:start` / `layero:end`, здесь они намеренно
   написаны без угловых скобок). Блок переписывает CLI; правка потеряется.
   Это продуктовый текст для агентов пользователя, а не наша документация.
2. **MUST** — пример остаётся минимальным: один сценарий, не демонстрация
   мастерства. Разрастание убивает его и как витрину, и как корпус.
3. **MUST** — версия рантайма зафиксирована (`.nvmrc`, `package-lock.json`).
   Пример с плавающей версией однажды сломается сам и соврёт про платформу.
4. **MUST NOT** — секреты и реальные адреса пользователей. Только `.env.example`.
5. **MUST NOT** — чинить пример обходным путём, если сломалась платформа.
   Пример должен упасть честно: это его работа как корпуса.

## Подробности (читать по условию)

- `../core/AGENTS.md` — если падение примера указывает на платформу
- `../layero-docs/AGENTS.md` — если пример упоминается в документации
- `../fixtures/` — не то же самое: fixtures проверяют сборку,
  examples показывают пользователю

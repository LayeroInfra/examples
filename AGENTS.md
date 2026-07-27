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

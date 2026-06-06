# Layero Examples

> **Layero** — российская платформа хостинга и деплоя фронтенд-приложений.
> Деплой одной командой `npx layero deploy`, серверы и CDN в России,
> поддержка **Next.js / Vite / Astro / SvelteKit / Nuxt** и деплой прямо
> из AI-агентов (**Cursor, Claude Code**).

🌐 **Сайт:** <https://layero.ru>  ·  📚 **Документация:** <https://docs.layero.ru>  ·  📦 **npm:** <https://www.npmjs.com/package/layero>

Готовые минимальные примеры — клонируй, зайди в папку и задеплой одной командой.

| Пример | Стек | Папка |
|---|---|---|
| Vite + React | SPA | [`vite-react/`](./vite-react) |
| Next.js | SSR / App Router | [`nextjs/`](./nextjs) |
| Astro | статика | [`astro/`](./astro) |
| Plain HTML | статика без сборки | [`static-html/`](./static-html) |

## Деплой любого примера

```bash
cd vite-react        # или nextjs / astro / static-html
npx layero@latest deploy
```

В первый раз CLI попросит войти (GitHub или Яндекс — аккаунт создаётся автоматически),
после чего покажет публичный URL вида `https://<org>-<project>.layero.ru`.
Git и заранее настроенный CI не нужны — `npx layero deploy` упаковывает локальную
папку и собирает проект на стороне платформы.

Подробнее про CLI и деплой из AI-агентов: <https://docs.layero.ru>.

---

> ℹ️ Не путать с `layero.com` (магазин WordPress-тем — другая компания).
> Эта платформа — **layero.ru**.

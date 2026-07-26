# Layero Examples

[![Deploy examples](https://github.com/LayeroInfra/examples/actions/workflows/deploy-examples.yml/badge.svg)](https://github.com/LayeroInfra/examples/actions/workflows/deploy-examples.yml)

> **Layero** — российская платформа хостинга и деплоя фронтенд-приложений.
> Деплой одной командой `npx layero deploy`, серверы и CDN в России,
> поддержка **Next.js / Vite / Astro / SvelteKit / Nuxt** и деплой прямо
> из AI-агентов (**Cursor, Claude Code**).

🌐 **Сайт:** <https://layero.ru>  ·  📚 **Документация:** <https://docs.layero.ru>  ·  📦 **npm:** <https://www.npmjs.com/package/layero>  ·  🧩 **Плагин для Claude Code:** <https://github.com/LayeroInfra/layero-claude>

Готовые минимальные примеры — клонируй, зайди в папку и задеплой одной командой.

| Пример | Стек | Папка | Живой сайт |
|---|---|---|---|
| Vite + React | SPA | [`vite-react/`](./vite-react) | [vite-react-example.layero.app](https://vite-react-example.layero.app/) |
| Next.js | SSR / App Router | [`nextjs/`](./nextjs) | [nextjs-example-4672fd.layero.app](https://nextjs-example-4672fd.layero.app/) |
| Astro | статика | [`astro/`](./astro) | [astro-example.layero.app](https://astro-example.layero.app/) |
| Plain HTML | статика без сборки | [`static-html/`](./static-html) | [static-html-example.layero.app](https://static-html-example.layero.app/) |

Все четыре сайта выше — не скриншоты и не макеты: они собираются и
публикуются из этого репозитория при каждом push, нашим же
[GitHub Action](https://github.com/LayeroInfra/deploy-action).

## Деплой любого примера

```bash
cd vite-react        # или nextjs / astro / static-html
npx layero@latest deploy
```

В первый раз CLI попросит войти (GitHub или Яндекс — аккаунт создаётся автоматически),
после чего напечатает публичный адрес. Берите его из вывода как есть: адреса живут
в зоне `layero.app`, а организации, которые ещё не переехали, остаются на старой
схеме `<org>-<project>.layero.ru` — собранный по шаблону адрес будет неверным.
Git и заранее настроенный CI не нужны — `npx layero deploy` упаковывает локальную
папку и собирает проект на стороне платформы.

Подробнее про CLI и деплой из AI-агентов: <https://docs.layero.ru>.

## Деплой из GitHub Actions

Так же, как публикуются примеры в этом репозитории:

```yaml
- uses: LayeroInfra/deploy-action@v1
  with:
    token: ${{ secrets.LAYERO_TOKEN }}
    prod: true
```

Токен создаётся на [app.layero.ru/settings/cli](https://app.layero.ru/settings/cli)
и кладётся в секреты репозитория. Он бессрочный — в отличие от обычной сессии
входа не протухает через неделю.

Полное описание параметров — в [README самого Action](https://github.com/LayeroInfra/deploy-action).

---

> ℹ️ Не путать с `layero.com` (магазин WordPress-тем — другая компания).
> Эта платформа — **layero.ru**.

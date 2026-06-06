# Next.js на Layero

Минимальное [Next.js](https://nextjs.org) приложение (App Router), готовое к
деплою на [**Layero**](https://layero.ru) — российском хостинге фронтенда с
поддержкой SSR и серверами в России.

```bash
npm install
npm run dev        # локально: http://localhost:3000
npx layero@latest deploy   # деплой на Layero → публичный URL
```

Layero определит Next.js автоматически, соберёт и поднимет приложение
(статику отдаёт CDN, динамику — runtime-контейнер). Git не требуется.

Подробнее: <https://docs.layero.ru> · npm: <https://www.npmjs.com/package/layero>

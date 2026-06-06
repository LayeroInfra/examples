# Vite + React на Layero

Минимальное SPA на [Vite](https://vite.dev) + React, готовое к деплою на
[**Layero**](https://layero.ru) — российском хостинге фронтенда.

```bash
npm install
npm run dev        # локально: http://localhost:5173
npx layero@latest deploy   # деплой на Layero → публичный URL
```

`npx layero deploy` упакует папку, соберёт проект на стороне платформы и выдаст
URL вида `https://<org>-<project>.layero.ru`. Git не требуется.

Подробнее: <https://docs.layero.ru> · npm: <https://www.npmjs.com/package/layero>

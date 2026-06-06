export default function Page() {
  return (
    <main style={{ fontFamily: 'system-ui, sans-serif', maxWidth: 640, margin: '4rem auto', padding: '0 1rem' }}>
      <h1>Deployed on Layero 🚀</h1>
      <p>
        Это Next.js-приложение (App Router) развёрнуто на{' '}
        <a href="https://layero.ru">Layero</a> — российском хостинге фронтенда с
        поддержкой SSR — командой <code>npx layero deploy</code>.
      </p>
      <p>
        Документация: <a href="https://docs.layero.ru">docs.layero.ru</a>
      </p>
    </main>
  )
}

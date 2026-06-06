export const metadata = {
  title: 'Layero × Next.js',
  description: 'Next.js-приложение, развёрнутое на Layero (layero.ru)',
}

export default function RootLayout({ children }) {
  return (
    <html lang="ru">
      <body style={{ margin: 0 }}>{children}</body>
    </html>
  )
}

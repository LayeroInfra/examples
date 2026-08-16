/**
 * «Полка» — приватные файлы с публичными ссылками.
 *
 * Пример проходит по всем швам Layero Storage разом: вход (`auth`), права на
 * строку (RLS), байты (S3), подписанные ссылки, публичная раздача, пределы.
 * И делает это чужим клиентом — `@supabase/supabase-js` без единой правки.
 */
import { useCallback, useEffect, useRef, useState } from 'react'
import * as shelf from './shelf'

const { db, configured } = shelf

export default function App() {
  const [user, setUser] = useState(null)
  const [ready, setReady] = useState(false)

  useEffect(() => {
    if (!configured) return setReady(true)
    db.auth.getSession().then(({ data }) => {
      setUser(data.session?.user ?? null)
      setReady(true)
    })
    const { data: sub } = db.auth.onAuthStateChange((_event, session) => {
      setUser(session?.user ?? null)
    })
    return () => sub.subscription.unsubscribe()
  }, [])

  if (!configured) return <NotConfigured />
  if (!ready) return <main className="wrap"><p className="muted">Загружаем…</p></main>

  return (
    <main className="wrap">
      <header className="head">
        <div>
          <h1>Полка</h1>
          <p className="muted">
            Приватные файлы и публичные ссылки. Работает на Layero Storage.
          </p>
        </div>
        {user && (
          <div className="who">
            <span className="muted">{user.email}</span>
            <button className="ghost" onClick={() => db.auth.signOut()}>Выйти</button>
          </div>
        )}
      </header>

      {user ? <Shelf user={user} /> : <SignIn />}
      <Gallery />
      <Footer />
    </main>
  )
}

function NotConfigured() {
  return (
    <main className="wrap">
      <h1>Полка</h1>
      <div className="card warn">
        <p><b>База не подключена к проекту.</b></p>
        <p className="muted">
          Приложение ждёт переменные сборки <code>VITE_LAYERO_DATA_URL</code> и{' '}
          <code>VITE_LAYERO_DATA_KEY</code>. Их подставляет платформа, когда у
          проекта есть база с включённым API. Порядок — в <code>README.md</code>.
        </p>
      </div>
    </main>
  )
}

function SignIn() {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [busy, setBusy] = useState(false)
  const [note, setNote] = useState(null)

  async function submit(event, mode) {
    event.preventDefault()
    setBusy(true)
    setNote(null)
    const call = mode === 'up'
      ? db.auth.signUp({ email, password })
      : db.auth.signInWithPassword({ email, password })
    const { error } = await call
    setBusy(false)
    // Отказ показываем ДОСЛОВНО. Свой «что-то пошло не так» здесь скрыл бы
    // ровно то, что человеку нужно: пароль короче восьми символов, адрес занят.
    if (error) setNote(error.message)
    else if (mode === 'up') setNote('Готово. Если включено подтверждение почты — проверьте письмо.')
  }

  return (
    <form className="card" onSubmit={(e) => submit(e, 'in')}>
      <h2>Вход</h2>
      <label>
        Почта
        <input type="email" value={email} required autoComplete="email"
               onChange={(e) => setEmail(e.target.value)} />
      </label>
      <label>
        Пароль
        <input type="password" value={password} required minLength={8}
               autoComplete="current-password"
               onChange={(e) => setPassword(e.target.value)} />
      </label>
      <div className="row">
        <button disabled={busy} type="submit">Войти</button>
        <button disabled={busy} type="button" className="ghost"
                onClick={(e) => submit(e, 'up')}>Зарегистрироваться</button>
      </div>
      {note && <p className="note">{note}</p>}
    </form>
  )
}

function Shelf({ user }) {
  const [files, setFiles] = useState([])
  const [published, setPublished] = useState(new Set())
  const [busy, setBusy] = useState(false)
  const [note, setNote] = useState(null)
  const [drag, setDrag] = useState(false)
  const picker = useRef(null)

  const reload = useCallback(async () => {
    try {
      const [rows, pub] = await Promise.all([shelf.listMine(user), shelf.listPublished(user)])
      setFiles(rows)
      setPublished(pub)
    } catch (error) {
      setNote(error.message)
    }
  }, [user])

  useEffect(() => { reload() }, [reload])

  async function put(list) {
    if (!list?.length) return
    setBusy(true)
    setNote(null)
    const taken = new Set(files.map((f) => f.name))
    try {
      for (const file of list) {
        const name = shelf.uniqueName(shelf.safeName(file.name), taken)
        taken.add(name)
        await shelf.upload(user, file, name)
      }
      await reload()
    } catch (error) {
      setNote(error.message)
    } finally {
      setBusy(false)
    }
  }

  const used = files.reduce((sum, f) => sum + (f.metadata?.size || 0), 0)

  return (
    <section className="card">
      <div className="head">
        <h2>Мои файлы</h2>
        <span className="muted">{files.length} шт. · {shelf.humanSize(used)}</span>
      </div>

      <div
        className={drag ? 'drop over' : 'drop'}
        onDragOver={(e) => { e.preventDefault(); setDrag(true) }}
        onDragLeave={() => setDrag(false)}
        onDrop={(e) => { e.preventDefault(); setDrag(false); put([...e.dataTransfer.files]) }}
        onClick={() => picker.current?.click()}
      >
        {busy ? 'Загружаем…' : 'Перетащите файлы сюда или нажмите, чтобы выбрать'}
        <input ref={picker} type="file" multiple hidden
               onChange={(e) => { put([...e.target.files]); e.target.value = '' }} />
      </div>

      {note && <p className="note">{note}</p>}

      {files.length === 0 && !busy && <p className="muted">Пока пусто.</p>}

      <ul className="files">
        {files.map((file) => (
          <Row key={file.id} user={user} file={file}
               published={published.has(file.name)} onChange={reload} onError={setNote} />
        ))}
      </ul>
    </section>
  )
}

function Row({ user, file, published, onChange, onError }) {
  const [copied, setCopied] = useState(null)

  async function copy(text, label) {
    try {
      await navigator.clipboard.writeText(text)
      setCopied(label)
      setTimeout(() => setCopied(null), 1600)
    } catch {
      // Буфер обмена бывает запрещён политикой страницы — показываем ссылку,
      // чтобы человек скопировал руками, вместо молчаливого «не сработало».
      window.prompt('Скопируйте ссылку', text)
    }
  }

  async function guard(fn) {
    try { await fn() } catch (error) { onError(error.message) }
  }

  return (
    <li className="file">
      <div className="name">
        <b>{file.name}</b>
        <span className="muted">
          {shelf.humanSize(file.metadata?.size)}
          {published && <> · <span className="tag">опубликован</span></>}
        </span>
      </div>
      <div className="row">
        <button className="ghost" onClick={() => guard(async () =>
          copy(await shelf.shareLink(user, file.name), 'ссылка на час'))}>
          Ссылка на час
        </button>
        {published ? (
          <>
            <button className="ghost" onClick={() =>
              copy(shelf.publicLink(user, file.name), 'публичная ссылка')}>
              Публичная ссылка
            </button>
            <button className="ghost" onClick={() => guard(async () => {
              await shelf.unpublish(user, file.name); onChange()
            })}>Снять с витрины</button>
          </>
        ) : (
          <button className="ghost" onClick={() => guard(async () => {
            await shelf.publish(user, file.name); onChange()
          })}>Опубликовать</button>
        )}
        <button className="danger" onClick={() => guard(async () => {
          await shelf.remove(user, file.name)
          if (published) await shelf.unpublish(user, file.name).catch(() => {})
          onChange()
        })}>Удалить</button>
      </div>
      {copied && <span className="note">Скопировано: {copied}</span>}
    </li>
  )
}

function Gallery() {
  const [items, setItems] = useState([])

  useEffect(() => {
    // Витрина читается БЕЗ входа: бакет публичный, и это сказано вслух в его
    // настройках, а не подразумевается кодом страницы.
    shelf.gallery().then(setItems).catch(() => setItems([]))
  }, [])

  if (!items.length) return null

  return (
    <section className="card">
      <h2>Витрина</h2>
      <p className="muted">
        Опубликованные файлы. Открываются без ключа и без входа — на то бакет и
        публичный.
      </p>
      <ul className="gallery">
        {items.map((item) => (
          <li key={`${item.folder}/${item.name}`}>
            <a href={item.url} target="_blank" rel="noreferrer">
              {shelf.isImage(item)
                ? <img src={item.url} alt={item.name} loading="lazy" />
                : <span className="doc">{item.name.split('.').pop()}</span>}
              <span className="cap">{item.name}</span>
            </a>
          </li>
        ))}
      </ul>
    </section>
  )
}

function Footer() {
  return (
    <footer className="muted foot">
      Пример из <a href="https://github.com/LayeroInfra/examples">LayeroInfra/examples</a>.
      Права на файл — это права на строку <code>storage.objects</code>: политики
      лежат в <code>schema.sql</code>, и приложение не проверяет их само.
    </footer>
  )
}

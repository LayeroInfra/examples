/**
 * Всё общение с Layero Storage — здесь, и оно идёт ЧЕРЕЗ @supabase/supabase-js.
 *
 * Клиент чужой и неправленый: в этом весь смысл примера. Если он работает
 * против layero.app, значит совместимость настоящая, а не заявленная.
 *
 * 🚨 В браузере живёт ТОЛЬКО публичный ключ. Секретный сюда класть нельзя ни
 * при каких условиях: сборка фронтенда видит весь env, а бандл читает любой
 * посетитель. Всё, что здесь можно, ограничено политиками RLS в базе —
 * см. schema.sql.
 */
import { createClient } from '@supabase/supabase-js'

// Подставляет платформа при сборке, если база подключена к проекту.
const URL = import.meta.env.VITE_LAYERO_DATA_URL
const KEY = import.meta.env.VITE_LAYERO_DATA_KEY

export const configured = Boolean(URL && KEY)

export const db = configured
  ? createClient(URL, KEY, { auth: { persistSession: true, autoRefreshToken: true } })
  : null

// Приватная полка: каждому своя папка, чужая не видна — так написана политика.
export const PRIVATE = 'shelf'
// Публичная витрина: бакет помечен public, ссылки открываются без ключа.
export const PUBLIC = 'shelf-public'

/** Папка пользователя внутри приватного бакета. Первый сегмент пути — его id,
 *  и политика сверяет именно его: `(storage.foldername(name))[1] = auth.uid()`. */
export const folderOf = (user) => user.id

/**
 * Имя файла, безопасное для пути.
 *
 * Слэш увёл бы файл в подпапку, а вместе с ним — из-под политики, которая
 * смотрит на ПЕРВЫЙ сегмент. Пробелы и кириллицу оставляем: хранилище их
 * принимает, а «отчёт за март.pdf» человеку понятнее, чем otchet-za-mart.pdf.
 */
export function safeName(name) {
  const cleaned = name.replace(/[/\\]/g, '-').replace(/^\.+/, '').trim()
  return cleaned || 'файл'
}

/** Уникальность без потери имени: `отчёт.pdf` → `отчёт (2).pdf`. */
export function uniqueName(name, taken) {
  if (!taken.has(name)) return name
  const dot = name.lastIndexOf('.')
  const [stem, ext] = dot > 0 ? [name.slice(0, dot), name.slice(dot)] : [name, '']
  for (let n = 2; ; n++) {
    const candidate = `${stem} (${n})${ext}`
    if (!taken.has(candidate)) return candidate
  }
}

export async function listMine(user) {
  const { data, error } = await db.storage
    .from(PRIVATE)
    .list(folderOf(user), { limit: 200, sortBy: { column: 'created_at', order: 'desc' } })
  if (error) throw error
  // Подпапок мы не заводим, но клиент отличает их по пустому id — на всякий
  // случай отфильтруем, чтобы папка не притворилась файлом нулевого размера.
  return (data || []).filter((row) => row.id)
}

export async function upload(user, file, name) {
  const { error } = await db.storage
    .from(PRIVATE)
    .upload(`${folderOf(user)}/${name}`, file, {
      cacheControl: '3600',
      contentType: file.type || 'application/octet-stream',
    })
  if (error) throw error
}

export async function remove(user, name) {
  const { error } = await db.storage.from(PRIVATE).remove([`${folderOf(user)}/${name}`])
  if (error) throw error
}

/**
 * Ссылка на приватный файл — подписанная и на час.
 *
 * Именно так и надо делиться приватным: не делая файл публичным. Ссылка
 * протухнет сама, а бакет останется закрытым.
 */
export async function shareLink(user, name, seconds = 3600) {
  const { data, error } = await db.storage
    .from(PRIVATE)
    .createSignedUrl(`${folderOf(user)}/${name}`, seconds)
  if (error) throw error
  return data.signedUrl
}

/**
 * Опубликовать — это копия в публичный бакет, а не «снять галочку приватности».
 *
 * Разница принципиальна: оригинал остаётся закрытым, публикуется отдельный
 * объект, и отозвать публикацию можно, не трогая исходный файл.
 */
export async function publish(user, name) {
  const target = `${folderOf(user)}/${name}`
  const { error } = await db.storage.from(PRIVATE).copy(target, target, {
    destinationBucket: PUBLIC,
  })
  if (error && error.message && !/already exists/i.test(error.message)) throw error
  return publicLink(user, name)
}

export async function unpublish(user, name) {
  const { error } = await db.storage.from(PUBLIC).remove([`${folderOf(user)}/${name}`])
  if (error) throw error
}

export function publicLink(user, name) {
  const { data } = db.storage.from(PUBLIC).getPublicUrl(`${folderOf(user)}/${name}`)
  return data.publicUrl
}

export async function listPublished(user) {
  const { data, error } = await db.storage.from(PUBLIC).list(folderOf(user), { limit: 200 })
  if (error) throw error
  return new Set((data || []).filter((r) => r.id).map((r) => r.name))
}

/** Витрина: последние опубликованные файлы ВСЕХ пользователей. */
export async function gallery() {
  const { data, error } = await db.storage.from(PUBLIC).list('', { limit: 60 })
  if (error) throw error
  const folders = (data || []).filter((row) => !row.id).map((row) => row.name)
  const found = []
  for (const folder of folders) {
    const { data: inner } = await db.storage
      .from(PUBLIC)
      .list(folder, { limit: 20, sortBy: { column: 'created_at', order: 'desc' } })
    for (const row of (inner || []).filter((r) => r.id)) {
      const { data: url } = db.storage.from(PUBLIC).getPublicUrl(`${folder}/${row.name}`)
      found.push({ ...row, folder, url: url.publicUrl })
    }
  }
  return found.sort((a, b) => (b.created_at || '').localeCompare(a.created_at || ''))
}

export function humanSize(bytes) {
  if (!Number.isFinite(bytes)) return '—'
  const units = ['Б', 'КБ', 'МБ', 'ГБ']
  let value = bytes
  let unit = 0
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024
    unit++
  }
  return `${value < 10 && unit > 0 ? value.toFixed(1) : Math.round(value)} ${units[unit]}`
}

export function isImage(row) {
  return String(row?.metadata?.mimetype || '').startsWith('image/')
}

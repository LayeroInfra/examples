-- Полка: бакеты и политики доступа к файлам.
--
-- Выполнять в редакторе запросов панели Layero (или psql к своей базе) ПОСЛЕ
-- того, как у базы включены API, авторизация и хранилище.
--
-- 🚨 ГЛАВНОЕ, РАДИ ЧЕГО ЭТОТ ФАЙЛ СУЩЕСТВУЕТ: приложение не проверяет права.
-- Ни строчки «а свой ли это файл» в JavaScript нет и быть не должно — код в
-- браузере читает и правит любой посетитель. Кто что может, решают политики
-- ниже, и решают в базе.
--
-- Политики написаны в форме Supabase: те же storage.objects, тот же
-- storage.foldername(), тот же auth.uid().
--
-- 🚨 РОЛЬ ПИШЕТСЯ НЕ `authenticated`, И ЭТО ПЕРВОЕ, ОБО ЧТО СПОТЫКАЮТСЯ.
-- В Postgres роли КЛАСТЕРНЫЕ, а на шарде живут сотни чужих баз: глобальная
-- `authenticated` означала бы роль одного арендатора внутри базы другого.
-- Поэтому у каждой базы свои роли — `u_<hex>_<слаг>_anon` / `_auth` / `_svc`,
-- и `CREATE POLICY ... TO authenticated` отвечает «role does not exist».
--
-- Вписывать своё имя руками не нужно: блок ниже находит роли сам и собирает
-- политики через format(). Копируется в любую базу Layero как есть.
--
-- (Дамп, приезжающий с Supabase, переписывает импортёр — там `TO
-- authenticated` подменяется автоматически. Здесь SQL пишется руками, поэтому
-- подменяем сами.)

-- ── Бакеты ───────────────────────────────────────────────────────────────
--
-- Приватный. Потолок на файл — 20 МБ: полка для документов и картинок, а не
-- файлообменник. Потолок стоит у БАКЕТА, то есть проверяется до чтения тела.
INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES ('shelf', 'shelf', false, 20 * 1024 * 1024)
ON CONFLICT (id) DO NOTHING;

-- Публичная витрина. `public = true` означает «раздаётся без ключа» — это
-- сказано вслух здесь, а не подразумевается кодом страницы.
INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES ('shelf-public', 'shelf-public', true, 20 * 1024 * 1024)
ON CONFLICT (id) DO NOTHING;

-- ── Приватная полка: своя папка и только своя ────────────────────────────
--
-- Первый сегмент пути — это id пользователя. `storage.foldername(name)`
-- возвращает массив сегментов без имени файла, поэтому [1] — папка верхнего
-- уровня. Сравниваем её с auth.uid() — и чужая папка не видна ВООБЩЕ: не
-- «нельзя скачать», а не существует с точки зрения запроса.
--
-- Четыре политики, а не одна на ALL: читать, класть, менять и удалять — это
-- четыре разных права, и однажды они разойдутся (например, удаление захочется
-- запретить). Разложенные заранее, они не потребуют переписывания.

DO $do$
DECLARE
  -- Роль вошедшего пользователя ЭТОЙ базы. Ищем по двум признакам сразу:
  -- имя оканчивается на `_auth` И роль имеет право подключаться именно сюда.
  -- Одного имени мало: на шарде живут роли сотен чужих баз, и совпадение по
  -- суффиксу выбрало бы чужую.
  r_auth text := (SELECT rolname FROM pg_roles
                   WHERE rolname LIKE 'u\_%\_auth'
                     AND has_database_privilege(rolname, current_database(), 'CONNECT')
                   LIMIT 1);
  own text := '(storage.foldername(name))[1] = auth.uid()::text';
BEGIN
  IF r_auth IS NULL THEN
    RAISE EXCEPTION 'не нашлась роль вошедшего (…_auth). Включена ли авторизация у базы?';
  END IF;
  RAISE NOTICE 'роль вошедшего: %', r_auth;

  -- Четыре политики, а не одна на ALL: читать, класть, менять и удалять — это
  -- четыре разных права, и однажды они разойдутся (например, удаление
  -- захочется запретить). Разложенные заранее, они не потребуют переписывания.
  EXECUTE format(
    'DROP POLICY IF EXISTS "полка: вижу свои" ON storage.objects');
  EXECUTE format(
    'CREATE POLICY "полка: вижу свои" ON storage.objects FOR SELECT TO %I '
    'USING (bucket_id = ''shelf'' AND %s)', r_auth, own);

  EXECUTE format(
    'DROP POLICY IF EXISTS "полка: кладу к себе" ON storage.objects');
  EXECUTE format(
    'CREATE POLICY "полка: кладу к себе" ON storage.objects FOR INSERT TO %I '
    'WITH CHECK (bucket_id = ''shelf'' AND %s)', r_auth, own);

  EXECUTE format(
    'DROP POLICY IF EXISTS "полка: правлю свои" ON storage.objects');
  EXECUTE format(
    'CREATE POLICY "полка: правлю свои" ON storage.objects FOR UPDATE TO %I '
    'USING (bucket_id = ''shelf'' AND %s) '
    'WITH CHECK (bucket_id = ''shelf'' AND %s)', r_auth, own, own);

  EXECUTE format(
    'DROP POLICY IF EXISTS "полка: удаляю свои" ON storage.objects');
  EXECUTE format(
    'CREATE POLICY "полка: удаляю свои" ON storage.objects FOR DELETE TO %I '
    'USING (bucket_id = ''shelf'' AND %s)', r_auth, own);

  -- ── Витрина: читают все, публикует только владелец ─────────────────────
  --
  -- Чтение открыто ВСЕМ ролям (`TO public` — это встроенная псевдороль
  -- Postgres «кто угодно», а не наша анонимная): витрина показывается до
  -- входа, а картинки в <img src> браузер запрашивает вообще без заголовков.
  EXECUTE format(
    'DROP POLICY IF EXISTS "витрина: видно всем" ON storage.objects');
  EXECUTE format(
    'CREATE POLICY "витрина: видно всем" ON storage.objects FOR SELECT '
    'TO public USING (bucket_id = ''shelf-public'')');

  EXECUTE format(
    'DROP POLICY IF EXISTS "витрина: публикую своё" ON storage.objects');
  EXECUTE format(
    'CREATE POLICY "витрина: публикую своё" ON storage.objects FOR INSERT '
    'TO %I WITH CHECK (bucket_id = ''shelf-public'' AND %s)', r_auth, own);

  EXECUTE format(
    'DROP POLICY IF EXISTS "витрина: снимаю своё" ON storage.objects');
  EXECUTE format(
    'CREATE POLICY "витрина: снимаю своё" ON storage.objects FOR DELETE '
    'TO %I USING (bucket_id = ''shelf-public'' AND %s)', r_auth, own);
END
$do$;

-- ── Проверка, которую стоит сделать руками ───────────────────────────────
--
-- Политику легко написать так, что она выглядит рабочей и открыта всем.
-- Единственная честная проверка — попробовать чужим:
--
--   1. зайти вторым пользователем;
--   2. открыть в консоли браузера
--        await db.storage.from('shelf').list('<id ПЕРВОГО пользователя>')
--      — ожидается пустой список, а не отказ и не чужие файлы;
--   3. попробовать скачать чужой файл по прямому пути
--        await db.storage.from('shelf').download('<чужой id>/<имя>')
--      — ожидается «Object not found».
--
-- Пустой список и «не найдено» — правильные ответы: политика не различает
-- «нет прав» и «нет файла», и не должна. Разница между ними — оракул,
-- отвечающий перебирающему «здесь что-то есть».

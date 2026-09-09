-- Большая игра: темы × номиналы. Данные в app, поверхность — только функции.
--
-- 🚨 Участнику НЕ ВЫДАНО НИ ОДНОГО ГРАНТА на таблицы. Ответы лежат в
-- app.cells.answer, и прочитать их анонимным ключом нельзя ничем: ни REST, ни
-- перебором. Это и есть то, что проверяется приёмкой, а не «в приложении так
-- не сделано».

CREATE SCHEMA IF NOT EXISTS app;

DROP TABLE IF EXISTS app.answers, app.players, app.cells, app.themes, app.games CASCADE;

CREATE TABLE app.games (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code           text UNIQUE NOT NULL,
  title          text NOT NULL,
  operator_token text NOT NULL,
  status         text NOT NULL DEFAULT 'lobby',   -- lobby | playing | finished
  current_cell   uuid,
  -- 🚨 МОМЕНТ ПОКАЗА, А НЕ МОМЕНТ ПРИХОДА ПАКЕТА. Вопрос не отдаётся никому,
  -- пока не наступило это время, и наступает оно у всех одновременно —
  -- по часам сервера. Иначе выигрывает тот, у кого короче сеть.
  reveal_at      timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE app.themes (
  id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  game_id  uuid NOT NULL REFERENCES app.games(id) ON DELETE CASCADE,
  title    text NOT NULL,
  position int  NOT NULL
);

CREATE TABLE app.cells (
  id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  theme_id uuid NOT NULL REFERENCES app.themes(id) ON DELETE CASCADE,
  value    int  NOT NULL,
  question text NOT NULL,
  answer   text NOT NULL,
  state    text NOT NULL DEFAULT 'closed'         -- closed | open | done
);

CREATE TABLE app.players (
  id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  game_id   uuid NOT NULL REFERENCES app.games(id) ON DELETE CASCADE,
  name      text NOT NULL,
  token     text NOT NULL,
  score     int  NOT NULL DEFAULT 0,
  joined_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (game_id, token)
);

CREATE TABLE app.answers (
  id           bigserial PRIMARY KEY,
  cell_id      uuid NOT NULL REFERENCES app.cells(id) ON DELETE CASCADE,
  player_id    uuid NOT NULL REFERENCES app.players(id) ON DELETE CASCADE,
  text         text NOT NULL,
  -- Миллисекунды ОТ МОМЕНТА ПОКАЗА, считает сервер. Не «когда пришло», а
  -- «сколько думал»: у всех отсчёт от одного и того же мгновения.
  ms           int  NOT NULL,
  correct      boolean NOT NULL,
  submitted_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (cell_id, player_id)                     -- один ответ на клетку
);

CREATE INDEX ON app.themes (game_id, position);
CREATE INDEX ON app.cells (theme_id, value);
CREATE INDEX ON app.players (game_id, score DESC);
-- ── Нормализация ответа ────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION app.norm(t text) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path = '' AS $$
  SELECT pg_catalog.btrim(
           pg_catalog.regexp_replace(
             pg_catalog.replace(pg_catalog.lower(coalesce(t,'')), 'ё', 'е'),
             '[^a-zа-я0-9 ]', '', 'g'))
$$;

-- ── Создать игру из пакета ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION api.quiz_new(p_title text, p_pack jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE g_id uuid; g_code text; op text; th jsonb; c jsonb; t_id uuid; pos int := 0;
BEGIN
  IF pg_catalog.jsonb_typeof(p_pack) <> 'array' OR pg_catalog.jsonb_array_length(p_pack) = 0 THEN
    RAISE EXCEPTION 'Пакет пуст: ожидается массив тем';
  END IF;
  -- Код короткий и читается вслух: его диктуют в комнате.
  g_code := pg_catalog.upper(pg_catalog.substr(pg_catalog.encode(public.gen_random_bytes(8),'hex'), 1, 6));
  op     := pg_catalog.encode(public.gen_random_bytes(24), 'hex');
  INSERT INTO app.games (code, title, operator_token) VALUES (g_code, p_title, op) RETURNING id INTO g_id;

  FOR th IN SELECT * FROM pg_catalog.jsonb_array_elements(p_pack) LOOP
    pos := pos + 1;
    INSERT INTO app.themes (game_id, title, position)
    VALUES (g_id, th ->> 'theme', pos) RETURNING id INTO t_id;
    FOR c IN SELECT * FROM pg_catalog.jsonb_array_elements(th -> 'cells') LOOP
      INSERT INTO app.cells (theme_id, value, question, answer)
      VALUES (t_id, (c ->> 'value')::int, c ->> 'q', c ->> 'a');
    END LOOP;
  END LOOP;

  RETURN pg_catalog.jsonb_build_object('code', g_code, 'operator_token', op, 'title', p_title);
END $$;

-- ── Присоединиться ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION api.quiz_join(p_code text, p_name text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE g app.games; tok text; p_id uuid; nm text;
BEGIN
  SELECT * INTO g FROM app.games WHERE code = pg_catalog.upper(pg_catalog.btrim(p_code));
  IF g.id IS NULL THEN RAISE EXCEPTION 'Игры с таким кодом нет'; END IF;
  nm := pg_catalog.btrim(coalesce(p_name, ''));
  IF pg_catalog.length(nm) < 1 OR pg_catalog.length(nm) > 24 THEN
    RAISE EXCEPTION 'Имя от одного до двадцати четырёх символов';
  END IF;
  IF pg_catalog.length(nm) > 0 AND EXISTS (SELECT 1 FROM app.players WHERE game_id = g.id AND app.norm(name) = app.norm(nm)) THEN
    RAISE EXCEPTION 'Это имя уже занято — возьмите другое';
  END IF;
  tok := pg_catalog.encode(public.gen_random_bytes(18), 'hex');
  INSERT INTO app.players (game_id, name, token) VALUES (g.id, nm, tok) RETURNING id INTO p_id;
  RETURN pg_catalog.jsonb_build_object('player_token', tok, 'name', nm, 'title', g.title);
END $$;

-- ── Состояние для УЧАСТНИКА ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION api.quiz_state(p_code text, p_token text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE g app.games; me app.players; cur jsonb; revealed boolean;
BEGIN
  SELECT * INTO g FROM app.games WHERE code = pg_catalog.upper(pg_catalog.btrim(p_code));
  IF g.id IS NULL THEN RAISE EXCEPTION 'Игры с таким кодом нет'; END IF;
  SELECT * INTO me FROM app.players WHERE game_id = g.id AND token = p_token;
  IF me.id IS NULL THEN RAISE EXCEPTION 'Вы не в этой игре — присоединитесь заново'; END IF;

  revealed := g.reveal_at IS NOT NULL AND pg_catalog.now() >= g.reveal_at;

  -- 🚨 ВОПРОС НЕ ОТДАЁТСЯ, ПОКА НЕ НАСТУПИЛ МОМЕНТ ПОКАЗА, и `answer` не
  -- отдаётся участнику никогда. Проверять это на клиенте было бы то же
  -- самое, что не проверять.
  SELECT pg_catalog.jsonb_build_object(
           'id', c.id, 'value', c.value, 'theme', t.title,
           'question', CASE WHEN revealed THEN c.question END,
           'answered', EXISTS (SELECT 1 FROM app.answers a WHERE a.cell_id = c.id AND a.player_id = me.id))
    INTO cur
    FROM app.cells c JOIN app.themes t ON t.id = c.theme_id
   WHERE c.id = g.current_cell;

  RETURN pg_catalog.jsonb_build_object(
    'server_now', pg_catalog.now(),
    'status',     g.status,
    'title',      g.title,
    'reveal_at',  g.reveal_at,
    'revealed',   revealed,
    'cell',       cur,
    'me',         pg_catalog.jsonb_build_object('name', me.name, 'score', me.score),
    'board', (SELECT pg_catalog.jsonb_agg(x ORDER BY x ->> 'position')
                FROM (SELECT pg_catalog.jsonb_build_object(
                               'theme', t.title, 'position', t.position,
                               'cells', (SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                                                  'id', c.id, 'value', c.value, 'state', c.state) ORDER BY c.value)
                                           FROM app.cells c WHERE c.theme_id = t.id)) AS x
                        FROM app.themes t WHERE t.game_id = g.id) s),
    'scores', (SELECT coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('name', p.name, 'score', p.score)
                        ORDER BY p.score DESC, p.joined_at), '[]'::jsonb)
                 FROM app.players p WHERE p.game_id = g.id));
END $$;

-- ── Ответ участника ────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION api.quiz_answer(p_code text, p_token text, p_text text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE g app.games; me app.players; c app.cells; ok boolean; delay int;
BEGIN
  SELECT * INTO g FROM app.games WHERE code = pg_catalog.upper(pg_catalog.btrim(p_code));
  IF g.id IS NULL THEN RAISE EXCEPTION 'Игры с таким кодом нет'; END IF;
  SELECT * INTO me FROM app.players WHERE game_id = g.id AND token = p_token;
  IF me.id IS NULL THEN RAISE EXCEPTION 'Вы не в этой игре'; END IF;
  IF g.current_cell IS NULL OR g.reveal_at IS NULL OR pg_catalog.now() < g.reveal_at THEN
    RAISE EXCEPTION 'Вопрос ещё не показан';
  END IF;
  SELECT * INTO c FROM app.cells WHERE id = g.current_cell;
  IF c.state <> 'open' THEN RAISE EXCEPTION 'Приём ответов на этот вопрос закрыт'; END IF;

  ok    := app.norm(p_text) = app.norm(c.answer);
  delay := pg_catalog.floor(extract(epoch FROM (pg_catalog.now() - g.reveal_at)) * 1000)::int;

  -- Один ответ на клетку: повтор — отказ, а не тихая перезапись.
  INSERT INTO app.answers (cell_id, player_id, text, ms, correct)
  VALUES (c.id, me.id, pg_catalog.btrim(coalesce(p_text,'')), delay, ok);

  RETURN pg_catalog.jsonb_build_object('accepted', true, 'ms', delay);
EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'Вы уже отвечали на этот вопрос';
END $$;
-- ── Доска ОПЕРАТОРА: вопросы и ответы видит только он ──────────────────────
CREATE OR REPLACE FUNCTION api.quiz_board(p_code text, p_op text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE g app.games;
BEGIN
  SELECT * INTO g FROM app.games WHERE code = pg_catalog.upper(pg_catalog.btrim(p_code));
  -- Сравнение в постоянном времени: подбирать токен по времени ответа нельзя.
  IF g.id IS NULL OR NOT public.hmac(g.operator_token,'k','sha256') = public.hmac(coalesce(p_op,''),'k','sha256') THEN
    RAISE EXCEPTION 'Не ваша игра';
  END IF;
  RETURN pg_catalog.jsonb_build_object(
    'server_now', pg_catalog.now(),
    'title', g.title, 'code', g.code, 'status', g.status,
    'reveal_at', g.reveal_at, 'current_cell', g.current_cell,
    'revealed', g.reveal_at IS NOT NULL AND pg_catalog.now() >= g.reveal_at,
    'board', (SELECT pg_catalog.jsonb_agg(x ORDER BY x ->> 'position')
                FROM (SELECT pg_catalog.jsonb_build_object(
                               'theme', t.title, 'position', t.position,
                               'cells', (SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                                                  'id', c.id, 'value', c.value, 'state', c.state,
                                                  'question', c.question, 'answer', c.answer) ORDER BY c.value)
                                           FROM app.cells c WHERE c.theme_id = t.id)) AS x
                        FROM app.themes t WHERE t.game_id = g.id) s),
    'players', (SELECT pg_catalog.count(*) FROM app.players p WHERE p.game_id = g.id),
    'scores', (SELECT coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('name', p.name, 'score', p.score)
                        ORDER BY p.score DESC, p.joined_at), '[]'::jsonb)
                 FROM app.players p WHERE p.game_id = g.id),
    -- Ответы на текущую клетку — оператору видно, кто что написал и за сколько.
    'answers', (SELECT coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                          'name', p.name, 'text', a.text, 'ms', a.ms, 'correct', a.correct) ORDER BY a.ms), '[]'::jsonb)
                  FROM app.answers a JOIN app.players p ON p.id = a.player_id
                 WHERE a.cell_id = g.current_cell));
END $$;

-- ── Открыть клетку ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION api.quiz_open(p_code text, p_op text, p_cell uuid, p_delay_ms int DEFAULT 3000)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE g app.games; c app.cells; at timestamptz; d int;
BEGIN
  SELECT * INTO g FROM app.games WHERE code = pg_catalog.upper(pg_catalog.btrim(p_code));
  IF g.id IS NULL OR NOT public.hmac(g.operator_token,'k','sha256') = public.hmac(coalesce(p_op,''),'k','sha256') THEN
    RAISE EXCEPTION 'Не ваша игра';
  END IF;
  SELECT c.* INTO c FROM app.cells c JOIN app.themes t ON t.id = c.theme_id
   WHERE c.id = p_cell AND t.game_id = g.id;
  IF c.id IS NULL THEN RAISE EXCEPTION 'Такой клетки в этой игре нет'; END IF;
  IF c.state = 'done' THEN RAISE EXCEPTION 'Эта клетка уже сыграна'; END IF;

  -- Задержка показа — это и есть справедливость. Меньше секунды не даём:
  -- участник должен успеть получить `reveal_at` и подгадать опрос к нему.
  d  := greatest(1000, least(coalesce(p_delay_ms, 3000), 30000));
  at := pg_catalog.now() + (d || ' milliseconds')::interval;

  UPDATE app.cells SET state = 'open' WHERE id = c.id;
  UPDATE app.games SET current_cell = c.id, reveal_at = at, status = 'playing' WHERE id = g.id;
  RETURN pg_catalog.jsonb_build_object('reveal_at', at, 'server_now', pg_catalog.now(), 'delay_ms', d);
END $$;

-- ── Закрыть клетку и начислить ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION api.quiz_close(p_code text, p_op text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE g app.games; c app.cells; awarded int := 0;
BEGIN
  SELECT * INTO g FROM app.games WHERE code = pg_catalog.upper(pg_catalog.btrim(p_code));
  IF g.id IS NULL OR NOT public.hmac(g.operator_token,'k','sha256') = public.hmac(coalesce(p_op,''),'k','sha256') THEN
    RAISE EXCEPTION 'Не ваша игра';
  END IF;
  IF g.current_cell IS NULL THEN RAISE EXCEPTION 'Открытой клетки нет'; END IF;
  SELECT * INTO c FROM app.cells WHERE id = g.current_cell;

  -- Начисляем ОДИН РАЗ: клетка переходит в `done`, и повторный вызов сюда
  -- уже не дойдёт. Иначе двойной клик оператора удваивал бы очки.
  IF c.state = 'open' THEN
    UPDATE app.players p SET score = p.score + c.value
      FROM app.answers a
     WHERE a.player_id = p.id AND a.cell_id = c.id AND a.correct;
    GET DIAGNOSTICS awarded = ROW_COUNT;
    UPDATE app.cells SET state = 'done' WHERE id = c.id;
  END IF;
  UPDATE app.games SET current_cell = NULL, reveal_at = NULL WHERE id = g.id;

  RETURN pg_catalog.jsonb_build_object(
    'answer', c.answer, 'awarded', awarded,
    'left', (SELECT pg_catalog.count(*) FROM app.cells cc JOIN app.themes t ON t.id = cc.theme_id
              WHERE t.game_id = g.id AND cc.state <> 'done'));
END $$;

-- ── Гранты ─────────────────────────────────────────────────────────────────
-- 🚨 СНАЧАЛА ОТБИРАЕМ У PUBLIC. Postgres выдаёт PUBLIC право выполнять каждую
-- новую функцию, а шлюз такую функцию не пускает вовсе (`public_execute_only`):
-- «открыта всем по умолчанию» — это недосмотр, а не доступ.

REVOKE EXECUTE ON FUNCTION
  api.quiz_new(text, jsonb), api.quiz_join(text, text), api.quiz_state(text, text),
  api.quiz_answer(text, text, text), api.quiz_board(text, text),
  api.quiz_open(text, text, uuid, int), api.quiz_close(text, text)
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION
  api.quiz_join(text, text), api.quiz_state(text, text), api.quiz_answer(text, text, text),
  api.quiz_board(text, text), api.quiz_open(text, text, uuid, int), api.quiz_close(text, text)
TO u_3ac64753f4154839b7615b7dba8742f4_polka_anon;

-- `quiz_new` анониму НЕ выдаём: игру заводит владелец секретным ключом.
GRANT EXECUTE ON FUNCTION api.quiz_new(text, jsonb) TO u_3ac64753f4154839b7615b7dba8742f4_polka_svc;

-- 🚨 И НИ ОДНОГО ГРАНТА НА ТАБЛИЦЫ. Проверяется это не глазами, а запросом:
-- REST по app.cells анонимным ключом обязан отвечать отказом.
-- ── Лёгкий общий опрос: то, что спрашивают ВСЕ и ОДНОВРЕМЕННО ──────────────
--
-- 🚨 РАЗДЕЛЕНИЕ ПО ФОРМЕ НАГРУЗКИ, А НЕ ПО УДОБСТВУ. В момент показа сорок
-- участников спрашивают ОДНО И ТО ЖЕ и получают одинаковый ответ: вопрос
-- общий по построению — показать его значит показать всем. Доска, счета и
-- «отвечал ли я» в это мгновение не меняются вовсе, а стоят четырёх агрегатов
-- по всей игре. Мы платили ими сорок раз за секунду ради одной строки.
--
-- Отсюда две ручки вместо одной: эта — крошечная и без токена, её зовут
-- залпом ровно в момент показа; `quiz_state` — полная, её зовут лениво.
--
-- ⚠️ Токен здесь НЕ НУЖЕН, и это не послабление: ответ не содержит ничего
-- личного, а вопрос после показа публичен по смыслу игры. Заодно это делает
-- ответ пригодным для общего кеша — сегодня мы им не пользуемся, но форма
-- ответа больше не мешает.
CREATE OR REPLACE FUNCTION api.quiz_watch(p_code text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT pg_catalog.jsonb_build_object(
           'server_now', pg_catalog.now(),
           'status',     g.status,
           'reveal_at',  g.reveal_at,
           'revealed',   g.reveal_at IS NOT NULL AND pg_catalog.now() >= g.reveal_at,
           'cell', (SELECT pg_catalog.jsonb_build_object(
                             'id', c.id, 'value', c.value, 'theme', t.title,
                             'question', CASE WHEN pg_catalog.now() >= g.reveal_at
                                              THEN c.question END)
                      FROM app.cells c JOIN app.themes t ON t.id = c.theme_id
                     WHERE c.id = g.current_cell))
    FROM app.games g
   WHERE g.code = pg_catalog.upper(pg_catalog.btrim(p_code));
$$;

REVOKE EXECUTE ON FUNCTION api.quiz_watch(text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION api.quiz_watch(text) TO u_3ac64753f4154839b7615b7dba8742f4_polka_anon;

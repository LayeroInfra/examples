# Стенд проверки входа

Шесть сайтов, по одному на способ входа, у каждого своя база, где включён
только этот способ.

| Способ | Сайт | База |
|---|---|---|
| Почта и пароль | https://auth-password.layero.app | auth-password |
| Ссылка из письма | https://auth-link.layero.app | auth-link |
| Код из письма | https://auth-code.layero.app | auth-code |
| Яндекс | https://auth-oauth-ya.layero.app | auth-yandex |
| VK ID | https://auth-oauth-vk.layero.app | auth-vkid |
| Сбер ID | https://auth-oauth-sb.layero.app | auth-sber |

Сайт один — `index.html`; какой способ показывать, говорит `config.json`,
который кладёт `stand.py`. Второй фактор включён у всех баз: подключается на
любом сайте после входа.

```bash
python3 stand.py up        # завести недостающее (повторный запуск безопасен)
python3 stand.py status    # адреса и готовность провайдеров
python3 check.py           # автопроверка всех способов через настоящий адрес
```

`check.py` шлёт письма на адрес-имитатор почтового сервиса (людям ничего не
приходит), а ссылку и код берёт из очереди писем платформы — нужен ssh на
прод. Провайдеров проверяет до страницы провайдера; сам вход — руками.

Ключи сайтов — в `~/.layero/auth-stand.json`, в git не идут. Организация
`valya` держит базы стенда бесплатно: настройка `userdb_shared_extra_orgs`.

# BULLIT — автобилды и раздача плейтест-версий

Пуш в ветку `playtest` → GitHub Actions собирает Windows-билд → публикует
GitHub Release → лаунчер у каждого тестера сам качает обновление и запускает
игру. Это раздача билдов; сетевой код игры — отдельное ТЗ.

## Как это устроено

1. **`.github/workflows/build.yml`** — на пуш в `playtest`:
   скачивает Godot 4.7 + export templates, импортирует ресурсы, экспортирует
   пресет «Windows Desktop» (`export_presets.cfg`, embed_pck — один exe),
   прогоняет headless smoke-тесты, пакует `bullit_win.zip` (внутри
   `bullit.exe` + `version.txt`) и публикует релиз `playtest-<дата>-<коммит>`.
2. **`tools/launcher/`** — мини-лаунчер (отдельный от игры):
   `launcher.bat` → `launcher.ps1`: берёт последний релиз через GitHub API,
   сравнивает `tag` с локальным `game/version.txt`, при отличии качает
   `bullit_win.zip`, распаковывает в `game/` и запускает `game/bullit.exe`.

## Настройка (один раз, хост)

1. Запушить репозиторий на GitHub (текущий remote: `Fijekronk/bullit`).
   Если имя репо другое — поправить `$Repo` в `tools/launcher/launcher.ps1`.
2. Secrets НЕ нужны: релиз публикуется встроенным `GITHUB_TOKEN`
   (в workflow уже стоит `permissions: contents: write`).
3. Создать ветку и запушить:
   ```
   git checkout -b playtest
   git push -u origin playtest
   ```
4. Проверить: вкладка Actions → зелёный прогон → в Releases появился
   `playtest-...` с `bullit_win.zip`.
5. Дальше: `git push origin <ветка>:playtest` — каждый пуш = новый релиз.

## Установка у друга (один раз)

1. Скачать из репозитория папку `tools/launcher/` (два файла:
   `launcher.bat`, `launcher.ps1`) в любую пустую папку.
   Если репозиторий приватный — прислать файлы напрямую, они маленькие.
2. Запускать игру ТОЛЬКО через `launcher.bat`: он сам качает свежий билд
   при каждом запуске (если есть новый) и стартует игру.
3. Никаких ручных перекидываний файлов: новый пуш хоста в `playtest` —
   при следующем запуске лаунчер обновится сам.

Примечание для приватного репо: GitHub API без токена не отдаст релизы —
либо сделать репо публичным, либо в `launcher.ps1` добавить к `$headers`
строку `Authorization = "Bearer <token>"` (fine-grained token, только
чтение Releases).

## Проверка обновления вручную

1. Запустить `launcher.bat` — игра скачается и стартует.
2. В `game/version.txt` подменить строку на `test-old` и снова запустить
   лаунчер: версия не совпадает → он перекачает свежий билд и перезапишет
   `version.txt` реальной версией релиза.

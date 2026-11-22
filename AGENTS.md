# YAMP: сведения для агентов

YAMP (Yet Another Music Player): неофициальный клиент Яндекс Музыки для
компьютера и телефона. Лицензия GPL-3.0, репозиторий TheGreatPepix/YAMP.
Вся документация и строки интерфейса на русском языке.

## Архитектура

Приложение состоит из двух частей: ядра на Go (`ymcore`) и окна на Flutter
(`app/`). Вся бизнес-логика живёт в ядре, окно только рисует интерфейс и
воспроизводит звук.

Протокол между ядром и окном: JSON-строки, одна строка, один объект. Окно
отправляет команды (`{"cmd": "play", ...}`), ядро присылает события
(`{"type": "account", ...}`).

- Десктоп (Windows, Linux, macOS): ядро запускается как дочерний процесс
  `cmd/ymcore`. Окно ищет исполняемый файл `ymcore.exe` или `ymcore` рядом с
  собой (переопределение переменной окружения `YMCORE`) и общается с ним через
  stdin/stdout. Если ядро не найдено, окно показывает ошибку. См.
  `app/lib/core/core.dart` (ProcessCore) и `cmd/ymcore/main.go`.
- Android: то же ядро собирается в AAR через gomobile из модуля `mobile/`
  (`gomobile bind -javapkg ru.yamp.core`), лежит в
  `app/android/app/libs/ymcore.aar` (каталог в .gitignore). Dart-сторона:
  `app/lib/core/android_core.dart`, Kotlin-мост:
  `app/android/app/src/main/kotlin/ru/yamp/app/`.
- В Dart ядро скрыто за абстракцией `Core` с тремя реализациями: ProcessCore
  (десктоп), AndroidCore (Android), FakeCore (демо-режим по флагу `--demo` или
  `YMD_DEMO`, а также все виджет-тесты).

Воспроизведение: очередь треков ведёт ядро, окно лишь сообщает ему события
плеера (`playerNext`, `playerEnded`, `playerPosition` и т.д.). Звук играет
через media_kit (libmpv) с локального HTTP-сервера ядра на 127.0.0.1 со
случайным префиксом пути (`internal/gui/stream.go`). На Android фоновое
воспроизведение и уведомление делает Kotlin PlaybackService.

### Модули Go (internal/)

- `yam`: клиент API Яндекс Музыки (api.music.yandex.net), вход по коду
  устройства через oauth.yandex.ru, разбор ссылок, поиск, главная, библиотека,
  текст песен, Моя волна, ссылки на потоки, загрузка: remux FLAC из MP4,
  теги ID3v2 и Vorbis comment, имена файлов.
- `player`: чистая логика очереди (repeat, shuffle), без сети и UI.
- `gui`: состояние приложения, разбор команд (`onMessage` в commands.go),
  менеджер загрузок с ограничением параллелизма (gate), настройки
  (config.json в каталоге `yamp` внутри os.UserConfigDir()), потоковый
  сервер, кеш треков для офлайна (SQLite через modernc.org/sqlite, индекс
  cache.db рядом с файлами, см. cache.go и cacher.go: качество и лимит в
  настройках, автокеширование треков после нескольких полных
  прослушиваний, LRU-вытеснение, отдача из кеша в потоковом сервере,
  источник «Скачанное»), Discord, вход по коду, восстановление очереди,
  хаб удалённого управления, самообновление. Здесь же `const Version`.
- `remote`: сервер удалённого управления по локальной сети: TCP с TLS,
  сопряжение телефона по QR-коду.
- `update`: проверка и установка обновлений с GitHub Releases, разборка по
  платформам, перезапуск процесса.
- `discord`: Rich Presence через локальный IPC (named pipe на Windows, сокет
  на Unix).

Точка входа ядра: `cmd/ymcore/main.go`; флаг `update.ApplyFlag` переводит
бинарник в режим применения обновления.

## Сборка и проверки

Инструменты: Go (go.mod: go 1.27) и Flutter (SDK ^3.8.0; на машине разработчика
лежит в `C:\src\flutter\bin`, в PATH не входит; в CI закреплён 3.47.9).

```sh
# Go: проверки и сборка ядра (из корня репозитория)
go vet ./...
go test ./...
go build -trimpath -ldflags "-s -w -H=windowsgui" -o dist-core/ymcore.exe ./cmd/ymcore

# Flutter: проверки и сборка окна (из каталога app/)
flutter pub get
flutter analyze
flutter test
flutter build windows --release   # или linux, macos
```

Android-сборка ядра (gomobile, нужен NDK 28.2.13676358):

```sh
cd mobile
gomobile bind -target=android/arm64,android/arm,android/amd64 -androidapi 24 \
  -javapkg ru.yamp.core -trimpath -ldflags "-s -w" \
  -o ../app/android/app/libs/ymcore.aar .
```

Проверено: `go vet ./...`, `go test ./...`, `go build ./...` и
`flutter analyze` проходят чисто.

## Тестирование

- Go-тесты есть во всех пакетах internal/, сеть не нужна (httptest,
  поддельные клиенты). Запуск: `go test ./...` из корня.
- Flutter-тесты в `app/test/` работают на FakeCore без ядра и без сети:
  widget_test, compact_test, player_test, remote_test, system_media_test,
  tint_test. Запуск: `flutter test` из `app/`.

## Стиль и соглашения

- Никаких комментариев в коде. Исключение: директивы сборки вроде
  `//go:build`.
- Никаких длинных тире (— и –) нигде: ни в коде, ни в строках интерфейса, ни
  в документации, ни в коммитах. Вместо них дефис, двоеточие, запятая или
  точка. Это правило распространяется и на AGENTS.md.
- Коммиты: одна короткая строка, без тела и без трейлеров (никаких
  `Co-Authored-By`).
- Имена и строки интерфейса на русском.

## Выпуск версии

1. Поднять версию X.Y.Z везде, где записана текущая:
   - `app/pubspec.yaml`: `version: X.Y.Z+N`, N на единицу больше прежнего;
   - `internal/gui/app.go`: `const Version = "X.Y.Z"`;
   - `app/lib/core/fake_core.dart`: все вхождения прежней версии;
   - `app/test/widget_test.dart`: все вхождения прежней версии.
   Проверка: `grep -rn "<старая>" app/lib app/test app/pubspec.yaml internal`.
2. Прогнать `go test ./...`, а в `app/`: `flutter analyze` и `flutter test`.
3. Закоммитить в `main` одной строкой, например
   `Tray and single instance, version X.Y.Z` или просто `Version X.Y.Z`.
4. Поставить лёгкий тег `vX.Y.Z` и запушить ветку и тег:
   `git push origin main` и `git push origin vX.Y.Z`.
5. Workflow `.github/workflows/build.yml` по тегу сам собирает Windows (zip),
   Linux (AppImage), macOS (dmg) и Android (APK split-per-abi) и выкладывает
   релиз с пустым описанием. Локальные результаты сборки кладутся в `dist/` и
   `dist-core/` (оба каталога в .gitignore).

Подпись Android: секреты GitHub `ANDROID_KEYSTORE`, `ANDROID_KEYSTORE_PASSWORD`,
`ANDROID_KEY_ALIAS`; копия ключа на машине разработчика в `~/.yamp-keys`
(алиас `yamp`, пароль в `key.properties`). Без секретов CI собирает APK
отладочной подписью.

## Безопасность и данные

- Токен Яндекса хранится только локально в config.json, телеметрии нет,
  связь идёт напрямую с Яндексом.
- Потоковый сервер слушает только 127.0.0.1 со случайным префиксом пути.
- Удалённое управление: шифрование TLS и сопряжение по QR, компьютер слушает
  только связанные телефоны.
- В исходниках зашиты clientID/clientSecret OAuth-приложения Яндекса
  (`internal/yam/oauth.go`): так устроен протокол, менять их не нужно.

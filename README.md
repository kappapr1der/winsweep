# Windows Cleanup Kit

Безопасный стартовый комплект для автоматической чистки системного диска Windows.

## Что чистит по умолчанию

- `%TEMP%` текущего пользователя.
- `%LOCALAPPDATA%\Temp`.
- `C:\Windows\Temp`.
- локальные отчеты об ошибках Windows.
- DirectX shader cache.
- раз в неделю в глубоком режиме: старый Windows Update download cache, Delivery Optimization cache и `DISM /StartComponentCleanup`.

## Что умеет дополнительно

- кеши браузеров Edge, Chrome, Brave и Firefox.
- кеш Spotify, включая классическую и Microsoft Store версии.
- кеши Discord, Slack, Telegram Desktop и Zoom.
- безопасную часть реестра: историю `Run`, недавние документы, typed paths, поиск Explorer, open/save dialog MRU.
- Jump Lists и недавние ярлыки Explorer.
- дополнительные cache/temp папки с других дисков через `extra-cache-paths.txt`.
- корзину, если явно включить.

## Что не трогает

- `Downloads`, `Desktop`, `Documents`, фото, видео, проекты.
- пароли, cookies, сессии браузера.
- папки программ целиком.
- `WinSxS` вручную. Для него используется только штатный DISM без `ResetBase`.
- агрессивную "починку" реестра, COM, драйверы, uninstall-записи и ассоциации файлов.

## Быстрый запуск

1. Запусти `setup-desktop-folder.bat`, чтобы создать папку `WinSweep` на рабочем столе и сразу поставить расписание.
2. Запусти `cleanup-smart-now.bat` для ручной чистки temp, Spotify cache и безопасной части реестра.
3. Запусти `cleanup-deep-now.bat` для глубокой чистки с запросом прав администратора.
4. Для проверки без удаления запусти `cleanup-preview.bat` или команду:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\cleanup-windows.ps1 -DryRun
```

`setup-desktop-folder.bat` по умолчанию ставит расписание с `-SpotifyCache -Registry -ExtraPaths`. Если хочешь шире, запускай:

```bat
setup-desktop-folder.bat -BrowserCaches -AppCaches
```

## Автоматическое расписание

Запусти `install-scheduled-cleanup.bat` от имени администратора. Он создаст задачи:

- `Light Noon` - каждый день около 12:35, с небольшим случайным сдвигом.
- `Light Evening` - каждый день около 22:45, с небольшим случайным сдвигом.
- `Deep Weekly` - каждое воскресенье около 03:20, с небольшим случайным сдвигом.

Задачи появятся в Планировщике задач по пути:

```text
\Codex Windows Cleanup\
```

Удалить расписание можно через `uninstall-scheduled-cleanup.bat`.

## Папка на рабочем столе

`setup-desktop-folder.bat` создает:

```text
Desktop\WinSweep
```

Внутри будут:

- `cleanup-smart-now.bat` - ручная умная чистка: temp, Spotify, безопасный registry cleanup.
- `cleanup-preview.bat` - preview без удаления.
- `cleanup-deep-now.bat` - глубокая чистка с правами администратора.
- `open-cleanup-logs.bat` - открыть папку логов.
- `install-scheduled-cleanup.bat` - переустановить расписание.
- `uninstall-scheduled-cleanup.bat` - удалить расписание.
- `extra-cache-paths.txt` - список дополнительных cache/temp папок на любых дисках.

## Опциональные режимы

Чистка кешей браузеров Edge, Chrome, Brave и Firefox:

```bat
cleanup-now.bat -CleanBrowserCaches
```

Чистка кеша Spotify:

```bat
cleanup-now.bat -CleanSpotifyCache
```

Важно: `Spotify\Data` может включать офлайн-загрузки Spotify. После чистки Spotify может заново скачать часть контента.

Чистка кешей популярных приложений, включая Spotify, Discord, Slack, Telegram Desktop и Zoom:

```bat
cleanup-now.bat -CleanAppCaches
```

Безопасная чистка реестра и истории Explorer с `.reg`-бэкапами:

```bat
cleanup-now.bat -CleanRegistry
```

Чистка дополнительных папок из `extra-cache-paths.txt`:

```bat
cleanup-now.bat -CleanExtraPaths
```

Пример содержимого `extra-cache-paths.txt`:

```text
D:\Temp
D:\Games\SomeLauncher\Cache
E:\Scratch\BuildCache
```

Не добавляй туда корень диска, `C:\Users`, `Documents`, `Desktop`, фото, проекты и любые папки, где могут быть единственные копии файлов.

Очистка корзины:

```bat
cleanup-now.bat -ClearRecycleBin
```

Можно включить эти опции и при установке расписания:

```bat
install-scheduled-cleanup.bat -BrowserCaches
install-scheduled-cleanup.bat -SpotifyCache
install-scheduled-cleanup.bat -AppCaches
install-scheduled-cleanup.bat -Registry
install-scheduled-cleanup.bat -ExtraPaths
install-scheduled-cleanup.bat -RecycleBin
install-scheduled-cleanup.bat -BrowserCaches -AppCaches -Registry -ExtraPaths
```

## Логи

Логи пишутся сюда:

```text
C:\ProgramData\CodexWindowsCleanup\Logs
```

Если туда нельзя записать, скрипт использует временную папку пользователя.

Бэкапы реестра сохраняются в подпапке:

```text
C:\ProgramData\CodexWindowsCleanup\Logs\RegistryBackups
```

## Мой совет

Начни с `-SpotifyCache` и без `-RecycleBin`. Если хочется ближе к CCleaner, используй:

```bat
install-scheduled-cleanup.bat -BrowserCaches -AppCaches -Registry
```

Корзину лучше оставить ручной опцией: это последний шанс быстро вернуть случайно удаленный файл.

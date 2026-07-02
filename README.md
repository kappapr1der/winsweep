# WinSweep

Windows cleanup kit для ситуации, когда системный диск снова внезапно стал красным.

## Быстрый запуск

1. Запусти `setup-desktop-folder.bat` от имени администратора.
   Он создаст `Desktop\WinSweep`, скопирует туда батники и поставит задачи в Планировщик.
2. Запусти `disk-space-report.bat`, если хочешь понять, что именно съело диск.
3. Запусти `cleanup-preview.bat`, если хочешь preview без удаления.
4. Запусти `cleanup-smart-now.bat`, если хочешь ручную safe-чистку прямо сейчас.
5. Запусти `cleanup-emergency-now.bat`, если на `C:` уже осталось совсем мало места.

## Планировщик

`install-scheduled-cleanup.bat` больше не ставит тупую чистку строго в полдень и вечером. Теперь модель такая:

- `Pressure Guard` - стартует около `00:15` и повторяется каждые 3 часа.
- `Startup Guard` - проверяет диск через несколько минут после входа в Windows.
- `Deep Weekly` - каждое воскресенье около `03:20`.

`Pressure Guard` и `Startup Guard` сначала смотрят на системный диск. Чистка запускается только если свободного места меньше `35 GB` или меньше `18%`.

Задачи лежат здесь:

```text
Task Scheduler Library\Codex Windows Cleanup
```

Пороги можно поменять при установке:

```bat
install-scheduled-cleanup.bat -LowFreeGB 50 -LowFreePercent 20 -GuardEveryHours 2
```

## Что чистит

Базово:

- `%TEMP%` текущего пользователя.
- `%LOCALAPPDATA%\Temp`.
- `C:\Windows\Temp`.
- Windows Error Reporting.
- DirectX shader cache.
- Explorer thumbnail/icon cache.
- пользовательские crash dumps.
- старый Prefetch, но не младше 7 дней.
- NVIDIA/AMD shader caches.

В aggressive-safe режиме:

- кеши Edge, Chrome, Brave, Firefox.
- Spotify cache, включая classic и Microsoft Store версии.
- Discord, Slack, Telegram Desktop, Zoom, Microsoft Teams.
- Steam shader/http cache, Epic Games Launcher webcache, Battle.net cache, EA Desktop cache.
- дополнительные cache/temp папки из `extra-cache-paths.txt`.

С `-CleanDeveloperCaches`:

- npm, Yarn, pnpm.
- pip, Poetry.
- NuGet http/plugins cache.
- Gradle build cache.

С `-Deep`:

- Windows Update download cache.
- Delivery Optimization cache.
- `DISM /Online /Cleanup-Image /StartComponentCleanup`.

С `-CleanRegistry`:

- Run dialog history.
- Recent documents history.
- Explorer typed paths.
- Explorer search box history.
- Open/save dialog MRU.
- Jump Lists и recent shortcuts.

Перед удалением registry-ключей сохраняются `.reg`-бэкапы.

## Что не трогает

- `Downloads`, `Desktop`, `Documents`, фото, видео, проекты.
- пароли, cookies, сессии браузера.
- папки программ целиком.
- игровые сохранения.
- `WinSxS` руками.
- COM, драйверы, uninstall-записи и ассоциации файлов.
- корзину, если явно не передать `-ClearRecycleBin`.

## Команды

Preview без удаления:

```bat
cleanup-preview.bat
```

Ручная safe-чистка:

```bat
cleanup-smart-now.bat
```

Проверка как в Планировщике:

```bat
guard-check-now.bat
```

Аварийная глубокая safe-чистка:

```bat
cleanup-emergency-now.bat
```

Отчёт по дискам и крупным папкам:

```bat
disk-space-report.bat
```

Открыть логи:

```bat
open-cleanup-logs.bat
```

## Другие диски

Для D/E/F и любых соседних дисков добавь disposable cache/temp папки в:

```text
extra-cache-paths.txt
```

Пример:

```text
D:\Temp
D:\Games\SomeLauncher\Cache
E:\Scratch\BuildCache
```

Не добавляй туда корень диска, `C:\Users`, `Documents`, `Desktop`, фото, проекты и любые папки, где могут быть единственные копии файлов.

## Логи

Основной путь:

```text
C:\ProgramData\CodexWindowsCleanup\Logs
```

Если туда нельзя писать без администратора, WinSweep автоматически использует:

```text
%TEMP%\CodexWindowsCleanup\Logs
```

## Практичный порядок

Если на `C:` осталось около 20 GB из 200+:

1. Запусти `disk-space-report.bat`.
2. Запусти `cleanup-preview.bat`.
3. Если preview выглядит нормально, запусти `cleanup-emergency-now.bat`.
4. Потом запусти `setup-desktop-folder.bat`, чтобы поставить новый `Pressure Guard`.

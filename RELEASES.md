# Публикация релизов

У WinSweep два варианта публикации: через GitHub Actions или напрямую с этого
ПК. Основной формат для пользователей - portable-архив: внутри только
`WinSweep.exe`, `README.md` и `CONFIG.md`.

## Portable-версия

Собрать архив локально:

```powershell
.\build-release.ps1 -Version 1.0.3 -Portable
```

Готовый файл появится в `dist\WinSweep-Portable-v1.0.3.zip`. После первого
запуска `WinSweep.exe` создаст скрытую папку `WinSweepData` рядом с собой.
В ней находятся настройки и внутренний движок, поэтому всю папку можно
переносить целиком.

Обычная сборка остаётся доступна для совместимости:

```powershell
.\build-release.ps1 -Version 1.0.3
```

## Автоматический релиз GitHub Actions

GitHub Actions собирает релиз после пуша тега:

```powershell
git tag v1.0.3
git push origin v1.0.3
```

Это работает, только пока для аккаунта разрешён запуск Actions. При ошибке
про billing lock используй локальную публикацию ниже: она не расходует минуты
GitHub Actions.

## Локальная публикация без Actions

Один раз сохрани fine-grained token с доступом `Contents: Read and write` к
`kappapr1der/winsweep`:

```powershell
.\save-github-token.ps1
```

Затем опубликуй portable-архив:

```powershell
.\publish-release.ps1 -Version 1.0.3 -Portable
```

Сценарий собирает ZIP, создаёт или использует тег `v1.0.3` и прикрепляет архив
к GitHub Release. Токен сохраняется зашифрованным через DPAPI в
`%APPDATA%\WinSweep\github-token.txt`, а в репозиторий не попадает.

Полезные варианты:

```powershell
.\publish-release.ps1 -Version 1.0.3 -Portable -DryRun
.\publish-release.ps1 -Version 1.0.3 -Portable -Prerelease
.\publish-release.ps1 -Version 1.0.3 -Portable -UpdateExisting -ReplaceAsset
.\save-github-token.ps1 -Clear
```

Токен ищется в таком порядке: параметр `-Token`, переменные окружения
`WINSWEEP_GITHUB_TOKEN` / `GITHUB_TOKEN` / `GH_TOKEN`, сохранённый DPAPI-токен,
затем скрытый запрос в консоли.

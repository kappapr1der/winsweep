# Настройки WinSweep

В portable-версии WinSweep читает `winsweep-config.json` из скрытой папки
`WinSweepData` рядом с EXE. В обычной EXE-сборке этот путь остаётся
`%LOCALAPPDATA%\WinSweep\Engine`. Параметры, переданные внутреннему движку,
важнее значений из файла.

Самый удобный способ менять настройки - вкладка `Кэши и правила` в GUI.

## Основные поля

- `defaultProfile`: `Safe`, `Gaming`, `Deep`, `Emergency` или пустая строка.
- `thresholds.minFreeGB`: общий порог свободного места в ГБ.
- `thresholds.minFreePercent`: общий порог свободного места в процентах.
- `thresholds.perDrive`: отдельные пороги для дисков. Пример:

```json
"perDrive": {
  "C:": { "minFreeGB": 35, "minFreePercent": 18 },
  "D:": { "minFreeGB": 60, "minFreePercent": 10 }
}
```

- `thresholds.tempOlderThanDays`: возраст временных файлов для очистки.
- `thresholds.cacheOlderThanDays`: возраст файлов кэша для очистки.
- `paths.extraPathsFile`: обычно `extra-cache-paths.txt`.
- `paths.logDir`: оставь пустым, чтобы WinSweep сам выбрал папку журналов.
- `paths.excludedPaths`: папки, которые WinSweep никогда не удаляет.

## Кэши программ

В секции `features` используются отдельные переключатели:

- `spotifyCache`
- `discordCache`
- `telegramCache`
- `slackCache`
- `teamsCache`
- `zoomCache`
- `browserCaches`: чистятся только когда Chrome, Edge, Brave и Firefox закрыты, чтобы не ломать открытые вкладки.
- `developerCaches`
- `gameCaches`

`appCaches` оставлен для совместимости и включает все кэши программ разом.
Обычно лучше использовать отдельные переключатели.

Другие полезные поля:

- `features.registry`: безопасная очистка истории недавних файлов в реестре.
- `features.clearRecycleBin`: по умолчанию выключена.
- `features.notifyOnPressure`: показывать итоговое системное уведомление после фоновой очистки: сколько освобождено и какие крупнейшие категории очищены. Название ключа сохранено для совместимости со старыми конфигами.

Системные действия не включаются автоматически через конфиг: анализ хранилища
компонентов и изменение гибернации запускаются отдельными кнопками GUI с UAC.
- `schedule.guardStart`: первое ежедневное срабатывание контроля места,
  например `00:15`.
- `schedule.guardEveryHours`: интервал проверки свободного места.
- `schedule.deepWeekly`: время еженедельной глубокой очистки.
- `schedule.deepDay`: день недели для глубокой очистки.

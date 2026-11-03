# Ручной переход с Krema на KDockW

Язык: [English](krema-to-kdockw.md) · Русский

Переход выполняется только по вашему решению. Установка KDockW не читает,
не переносит, не перезаписывает и не удаляет файлы Krema, не отключает его
автозапуск и не включает службу KDockW. Выполняйте шаги ниже, только сначала
проверив KDockW в собственном сеансе Plasma. Они не меняют настройки NVIDIA,
KWin, Plasma или SDDM.

## Идентификаторы и совместимость

| Старый идентификатор Krema | Идентификатор KDockW | Решение о совместимости |
|---|---|---|
| `/usr/local/bin/krema` | `/usr/local/bin/kdockw` | Новый исполняемый файл; оба приложения могут сосуществовать. |
| `com.bhyoo.krema.desktop` | `com.thicking.kdockw.desktop` | Новый desktop ID. В файле объявлены действующие интерфейсы KWin Wayland. |
| `~/.config/kremarc` | `~/.config/kdockwrc` | Те же группы KConfig, ключи, значения и URL ярлыков; скрипт копирует файл без изменений. |
| Домен KI18n `krema` | Домен KI18n `kdockw` | Новое имя каталога переводов; русский перевод сохранён. |
| URI QML `com.bhyoo.krema` | `com.thicking.kdockw` | Приватный импорт, используемый только приложением и его тестами. |
| KWin pointer watcher `com.bhyoo.krema.*` | `com.thicking.kdockw.*` | Приватный callback-интерфейс; имя обновлено на обеих сторонах. |
| Унаследованная `krema.service` | У KDockW нет эквивалентной службы | KDockW использует XDG autostart; старая служба Krema остаётся под контролем пользователя. |
| Запись автозапуска Krema в XDG | Запись автозапуска KDockW в XDG | KDockW устанавливает `com.thicking.kdockw.autostart.desktop` и запускает бинарный файл напрямую. |

Значения метаданных разрешений KWin
`org_kde_plasma_window_management`,
`org_kde_plasma_activation_feedback` и `zkde_screencast_unstable_v1` не
изменяются. KWin сопоставляет эти разрешения с установленным desktop ID.
Пространства имён layer-shell `dock` и `tooltip` также остаются прежними:
KWin трактует их как типы окон, а не названия продукта. Стандартные имена
протоколов TaskManager, KPipeWire, уведомлений и Unity LauncherEntry не
меняются.

## 1. Установите и проверьте KDockW до переноса

Соберите и установите KDockW по [руководству для TUXEDO OS](../building/tuxedo-os.md).
Убедитесь, что эти файлы существуют, прежде чем менять способ запуска при
входе:

```sh
test -x /usr/local/bin/kdockw
test -f /usr/local/share/applications/com.thicking.kdockw.desktop
grep '^X-KDE-Wayland-Interfaces=' /usr/local/share/applications/com.thicking.kdockw.desktop
```

В desktop-файле должны быть перечислены три интерфейса выше. Оставьте этот
стандартный desktop entry и его прямой `Exec=/usr/local/bin/kdockw` без
изменений; установленная запись XDG autostart запускает KDockW при входе.

## 2. Скопируйте всю конфигурацию

Обычным способом закройте Krema, чтобы она сохранила последние настройки.
Затем запустите эту команду из checkout исходников от имени пользователя
рабочего стола:

```sh
scripts/migrate-krema-config.sh
```

Скрипт откажется работать от root, перезаписывать уже существующую
конфигурацию KDockW и копировать файл, пока запущен процесс с именем `krema`.
Он копирует весь файл `kremarc`, включая закреплённые приложения и группы
отдельных экранов, в `kdockwrc`, проверяет копию и оставляет исходный файл на
месте. Резервная копия с меткой времени сохраняется в
`~/.local/state/kdockw/migrations/`. Скрипт не меняет systemd или автозапуск.

Если используются нестандартные `XDG_CONFIG_HOME` или `XDG_STATE_HOME`, скрипт
учитывает эти переменные. Не копируйте только группу `[General]`: настройки
отдельных экранов находятся в том же файле.

## 3. Переключитесь на XDG autostart KDockW после проверки

Если Krema запускается пользовательской службой, проверьте состояние и
отключите её для последующих входов:

```sh
systemctl --user is-enabled krema.service || true
systemctl --user is-active krema.service || true
systemctl --user disable krema.service
```

Пропустите последнюю команду, если службы нет или она уже отключена.
Отключение без `--now` не останавливает работающую Krema; штатно закройте её
перед запуском KDockW в том же сеансе. Старая установленная запись
автозапуска называлась `com.bhyoo.krema.autostart.desktop`. Если у Krema также
есть запись XDG, сохраните существующее одноимённое пользовательское
переопределение перед отключением старой записи.

Единственная штатная запись автозапуска KDockW —
`com.thicking.kdockw.autostart.desktop`. Проверьте, не скрывает ли её
одноимённый пользовательский файл:

```sh
grep -nE '^(Hidden|Exec|OnlyShowIn)=' \
  "$HOME/.config/autostart/com.thicking.kdockw.autostart.desktop" 2>/dev/null || true
```

Сохраните резервную копию переопределения `Hidden=true` до его изменения или
перемещения. Не создавайте обёртку и не меняйте desktop ID. Если прежний
checkout KDockW создал `kdockw.service`, следуйте отдельной
[инструкции перехода со службы на XDG autostart](systemd-to-xdg-autostart.ru.md).

## 4. Проверьте результат и сохраните возможность отката

После следующего входа проверьте процесс, конфигурацию и регистрацию desktop-файла:

```sh
pgrep -a -x kdockw || true
grep -E '^(Exec|Icon|X-KDE-Wayland-Interfaces)=' \
  /usr/local/share/applications/com.thicking.kdockw.desktop
cmp ~/.config/kdockwrc \
  "$(find ~/.local/state/kdockw/migrations -name kdockwrc-migrated -print -quit)"
```

Затем проверьте в настоящем сеансе Wayland предпросмотр окон, индикаторы
работающих приложений, группировку ярлыков, закрепление и перетаскивание файлов.
Исходная конфигурация Krema и ярлыки остаются доступными, пока эта проверка не
будет завершена.

Чтобы вернуть резервную копию настроек в Krema, закройте KDockW и передайте
скрипту каталог резервной копии с меткой времени, выведенной скриптом переноса:

```sh
scripts/rollback-kdockw-config.sh \
  ~/.local/state/kdockw/migrations/YYYYMMDD-HHMMSS
```

Перед восстановлением скрипт сохраняет текущую конфигурацию Krema. Он не
останавливает приложения, не меняет автозапуск и не удаляет конфигурацию
KDockW. Если вы отключили старую службу Krema, включайте её снова только если
она была включена до миграции и после завершения процесса KDockW. Храните
конфигурацию KDockW и резервную копию до тех пор, пока откат может понадобиться.
Ни одна команда переноса или отката не удаляет старое приложение.

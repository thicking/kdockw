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
| `krema.service` | `kdockw.service` | Новая необязательная пользовательская служба с очисткой PRIME и Qt-переменных. |
| Запись автозапуска Krema в XDG | Запись автозапуска KDockW в XDG | При входе выбирайте только один механизм запуска: XDG autostart или systemd user service. |

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
изменений; отдельный ярлык будет запускать службу.

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

## 3. После проверки переключите один способ запуска при входе

Оставьте старую службу и файл автозапуска до проверки KDockW. Если Krema
сейчас запускается пользовательской службой, сначала отключите её:

```sh
systemctl --user disable --now krema.service
```

Если такой службы не было, пропустите эту команду. Перед маскировкой старой
записи XDG autostart сохраните существующее пользовательское переопределение.
Установленный старый файл назывался `com.bhyoo.krema.autostart.desktop`; файл
переопределения с тем же именем скрывает его для этого пользователя:

```sh
mkdir -p ~/.config/autostart
cat > ~/.config/autostart/com.bhyoo.krema.autostart.desktop <<'EOF'
[Desktop Entry]
Hidden=true
EOF
```

Выберите один механизм запуска KDockW при входе:

### Использовать systemd user service с очисткой NVIDIA

Установите шаблон службы из checkout и запустите её:

```sh
install -D -m 644 packaging/systemd/kdockw.service \
  ~/.config/systemd/user/kdockw.service
systemctl --user daemon-reload
systemctl --user enable --now kdockw.service
```

Служба запускает `/usr/local/bin/kdockw` напрямую и очищает только в своём
окружении переменные `DRI_PRIME`, `__GLX_VENDOR_LIBRARY_NAME`,
`__NV_PRIME_RENDER_OFFLOAD`, `__VK_LAYER_NV_optimus` и `QSG_RHI_BACKEND`.
Она не меняет глобальное окружение сеанса или настройки драйвера.

Скройте XDG autostart KDockW для этого пользователя, чтобы служба была
единственным способом запуска при входе:

```sh
cat > ~/.config/autostart/com.thicking.kdockw.autostart.desktop <<'EOF'
[Desktop Entry]
Hidden=true
EOF
```

Создайте необязательный ярлык меню, который запрашивает запуск службы:

```sh
mkdir -p ~/.local/share/applications
cat > ~/.local/share/applications/kdockw-service.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=KDockW (service)
Comment=Start KDockW through the user service
Exec=systemctl --user start kdockw.service
Icon=com.thicking.kdockw
Terminal=false
Categories=Utility;
StartupNotify=false
EOF
kbuildsycoca6
```

### Использовать XDG autostart

Не включайте `kdockw.service`. Оставьте
`com.thicking.kdockw.autostart.desktop` активным и убедитесь, что служба
KDockW не включена. Если при проверке службы вы создали переопределение
`Hidden=true`, восстановите сохранённый предыдущий вариант или удалите это
переопределение.

## 4. Проверьте результат и сохраните возможность отката

После запуска KDockW проверьте процесс, конфигурацию, регистрацию desktop-файла
и окружение службы:

```sh
systemctl --user status kdockw.service
systemctl --user show kdockw.service -p UnsetEnvironment
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
останавливает службы, не меняет автозапуск и не удаляет конфигурацию KDockW.
Чтобы вернуться со службы, отключите её и восстановите сохранённое переопределение
автозапуска или исходный unit-файл:

```sh
systemctl --user disable --now kdockw.service
```

Повторно включайте старую службу, только если она была включена до переноса.
Храните конфигурацию KDockW и резервную копию переноса до подтверждения отката.
Ни одна команда переноса или отката не удаляет старое приложение.

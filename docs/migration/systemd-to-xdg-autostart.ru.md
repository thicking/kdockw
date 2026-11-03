# Переход KDockW со службы systemd на XDG autostart

Теперь XDG autostart — единственный поддерживаемый механизм автоматического
запуска KDockW при входе. Руководство предназначено для пользователей,
создавших или установивших `kdockw.service` в предыдущей версии проекта.
Переход выполняется вручную: установка и обновление KDockW не проверяют и не
меняют пользовательские службы, переопределения, ярлыки и запущенные процессы.

Язык: [English](systemd-to-xdg-autostart.md) · Русский

## 1. Проверьте текущее состояние

Команды только проверяют пользовательскую службу и процессы. Отсутствующая
служба — нормальная ситуация:

```sh
systemctl --user is-enabled kdockw.service || true
systemctl --user is-active kdockw.service || true
systemctl --user status --no-pager kdockw.service || true
systemctl --user show kdockw.service -p FragmentPath -p DropInPaths --no-pager || true
pgrep -a -x kdockw || true
```

Запишите, включена ли служба, активна ли она или отключена. `FragmentPath` и
`DropInPaths` показывают расположение unit-файла и локальных переопределений.
Не редактируйте файлы из `/usr`, `/usr/local` или `/etc` как пользовательские.
Если путь находится вне домашнего каталога, используйте предусмотренное
пакетом удаление/обновление либо обратитесь к администратору.

## 2. Сохраните пользовательские файлы

Создайте закрытый каталог резервной копии с временной меткой и скопируйте
существующие файлы. Команды не удаляют и не меняют оригиналы:

```sh
backup="$HOME/.local/state/kdockw/migrations/systemd-to-xdg-$(date +%Y%m%d-%H%M%S)"
install -d -m 700 "$backup"

for path in \
  "$HOME/.config/systemd/user/kdockw.service" \
  "$HOME/.config/systemd/user/kdockw.service.d" \
  "$HOME/.local/share/systemd/user/kdockw.service" \
  "$HOME/.local/share/systemd/user/kdockw.service.d" \
  "$HOME/.config/autostart/com.thicking.kdockw.autostart.desktop" \
  "$HOME/.local/share/applications/kdockw-service.desktop"; do
  if [ -e "$path" ]; then
    cp -a --parents "$path" "$backup"
  fi
done
printf 'Резервная копия: %s\n' "$backup"
```

Если `systemctl show` указал другие пользовательские пути unit-файла или
переопределений, скопируйте их в эту резервную копию до перемещения или
изменения. Не удаляйте копию, пока не проверите запуск после входа.

## 3. Отключите старый автозапуск

Если `kdockw.service` включена, отключите её без параметра `--now`:

```sh
systemctl --user disable kdockw.service
```

Так служба не запустится при следующем входе, но уже работающий KDockW не
будет остановлен. Не останавливайте и не завершайте процесс док-панели во
время миграции. Дайте запущенному службой экземпляру закрыться обычным
способом или дождитесь штатного завершения сеанса. Если позже решите удалить
пользовательский unit, сначала убедитесь, что служба неактивна, переместите
оригинал в резервную копию и обновите пользовательский менеджер. Не удаляйте
unit или override, пока не проверили резервную копию.

## 4. Восстановите XDG autostart

Установленная запись называется `com.thicking.kdockw.autostart.desktop`. Её
`Exec` запускает бинарный файл `kdockw` напрямую. Найдите установленную запись:

```sh
test -f /etc/xdg/autostart/com.thicking.kdockw.autostart.desktop
grep '^Exec=' /etc/xdg/autostart/com.thicking.kdockw.autostart.desktop
```

Файл с тем же именем в `~/.config/autostart/` перекрывает установленный.
Сначала проверьте его:

```sh
grep -nE '^(Hidden|Exec|OnlyShowIn)=' \
  "$HOME/.config/autostart/com.thicking.kdockw.autostart.desktop" 2>/dev/null || true
```

Если в нём есть `Hidden=true`, сохраните копию из шага 2. Затем либо удалите
этот ключ, сохранив остальные пользовательские настройки, либо, если файл
создан только для блокировки системной записи, переместите его в резервную
копию:

```sh
mv "$HOME/.config/autostart/com.thicking.kdockw.autostart.desktop" "$backup/"
```

Не создавайте обёртку. Оставьте `com.thicking.kdockw.desktop` и его строку
`X-KDE-Wayland-Interfaces` без изменений. Ручной запуск приложения также
поддерживается. KDockW регистрирует уникальную службу приложения KDE D-Bus,
поэтому повторный запуск из меню передаётся уже работающему экземпляру;
после входа всё равно проверьте список процессов.

Созданный ранее `kdockw-service.desktop` — только ярлык меню. Если он больше
не нужен и запускает отключённую службу, после резервного копирования
переместите его из каталога приложений:

```sh
if [ -e "$HOME/.local/share/applications/kdockw-service.desktop" ]; then
  install -d "$backup/retired-shortcuts"
  mv "$HOME/.local/share/applications/kdockw-service.desktop" "$backup/retired-shortcuts/"
fi
```

## 5. Проверьте запуск после следующего входа

После следующего входа в Plasma выполните:

```sh
systemctl --user is-enabled kdockw.service || true
pgrep -a -x kdockw || true
```

Старая служба не должна быть включена; должен работать один процесс KDockW.
Проверьте запуск из меню приложений и вручную. Для установки в `/usr`
используйте `/usr/bin/kdockw`, для стандартного префикса TUXEDO —
`/usr/local/bin/kdockw`.

## Откат

Если XDG autostart не сработал, проверьте `Exec`, префикс установки и наличие
`Hidden=true` в пользовательском переопределении. Восстанавливайте только
пользовательские файлы, заранее скопированные в резервную копию, по исходным
путям. Например:

```sh
unit_backup="$backup$HOME/.config/systemd/user/kdockw.service"
if [ -e "$unit_backup" ]; then
  install -d "$HOME/.config/systemd/user"
  cp -a "$unit_backup" "$HOME/.config/systemd/user/"
fi

override_backup="$backup$HOME/.config/autostart/com.thicking.kdockw.autostart.desktop"
if [ -e "$override_backup" ]; then
  install -d "$HOME/.config/autostart"
  cp -a "$override_backup" "$HOME/.config/autostart/"
fi
```

Также восстановите пользовательские drop-in из копии. Не копируйте резервный
unit поверх файла, принадлежащего системному пакету. Верните именно прежнюю
конфигурацию автозапуска: если служба была единственным способом запуска и
до миграции пользовательского XDG-переопределения не было, скройте системную
XDG-запись перед повторным включением службы:

```sh
if [ ! -e "$override_backup" ]; then
  install -d "$HOME/.config/autostart"
  cat >"$HOME/.config/autostart/com.thicking.kdockw.autostart.desktop" <<'EOF'
[Desktop Entry]
Hidden=true
EOF
fi
```

Затем обновите менеджер и включайте службу, только если она была включена до
миграции:

```sh
systemctl --user daemon-reload
systemctl --user enable kdockw.service
```

Перед запуском службы убедитесь, что экземпляр KDockW из XDG autostart штатно
закрыт, и восстановите прежнее переопределение автозапуска. Не копируйте
резервный пользовательский unit поверх файла, принадлежащего системному пакету.

#!/usr/bin/env python3
"""Check the current Russian KI18n catalog in an extracted install package."""

from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path


REQUIRED_TRANSLATIONS = {
    "General": "Общие",
    "Icons": "Значки",
    "Layout & Position": "Расположение и позиция",
    "Panel Style": "Стиль панели",
    "Shadow": "Тень",
    "Animations & Badges": "Анимация и индикаторы",
    "Behavior": "Поведение",
    "Monitors & Desktops": "Мониторы и рабочие столы",
    "Window Preview": "Предпросмотр окон",
    "Update Checks": "Проверка обновлений",
    # Regression marker absent from the stale catalog observed on the owner host.
    "Badge text size": "Размер текста бейджа",
    "Spring stiffness": "Упругость пружины",
}


def read_mo(path: Path) -> dict[str, str]:
    data = path.read_bytes()
    if len(data) < 28:
        raise ValueError("catalog is shorter than the GNU MO header")
    little_magic = struct.unpack_from("<I", data, 0)[0]
    big_magic = struct.unpack_from(">I", data, 0)[0]
    if little_magic == 0x950412DE:
        unpack = "<"
    elif big_magic == 0x950412DE:
        unpack = ">"
    else:
        raise ValueError("catalog has an invalid GNU MO magic number")
    _magic, _revision, count, originals, translations, _hash_size, _hash_offset = struct.unpack_from(
        unpack + "7I", data, 0
    )
    messages: dict[str, str] = {}
    for index in range(count):
        original_length, original_offset = struct.unpack_from(
            unpack + "2I", data, originals + index * 8
        )
        translated_length, translated_offset = struct.unpack_from(
            unpack + "2I", data, translations + index * 8
        )
        original = data[original_offset : original_offset + original_length]
        translated = data[translated_offset : translated_offset + translated_length]
        msgid_bytes = original.split(b"\0", 1)[0]
        if b"\x04" in msgid_bytes:
            msgid_bytes = msgid_bytes.split(b"\x04", 1)[1]
        msgid = msgid_bytes.decode("utf-8")
        msgstr = translated.split(b"\0", 1)[0].decode("utf-8")
        messages[msgid] = msgstr
    return messages


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("package_root", type=Path)
    parser.add_argument("version")
    # package_root is the directory produced by dpkg-deb -x/rpm2cpio, so its
    # paths include the install prefix (normally usr/share/locale).
    parser.add_argument("--locale-dir", default="usr/share/locale")
    args = parser.parse_args()
    catalog = args.package_root / args.locale_dir / "ru/LC_MESSAGES/kdockw.mo"
    if not catalog.is_file():
        print(f"error: package is missing installed catalog at {catalog}", file=sys.stderr)
        return 1
    try:
        messages = read_mo(catalog)
    except (OSError, ValueError, UnicodeError, struct.error) as error:
        print(f"error: cannot read package catalog: {error}", file=sys.stderr)
        return 1
    header = messages.get("")
    expected_header = f"Project-Id-Version: KDockW {args.version}"
    if not header or expected_header not in header:
        print(
            f"error: catalog header does not identify {args.version}: {header!r}",
            file=sys.stderr,
        )
        return 1
    missing = [
        f"{msgid!r}: expected {expected!r}, got {messages.get(msgid)!r}"
        for msgid, expected in REQUIRED_TRANSLATIONS.items()
        if messages.get(msgid) != expected
    ]
    if missing:
        print("error: package catalog is incomplete:", file=sys.stderr)
        print("\n".join(f"  {line}" for line in missing), file=sys.stderr)
        return 1
    print(f"verified {len(REQUIRED_TRANSLATIONS)} Russian settings translations in {catalog}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

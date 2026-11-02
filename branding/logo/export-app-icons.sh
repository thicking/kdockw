#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 KDockW Contributors

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source_png="${script_dir}/kdockw-icon-source.png"
output_dir="${script_dir}/kdockw-app-icons"

command -v magick >/dev/null || {
    echo "ImageMagick (magick) is required to export the application icon sizes." >&2
    exit 1
}

mkdir -p "${output_dir}"
for size in 16 22 24 32 48 64 128 256 512; do
    magick "${source_png}" \
        -filter Lanczos \
        -resize "${size}x${size}" \
        "${output_dir}/${size}-apps-com.thicking.kdockw.png"
done

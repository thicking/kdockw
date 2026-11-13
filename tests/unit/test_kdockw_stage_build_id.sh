#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
source "${repo_root}/tools/lib/kdockw-stage-build-id.sh"

temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/kdockw-stage-build-id.XXXXXX")"
trap 'rm -rf -- "$temporary_dir"' EXIT

cp -- /usr/bin/true "${temporary_dir}/matching-copy"
cp -- /usr/bin/false "${temporary_dir}/mismatched-copy"

if ! kdockw_stage_build_ids_match /usr/bin/true "${temporary_dir}/matching-copy"; then
    printf 'Identical ELF Build IDs should match.\n' >&2
    exit 1
fi

if kdockw_stage_build_ids_match /usr/bin/true "${temporary_dir}/mismatched-copy"; then
    printf 'Different ELF Build IDs must not match.\n' >&2
    exit 1
fi

if printf 'not an ELF executable\n' > "${temporary_dir}/invalid-elf" \
    && kdockw_elf_build_id "${temporary_dir}/invalid-elf" >/dev/null 2>&1; then
    printf 'A damaged/non-ELF file must not produce a Build ID.\n' >&2
    exit 1
fi

localized_id="$(env -u LC_ALL LANG=ru_RU.UTF-8 LC_MESSAGES=ru_RU.UTF-8 \
    bash -c 'source "$1"; kdockw_elf_build_id "$2"' _ \
    "${repo_root}/tools/lib/kdockw-stage-build-id.sh" /usr/bin/true)"
expected_id="$(kdockw_elf_build_id /usr/bin/true)"
if [[ "$localized_id" != "$expected_id" ]]; then
    printf 'Build ID parsing must be independent of the caller locale.\n' >&2
    exit 1
fi

printf 'ELF Build ID comparison accepts matching binaries and rejects mismatches.\n'

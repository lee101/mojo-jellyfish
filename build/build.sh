#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$repo_dir/dist"
mojo build --emit shared-lib \
    "$repo_dir/src/kernels.mojo" \
    -o "$repo_dir/dist/libmojo-jellyfish.so"

extension_suffix="$(python3-config --extension-suffix)"
cc -O3 -fPIC -shared \
    $(python3-config --includes) \
    "$repo_dir/python/mojo_jellyfish/_native.c" \
    -L"$repo_dir/dist" -l:libmojo-jellyfish.so \
    -Wl,-rpath,'$ORIGIN/../../dist' \
    -o "$repo_dir/python/mojo_jellyfish/_native${extension_suffix}"

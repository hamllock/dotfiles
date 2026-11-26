#!/usr/bin/env bash
# Link the Stow packages in this repo into $HOME.
set -euo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${HOME}"
DEFAULT_PACKAGES=(btop fastfetch fish hypr kitty matugen nvim qt5ct qt6ct starship swayosd vicinae)

dry_run=0
if [[ "${1:-}" == "--dry-run" ]]; then
    dry_run=1
    shift
fi

if (( $# > 0 )); then
    packages=("$@")
else
    packages=("${DEFAULT_PACKAGES[@]}")
fi

if ! command -v stow >/dev/null 2>&1; then
    printf 'GNU Stow is required. Install it, then re-run.\n' >&2
    exit 1
fi

# Stow cannot take over paths that are already occupied by unrelated files.
conflicts=()
for pkg in "${packages[@]}"; do
    src="$REPO/$pkg/.config"
    if [[ ! -d "$src" ]]; then
        printf 'Unknown package: %s\n' "$pkg" >&2
        exit 1
    fi
    while IFS= read -r -d '' entry; do
        name="${entry##*/}"
        target="$TARGET/.config/$name"
        [[ -e "$target" || -L "$target" ]] || continue
        dest="$(readlink -f "$target" 2>/dev/null || true)"
        # Already managed by this repo: safe for stow --restow.
        [[ -n "$dest" && "$dest" == "$REPO/"* ]] && continue
        conflicts+=("$target")
    done < <(find "$src" -mindepth 1 -maxdepth 1 -print0)
done

if (( ${#conflicts[@]} > 0 )); then
    printf 'These targets already exist and are not managed by this repo:\n' >&2
    printf '  %s\n' "${conflicts[@]}" >&2
    printf '\nMove them aside (e.g. mv path path.bak) or remove them, then re-run.\n' >&2
    exit 1
fi

args=(--restow --target="$TARGET" --dir="$REPO" "${packages[@]}")
if (( dry_run )); then
    args=(-n "${args[@]}")
fi

printf 'Linking: %s\n' "${packages[*]}"
stow "${args[@]}"
printf 'Done.\n'

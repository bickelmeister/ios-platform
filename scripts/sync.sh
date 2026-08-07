#!/usr/bin/env bash
#
# Verteilt die geteilten Dateien aus shared/ in die App-Repos.
#
# Workflows werden NICHT verteilt — die App-Repos rufen sie über workflow_call
# auf, eine Änderung hier wirkt dort ohne Sync.
#
# Aufruf:
#   scripts/sync.sh                    # alle Repos, nur Diff anzeigen
#   scripts/sync.sh --apply            # alle Repos, Branch anlegen und pushen
#   scripts/sync.sh --apply diaro-ios  # nur ein Repo
#
set -euo pipefail

PLATFORM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="$(dirname "$PLATFORM_DIR")"
SHARED="$PLATFORM_DIR/shared"

REPOS=(diaro-ios portio-ios fincheck-ios)
BRANCH="chore/sync-ios-platform"

APPLY=false
if [[ "${1:-}" == "--apply" ]]; then
  APPLY=true
  shift
fi
if [[ $# -gt 0 ]]; then
  REPOS=("$@")
fi

# Ersetzt den Block zwischen den SYNC-Markern in $2 durch den Inhalt von $1.
# Fehlen die Marker, wird die Datei nicht angefasst — lieber nichts tun als den
# repo-spezifischen Teil überschreiben.
splice_block() {
  local source_file="$1" target_file="$2"
  if [[ ! -f "$target_file" ]]; then
    echo "    übersprungen (fehlt): $(basename "$target_file")"
    return
  fi
  if ! grep -q '<!-- SYNC:START ios-platform -->' "$target_file"; then
    echo "    übersprungen (keine SYNC-Marker): $(basename "$target_file")"
    return
  fi
  python3 - "$source_file" "$target_file" <<'PY'
import re, sys
source, target = sys.argv[1], sys.argv[2]
block = open(source, encoding="utf-8").read().strip("\n")
text = open(target, encoding="utf-8").read()
new = re.sub(
    r"(<!-- SYNC:START ios-platform -->\n).*?(\n<!-- SYNC:END ios-platform -->)",
    lambda m: m.group(1) + block + m.group(2),
    text,
    flags=re.DOTALL,
)
if new != text:
    open(target, "w", encoding="utf-8").write(new)
PY
  echo "    Block ersetzt: $(basename "$target_file")"
}

# Wie splice_block, aber für Makefiles (Marker sind '# SYNC:START/END').
splice_makefile() {
  local source_file="$1" target_file="$2"
  if [[ ! -f "$target_file" ]] || ! grep -q '# SYNC:START ios-platform' "$target_file"; then
    echo "    übersprungen (keine SYNC-Marker): Makefile"
    return
  fi
  python3 - "$source_file" "$target_file" <<'PY'
import re, sys
source, target = sys.argv[1], sys.argv[2]
block = open(source, encoding="utf-8").read().strip("\n")
text = open(target, encoding="utf-8").read()
new = re.sub(
    r"(# SYNC:START ios-platform\n).*?(\n# SYNC:END ios-platform)",
    lambda m: m.group(1) + block + m.group(2),
    text,
    flags=re.DOTALL,
)
if new != text:
    open(target, "w", encoding="utf-8").write(new)
PY
  echo "    Block ersetzt: Makefile"
}

for repo in "${REPOS[@]}"; do
  target="$WORKSPACE/$repo"
  echo "==> $repo"

  if [[ ! -d "$target/.git" ]]; then
    echo "    kein Git-Repo unter $target — übersprungen"
    continue
  fi
  if [[ -n "$(git -C "$target" status --porcelain)" ]]; then
    echo "    Arbeitsverzeichnis nicht sauber — übersprungen"
    continue
  fi

  git -C "$target" fetch --quiet origin
  git -C "$target" checkout --quiet main
  git -C "$target" reset --hard --quiet origin/main

  # Ganze Dateien: gehören vollständig der Plattform. Das Fastfile ist bewusst
  # app-unabhängig (Projekt und Scheme kommen aus der Umgebung), app-spezifisch
  # ist nur das Appfile — das bleibt unangetastet.
  cp "$SHARED/.swiftlint.yml"  "$target/.swiftlint.yml"
  cp "$SHARED/.editorconfig"   "$target/.editorconfig"
  cp "$SHARED/Gemfile"         "$target/Gemfile"
  mkdir -p "$target/.github" "$target/fastlane"
  cp "$SHARED/PULL_REQUEST_TEMPLATE.md" "$target/.github/PULL_REQUEST_TEMPLATE.md"
  cp "$SHARED/fastlane/Fastfile"        "$target/fastlane/Fastfile"
  echo "    kopiert: .swiftlint.yml, .editorconfig, Gemfile, PULL_REQUEST_TEMPLATE.md, Fastfile"

  # Teil-Dateien: nur der markierte Block, der Rest bleibt repo-eigen.
  splice_block    "$SHARED/AGENTS.core.md"  "$target/AGENTS.md"
  splice_makefile "$SHARED/Makefile.shared" "$target/Makefile"

  if [[ -z "$(git -C "$target" status --porcelain)" ]]; then
    echo "    keine Änderungen"
    continue
  fi

  if ! $APPLY; then
    echo "    --- Diff (Probelauf, nichts wird geschrieben) ---"
    git -C "$target" --no-pager diff --stat
    git -C "$target" checkout --quiet -- .
    continue
  fi

  git -C "$target" checkout --quiet -B "$BRANCH"
  git -C "$target" add -A
  git -C "$target" commit --quiet -m "chore: sync shared files from ios-platform"
  git -C "$target" push --quiet --force-with-lease -u origin "$BRANCH"
  gh pr create --repo "bickelmeister/$repo" \
    --base main --head "$BRANCH" \
    --title "chore: sync shared files from ios-platform" \
    --body "Automatisch erzeugt von \`ios-platform/scripts/sync.sh\`. Betrifft nur geteilte Dateien und die SYNC-Blöcke." \
    2>/dev/null || echo "    PR existiert bereits"
  git -C "$target" checkout --quiet main
  echo "    PR gepusht"
done

$APPLY || echo
$APPLY || echo "Probelauf. Mit --apply werden Branches angelegt und PRs geöffnet."

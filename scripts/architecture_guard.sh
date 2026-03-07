#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

check_allowlist() {
  local label="$1"
  local pattern="$2"
  local allowlist_file="$3"

  if [[ ! -f "$allowlist_file" ]]; then
    echo "Missing allowlist: $allowlist_file" >&2
    return 1
  fi

  local current_file
  local allowlist_sorted_file
  current_file="$(mktemp)"
  allowlist_sorted_file="$(mktemp)"

  rg -n "$pattern" PharmaApp --glob '*.swift' --no-heading \
    | cut -d: -f1 \
    | sort -u > "$current_file" || true

  sed '/^[[:space:]]*$/d' "$allowlist_file" | sort -u > "$allowlist_sorted_file"

  local unexpected
  unexpected="$(comm -23 "$current_file" "$allowlist_sorted_file" || true)"

  rm -f "$current_file" "$allowlist_sorted_file"

  if [[ -n "$unexpected" ]]; then
    echo "$label: found imports outside allowlist" >&2
    echo "$unexpected" >&2
    return 1
  fi
}

check_allowlist \
  "CoreData guard" \
  '^import[[:space:]]+CoreData\b' \
  "scripts/architecture-baseline/coredata-import-allowlist.txt"

check_allowlist \
  "Firebase guard" \
  '^import[[:space:]]+Firebase(Auth|Core)\b' \
  "scripts/architecture-baseline/firebase-import-allowlist.txt"

direct_save_matches="$(
  rg -n '\b(managedObjectContext|context)\.save\(' PharmaApp/Feature PharmaApp/Settings --glob '*.swift' --no-heading || true
)"

if [[ -n "$direct_save_matches" ]]; then
  echo "Feature/Settings guard: found direct context.save() usage" >&2
  echo "$direct_save_matches" >&2
  exit 1
fi

forbidden_ui_coredata_matches="$(
  rg -n '@FetchRequest|NSManagedObjectID|\bobjectID\b' PharmaApp/Feature PharmaApp/Settings --glob '*.swift' --no-heading || true
)"

if [[ -n "$forbidden_ui_coredata_matches" ]]; then
  echo "Feature/Settings guard: found forbidden CoreData UI patterns" >&2
  echo "$forbidden_ui_coredata_matches" >&2
  exit 1
fi

settings_coredata_imports="$(
  rg -n '^import[[:space:]]+CoreData\b' PharmaApp/Settings --glob '*.swift' --no-heading || true
)"

if [[ -n "$settings_coredata_imports" ]]; then
  echo "Settings guard: found CoreData imports in Settings module" >&2
  echo "$settings_coredata_imports" >&2
  exit 1
fi

echo "Architecture guard passed."

#!/bin/bash
# Verifies that every shipped language defines the same key set.
# A key present in one language but missing in another renders the source
# key string (e.g. "cleaner.history_total") in the UI, so alignment is a
# release gate, not a nicety.
# Written for macOS's stock bash 3.2: no associative arrays, no mkshisms.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FAILED=0

extract_keys() {
  # Strip comments and pull the leading quoted key from each definition.
  grep -oE '^"[^"]+"' "$1" | tr -d '"' | sort -u
}

KEYS_ZH="$(extract_keys "$ROOT/ThreeOneOSSix/zh-Hans.lproj/Localizable.strings")"
KEYS_EN="$(extract_keys "$ROOT/ThreeOneOSSix/en.lproj/Localizable.strings")"
KEYS_VI="$(extract_keys "$ROOT/ThreeOneOSSix/vi.lproj/Localizable.strings")"
KEYS_KO="$(extract_keys "$ROOT/ThreeOneOSSix/ko.lproj/Localizable.strings")"

echo "zh-Hans: $(echo "$KEYS_ZH" | grep -c . || true) keys"
echo "en: $(echo "$KEYS_EN" | grep -c . || true) keys"
echo "vi: $(echo "$KEYS_VI" | grep -c . || true) keys"
echo "ko: $(echo "$KEYS_KO" | grep -c . || true) keys"

# Pairwise comparison against zh-Hans (the authoring language).
for PAIR in "en:$KEYS_EN" "vi:$KEYS_VI" "ko:$KEYS_KO"; do
  LANG_NAME="${PAIR%%:*}"
  OTHER="${PAIR#*:}"
  MISSING=$(comm -23 <(echo "$KEYS_ZH") <(echo "$OTHER") || true)
  EXTRA=$(comm -13 <(echo "$KEYS_ZH") <(echo "$OTHER") || true)
  if [[ -n "$MISSING" ]]; then
    echo "FAIL: $LANG_NAME missing keys:" >&2
    echo "$MISSING" | sed 's/^/  /' >&2
    FAILED=1
  fi
  if [[ -n "$EXTRA" ]]; then
    echo "FAIL: $LANG_NAME has extra keys:" >&2
    echo "$EXTRA" | sed 's/^/  /' >&2
    FAILED=1
  fi
done

# Duplicate keys are invisible to the set comparison above because `sort -u`
# folds them, yet .strings resolves them by last-wins. A duplicate that holds a
# stale translation therefore looks aligned while the file carries a second,
# dead copy. Detect them explicitly.
for LANG_FILE in zh-Hans en vi ko; do
  DUPS="$(grep -oE '^"[^"]+"' "$ROOT/ThreeOneOSSix/$LANG_FILE.lproj/Localizable.strings" \
    | tr -d '"' | sort | uniq -d || true)"
  if [[ -n "$DUPS" ]]; then
    echo "FAIL: $LANG_FILE has duplicate keys (last one silently wins):" >&2
    echo "$DUPS" | sed 's/^/  /' >&2
    FAILED=1
  fi
done

# Format specifiers must match per key across languages. AppLanguage.text uses
# String(format:), which consumes arguments in order; a translation that moves
# a specifier without moving the argument, or drops one, crashes or prints the
# wrong value at runtime. This is a build-time gate for that class of bug.
if command -v python3 >/dev/null 2>&1; then
  python3 - "$ROOT" <<'PY' || FAILED=1
import re, sys, io, os
root = sys.argv[1]
base_lang = "zh-Hans"
langs = ["en", "vi", "ko"]
spec = re.compile(r'(%lld|%ld|%llX|%[@d])')

def load(path):
    out = {}
    for line in io.open(path, encoding="utf-8"):
        m = re.match(r'^"([^"]+)"\s*=\s*"(.*)";\s*$', line.rstrip("\n"))
        if m:
            out[m.group(1)] = spec.findall(m.group(2))
    return out

base = load(os.path.join(root, "ThreeOneOSSix", base_lang + ".lproj", "Localizable.strings"))
failed = False
for lang in langs:
    other = load(os.path.join(root, "ThreeOneOSSix", lang + ".lproj", "Localizable.strings"))
    for key, base_seq in base.items():
        if key not in other:
            continue  # key-set gate reports this
        if other[key] != base_seq:
            if not failed:
                print("FAIL: format specifier mismatch vs %s:" % base_lang, file=sys.stderr)
            failed = True
            print("  %s/%s: base=%s got=%s" % (lang, key, base_seq, other[key]), file=sys.stderr)
if failed:
    sys.exit(1)
PY
else
  echo "WARN: python3 unavailable, skipped format-specifier check" >&2
fi

if [[ "$FAILED" -eq 0 ]]; then
  echo "PASS: localization keys, duplicates and format specifiers aligned across zh-Hans / en / vi / ko"
fi
exit "$FAILED"
#!/bin/bash
# Static guardrails for the iOS 27 grant-chain hardening (spec
# 02-00-ios27-grant-hardening, T-009). Grep-level assertions that each
# hardening stays in place; wired into run_policy_tests.sh so CI runs it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/ThreeOneOSSix"

fail() { echo "FAIL: $1" >&2; exit 1; }

# T-003: lstat is no longer a hard gate — -254 must never be returned again.
if grep -q 'return -254' "$SRC/exploit/worse_query.m"; then
  fail "-254 hard gate returned from grant again (T-003 regression)"
fi

# T-004: flags candidate table keeps at least 3 entries.
CANDIDATES=$(grep -c '0x[0-9A-Fa-f]\{16\}ULL,' "$SRC/exploit/worse_query.m" || true)
if [ "$CANDIDATES" -lt 3 ]; then
  fail "flags candidate table shrank below 3 entries (T-004 regression)"
fi

# T-004: the learned-preference key carries the OS-major suffix; the legacy
# un-versioned string constant must not come back.
if ! grep -q 'wq.preferredQueryFlags.v' "$SRC/exploit/worse_query.m"; then
  fail "versioned preference key missing (T-004 regression)"
fi
if grep -q '@"wq.preferredQueryFlags"' "$SRC/exploit/worse_query.m"; then
  fail "legacy un-versioned preference key constant is back (T-004 regression)"
fi

# T-005: write probe + grant_ex API present; legacy grant forwards read-only.
grep -q 'WQPathWriteProbe' "$SRC/exploit/worse_query.m" \
  || fail "write probe missing (T-005 regression)"
grep -q 'worse_query_grant_ex(const char \*path' "$SRC/exploit/worse_query.h" \
  || fail "grant_ex declaration missing (T-005 regression)"
grep -q 'worse_query_grant_ex(path, 0)' "$SRC/exploit/worse_query.m" \
  || fail "legacy grant no longer forwards read-only (T-005 regression)"

# T-006: real probe with TTL wired into hasSandboxAccess.
grep -q 'probeCached' "$SRC/helpers/SandboxAccess.swift" \
  || fail "TTL-cached probe missing (T-006 regression)"
if grep -q 'return SandboxAccess.hasAppGroup' "$SRC/helpers/KernelExploit.swift"; then
  fail "hasSandboxAccess fell back to the bare entitlement check (T-006 regression)"
fi

# T-007: retry wired into all three write services (FileReplace/MobileGestalt
# go through withGrant; FileManagerService uses the GrantRetry classification
# directly because transferItem does not own its grant).
grep -q 'withGrant(directory:' "$SRC/helpers/FileReplaceService.swift" \
  || fail "FileReplaceService lost its withGrant integration (T-007 regression)"
grep -q 'withGrant(directory:' "$SRC/helpers/MobileGestaltService.swift" \
  || fail "MobileGestaltService lost its withGrant integration (T-007 regression)"
grep -q 'GrantRetry.isPermissionDenied' "$SRC/helpers/FileManagerService.swift" \
  || fail "FileManagerService lost its permission-denial retry (T-007 regression)"

# T-002: trilingual sandbox.* keys stay present (the alignment test checks
# parity across languages; this checks presence against accidental removal).
# 24 keys: 10 error codes + 3 banner + 11 diagnostics view.
for lang in zh-Hans en vi; do
  COUNT=$(grep -c '^"sandbox\.' "$SRC/$lang.lproj/Localizable.strings" || true)
  if [ "$COUNT" -lt 24 ]; then
    fail "$lang lost sandbox.* keys ($COUNT < 24) (T-002 regression)"
  fi
done

echo "PASS: sandbox static guardrails"

#!/bin/bash
# Migration engine verification (stage 2). Compiles the migration subsystem
# without UIKit-dependent files and runs the synthetic-container harness.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# swiftc rejects non-.swift input files; the .txt harness follows the
# verify_filereplace convention (cp first, compile the copy).
HARNESS="$TMP/main.swift"
cp "$ROOT/Tests/verify_migration_main.swift.txt" "$HARNESS"

swiftc -O \
  "$ROOT/ThreeOneOSSix/helpers/MigrationModels.swift" \
  "$ROOT/ThreeOneOSSix/helpers/MigrationTreeScanner.swift" \
  "$ROOT/ThreeOneOSSix/helpers/MigrationFileCopy.swift" \
  "$ROOT/ThreeOneOSSix/helpers/MigrationCheckpointStore.swift" \
  "$ROOT/ThreeOneOSSix/helpers/MigrationResumeService.swift" \
  "$ROOT/ThreeOneOSSix/helpers/MigrationAppResolver.swift" \
  "$ROOT/ThreeOneOSSix/helpers/MigrationEngine.swift" \
  "$ROOT/ThreeOneOSSix/helpers/TaskCancellation.swift" \
  "$ROOT/ThreeOneOSSix/helpers/LaunchArtworkRenderer.swift" \
  "$HARNESS" \
  -o "$TMP/migration-tests"

"$TMP/migration-tests"

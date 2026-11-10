#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

swiftc -O \
  "$ROOT/ThreeOneOSSix/helpers/SupportPolicy.swift" \
  "$ROOT/ThreeOneOSSix/helpers/LaunchServicesStore.swift" \
  "$ROOT/ThreeOneOSSix/helpers/ContainerBrowserLogic.swift" \
  "$ROOT/ThreeOneOSSix/helpers/FileBrowserMetadata.swift" \
  "$ROOT/Tests/main.swift" \
  -o "$TMP/policy-tests"

"$TMP/policy-tests"
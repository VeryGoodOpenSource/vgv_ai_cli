#!/bin/bash
# Regenerates the config brick bundles from bricks/.
#
# The bundles are committed. CI regenerates them and fails if the result
# differs, so run this whenever a brick changes.
set -euo pipefail

BUNDLE_OUTPUT_DIR="packages/vgv_ai_cli/lib/src/templates"

for brick in user_config; do
  mason bundle --source path "./bricks/$brick/" -t dart --output-dir "$BUNDLE_OUTPUT_DIR"

  input="$BUNDLE_OUTPUT_DIR/${brick}_bundle.dart"
  echo -e "// To generate this file, run: tool/generate_bundles.sh\n$(cat "$input")" > "$input"
done

dart format "$BUNDLE_OUTPUT_DIR"

#!/bin/bash
# Regenerates the agents bundle from bricks/agents.
#
# The bundle is committed. CI regenerates it and fails if the result differs,
# so run this whenever the brick changes.
set -euo pipefail

BUNDLE_OUTPUT_DIR="packages/vgv_ai_cli/lib/src/templates"

mason bundle --source path ./bricks/agents/ -t dart --output-dir "$BUNDLE_OUTPUT_DIR"

input="$BUNDLE_OUTPUT_DIR/agents_bundle.dart"
echo -e "// To generate this file, run: tool/generate_agents_bundle.sh\n$(cat "$input")" > "$input"

dart format "$BUNDLE_OUTPUT_DIR"

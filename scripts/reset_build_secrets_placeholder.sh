#!/bin/sh

set -eu

OUTPUT_FILE="${SRCROOT}/S400Scale/Generated/BuildSecrets.swift"

cat > "${OUTPUT_FILE}" <<'EOF'
import Foundation

enum BuildSecrets {
    // Overwritten by scripts/generate_build_secrets.sh during build.
    static let defaultBindKeyHex = ""
    static let defaultScaleMACAddress = ""
}
EOF

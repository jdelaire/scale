#!/bin/sh

set -eu

ENV_FILE="${SRCROOT}/.env"
OUTPUT_FILE="${SRCROOT}/S400Scale/Generated/BuildSecrets.swift"

if [ ! -f "${ENV_FILE}" ]; then
    echo "error: Missing ${ENV_FILE}. Copy .env.example to .env and set DEFAULT_BIND_KEY_HEX / DEFAULT_SCALE_MAC_ADDRESS."
    exit 1
fi

set -a
. "${ENV_FILE}"
set +a

: "${DEFAULT_BIND_KEY_HEX:?error: DEFAULT_BIND_KEY_HEX is missing from .env}"
: "${DEFAULT_SCALE_MAC_ADDRESS:?error: DEFAULT_SCALE_MAC_ADDRESS is missing from .env}"

BIND_KEY_HEX="$(printf '%s' "${DEFAULT_BIND_KEY_HEX}" | tr -d '[:space:]')"
SCALE_MAC_ADDRESS="$(printf '%s' "${DEFAULT_SCALE_MAC_ADDRESS}" | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')"

case "${BIND_KEY_HEX}" in
    (*[!0-9A-Fa-f]*|'')
        echo "error: DEFAULT_BIND_KEY_HEX must be exactly 32 hexadecimal characters."
        exit 1
        ;;
esac

if [ "${#BIND_KEY_HEX}" -ne 32 ]; then
    echo "error: DEFAULT_BIND_KEY_HEX must be exactly 32 hexadecimal characters."
    exit 1
fi

if ! printf '%s' "${SCALE_MAC_ADDRESS}" | grep -Eq '^[0-9A-F]{2}(:[0-9A-F]{2}){5}$'; then
    echo "error: DEFAULT_SCALE_MAC_ADDRESS must match AA:BB:CC:DD:EE:FF."
    exit 1
fi

mkdir -p "$(dirname "${OUTPUT_FILE}")"

TMP_FILE="$(mktemp)"
cat > "${TMP_FILE}" <<EOF
import Foundation

enum BuildSecrets {
    static let defaultBindKeyHex = "${BIND_KEY_HEX}"
    static let defaultScaleMACAddress = "${SCALE_MAC_ADDRESS}"
}
EOF

if ! cmp -s "${TMP_FILE}" "${OUTPUT_FILE}" 2>/dev/null; then
    mv "${TMP_FILE}" "${OUTPUT_FILE}"
else
    rm -f "${TMP_FILE}"
fi

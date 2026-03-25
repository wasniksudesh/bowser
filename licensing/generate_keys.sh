#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PRIVATE_PEM="$SCRIPT_DIR/private.pem"
PUBLIC_PEM="$SCRIPT_DIR/public.pem"

echo "=== Bowser License Key Pair Generator ==="
echo ""

# Generate Ed25519 private key
openssl genpkey -algorithm Ed25519 -out "$PRIVATE_PEM" 2>/dev/null
echo "Private key written to: $PRIVATE_PEM"

# Extract public key
openssl pkey -in "$PRIVATE_PEM" -pubout -out "$PUBLIC_PEM" 2>/dev/null
echo "Public key written to:  $PUBLIC_PEM"

echo ""
echo "--- For LicenseService.swift (publicKeyHex) ---"
# DER-encoded Ed25519 public key is 44 bytes: 12-byte header + 32-byte raw key
PUBLIC_KEY_HEX=$(openssl pkey -in "$PUBLIC_PEM" -pubin -outform DER 2>/dev/null | tail -c 32 | xxd -p | tr -d '\n')
echo "$PUBLIC_KEY_HEX"

echo ""
echo "--- For Lambda env var SIGNING_PRIVATE_KEY (base64 of PEM) ---"
PRIVATE_KEY_B64=$(base64 < "$PRIVATE_PEM" | tr -d '\n')
echo "$PRIVATE_KEY_B64"

echo ""
echo "=== Done ==="
echo ""
echo "Next steps:"
echo "  1. Paste publicKeyHex into LicenseService.swift"
echo "  2. Set SIGNING_PRIVATE_KEY env var in Lambda to the base64 value above"
echo "  3. Keep private.pem safe — do NOT commit it to git"

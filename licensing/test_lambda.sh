#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PUBLIC_PEM="$SCRIPT_DIR/public.pem"
LAMBDA_URL="https://f2kanwumt4wz4xrxfistvimi6y0ndplb.lambda-url.us-west-2.on.aws/"

# Default test values — override with env vars or args
LICENSE_KEY="BOWSER-1234-5678-9123"
NONCE=$(uuidgen 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())")
MACHINE_ID=$(ioreg -d2 -c IOPlatformExpertDevice | awk -F'"' '/IOPlatformUUID/{print $4}' 2>/dev/null || echo "test-machine")

echo "=== Bowser Lambda License Verification Test ==="
echo ""
echo "Lambda URL:   $LAMBDA_URL"
echo "License key:  $LICENSE_KEY"
echo "Machine ID:   $MACHINE_ID"
echo "Nonce:        $NONCE"
echo ""

# Build request
REQUEST_JSON=$(python3 -c "
import json
print(json.dumps({
    'license_key': '$LICENSE_KEY',
    'machine_id': '$MACHINE_ID',
    'nonce': '$NONCE'
}))
")

echo "--- Request ---"
echo "$REQUEST_JSON" | python3 -m json.tool
echo ""

# Call Lambda
echo "--- Calling Lambda... ---"
HTTP_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "$REQUEST_JSON" \
    "$LAMBDA_URL")

HTTP_BODY=$(echo "$HTTP_RESPONSE" | sed '$d')
HTTP_CODE=$(echo "$HTTP_RESPONSE" | tail -1)

echo "HTTP Status: $HTTP_CODE"
echo ""

if [ "$HTTP_CODE" != "200" ]; then
    echo "ERROR: Lambda returned HTTP $HTTP_CODE"
    echo "$HTTP_BODY"
    exit 1
fi

echo "--- Raw Response ---"
echo "$HTTP_BODY" | python3 -m json.tool
echo ""

# Decode and verify with Python + cryptography
echo "--- Decoded Payload & Signature Verification ---"
python3 - "$HTTP_BODY" "$NONCE" "$PUBLIC_PEM" <<'PYEOF'
import sys
import json
import base64

raw_response = sys.argv[1]
expected_nonce = sys.argv[2]
public_pem_path = sys.argv[3]

response = json.loads(raw_response)
payload_b64 = response["payload"]
signature_b64 = response["signature"]

payload_bytes = base64.b64decode(payload_b64)
signature_bytes = base64.b64decode(signature_b64)
payload = json.loads(payload_bytes)

print("Payload:")
print(json.dumps(payload, indent=2))
print()

# Verify signature
try:
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
    from cryptography.hazmat.primitives import serialization

    with open(public_pem_path, "rb") as f:
        public_key = serialization.load_pem_public_key(f.read())

    public_key.verify(signature_bytes, payload_bytes)
    print("Signature:  VALID")
except ImportError:
    # Fallback: use openssl via subprocess
    import subprocess, tempfile, os
    with tempfile.NamedTemporaryFile(delete=False, suffix=".bin") as pf:
        pf.write(payload_bytes)
        payload_file = pf.name
    with tempfile.NamedTemporaryFile(delete=False, suffix=".sig") as sf:
        sf.write(signature_bytes)
        sig_file = sf.name
    try:
        subprocess.run(
            ["openssl", "pkeyutl", "-verify", "-pubin",
             "-inkey", public_pem_path,
             "-rawin", "-in", payload_file, "-sigfile", sig_file],
            check=True, capture_output=True, text=True
        )
        print("Signature:  VALID (verified via openssl)")
    except subprocess.CalledProcessError:
        print("Signature:  INVALID")
        sys.exit(1)
    finally:
        os.unlink(payload_file)
        os.unlink(sig_file)
except Exception as e:
    print(f"Signature:  INVALID — {e}")
    sys.exit(1)

# Check nonce
if payload.get("valid"):
    if payload.get("nonce") == expected_nonce:
        print(f"Nonce:      MATCH")
    else:
        print(f"Nonce:      MISMATCH (expected {expected_nonce}, got {payload.get('nonce')})")
        sys.exit(1)

    import datetime
    expiry = payload.get("expiry", 0)
    expiry_dt = datetime.datetime.fromtimestamp(expiry)
    print(f"Expiry:     {expiry_dt.isoformat()} ({'VALID' if expiry > datetime.datetime.now().timestamp() else 'EXPIRED'})")
    print(f"Machine:    {'match' if payload.get('machine_match') else 'MISMATCH'}")
else:
    print(f"Reason:     {payload.get('reason')}")
    print(f"Message:    {payload.get('message')}")

print()
print("=== Test complete ===")
PYEOF

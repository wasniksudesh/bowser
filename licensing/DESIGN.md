# Bowser Licensing System — Design Document

## Overview

Bowser uses a server-verified licensing system. On startup the client sends
its license key to an AWS Lambda function which validates it against DynamoDB
and returns a **signed** response. The client verifies the signature using an
embedded Ed25519 public key. The private key **never** leaves the server.

---

## Protocol

```
Client                              Lambda                     DynamoDB
  |                                    |                           |
  |-- POST {license_key,              |                           |
  |         machine_id, nonce} ------->|                           |
  |                                    |-- GetItem PK/SK --------->|
  |                                    |<-- {expiry, machine_id,   |
  |                                    |     is_active} -----------|
  |                                    |                           |
  |                                    | validate, sign payload    |
  |<-- {payload_b64, signature_b64} ---|                           |
  |                                    |                           |
  | verify signature (embedded pubkey) |                           |
  | check nonce, expiry                |                           |
  | store key in Keychain              |                           |
  | proceed to app                     |                           |
```

### Request (Client → Lambda)

```json
{
  "license_key": "ACME-ABC1-DEF2-GHI3",
  "machine_id":  "8A1B2C3D-4E5F-6789-ABCD-EF0123456789",
  "nonce":       "550e8400-e29b-41d4-a716-446655440000"
}
```

- `license_key` — user-entered string. First segment is the org ID, remainder
  is the license suffix, split on the first `-`.
- `machine_id` — macOS Hardware UUID from `IOPlatformExpertDevice`.
- `nonce` — random UUID generated per request to prevent replay attacks.

### Response (Lambda → Client)

```json
{
  "payload":   "<base64 of canonical JSON>",
  "signature": "<base64 of Ed25519 signature over the canonical JSON bytes>"
}
```

Decoded payload on success:

```json
{
  "valid": true,
  "org_id": "ACME",
  "expiry": 1774224000,
  "nonce": "550e8400-e29b-41d4-a716-446655440000",
  "issued_at": 1711324800,
  "machine_match": true
}
```

Decoded payload on failure:

```json
{
  "valid": false,
  "reason": "expired",
  "message": "License has expired",
  "issued_at": 1711324800
}
```

### Verification Steps (Client)

1. Base64-decode `payload` and `signature`.
2. Verify `signature` over the raw payload bytes using the embedded Ed25519
   public key (`CryptoKit.Curve25519.Signing.PublicKey`).
3. Parse the JSON payload.
4. Confirm `nonce` matches the one sent in the request.
5. Confirm `valid == true` and `expiry > now`.

---

## License Key Format

Single string: `ORGID-XXXX-XXXX-XXXX`

- Split on first `-`: org = `ORGID`, suffix = `XXXX-XXXX-XXXX`
- DynamoDB lookup: `PK = ORG#ORGID`, `SK = LIC#XXXX-XXXX-XXXX`

Example: user enters `ACME-ABC1-DEF2-GHI3`
→ PK = `ORG#ACME`, SK = `LIC#ABC1-DEF2-GHI3`

---

## DynamoDB Table

**Table name:** `bowser-licenses`

| Attribute   | Type    | Example               | Notes                           |
|-------------|---------|------------------------|---------------------------------|
| PK          | String  | `ORG#ACME`            | Partition key — organization    |
| SK          | String  | `LIC#ABC1-DEF2-GHI3`  | Sort key — license suffix       |
| expiry_date | Number  | `1774224000`           | Unix epoch seconds              |
| machine_id  | String  | `8A1B-...-EF01`       | Hardware UUID (set on first use)|
| is_active   | Boolean | `true`                 | Emergency kill-switch           |

### Create Table

```bash
aws dynamodb create-table \
  --table-name bowser-licenses \
  --attribute-definitions \
    AttributeName=PK,AttributeType=S \
    AttributeName=SK,AttributeType=S \
  --key-schema \
    AttributeName=PK,KeyType=HASH \
    AttributeName=SK,KeyType=RANGE \
  --billing-mode PAY_PER_REQUEST
```

### Insert Sample Record

```bash
aws dynamodb put-item \
  --table-name bowser-licenses \
  --item '{
    "PK":          {"S": "ORG#ACME"},
    "SK":          {"S": "LIC#ABC1-DEF2-GHI3"},
    "expiry_date": {"N": "1774224000"},
    "machine_id":  {"S": ""},
    "is_active":   {"BOOL": true}
  }'
```

---

## Ed25519 Key Generation

Run once. Store the private key in Lambda, embed the public key in the Swift
binary.

```bash
# Generate private key
openssl genpkey -algorithm Ed25519 -out private.pem

# Extract public key
openssl pkey -in private.pem -pubout -out public.pem

# Base64-encode private PEM for Lambda env var
base64 < private.pem          # → set as SIGNING_PRIVATE_KEY

# Extract raw 32-byte public key for Swift embedding
openssl pkey -in public.pem -pubin -outform DER | tail -c 32 | xxd -p
# → paste into LicenseService.swift as the publicKeyBytes constant
```

---

## AWS Lambda Function

**Runtime:** Python 3.12
**Handler:** `lambda_function.lambda_handler`
**Function URL:** public (auth type `NONE`)
**Environment variables:**

| Variable             | Value                                  |
|----------------------|----------------------------------------|
| `TABLE_NAME`         | `bowser-licenses`                      |
| `SIGNING_PRIVATE_KEY`| Base64-encoded PEM of Ed25519 key      |

### Dependencies

The `cryptography` library is required (not in default Lambda runtime).
Package as a Lambda Layer using Docker (native C extensions must be compiled
for Amazon Linux, not macOS):

```bash
# Use the build script:
./licensing/build_lambda_layer.sh

# Or manually with Docker:
mkdir -p _layer/python/lib/python3.12/site-packages
docker run --rm -v "$PWD/_layer":/out --platform linux/amd64 \
    public.ecr.aws/sam/build-python3.12 \
    pip install cryptography -t /out/python/lib/python3.12/site-packages/ --quiet
cd _layer && zip -r ../lambda_layer.zip python/

# Publish and attach:
aws lambda publish-layer-version \
    --layer-name cryptography-py312 \
    --compatible-runtimes python3.12 \
    --compatible-architectures x86_64 \
    --zip-file fileb://lambda_layer.zip

aws lambda update-function-configuration \
    --function-name YOUR_FUNCTION_NAME \
    --layers LAYER_ARN_FROM_ABOVE
```

**IMPORTANT**: Do NOT run `pip install` directly on macOS — the `cryptography`
package has C extensions that produce `.dylib` (macOS) instead of `.so` (Linux).
The zip directory structure must have packages inside `python/` (not at root)
for Lambda to add them to `sys.path`.

### Complete Code (`lambda_function.py`)

```python
import json
import os
import time
import base64
import boto3
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives import serialization

dynamodb = boto3.resource("dynamodb")
TABLE_NAME = os.environ["TABLE_NAME"]
table = dynamodb.Table(TABLE_NAME)

_pem_b64 = os.environ["SIGNING_PRIVATE_KEY"]
_pem_bytes = base64.b64decode(_pem_b64)
PRIVATE_KEY: Ed25519PrivateKey = serialization.load_pem_private_key(
    _pem_bytes, password=None
)


def lambda_handler(event, context):
    try:
        body = json.loads(event.get("body", "{}"))
    except (json.JSONDecodeError, TypeError):
        return _error_response("malformed_request", "Invalid JSON body")

    license_key = body.get("license_key", "").strip()
    client_machine_id = body.get("machine_id", "").strip()
    nonce = body.get("nonce", "").strip()

    if not license_key or not nonce:
        return _error_response(
            "missing_fields", "license_key and nonce are required"
        )

    parts = license_key.split("-", 1)
    if len(parts) != 2 or not parts[0] or not parts[1]:
        return _error_response(
            "invalid_format", "Expected format: ORGID-XXXX-XXXX-XXXX"
        )

    org_id = parts[0].upper()
    license_suffix = parts[1].upper()

    pk = f"ORG#{org_id}"
    sk = f"LIC#{license_suffix}"

    try:
        resp = table.get_item(Key={"PK": pk, "SK": sk})
    except Exception as e:
        print(f"DynamoDB error: {e}")
        return _error_response("internal_error", "Database lookup failed")

    item = resp.get("Item")
    if not item:
        return _error_response("not_found", "License key not found")

    is_active = item.get("is_active", False)
    if not is_active:
        return _error_response("deactivated", "License has been deactivated")

    expiry_date = int(item.get("expiry_date", 0))
    now = int(time.time())
    if expiry_date <= now:
        return _error_response("expired", "License has expired")

    stored_machine_id = item.get("machine_id", "")
    if not stored_machine_id and client_machine_id:
        try:
            table.update_item(
                Key={"PK": pk, "SK": sk},
                UpdateExpression="SET machine_id = :mid",
                ExpressionAttributeValues={":mid": client_machine_id},
            )
            stored_machine_id = client_machine_id
        except Exception as e:
            print(f"Failed to store machine_id: {e}")

    machine_match = True
    if stored_machine_id and client_machine_id:
        machine_match = stored_machine_id == client_machine_id
        if not machine_match:
            print(
                f"Machine mismatch: stored={stored_machine_id}, "
                f"client={client_machine_id}"
            )

    payload = {
        "valid": True,
        "org_id": org_id,
        "expiry": expiry_date,
        "nonce": nonce,
        "issued_at": now,
        "machine_match": machine_match,
    }
    return _signed_response(payload)


def _error_response(code, message):
    payload = {
        "valid": False,
        "reason": code,
        "message": message,
        "issued_at": int(time.time()),
    }
    return _signed_response(payload, status_code=200)


def _signed_response(payload, status_code=200):
    payload_json = json.dumps(payload, separators=(",", ":"), sort_keys=True)
    payload_b64 = base64.b64encode(payload_json.encode()).decode()

    signature = PRIVATE_KEY.sign(payload_json.encode())
    signature_b64 = base64.b64encode(signature).decode()

    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(
            {"payload": payload_b64, "signature": signature_b64}
        ),
    }
```

---

## Client Implementation (macOS / Swift)

### Storage

- **License key** → macOS Keychain (`com.bowser.license` / `license-key`)
- **Last-verified timestamp** → Keychain (`com.bowser.license` / `last-verified`)
- **Cached expiry** → Keychain (`com.bowser.license` / `cached-expiry`)

### Machine ID

Hardware UUID via IOKit `IOPlatformExpertDevice` → `kIOPlatformUUIDKey`.

### Grace Period

If the daily background check fails due to network error, the app continues
operating for up to **7 days** from the last successful verification. After
that, the license gate reappears.

### Startup Flow

1. Check Keychain for stored license key.
2. If found → verify with Lambda in background.
   - If valid → proceed to app.
   - If network fails → check grace period; proceed if within 7 days.
   - If invalid/expired → show license entry screen.
3. If not found → show license entry screen.

### Daily Background Check

A 24-hour repeating task calls the Lambda endpoint with the stored key. On
failure beyond the grace period, the app returns to the license entry screen.

---

## Threat Model

| Threat                              | Mitigation                                    | Residual Risk        |
|-------------------------------------|-----------------------------------------------|----------------------|
| Replay captured valid response      | Nonce per request; client checks nonce match   | None                 |
| Forge server response               | Ed25519 signature; public key in binary        | None without privkey |
| MITM / local proxy                  | HTTPS + signature verification                 | None                 |
| Extract public key from binary      | Public key is safe to expose by design         | None                 |
| Patch binary to skip license check  | Acceptable for <20 trusted users               | Low                  |
| Brute-force license keys            | Key space is large; add rate-limit later       | Low                  |
| Share key across machines           | machine_id stored (not enforced yet)           | Low (logged)         |
| Steal key from Keychain             | Requires macOS login; Keychain is encrypted    | Very low             |

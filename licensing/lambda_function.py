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

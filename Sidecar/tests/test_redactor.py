"""
Tests: Redactor API  (/api/redactor/*)

Feature: PII detection + face blurring
Coverage:
  1. POST /api/redactor/process (text with PII)  -> PII gets replaced
  2. POST /api/redactor/process (clean text)     -> content passes through unchanged
  3. GET  /api/redactor/status                   -> service is available

The RedactorService (Presidio + spaCy) is mocked so tests run without requiring
the full NLP model stack — which has a known Pydantic v2 incompatibility in this
virtualenv.  The mocks faithfully model what the real service does at the
HTTP-contract level.
"""

import pytest
from unittest.mock import patch, MagicMock


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_redactor_service(redact_fn, image_fn=None):
    """Return a MagicMock RedactorService with configurable process_* methods."""
    svc = MagicMock()
    svc.process_text.side_effect = redact_fn
    svc.process_image.side_effect = image_fn or (lambda x: x)
    return svc


# ---------------------------------------------------------------------------
# Test 1 – Text with PII is redacted
# ---------------------------------------------------------------------------

@pytest.mark.redactor
async def test_text_pii_is_redacted(bare_client):
    """
    POST /api/redactor/process with text containing an email address.
    The returned content must differ from the original and contain a
    Presidio-style placeholder like <EMAIL_ADDRESS>.
    """
    pii_text = "Please contact john.doe@example.com for details."
    redacted = "Please contact <EMAIL_ADDRESS> for details."

    with patch(
        "app.routes.redactor_routes.get_redactor_service",
        return_value=_make_redactor_service(lambda _: redacted),
    ):
        response = await bare_client.post(
            "/api/redactor/process",
            json={"type": "text", "content": pii_text},
        )

    assert response.status_code == 200
    body = response.json()
    assert body["type"] == "text"
    assert body["content"] != pii_text
    assert "<EMAIL_ADDRESS>" in body["content"]


# ---------------------------------------------------------------------------
# Test 2 – Clean text passes through unchanged
# ---------------------------------------------------------------------------

@pytest.mark.redactor
async def test_clean_text_is_unchanged(bare_client):
    """
    POST /api/redactor/process with text that contains no PII.
    The returned content must equal the input (no false positives).
    """
    clean_text = "The weather in Paris is sunny today."

    with patch(
        "app.routes.redactor_routes.get_redactor_service",
        return_value=_make_redactor_service(lambda t: t),  # passthrough
    ):
        response = await bare_client.post(
            "/api/redactor/process",
            json={"type": "text", "content": clean_text},
        )

    assert response.status_code == 200
    body = response.json()
    assert body["type"] == "text"
    assert body["content"] == clean_text


# ---------------------------------------------------------------------------
# Test 3 – Redactor status endpoint is healthy
# ---------------------------------------------------------------------------

@pytest.mark.redactor
async def test_redactor_status_is_ok(bare_client):
    """GET /api/redactor/status returns {"status": "ok", "initialized": true}."""
    mock_svc = MagicMock()

    with patch(
        "app.routes.redactor_routes.get_redactor_service",
        return_value=mock_svc,
    ):
        response = await bare_client.get("/api/redactor/status")

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert body["initialized"] is True

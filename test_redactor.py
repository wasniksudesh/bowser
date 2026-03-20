#!/usr/bin/env python3
"""
Test script for the redactor feature
Tests both the Python backend service and integration
"""

import sys
import json
import base64
import requests
from pathlib import Path

# Test configuration
BACKEND_URL = "http://localhost:8765"
REDACTOR_ENDPOINT = f"{BACKEND_URL}/api/redactor/process"

def test_text_redaction():
    """Test text PII redaction"""
    print("\n=== Testing Text Redaction ===")
    
    test_cases = [
        {
            "name": "SSN",
            "text": "My SSN is 123-45-6789",
            "expected_contains": "<"
        },
        {
            "name": "Email",
            "text": "Contact me at john.doe@example.com",
            "expected_contains": "<"
        },
        {
            "name": "Phone",
            "text": "Call me at (555) 123-4567",
            "expected_contains": "<"
        },
        {
            "name": "Name",
            "text": "My name is John Smith and I live in New York",
            "expected_contains": "<"
        },
        {
            "name": "No PII",
            "text": "This is a simple sentence with no personal information",
            "expected_contains": None  # Should remain unchanged
        }
    ]
    
    for test in test_cases:
        try:
            response = requests.post(
                REDACTOR_ENDPOINT,
                json={"type": "text", "content": test["text"]},
                timeout=5
            )
            
            if response.status_code == 200:
                result = response.json()
                redacted = result["content"]
                
                if test["expected_contains"]:
                    if test["expected_contains"] in redacted and redacted != test["text"]:
                        print(f"✓ {test['name']}: PASS")
                        print(f"  Original: {test['text']}")
                        print(f"  Redacted: {redacted}")
                    else:
                        print(f"✗ {test['name']}: FAIL - Expected redaction")
                else:
                    if redacted == test["text"]:
                        print(f"✓ {test['name']}: PASS (no redaction needed)")
                    else:
                        print(f"⚠ {test['name']}: WARNING - Unexpected redaction")
                        print(f"  Original: {test['text']}")
                        print(f"  Redacted: {redacted}")
            else:
                print(f"✗ {test['name']}: FAIL - HTTP {response.status_code}")
                
        except Exception as e:
            print(f"✗ {test['name']}: ERROR - {e}")

def test_image_redaction():
    """Test image face blurring"""
    print("\n=== Testing Image Redaction ===")
    
    # Create a simple test image (1x1 pixel PNG)
    # In a real test, you would use an image with faces
    test_image_base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
    data_url = f"data:image/png;base64,{test_image_base64}"
    
    try:
        response = requests.post(
            REDACTOR_ENDPOINT,
            json={"type": "image", "content": data_url},
            timeout=10
        )
        
        if response.status_code == 200:
            result = response.json()
            if result["type"] == "image" and result["content"].startswith("data:image/png;base64,"):
                print("✓ Image processing: PASS")
                print("  Image was processed and returned as data URL")
            else:
                print("✗ Image processing: FAIL - Invalid response format")
        else:
            print(f"✗ Image processing: FAIL - HTTP {response.status_code}")
            
    except Exception as e:
        print(f"✗ Image processing: ERROR - {e}")

def test_backend_status():
    """Test backend health"""
    print("\n=== Testing Backend Status ===")
    
    try:
        response = requests.get(f"{BACKEND_URL}/api/redactor/status", timeout=5)
        if response.status_code == 200:
            status = response.json()
            print(f"✓ Backend status: {status}")
        else:
            print(f"✗ Backend status: HTTP {response.status_code}")
    except Exception as e:
        print(f"✗ Backend status: ERROR - {e}")

def main():
    print("=" * 60)
    print("Redactor Feature Test Suite")
    print("=" * 60)
    
    # Check if backend is running
    try:
        response = requests.get(f"{BACKEND_URL}/health", timeout=2)
        if response.status_code != 200:
            print("\n⚠ WARNING: Backend is not healthy")
            print("Make sure the Sidecar backend is running:")
            print("  cd Sidecar && python -m uvicorn app.main:app --reload --port 8765")
            return 1
    except Exception as e:
        print(f"\n✗ ERROR: Cannot connect to backend at {BACKEND_URL}")
        print(f"  {e}")
        print("\nMake sure the Sidecar backend is running:")
        print("  cd Sidecar && python -m uvicorn app.main:app --reload --port 8765")
        return 1
    
    print("\n✓ Backend is running")
    
    # Run tests
    test_backend_status()
    test_text_redaction()
    test_image_redaction()
    
    print("\n" + "=" * 60)
    print("Test suite completed")
    print("=" * 60)
    print("\nNext steps:")
    print("1. Install Python dependencies: cd Sidecar && pip install -r requirements.txt")
    print("2. Test in the app: Enable redactor in Settings > Privacy & Security")
    print("3. Copy text with PII and paste into a web page")
    print("4. Copy an image with faces and paste into a web page")
    print("=" * 60)
    
    return 0

if __name__ == "__main__":
    sys.exit(main())

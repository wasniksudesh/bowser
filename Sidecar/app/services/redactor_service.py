"""
Redactor Service - Content Redaction for Images and Text
Handles PII redaction in text and face blurring in images
"""

import base64
import logging
import warnings
from typing import Optional

import cv2
import numpy as np
from presidio_analyzer import AnalyzerEngine
from presidio_anonymizer import AnonymizerEngine

# Suppress non-critical warnings
logging.getLogger('presidio-analyzer').setLevel(logging.ERROR)
warnings.filterwarnings("ignore")


class RedactorService:
    """Service for redacting sensitive content in text and images"""
    
    def __init__(self):
        """Initialize Presidio engines and OpenCV face cascade"""
        self.analyzer = AnalyzerEngine()
        self.anonymizer = AnonymizerEngine()
        
        # Load face cascade classifier
        cascade_path = cv2.data.haarcascades + 'haarcascade_frontalface_default.xml'
        self.face_cascade = cv2.CascadeClassifier(cascade_path)
        
        # Verify cascade loaded successfully
        if self.face_cascade.empty():
            raise RuntimeError(f"Failed to load face cascade from {cascade_path}")
        
        logging.info("RedactorService initialized successfully")
    
    def process_image(self, base64_str: str) -> str:
        """
        Process an image to blur detected faces
        
        Args:
            base64_str: Base64-encoded image (with or without data URL prefix)
            
        Returns:
            Base64-encoded image with blurred faces (data URL format)
            
        Raises:
            Exception: If image processing fails
        """
        try:
            # Remove data URL prefix if present
            encoded_data = base64_str.split(',')[1] if ',' in base64_str else base64_str
            
            # Decode base64 to numpy array
            nparr = np.frombuffer(base64.b64decode(encoded_data), np.uint8)
            img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
            
            if img is None:
                raise ValueError("Failed to decode image")
            
            # Convert to grayscale for face detection
            gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
            
            # Detect faces
            faces = self.face_cascade.detectMultiScale(gray, 1.1, 4)
            
            # Blur each detected face
            for (x, y, w, h) in faces:
                roi = img[y:y+h, x:x+w]
                img[y:y+h, x:x+w] = cv2.GaussianBlur(roi, (99, 99), 30)
            
            # Encode back to base64
            _, buffer = cv2.imencode('.png', img)
            result = "data:image/png;base64," + base64.b64encode(buffer).decode('utf-8')
            
            logging.info(f"Processed image, blurred {len(faces)} face(s)")
            return result
            
        except Exception as e:
            logging.error(f"Image processing error: {e}")
            raise
    
    def process_text(self, text: str) -> str:
        """
        Process text to redact PII (Personally Identifiable Information)
        
        Args:
            text: Plain text to redact
            
        Returns:
            Text with PII replaced by entity type placeholders
            
        Raises:
            Exception: If text processing fails
        """
        try:
            # Return empty text as-is
            if not text or not text.strip():
                return text
            
            # Analyze text for PII
            results = self.analyzer.analyze(text=text, language='en')
            
            # Anonymize detected PII
            redacted = self.anonymizer.anonymize(text=text, analyzer_results=results)
            
            logging.info(f"Processed text, redacted {len(results)} PII entity(ies)")
            return redacted.text
            
        except Exception as e:
            logging.error(f"Text processing error: {e}")
            raise


# Global service instance
_redactor_service: Optional[RedactorService] = None


def get_redactor_service() -> RedactorService:
    """Get or create the global RedactorService instance"""
    global _redactor_service
    if _redactor_service is None:
        _redactor_service = RedactorService()
    return _redactor_service

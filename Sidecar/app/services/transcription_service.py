# transcription_service.py - OpenAI Whisper audio transcription service
# Accepts raw audio bytes (WAV) and returns transcribed text.
# Reused by both the meeting recorder and the voice-to-text mic button.

import io
import logging
import os
from typing import Optional

logger = logging.getLogger(__name__)

# Lazily-initialised OpenAI client (populated after /api/configure is called)
_openai_client = None


def set_openai_client(client) -> None:
    """Called by ai_routes or configure endpoint after API key is available."""
    global _openai_client
    _openai_client = client
    logger.info("[Transcription] OpenAI client set")


def get_openai_client():
    """Return the current OpenAI client, or build one from env if needed."""
    global _openai_client
    if _openai_client is not None:
        return _openai_client

    # Fallback: try to build from environment variable
    api_key = os.getenv("OPENAI_API_KEY") or os.getenv("AI_API_KEY")
    if api_key:
        try:
            from openai import AsyncOpenAI
            _openai_client = AsyncOpenAI(api_key=api_key)
            logger.info("[Transcription] Built OpenAI client from environment")
            return _openai_client
        except Exception as e:
            logger.error(f"[Transcription] Failed to build OpenAI client: {e}")

    return None


async def transcribe_audio(audio_bytes: bytes, filename: str = "audio.wav") -> str:
    """
    Transcribe raw audio bytes using OpenAI Whisper API.

    Args:
        audio_bytes: Raw audio file bytes (WAV, MP3, M4A, etc.)
        filename: Filename hint passed to the API (affects format detection)

    Returns:
        Transcribed text string, or empty string on failure.
    """
    client = get_openai_client()
    if client is None:
        logger.warning("[Transcription] No OpenAI client available; configure API key first")
        return ""

    if not audio_bytes:
        return ""

    try:
        audio_file = io.BytesIO(audio_bytes)
        audio_file.name = filename  # OpenAI SDK uses .name to determine format

        response = await client.audio.transcriptions.create(
            model="whisper-1",
            file=audio_file,
            response_format="text",
        )
        # response is a plain str when response_format="text"
        text = response.strip() if isinstance(response, str) else str(response).strip()
        logger.debug(f"[Transcription] Result: {text[:80]}...")
        return text

    except Exception as e:
        logger.error(f"[Transcription] Whisper API error: {e}")
        return ""

# transcribe_routes.py - Audio transcription endpoint
# POST /api/transcribe - accepts multipart WAV audio, returns Whisper transcript
# Used by both the meeting recorder (5s chunks) and voice-to-text mic button.

import logging
from datetime import datetime

from fastapi import APIRouter, File, HTTPException, UploadFile
from fastapi.responses import JSONResponse

from app.services.transcription_service import transcribe_audio

logger = logging.getLogger(__name__)

router = APIRouter()


@router.post("")
async def transcribe_chunk(audio: UploadFile = File(...)):
    """
    Transcribe an uploaded audio chunk using OpenAI Whisper.

    Accepts:
        audio: multipart/form-data WAV (or any Whisper-supported format)

    Returns:
        { "text": "transcribed text", "timestamp": "ISO8601" }
    """
    try:
        audio_bytes = await audio.read()

        if not audio_bytes:
            raise HTTPException(status_code=400, detail="Empty audio file")

        logger.info(
            f"[Transcribe] Received {len(audio_bytes)} bytes "
            f"(filename={audio.filename}, content_type={audio.content_type})"
        )

        filename = audio.filename or "audio.wav"
        text = await transcribe_audio(audio_bytes, filename=filename)

        return JSONResponse(
            content={
                "text": text,
                "timestamp": datetime.utcnow().isoformat(),
            }
        )

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"[Transcribe] Unhandled error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

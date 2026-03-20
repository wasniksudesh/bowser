"""
Bowser AI Sidecar - Application Entry Point

This is the main entry point for the Sidecar application.
The actual application logic is in app/main.py
"""

if __name__ == "__main__":
    import uvicorn
    import logging
    
    logger = logging.getLogger(__name__)
    logger.info("Starting Bowser AI Sidecar...")
    logger.info("Listening on http://localhost:8765")
    
    uvicorn.run(
        "app.main:app",
        host="127.0.0.1",
        port=8765,
        reload=True,  # Enable hot reload for development
        log_level="info"
    )

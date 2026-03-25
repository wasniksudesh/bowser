"""
vsock_transport.py
ASGI server that listens on vsock instead of TCP

This allows the FastAPI backend to communicate with the Swift app
through the VM's vsock device without needing network access.
"""

import asyncio
import socket
import sys
import logging
from typing import Optional

logger = logging.getLogger(__name__)

# vsock constants
VMADDR_CID_HOST = 2        # Host (macOS) CID — used only as a reference, not for bind
VMADDR_CID_ANY = 0xFFFFFFFF  # Bind to any CID so the guest listens on its own CID
VMADDR_PORT_ANY = -1       # Let kernel assign port

# Import vsock support if available
try:
    import socket
    # On Linux, vsock is available through AF_VSOCK
    if hasattr(socket, 'AF_VSOCK'):
        AF_VSOCK = socket.AF_VSOCK
        HAS_VSOCK = True
    else:
        HAS_VSOCK = False
        logger.warning("AF_VSOCK not available on this system")
except Exception as e:
    HAS_VSOCK = False
    logger.warning(f"vsock support not available: {e}")


class VSockServer:
    """
    ASGI server that listens on vsock
    Compatible with FastAPI/Starlette applications
    """
    
    def __init__(self, app, host: str = "0.0.0.0", port: int = 8765):
        self.app = app
        self.host = host  # Ignored for vsock, kept for compatibility
        self.port = port
        self.server = None
        
    async def _trigger_lifespan(self):
        """Run the ASGI lifespan startup so FastAPI initializes services."""
        startup_complete = asyncio.Event()
        startup_failed = False
        # This event is set when the server is shutting down, which tells the
        # lifespan handler to proceed past yield and run shutdown cleanup.
        self._shutdown_event = asyncio.Event()

        async def receive():
            # First call: trigger startup
            if not startup_complete.is_set():
                return {"type": "lifespan.startup"}
            # Subsequent calls: block until shutdown is requested
            await self._shutdown_event.wait()
            return {"type": "lifespan.shutdown"}

        async def send(message):
            nonlocal startup_failed
            if message["type"] == "lifespan.startup.complete":
                startup_complete.set()
            elif message["type"] == "lifespan.startup.failed":
                startup_failed = True
                startup_complete.set()
            elif message["type"] == "lifespan.shutdown.complete":
                pass

        scope = {"type": "lifespan", "asgi": {"version": "3.0"}}
        self._lifespan_task = asyncio.create_task(self.app(scope, receive, send))
        await startup_complete.wait()
        if startup_failed:
            raise RuntimeError("ASGI lifespan startup failed")

    async def serve(self):
        """Start the vsock server"""
        if not HAS_VSOCK:
            logger.error("Cannot start vsock server: AF_VSOCK not available")
            logger.info("Falling back to TCP server on localhost")
            from hypercorn.asyncio import serve
            from hypercorn.config import Config
            
            config = Config()
            config.bind = [f"127.0.0.1:{self.port}"]
            await serve(self.app, config)
            return

        # Trigger ASGI lifespan so FastAPI runs its startup (initializes AI agent, etc.)
        await self._trigger_lifespan()
        
        logger.info(f"Starting vsock server on port {self.port}")
        
        sock = socket.socket(AF_VSOCK, socket.SOCK_STREAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind((VMADDR_CID_ANY, self.port))
        sock.listen(5)
        sock.setblocking(False)
        
        logger.info(f"vsock server listening on port {self.port}")
        
        loop = asyncio.get_event_loop()
        
        while True:
            try:
                client_sock, addr = await loop.sock_accept(sock)
                logger.info(f"Accepted vsock connection from CID {addr}")
                
                asyncio.create_task(self.handle_connection(client_sock))
                
            except Exception as e:
                logger.error(f"Error accepting connection: {e}")
                
    async def handle_connection(self, sock):
        """Handle a single vsock connection"""
        try:
            # Read HTTP request
            request_data = b""
            loop = asyncio.get_event_loop()
            
            while True:
                chunk = await loop.sock_recv(sock, 4096)
                if not chunk:
                    break
                request_data += chunk
                
                # Check if we have complete headers
                if b"\r\n\r\n" in request_data:
                    break
            
            if not request_data:
                sock.close()
                return
            
            # Parse HTTP request
            request_str = request_data.decode('utf-8', errors='replace')
            lines = request_str.split('\r\n')
            
            if not lines:
                sock.close()
                return
            
            # Parse request line
            request_line = lines[0]
            parts = request_line.split(' ')
            
            if len(parts) < 3:
                sock.close()
                return
            
            method, raw_path, _ = parts

            # Split path and query string so FastAPI/Starlette can read query params correctly
            from urllib.parse import urlparse
            parsed_path = urlparse(raw_path)
            path = parsed_path.path
            query_string = parsed_path.query.encode('utf-8')

            # Parse headers
            headers = {}
            for line in lines[1:]:
                if not line:
                    break
                if ':' in line:
                    key, value = line.split(':', 1)
                    headers[key.strip().lower()] = value.strip()
            
            # Get body if present
            body = b""
            if 'content-length' in headers:
                content_length = int(headers['content-length'])
                
                # Check if body is already in request_data
                header_end = request_data.find(b"\r\n\r\n") + 4
                body = request_data[header_end:]
                
                # Read remaining body if needed
                while len(body) < content_length:
                    chunk = await loop.sock_recv(sock, content_length - len(body))
                    if not chunk:
                        break
                    body += chunk
            
            # Build ASGI scope
            scope = {
                'type': 'http',
                'asgi': {'version': '3.0'},
                'http_version': '1.1',
                'method': method,
                'scheme': 'http',
                'path': path,
                'query_string': query_string,
                'root_path': '',
                'headers': [(k.encode(), v.encode()) for k, v in headers.items()],
                'server': ('vsock', self.port),
                'client': ('vsock', 0),
            }
            
            # Handle request through ASGI app
            response_started = False
            response_data = []
            
            async def send(message):
                nonlocal response_started, response_data
                
                if message['type'] == 'http.response.start':
                    response_started = True
                    status = message['status']
                    headers = message.get('headers', [])
                    
                    # Build HTTP response
                    response = f"HTTP/1.1 {status} OK\r\n"
                    for name, value in headers:
                        response += f"{name.decode()}: {value.decode()}\r\n"
                    response += "\r\n"
                    
                    response_data.append(response.encode())
                    
                elif message['type'] == 'http.response.body':
                    body = message.get('body', b'')
                    if body:
                        response_data.append(body)
            
            async def receive():
                return {
                    'type': 'http.request',
                    'body': body,
                }
            
            # Call ASGI app
            await self.app(scope, receive, send)
            
            # Send response
            for chunk in response_data:
                await loop.sock_sendall(sock, chunk)
            
            sock.close()
            
        except Exception as e:
            logger.error(f"Error handling connection: {e}", exc_info=True)
            try:
                sock.close()
            except:
                pass


async def serve_vsock(app, port: int = 8765):
    """
    Start vsock server
    
    Args:
        app: ASGI application (e.g., FastAPI app)
        port: vsock port number
    """
    server = VSockServer(app, port=port)
    await server.serve()

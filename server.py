"""A small HTTP service that speaks text in GLaDOS's voice.

Run locally with:

    uvicorn server:app --host 0.0.0.0 --port 8000

Or use the provided Dockerfile. The models are loaded once at startup, so the
first request after the service comes up is as fast as every request after it.
"""

import io
import os
import threading
from contextlib import asynccontextmanager
from typing import Optional

import anyio
from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import HTMLResponse, Response
from pydantic import BaseModel, Field

import glados

# The maximum number of characters accepted in a single request. Long inputs
# hold the synthesizer lock for a long time, which stalls every other client.
MAX_TEXT_LENGTH = int(os.environ.get("GLADOS_MAX_TEXT_LENGTH", "1000"))

# The ONNX sessions are not meant to be driven from several threads at once,
# so synthesis is serialized. Generating a sentence takes a fraction of a
# second, so this is not a meaningful bottleneck at small scale.
_synthesizer: Optional[glados.TTS] = None
_synthesizer_lock = threading.Lock()


@asynccontextmanager
async def lifespan(app: FastAPI):
    global _synthesizer

    print("Loading models...")
    _synthesizer = await anyio.to_thread.run_sync(glados.TTS)
    print("Models loaded, ready to speak.")

    yield

    _synthesizer = None


app = FastAPI(
    title="GLaDOS Text-To-Speech",
    description="Generate GLaDOS speech audio over HTTP.",
    version="1.0.0",
    lifespan=lifespan,
)


class SpeakRequest(BaseModel):
    text: str = Field(..., description="the text to speak")
    normalize: bool = Field(
        True,
        description="expand numbers and symbols into words before speaking",
    )


def _synthesize_wav(text: str, normalize: bool) -> bytes:
    """Generate speech audio and return it as the bytes of a wave file."""
    with _synthesizer_lock:
        audio = _synthesizer.generate_speech_audio(text, normalize=normalize)

        buffer = io.BytesIO()
        _synthesizer.save_wav(audio, buffer)

        return buffer.getvalue()


async def _speak(text: str, normalize: bool) -> Response:
    if _synthesizer is None:
        raise HTTPException(status_code=503, detail="The models are still loading.")

    text = text.strip()
    if not text:
        raise HTTPException(status_code=400, detail="No text was given.")
    if len(text) > MAX_TEXT_LENGTH:
        raise HTTPException(
            status_code=413,
            detail=f"The text is longer than the {MAX_TEXT_LENGTH} character limit.",
        )

    wav = await anyio.to_thread.run_sync(_synthesize_wav, text, normalize)

    return Response(
        content=wav,
        media_type="audio/wav",
        headers={"Content-Disposition": 'inline; filename="glados.wav"'},
    )


@app.get("/health")
async def health():
    """Report whether the service is ready to take requests."""
    return {"status": "ok" if _synthesizer is not None else "loading"}


@app.post("/speak")
async def speak_post(request: SpeakRequest):
    """Generate speech audio from a JSON body."""
    return await _speak(request.text, request.normalize)


@app.get("/speak")
async def speak_get(
    text: str = Query(..., description="the text to speak"),
    normalize: bool = Query(True, description="expand numbers and symbols into words"),
):
    """Generate speech audio from query parameters.

    This exists so that a browser, or a plain `curl`, can fetch audio without
    having to build a request body.
    """
    return await _speak(text, normalize)


INDEX_PAGE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>GLaDOS Text-To-Speech</title>
<style>
  :root { color-scheme: dark; }
  body {
    margin: 0; min-height: 100vh; display: flex; align-items: center;
    justify-content: center; background: #101014; color: #e8e8ea;
    font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  }
  main { width: min(38rem, calc(100% - 2rem)); }
  h1 { font-size: 1.25rem; letter-spacing: 0.08em; text-transform: uppercase; color: #f5a623; }
  textarea {
    width: 100%; box-sizing: border-box; min-height: 7rem; padding: 0.75rem;
    background: #1a1a20; color: inherit; border: 1px solid #33333d;
    border-radius: 0.35rem; font: inherit; resize: vertical;
  }
  button {
    margin-top: 0.75rem; padding: 0.6rem 1.4rem; font: inherit; cursor: pointer;
    background: #f5a623; color: #101014; border: 0; border-radius: 0.35rem;
  }
  button[disabled] { opacity: 0.5; cursor: progress; }
  audio { width: 100%; margin-top: 1rem; }
  p.error { color: #ff6b6b; min-height: 1.2rem; }
</style>
</head>
<body>
<main>
  <h1>GLaDOS Text-To-Speech</h1>
  <textarea id="text" placeholder="Hello, and thank you, world.">Hello, and thank you, world.</textarea>
  <button id="speak">Speak</button>
  <p class="error" id="error"></p>
  <audio id="player" controls></audio>
</main>
<script>
  const button = document.getElementById("speak");
  const error = document.getElementById("error");
  const player = document.getElementById("player");
  let lastUrl = null;

  button.addEventListener("click", async () => {
    const text = document.getElementById("text").value;
    button.disabled = true;
    error.textContent = "";

    try {
      const response = await fetch("/speak", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ text })
      });

      if (!response.ok) {
        const body = await response.json().catch(() => ({}));
        throw new Error(body.detail || response.statusText);
      }

      if (lastUrl) URL.revokeObjectURL(lastUrl);
      lastUrl = URL.createObjectURL(await response.blob());
      player.src = lastUrl;
      player.play();
    } catch (e) {
      error.textContent = e.message;
    } finally {
      button.disabled = false;
    }
  });
</script>
</body>
</html>
"""


@app.get("/", response_class=HTMLResponse)
async def index():
    """A small page for trying the service from a browser."""
    return INDEX_PAGE

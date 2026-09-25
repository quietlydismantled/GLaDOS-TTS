FROM python:3.12-slim

# The models are large and rarely change, so they are downloaded in their own
# early layer. Editing the source code below does not refetch them.
ADD --chmod=444 \
    https://github.com/dnhkng/GlaDOS/releases/download/0.1/glados.onnx \
    /app/glados/models/glados.onnx
ADD --chmod=444 \
    https://github.com/dnhkng/GlaDOS/releases/download/0.1/phomenizer_en.onnx \
    /app/glados/models/phomenizer_en.onnx

WORKDIR /app

COPY requirements.txt requirements_server.txt ./
RUN pip install --no-cache-dir -r requirements_server.txt

COPY glados/ ./glados/
COPY server.py ./

# Audio is returned over HTTP rather than played on a sound card, so PortAudio
# is deliberately not installed. `glados` imports `sounddevice` only when the
# playback methods are called.

ENV PYTHONUNBUFFERED=1
EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=120s --retries=3 \
    CMD python -c "import urllib.request, json, sys; \
sys.exit(0 if json.load(urllib.request.urlopen('http://127.0.0.1:8000/health'))['status'] == 'ok' else 1)"

CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "8000"]

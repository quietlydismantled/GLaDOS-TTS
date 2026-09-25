# GLaDOS Text-To-Speech Engine
Adapted from [dnhkng's GLaDOS repository](https://github.com/dnhkng/GlaDOS).

<p align="center"><img src="resources/tts_engine.png" alt="TTS Engine Splash Screen"/></p>

Add [the evil robot](https://en.wikipedia.org/wiki/GLaDOS) to your Python project as easy as:
```python
import glados

tts = glados.TTS()
tts.speak_text_aloud("Hello, World!")
```

Find more usage options [here](#Usage)!

# Installation

## Windows
### Pre-Built Portable Executables (CPU only)
If you just want to quickly make some GLaDOS TTS speech and don't really care about writing custom code, simply download the latest portable builds [here](https://github.com/nimaid/GLaDOS-TTS/releases/latest). All you have to do is download and run your preferred `.exe` file!

### Full Installation (CPU only or CUDA accelerated)
1. Install with `install_windows.bat`. This will automatically:
   1. Ask whether you want the CPU-only or the CUDA accelerated environment
   2. Install Miniconda to `%USERPROFILE%\Miniconda3` if you don't already have `conda` (no administrator password needed)
   3. Create the `glados` Conda environment (with CUDA and CuDNN if you chose that!)
   4. Download the required model files if not already present
   5. Verify that everything imports correctly
2. Run the interactive console demo with `run_console_windows.bat`

Pass `/y` to skip the confirmation prompts and install the CPU-only environment.

## Mac
### Automatic Installation (CPU only)
1. Install with `install_mac.command`. This will automatically:
   1. Install Miniconda to `~/miniconda3` if you don't already have `conda` (no administrator password needed)
   2. Create the `glados` Conda environment
   3. Download the required model files if not already present
   4. Verify that everything imports correctly
2. Run the interactive console demo with `conda run -n glados python speak_console.py`

Pass `--yes` to skip the confirmation prompts. Note that CUDA is not available on macOS, so the CPU-only environment is always used.

### Manual Installation (CPU only)
1. Install [Miniconda](https://www.anaconda.com/download/success) if you do not have `conda` already installed.
   - [64-Bit x86 (Intel)](https://repo.anaconda.com/miniconda/Miniconda3-latest-MacOSX-x86_64.pkg)
   - [64-Bit ARM64 (Apple)](https://repo.anaconda.com/miniconda/Miniconda3-latest-MacOSX-arm64.pkg)
2. Install the Conda environment with `conda env create -f environment.yml`
3. Download the required models with `download_models_mac.command`
4. Run the interactive console demo with `conda run -n glados python speak_console.py`

## Linux
1. Install [Miniconda](https://www.anaconda.com/download/success) if you do not have `conda` already installed.
   - [64-Bit x86](https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh)
   - [64-Bit ARM64](https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-aarch64.sh)
2. Install the Conda environment with one of the following commands:
   - GPU accelerated: `conda env create -f environment_cuda.yml`
   - CPU only: `conda env create -f environment.yml`
3. Download the required models with `download_models_linux.bash`
4. Run the interactive console demo with `conda run -n glados python speak_console.py`

### A Note On Conda Channels
Recent versions of `conda` refuse to use Anaconda's `defaults` channels until you accept [Anaconda's Terms of Service](https://www.anaconda.com/legal/terms/terms-of-service). This project only needs `conda-forge`, so if you hit that error you can avoid the `defaults` channels entirely by prefixing the command:

```bash
CONDA_DEFAULT_CHANNELS=conda-forge conda env create -f environment.yml
```

`install_mac.command` and `install_windows.bat` already do this for you.
## Docker (Web Service)
You can run the engine as a small HTTP service instead of installing it locally. The image is CPU-only and downloads the models during the build, so no separate download step is needed.

1. Build and start the service with `docker compose up --build`
2. Open <http://localhost:8000> to try it from your browser

The service loads the models once at startup, which takes a little while. Until that finishes, `/health` reports `loading` and requests to `/speak` return a `503`.

### Endpoints
| Method | Path      | Description                                    |
|--------|-----------|------------------------------------------------|
| `GET`  | `/`       | A small page for trying the service            |
| `GET`  | `/health` | Reports `ok` once the models have loaded       |
| `POST` | `/speak`  | Generates a `.wav` file from a JSON body       |
| `GET`  | `/speak`  | Generates a `.wav` file from query parameters  |
| `GET`  | `/docs`   | Interactive API documentation                  |

Both `/speak` endpoints take the text to speak and an optional `normalize` flag, which expands numbers and symbols into words before speaking (it is on by default). They respond with `audio/wav`.

On Linux, macOS, or Git Bash:

```bash
curl -X POST http://localhost:8000/speak \
    -H "Content-Type: application/json" \
    -d '{"text": "Hello, and thank you, world."}' \
    --output hello.wav
```

On Windows, PowerShell parses quotes differently, so the same command has to be written one of these ways:

```powershell
Invoke-WebRequest -Uri http://localhost:8000/speak -Method Post -ContentType application/json -Body '{"text": "Hello, and thank you, world."}' -OutFile hello.wav
```

```powershell
curl.exe -X POST http://localhost:8000/speak -H "Content-Type: application/json" -d '{\"text\": \"Hello, and thank you, world.\"}' --output hello.wav
```

The `GET` endpoint avoids quoting trouble entirely, since the text is URL encoded:

```bash
curl "http://localhost:8000/speak?text=Hello%2C%20and%20thank%20you%2C%20world." --output hello.wav
```


Requests longer than 1000 characters are rejected. Change that limit with the `GLADOS_MAX_TEXT_LENGTH` environment variable.

### Running Without Docker
```bash
pip install -r requirements_server.txt
uvicorn server:app --host 0.0.0.0 --port 8000
```

Note that the container has no sound card, so it never plays audio aloud. Audio generation does not need one, and `sounddevice` is only imported when the playback methods are actually called.

# Usage

## From An Interactive GUI
<p align="center"><img src="resources/tts_console.png" alt="Interactive Console Splash Screen"/></p>

You can get this a portable `.exe` file for Windows [here](https://github.com/nimaid/GLaDOS-TTS/releases/latest/download/speak_console.exe).

This is the suggested way to quickly generate messages. After it loads the models, it is actually very fast. It usually takes a fraction of a second to generate a message.

To run the installed version:

`conda run -n glados python speak_console.py`

There is a fixed delay between messages. By default this is `0.5` seconds, but you can change it with the `-d`/`--delay` parameter followed by the number of seconds you'd like the delay to be.

There is an automatic greeting message that plays on startup. You can change this with the `-g`/`--greeting` parameter followed by your greeting message.

You can also completely disable the greeting message with the `-ng`/`--no-greet` flag.

## From The Command Line
<p align="center"><img src="resources/tts_command.png" alt="Command Line Program Splash Screen"/></p>

You can get this a portable `.exe` file for Windows [here](https://github.com/nimaid/GLaDOS-TTS/releases/latest/download/speak.exe).

This has to load the models every single time it runs, so it can be a bit slow.

`conda run -n glados python speak.py -t "Hello, command line!"`

`-t` is the short version of the `--text` parameter.

You can optionally choose to save to a `.wav` file with the `-o`/`--output` parameter followed by the desired filename.

If you want to prevent the text from being read aloud, use the `-q`/`--quiet` flag. This is useful when you just want to make a `.wav` file with the `-o` parameter.

## In Custom Code
<p align="center"><img src="resources/tts_module.png" alt="Python Module Splash Screen"/></p>

Below is a more comprehensive example of using the module in your own code.

```python
import time  # For making delays
import glados  # Import the local module

# Create a reusable text-to-speech object (this will take some time to load the AI models)
tts = glados.TTS()

# Say some long text, delay 1 second, and then move on to the next line of code
# The speech will continue in the background until it finishes or is interrupted
tts.speak_text_aloud_async("Calcium is a soft, silvery-white metal and one of the most abundant elements on Earth.")
time.sleep(1)

# Say some text and wait until it is done being spoken
# If the previous speech isn't over yet, this will interrupt it
tts.speak_text_aloud("Hello, and thank you, world.")

# Manually stop the speech playback
tts.stop_audio()

# Generate audio to a Numpy array
audio = tts.generate_speech_audio("Wow, my voice is now stored directly in your random access memory.")

# Play the generated audio back, delay 1 second, and then move on to the next line of code
tts.play_audio_async(audio)
time.sleep(1)

# Restart the audio playback and wait until it's done this time.
tts.play_audio(audio)

# Save the generated audio as a wave file
tts.save_wav(audio, "example.wav")
```

# Todo
- Apply upstream changes from main GLaDOS repo
- Fix run script on Win to detect .venv / conda / the environment
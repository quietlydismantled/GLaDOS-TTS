#!/bin/bash
#
# GLaDOS-TTS installer for macOS
#
# Installs Miniconda (if needed), creates the "glados" conda environment
# from environment.yml, and downloads the required ONNX model files.
#
# Usage:
#   ./install_mac.command          # interactive
#   ./install_mac.command --yes    # assume "yes" to all prompts
#

set -u

# First, change to the script's directory
cd "$(dirname "$0")" || exit 1

ENV_NAME="glados"
ENV_FILE="environment.yml"
ASSUME_YES=0

for arg in "$@"; do
    case "$arg" in
        -y|--yes) ASSUME_YES=1 ;;
        -h|--help)
            echo "Usage: $0 [-y|--yes]"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            exit 1
            ;;
    esac
done

info()  { echo "==> $*"; }
warn()  { echo "!!! $*" >&2; }
die()   { warn "$*"; echo; echo "Installation failed."; hold; exit 1; }

hold() {
    # Keep the terminal window open so errors are readable when double-clicked
    if [ -t 0 ]; then
        echo "Press any key to close..."
        read -r -n 1 -s
        echo
    fi
}

confirm() {
    # confirm "Question?" -> returns 0 for yes, 1 for no
    if [ "$ASSUME_YES" -eq 1 ]; then
        return 0
    fi
    local reply
    read -r -p "$1 [y/N] " reply
    case "$reply" in
        [Yy]*) return 0 ;;
        *) return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# Sanity checks
# ---------------------------------------------------------------------------

if [ "$(uname -s)" != "Darwin" ]; then
    die "This installer is for macOS only. On Linux, use conda with $ENV_FILE and download_models_linux.bash."
fi

command -v curl >/dev/null 2>&1 || die "curl is required but was not found."
[ -f "$ENV_FILE" ] || die "Could not find $ENV_FILE. Run this script from inside the repository."

case "$(uname -m)" in
    arm64)  MINICONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-MacOSX-arm64.sh" ;;
    x86_64) MINICONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-MacOSX-x86_64.sh" ;;
    *)      die "Unsupported architecture: $(uname -m)" ;;
esac

echo
echo "GLaDOS-TTS macOS installer"
echo "=========================="
echo "Architecture: $(uname -m)"
echo

# ---------------------------------------------------------------------------
# 1. Locate (or install) conda
# ---------------------------------------------------------------------------

find_conda() {
    if command -v conda >/dev/null 2>&1; then
        command -v conda
        return 0
    fi
    local candidate
    for candidate in \
        "$HOME/miniconda3/bin/conda" \
        "$HOME/miniforge3/bin/conda" \
        "$HOME/anaconda3/bin/conda" \
        "/opt/miniconda3/bin/conda" \
        "/opt/homebrew/Caskroom/miniconda/base/bin/conda" \
        "/usr/local/Caskroom/miniconda/base/bin/conda" \
        "/opt/anaconda3/bin/conda"
    do
        if [ -x "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

install_miniconda() {
    local installer="${TMPDIR:-/tmp}/miniconda_installer.sh"
    local prefix="$HOME/miniconda3"

    info "Downloading Miniconda..."
    curl -fL "$MINICONDA_URL" --output "$installer" || die "Failed to download the Miniconda installer."

    info "Installing Miniconda to $prefix ..."
    bash "$installer" -b -p "$prefix" || die "Miniconda installation failed."
    rm -f "$installer"

    info "Initializing conda for your shell..."
    "$prefix/bin/conda" init "$(basename "${SHELL:-zsh}")" >/dev/null 2>&1 \
        || warn "Could not run 'conda init'. You may need to add $prefix/bin to your PATH manually."

    CONDA="$prefix/bin/conda"
}

CONDA="$(find_conda)" || CONDA=""

if [ -n "$CONDA" ]; then
    info "Found conda: $CONDA"
else
    warn "conda was not found on this system."
    echo "    Miniconda will be installed to $HOME/miniconda3 (no administrator password required)."
    echo
    if confirm "Install Miniconda now?"; then
        install_miniconda
    else
        die "conda is required. Install Miniconda from https://www.anaconda.com/download/success and re-run this script."
    fi
fi

# ---------------------------------------------------------------------------
# 2. Create or update the conda environment
# ---------------------------------------------------------------------------

# Miniconda's base configuration uses Anaconda's "defaults" channels, which recent
# conda versions refuse to use until Anaconda's Terms of Service are accepted.
# This project only needs conda-forge (see environment.yml), so redefine what the
# "defaults" alias points at. Anaconda's repositories are then never contacted and
# no Terms of Service acceptance is required.
#
# Note: CONDA_CHANNELS does NOT work here -- the "defaults" alias from the user's
# condarc survives it, and the Terms of Service gate still trips.
export CONDA_DEFAULT_CHANNELS="conda-forge"

tos_hint() {
    warn "If the failure above mentions Anaconda's Terms of Service, this script did"
    warn "not manage to avoid the 'defaults' channels. You can accept those terms"
    warn "yourself -- read them first, they are Anaconda's licensing terms -- with:"
    warn "    \"$CONDA\" tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main"
    warn "    \"$CONDA\" tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r"
    warn "or remove the 'defaults' channel from your conda configuration entirely."
}

if "$CONDA" env list | awk '{print $1}' | grep -qx "$ENV_NAME"; then
    info "Conda environment '$ENV_NAME' already exists."
    if confirm "Update it from $ENV_FILE?"; then
        if ! "$CONDA" env update --name "$ENV_NAME" --file "$ENV_FILE" --prune; then
            tos_hint
            die "Failed to update the '$ENV_NAME' environment."
        fi
    else
        info "Leaving the existing environment untouched."
    fi
else
    info "Creating conda environment '$ENV_NAME' from $ENV_FILE ..."
    # Note: CUDA is not available on macOS, so the CPU-only environment is always used.
    if ! "$CONDA" env create --file "$ENV_FILE"; then
        tos_hint
        die "Failed to create the '$ENV_NAME' environment."
    fi
fi

# ---------------------------------------------------------------------------
# 3. Download the model files
# ---------------------------------------------------------------------------

urls=(
    "https://github.com/dnhkng/GlaDOS/releases/download/0.1/glados.onnx"
    "https://github.com/dnhkng/GlaDOS/releases/download/0.1/phomenizer_en.onnx"
)
files=(
    "glados/models/glados.onnx"
    "glados/models/phomenizer_en.onnx"
)

info "Verifying and downloading required models..."
for i in "${!urls[@]}"; do
    if [ -s "${files[$i]}" ]; then
        echo "    ${files[$i]} already exists."
        continue
    fi
    echo "    Downloading ${files[$i]} ..."
    mkdir -p "$(dirname "${files[$i]}")"
    if ! curl -fL "${urls[$i]}" --output "${files[$i]}"; then
        rm -f "${files[$i]}"
        die "Failed to download ${files[$i]} from ${urls[$i]}"
    fi
done

# ---------------------------------------------------------------------------
# 4. Verify the installation
# ---------------------------------------------------------------------------

info "Verifying the installation..."
"$CONDA" run --no-capture-output -n "$ENV_NAME" python -c "import onnxruntime, sounddevice, num2words, tkinter" \
    || die "The environment is missing one or more dependencies."

echo
echo "Installation finished!"
echo
echo "Run the interactive console demo with:"
echo "    $CONDA run --no-capture-output -n $ENV_NAME python speak_console.py"
echo
echo "Or activate the environment first:"
echo "    conda activate $ENV_NAME"
echo "    python speak_console.py"
echo
hold

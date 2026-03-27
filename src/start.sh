#!/usr/bin/env bash

safe_ln() {
    if [ ! -e "$1" ]; then
        echo "Error: '$1' does not exist" >&2
        return 1
    fi
    mkdir -p "$(dirname "$2")"
    ln -s "$1" "$2"
}

ls -R /runpod-volume/ 2>/dev/null || true
if [ ! -d /runpod-volume ]; then
    echo "Info: /runpod-volume does not exist, skipping SNAPSHOT_DIR resolution"
    SNAPSHOT_DIR=""
elif SNAPSHOT_DIR=$(ls -d /runpod-volume/huggingface-cache/hub/*/snapshots/*/ 2>/dev/null | head -1) && [ -n "$SNAPSHOT_DIR" ]; then
    echo "Info: SNAPSHOT_DIR=$SNAPSHOT_DIR"
else
    echo "Info: flashvsr snapshot directory not found in /runpod-volume"
    SNAPSHOT_DIR=""
fi

# Create symlinks from SNAPSHOT_DIR to /comfyui/models/ based on MODEL_SYMLINKS env var
# Format: "rel/path" (dst mirrors src under /comfyui/models/) or "rel/path:/absolute/dst"
if [ -n "$MODEL_SYMLINKS" ] && [ -n "$SNAPSHOT_DIR" ]; then
    for entry in $MODEL_SYMLINKS; do
        case "$entry" in
            *:*)
                rel="${entry%%:*}"
                dst="${entry#*:}"
                [ -n "$rel" ] && src="${SNAPSHOT_DIR}${rel}" || src="${SNAPSHOT_DIR%/}"
                ;;
            *) src="${SNAPSHOT_DIR}${entry}"; dst="/comfyui/models/${entry}" ;;
        esac
        safe_ln "$src" "$dst"
    done
elif [ -n "$MODEL_SYMLINKS" ] && [ -z "$SNAPSHOT_DIR" ]; then
    echo "Warning: MODEL_SYMLINKS is set but SNAPSHOT_DIR is empty, skipping symlinks"
fi

# Run pre-start hook if it exists (sourced to inherit functions defined above)
if [ -f /prestart.sh ]; then
    source /prestart.sh
fi

# Start SSH server if PUBLIC_KEY is set (enables remote access and dev-sync.sh)
if [ -n "$PUBLIC_KEY" ]; then
    mkdir -p ~/.ssh
    echo "$PUBLIC_KEY" > ~/.ssh/authorized_keys
    chmod 700 ~/.ssh
    chmod 600 ~/.ssh/authorized_keys

    # Generate host keys if they don't exist (removed during image build for security)
    for key_type in rsa ecdsa ed25519; do
        key_file="/etc/ssh/ssh_host_${key_type}_key"
        if [ ! -f "$key_file" ]; then
            ssh-keygen -t "$key_type" -f "$key_file" -q -N ''
        fi
    done

    service ssh start && echo "worker-comfyui: SSH server started" || echo "worker-comfyui: SSH server could not be started" >&2
fi

# Use libtcmalloc for better memory management
TCMALLOC="$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1)"
export LD_PRELOAD="${TCMALLOC}"

# ---------------------------------------------------------------------------
# GPU pre-flight check
# Verify that the GPU is accessible before starting ComfyUI. If PyTorch
# cannot initialize CUDA the worker will never be able to process jobs,
# so we fail fast with an actionable error message.
# ---------------------------------------------------------------------------
echo "worker-comfyui: Checking GPU availability..."
if ! GPU_CHECK=$(python3 -c "
import torch
try:
    torch.cuda.init()
    name = torch.cuda.get_device_name(0)
    print(f'OK: {name}')
except Exception as e:
    print(f'FAIL: {e}')
    exit(1)
" 2>&1); then
    echo "worker-comfyui: GPU is not available. PyTorch CUDA init failed:"
    echo "worker-comfyui: $GPU_CHECK"
    echo "worker-comfyui: This usually means the GPU on this machine is not properly initialized."
    echo "worker-comfyui: Please contact RunPod support and report this machine."
    exit 1
fi
echo "worker-comfyui: GPU available — $GPU_CHECK"

# Ensure ComfyUI-Manager runs in offline network mode inside the container
comfy-manager-set-mode offline || echo "worker-comfyui - Could not set ComfyUI-Manager network_mode" >&2

echo "worker-comfyui: Starting ComfyUI"

# Allow operators to tweak verbosity; default is DEBUG.
: "${COMFY_LOG_LEVEL:=DEBUG}"

# PID file used by the handler to detect if ComfyUI is still running
COMFY_PID_FILE="/tmp/comfyui.pid"

# Serve the API and don't shutdown the container
if [ "$SERVE_API_LOCALLY" == "true" ]; then
    python -u /comfyui/main.py --disable-auto-launch --disable-metadata --listen --verbose "${COMFY_LOG_LEVEL}" --log-stdout &
    echo $! > "$COMFY_PID_FILE"

    echo "worker-comfyui: Starting RunPod Handler"
    python -u /handler.py --rp_serve_api --rp_api_host=0.0.0.0
else
    SAGE_ATTENTION_FLAG=""
    if [ "${USE_SAGE_ATTENTION:-true}" == "true" ]; then
        SAGE_ATTENTION_FLAG="--use-sage-attention"
    fi
    python -u /comfyui/main.py ${SAGE_ATTENTION_FLAG} ${COMFY_VRAM_MODE} --disable-auto-launch --disable-metadata --verbose "${COMFY_LOG_LEVEL}" --log-stdout &
    echo $! > "$COMFY_PID_FILE"

    echo "worker-comfyui: Starting RunPod Handler"
    python -u /handler.py
fi
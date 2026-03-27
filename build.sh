CACHE_DIR="$(pwd)/.docker-cache"

IMAGE_NAME="${1:-$(cat image_name.txt)}"

docker build \
    --build-arg BASE_IMAGE="nvidia/cuda:13.0.2-cudnn-runtime-ubuntu24.04" \
    --build-arg MODEL_TYPE="none" \
    --build-arg CUDA_VERSION_FOR_COMFY="12.9" \
    --build-arg ENABLE_PYTORCH_UPGRADE="true" \
    --build-arg COMFYUI_VERSION="v0.17.2" \
    --build-arg PYTORCH_INDEX_URL="https://download.pytorch.org/whl/cu130" \
    --platform linux/amd64 \
    --build-arg SOURCE_DATE_EPOCH=0 \
    --cache-to "type=local,dest=${CACHE_DIR},mode=max" \
    --cache-from "type=local,src=${CACHE_DIR}" \
    -t "${IMAGE_NAME}" \
    .

docker buildx build  \
    --builder "cloud-flefebvredev-cloud-builder-no-cache" \
    --build-arg BASE_IMAGE="nvidia/cuda:13.0.2-cudnn-runtime-ubuntu24.04" \
    --build-arg MODEL_TYPE="none" \
    --build-arg CUDA_VERSION_FOR_COMFY="12.9" \
    --build-arg ENABLE_PYTORCH_UPGRADE="true" \
    --build-arg COMFYUI_VERSION="v0.17.2" \
    --build-arg PYTORCH_INDEX_URL="https://download.pytorch.org/whl/cu130" \
    --platform linux/amd64 \
    --no-cache \
    --build-arg SOURCE_DATE_EPOCH=0 \
    -t flefebvredev/worker-comfyui:5.8.3-base \
    --push \
    .

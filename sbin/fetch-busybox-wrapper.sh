#!/bin/bash

# Define variables
CONTAINER_RUNTIME=$(command -v podman || command -v docker)
IMAGE_NAME="debian:stable-slim"

SCRIPT_DIR=$(dirname $(realpath $0))
SCRIPT_NAME="fetch-busybox-static.sh"
SCRIPT_PATH="$SCRIPT_DIR/fetch-busybox-static.sh"

if [ -w /srv ]; then
	BASE_DIR="/srv"
else
	BASE_DIR="$HOME/.cache/compass-ci"
fi

OUTPUT_DIR=$BASE_DIR/file-store/busybox
mkdir -p $OUTPUT_DIR

# Check if the script exists
if [ ! -f "$SCRIPT_PATH" ]; then
    echo "[ERROR] Script '$SCRIPT_PATH' not found in the current directory."
    exit 1
fi

# Function to log messages
log_message() {
    echo "[INFO] $1"
}

# try direct run
which dpkg-deb >/dev/null 2>&1 && {
	$SCRIPT_PATH $OUTPUT_DIR
	exit
}

# Step 1: Pull the base image
log_message "Pulling container image '$IMAGE_NAME'..."
if ! $CONTAINER_RUNTIME pull "$IMAGE_NAME"; then
    echo "[ERROR] Failed to pull container image '$IMAGE_NAME'. Exiting."
    exit 1
fi

# Step 2: Run the script inside the container
log_message "Running '$SCRIPT_PATH' inside a container..."

log_message "Output files will be stored in '$OUTPUT_DIR'."

$CONTAINER_RUNTIME run --rm \
    -v "$SCRIPT_PATH:/usr/local/bin/$SCRIPT_NAME:ro" \
    -v "$OUTPUT_DIR:/output" \
    -w /output \
    "$IMAGE_NAME" \
    bash -c "apt-get update && apt-get install -y wget dpkg cpio gzip && /usr/local/bin/$SCRIPT_NAME /output"

if [ $? -ne 0 ]; then
    echo "[ERROR] Failed to run script inside the container."
    rm -rf "$OUTPUT_DIR"
    exit 1
fi

log_message "Script execution completed. Output files are in '$OUTPUT_DIR'."

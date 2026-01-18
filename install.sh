#!/bin/bash
# ============================================================
# NVIDIA Isaac Sim Universal Installer (Unofficial)
#
# Features:
# 1. Bypasses strict GLIBC version checks (Legacy System Support).
# 2. Fixes "metadata-generation-failed" errors during pip install.
# 3. Full offline installation workflow with automatic cleanup.
# ============================================================

# Disable immediate exit on error to handle retries and cleanup manually
set +e 

# Save current directory to ensure safe cleanup later
CURRENT_DIR=$(pwd)

# --- 1. Version Selection Menu ---
clear
echo "========================================================"
echo "   NVIDIA Isaac Sim Installer (Universal Compatibility)"
echo "========================================================"
echo "Please select target version:"
echo " 1) 5.1.0 (Latest)"
echo " 2) 5.0.0"
echo " 3) 4.5.0"
echo " 4) Custom"
read -p "Select [1-4]: " choice

case $choice in
    1) INPUT_VERSION="5.1.0";;
    2) INPUT_VERSION="5.0.0";;
    3) INPUT_VERSION="4.5.0";;
    4) read -p "Enter Version (e.g. 4.2.0): " INPUT_VERSION;;
    *) INPUT_VERSION="5.1.0";;
esac

# Auto-correct version format: NVIDIA uses 4 digits (e.g., 5.1.0.0)
if [[ "$INPUT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    ISAAC_VERSION="${INPUT_VERSION}.0"
    echo "Auto-corrected version: $INPUT_VERSION -> $ISAAC_VERSION"
else
    ISAAC_VERSION="$INPUT_VERSION"
fi

# --- 2. Auto-detect Python Environment ---
PY_VER=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
PY_ABI="cp$(python3 -c "import sys; print(f'{sys.version_info.major}{sys.version_info.minor}')")"

# Define temporary download directory
DOWNLOAD_DIR="./temp_full_cache_${ISAAC_VERSION}_${PY_ABI}"

echo "------------------------------------------------"
echo "Target: $ISAAC_VERSION"
echo "Python: $PY_VER ($PY_ABI)"
echo "Temp:   $DOWNLOAD_DIR"
echo "------------------------------------------------"

# --- 3. Initialize Directory ---
echo ""
echo "[Step 1] Initializing temporary directory..."
if [ -d "$DOWNLOAD_DIR" ]; then
    rm -rf "$DOWNLOAD_DIR"
fi
mkdir -p "$DOWNLOAD_DIR"

# --- 4. Full Download (Robust Mode) ---
echo ""
echo "[Step 2] Downloading ALL packages..."
echo "   (This may take a while. Auto-retry enabled for unstable networks.)"
echo "   Mode: Multi-platform spoofing enabled."

# Download loop: Keep trying until exit code is 0 (Success)
# This handles network timeouts for large files automatically.
MAX_RETRIES=10
RETRY_COUNT=0

while true; do
    PIP_TRUSTED_HOST="pypi.nvidia.com pypi.tuna.tsinghua.edu.cn" \
    pip download "isaacsim[all,extscache]==$ISAAC_VERSION" \
        --dest "$DOWNLOAD_DIR" \
        --index-url https://pypi.nvidia.com \
        --extra-index-url https://pypi.tuna.tsinghua.edu.cn/simple \
        --trusted-host pypi.nvidia.com \
        --platform manylinux_2_35_x86_64 \
        --platform manylinux_2_34_x86_64 \
        --platform manylinux_2_28_x86_64 \
        --platform manylinux_2_17_x86_64 \
        --platform manylinux2014_x86_64 \
        --python-version "$PY_VER" \
        --implementation cp \
        --abi "$PY_ABI" \
        --only-binary=:all:
    
    EXIT_CODE=$?
    
    if [ $EXIT_CODE -eq 0 ]; then
        echo "Download complete."
        break
    else
        RETRY_COUNT=$((RETRY_COUNT+1))
        echo "Download interrupted (Network error?). Retrying ($RETRY_COUNT)..."
        sleep 3
    fi
done

# --- 5. Patch Filenames (The Hack) ---
echo ""
echo "[Step 3] Patching filenames for legacy system compatibility..."
cd "$DOWNLOAD_DIR" || exit 1

count=0
shopt -s nullglob

for file in *.whl; do
    # Logic: Rename any 'manylinux_2_XX' to 'manylinux_2_17'
    # This ensures maximum compatibility with older GLIBC versions
    if [[ "$file" == *"manylinux_2_"* ]] && [[ "$file" != *"manylinux_2_17"* ]]; then
        
        # Regex replacement using sed
        new_name=$(echo "$file" | sed -E "s/manylinux_2_[0-9]+_x86_64/manylinux_2_17_x86_64/")
        
        if [ "$file" != "$new_name" ]; then
            mv "$file" "$new_name"
            count=$((count + 1))
        fi
    fi
done

echo "Success: Patched $count files."

# IMPORTANT: Return to original directory
cd "$CURRENT_DIR"

# --- 6. Offline Installation ---
echo ""
echo "[Step 4] Installing from local cache..."

# Force pip to use ONLY our patched local files
pip install "isaacsim[all,extscache]==$ISAAC_VERSION" \
    --no-index \
    --find-links="$DOWNLOAD_DIR" \
    --no-cache-dir

INSTALL_CODE=$?

# --- 7. Cleanup ---
echo ""
if [ $INSTALL_CODE -eq 0 ]; then
    echo "========================================================"
    echo -e "  SUCCESS: Isaac Sim $ISAAC_VERSION Installed!"
    echo "========================================================"
    
    echo "[Step 5] Cleaning up disk space..."
    
    # Safety check: Ensure we are not inside the directory
    if [ "$(pwd)" == "$(realpath $DOWNLOAD_DIR)" ]; then
        cd ..
    fi
    
    # Execute deletion
    if [ -d "$DOWNLOAD_DIR" ]; then
        rm -rf "$DOWNLOAD_DIR"
        echo "   -> Removed temporary directory: $DOWNLOAD_DIR"
    fi
    
    echo ""
    echo "Verifying import..."
    python3 -c "import isaacsim; print('Isaac Sim import OK')"
else
    echo "========================================================"
    echo "   Install Failed (Code: $INSTALL_CODE)"
    echo "   NOTE: Temporary directory kept for debugging:"
    echo "   $DOWNLOAD_DIR"
    echo "========================================================"
    exit 1
fi
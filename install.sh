#!/bin/bash
# ============================================================
# NVIDIA Isaac Sim Universal Installer (No Emojis)
#
# Features:
# 1. Bypasses strict GLIBC version checks.
# 2. Fixes metadata errors.
# 3. Full offline installation with cleanup.
# ============================================================

# Disable immediate exit on error to handle retries manually
set +e 

# Save current directory
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

# Auto-correct version format
if [[ "$INPUT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    ISAAC_VERSION="${INPUT_VERSION}.0"
    echo "[INFO] Auto-corrected version: $INPUT_VERSION -> $ISAAC_VERSION"
else
    ISAAC_VERSION="$INPUT_VERSION"
fi

# --- 2. Auto-detect Python ---
PY_VER=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
PY_ABI="cp$(python3 -c "import sys; print(f'{sys.version_info.major}{sys.version_info.minor}')")"

# Define temp directory
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

# --- 4. Full Download (Best Effort Mode) ---
echo ""
echo "[Step 2] Downloading ALL packages..."
echo "   (This may take a while.)"
echo "   Mode: Multi-platform spoofing enabled."

# Reduced retries to avoid infinite loops on dependency errors
MAX_RETRIES=3
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
        echo "[OK] Download complete."
        break
    else
        RETRY_COUNT=$((RETRY_COUNT+1))
        echo "[WARNING] Download reported errors (Attempt $RETRY_COUNT/$MAX_RETRIES)..."
        
        # If max retries reached, we proceed anyway instead of exiting.
        # This handles cases where optional dependencies (like idna-ssl) fail but the main package is fine.
        if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
            echo ""
            echo "[WARNING] Max retries reached. Assuming core packages are present."
            echo "   Proceeding to installation step..."
            break
        fi
        
        sleep 2
    fi
done

# --- Check if we actually downloaded anything ---
count_whl=$(ls -1 "$DOWNLOAD_DIR"/*.whl 2>/dev/null | wc -l)
if [ "$count_whl" -eq 0 ]; then
    echo ""
    echo "[ERROR] No .whl files were downloaded. The version might not exist or network is down."
    echo "   Exiting."
    rm -rf "$DOWNLOAD_DIR"
    exit 1
fi

# --- 5. Patch Filenames ---
echo ""
echo "[Step 3] Patching filenames for legacy system compatibility..."
cd "$DOWNLOAD_DIR" || exit 1

count=0
shopt -s nullglob

for file in *.whl; do
    # Logic: Rename any 'manylinux_2_XX' to 'manylinux_2_17'
    if [[ "$file" == *"manylinux_2_"* ]] && [[ "$file" != *"manylinux_2_17"* ]]; then
        
        # Regex replacement using sed
        new_name=$(echo "$file" | sed -E "s/manylinux_2_[0-9]+_x86_64/manylinux_2_17_x86_64/")
        
        if [ "$file" != "$new_name" ]; then
            mv "$file" "$new_name"
            count=$((count + 1))
        fi
    fi
done

echo "[OK] Patched $count files."

# Return to original directory
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
    echo "   [SUCCESS] Isaac Sim $ISAAC_VERSION Installed!"
    echo "========================================================"
    
    echo "[Step 5] Cleaning up disk space..."
    
    # Safety check
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
    echo "   [FAILED] Install Failed (Code: $INSTALL_CODE)"
    echo "   NOTE: Temporary directory kept for debugging:"
    echo "   $DOWNLOAD_DIR"
    echo "========================================================"
    exit 1
fi

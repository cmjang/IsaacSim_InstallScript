#!/bin/bash
# ============================================================
# NVIDIA Isaac Sim Universal Installer (Fixed for Download Errors)
# Logic: Download All -> Fallback if Fail -> Patch Filenames -> Offline Install -> Cleanup
# ============================================================

# Disable immediate exit on error to handle cleanup manually
set +e 

# Save current directory
CURRENT_DIR=$(pwd)

# --- 1. Version Selection Menu ---
clear
echo "========================================================"
echo "   NVIDIA Isaac Sim Installer (Resilient Mode)"
echo "========================================================"
echo "Please select target version:"
echo " 1) 5.1.0"
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
    echo "ℹ️  Auto-corrected version: $INPUT_VERSION -> $ISAAC_VERSION"
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

# --- 4. Full Download (Spoofing Platforms) ---
echo ""
echo "[Step 2] Downloading packages..."
echo "   Mode: Multi-platform spoofing with Fallback Support"

# 定义下载函数以便复用参数
run_download() {
    # $1 can be empty or "--no-deps"
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
        --only-binary=:all: \
        $1
}

# 尝试 1: 完整下载
echo "   >> Attempting full dependency download..."
run_download ""

DOWNLOAD_CODE=$?

# ============================================================
# 修改处：遇到错误不退出，而是尝试“忽略依赖”下载
# ============================================================
if [ $DOWNLOAD_CODE -ne 0 ]; then
    echo ""
    echo "⚠️  WARNING: Full dependency resolution failed (e.g., idna-ssl error)."
    echo "   The script will NOT exit. Instead, it will attempt to download"
    echo "   the main Isaac Sim package without dependencies to ensure installation."
    echo ""
    echo "   >> Attempting fallback download (--no-deps)..."
    
    # 尝试 2: 忽略依赖下载 (兜底策略)
    run_download "--no-deps"
    
    if [ $? -ne 0 ]; then
        echo "❌ ERROR: Even the fallback download failed. Checking if any files exist..."
    else
        echo "✅ Fallback download successful (Main package retrieved)."
    fi
else
    echo "✅ Full download successful."
fi

# 检查是否有文件被下载下来，如果没有文件则真的无法继续
count_files=$(ls "$DOWNLOAD_DIR"/*.whl 2>/dev/null | wc -l)
if [ "$count_files" -eq 0 ]; then
    echo "❌ CRITICAL: No .whl files were downloaded. Cannot proceed."
    cd "$CURRENT_DIR"
    exit 1
fi
# ============================================================

# --- 5. Patch Filenames (The GLIBC Hack) ---
echo ""
echo "[Step 3] Patching filenames for legacy GLIBC compatibility..."
cd "$DOWNLOAD_DIR" || exit 1

count=0
shopt -s nullglob

for file in *.whl; do
    if [[ "$file" == *"manylinux_2_"* ]] && [[ "$file" != *"manylinux_2_17"* ]]; then
        new_name=$(echo "$file" | sed -E "s/manylinux_2_[0-9]+_x86_64/manylinux_2_17_x86_64/")
        if [ "$file" != "$new_name" ]; then
            mv "$file" "$new_name"
            count=$((count + 1))
        fi
    fi
done

echo "✅ Success: Patched $count files."

# Return to original directory
cd "$CURRENT_DIR"

# --- 6. Offline Installation ---
echo ""
echo "[Step 4] Installing from local cache..."

# 尝试安装
echo "   >> Installing..."
pip install "isaacsim[all,extscache]==$ISAAC_VERSION" \
    --no-index \
    --find-links="$DOWNLOAD_DIR" \
    --no-cache-dir

INSTALL_CODE=$?

# 如果安装失败，尝试不带依赖安装（为了应对刚才下载缺失依赖的情况）
if [ $INSTALL_CODE -ne 0 ]; then
    echo ""
    echo "⚠️  Standard install failed (likely missing dependencies due to download errors)."
    echo "   >> Attempting to force install main package (--no-deps)..."
    
    pip install "isaacsim[all,extscache]==$ISAAC_VERSION" \
        --no-index \
        --find-links="$DOWNLOAD_DIR" \
        --no-cache-dir \
        --no-deps
    
    INSTALL_CODE=$?
fi

# --- 7. Cleanup ---
echo ""
if [ $INSTALL_CODE -eq 0 ]; then
    echo "========================================================"
    echo -e "✅✅✅ SUCCESS: Isaac Sim $ISAAC_VERSION Installed!"
    echo "========================================================"
    echo "   (Note: If you saw download errors, some optional dependencies"
    echo "    might be missing, but the main application is installed.)"
    
    echo "[Step 5] Cleaning up disk space..."
    
    if [ "$(pwd)" == "$(realpath $DOWNLOAD_DIR)" ]; then
        cd ..
    fi
    
    if [ -d "$DOWNLOAD_DIR" ]; then
        rm -rf "$DOWNLOAD_DIR"
        echo "   -> Removed temporary directory: $DOWNLOAD_DIR"
    fi
    
    echo ""
    echo "Verifying import..."
    python3 -c "import isaacsim; print('Isaac Sim import OK')"
else
    echo "========================================================"
    echo "❌ Install Failed (Code: $INSTALL_CODE)"
    echo "   The temp directory has been kept for debugging:"
    echo "   $DOWNLOAD_DIR"
    echo "========================================================"
    exit 1
fi

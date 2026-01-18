# NVIDIA Isaac Sim Universal Installer

**Unofficial Auto-Installer for NVIDIA Isaac Sim.**
Designed to fix compatibility issues on legacy Linux systems (e.g., older GLIBC/Kernels like CentOS 7) and automate the "download -> patch -> install" workflow.

## ✨ Features
- **Legacy Support**: Patches binary wheels to bypass GLIBC version checks.
- **Auto-Retry**: Automatically resumes downloads if the connection drops.
- **Space Saver**: Installs offline and cleans up the cache immediately to save disk space.
- **Universal**: Supports Isaac Sim 5.1.0, 5.0.0, and 4.5.0.

## 🚀 Quick Start

**Run the following command in your terminal:**

```bash
curl -fsSL https://raw.githubusercontent.com/cmjang/IsaacSim_InstallScript/main/install.sh | bash

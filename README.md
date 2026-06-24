# Daslight 5 on Linux (Wine)

Run Daslight 5 lighting control software on Linux via Wine.
Downloads the official installer from Nicolaudie and sets everything up automatically.
No Daslight copyrighted files are included in this repository.

## One-liner install

```bash
curl -fsSL https://raw.githubusercontent.com/antonmoenninger/Daslight-installer-Linux/refs/heads/main/setup.sh | bash
```

## What it does

1. Downloads the official Daslight 5 installer from Nicolaudie's servers
2. Extracts all components from the installer
3. Creates a Wine prefix and directory structure
4. Copies Qt/FFmpeg/OpenCV DLLs for Wine compatibility
5. Creates configuration files
6. Installs launcher scripts

## Requirements

- **wine** (Wine 9.0+, `wine64` or `wine`)
- **7z** (p7zip-full or p7zip)
- **python3**
- **wget**

### Distro-specific install commands

**Ubuntu/Debian:**
```bash
sudo dpkg --add-architecture i386 && sudo apt update
sudo apt install wine wine64 p7zip-full python3 wget
```

**Fedora:**
```bash
sudo dnf install wine p7zip python3 wget
```

**Arch:**
```bash
sudo pacman -S wine p7zip python wget
```

**openSUSE:**
```bash
sudo zypper install wine p7zip-full python3 wget
```

Verify Wine works:
```bash
wine --version
```

## Usage

```bash
# Launch Daslight 5 (starts the full app: lighting console + 3D visualizer)
~/daslight5/run-daslight5.sh

# Launch EasyView 2 standalone (3D visualizer only)
~/daslight5/run-easyview2.sh
```

## Custom install path

```bash
INSTALL_DIR=/opt/daslight5 bash setup.sh
```

## How it works

The Daslight 5 installer is a Qt Installer Framework wrapper with embedded
7z archives. This script:

- Extracts the PE image appended data
- Locates and decompresses each component archive at known offsets
- Places files in the correct directory structure
- Creates minimal `_global.ini` configuration
- Works around Wine's lack of SxS assembly manifest support by copying DLLs locally

## Notes

- The HardwareManager (DMX firmware updater) is downloaded separately by the
  installer and is not included. It's only needed for DMX interface firmware updates.
- **USB DMX interfaces:** The setup script creates udev rules for Nicolaudie devices
  (vendor ID `0x10CE`). After setup, reconnect your USB interface.
  Wine's USB passthrough may not work with all devices — Art-Net/sACN over Ethernet
  is a more reliable option for DMX output on Linux.

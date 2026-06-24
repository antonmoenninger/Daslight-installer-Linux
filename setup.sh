#!/bin/bash
set -e

# ============================================================
# Daslight 5 on Linux (Wine) - Setup Script
# Downloads the official installer and extracts everything.
# No Daslight copyrighted files are included in this repo.
# ============================================================

DASLIGHT_URL="https://storage.googleapis.com/nicolaudie-eu-software/Release/Daslight5.exe"
INSTALL_DIR="${INSTALL_DIR:-$HOME/daslight5}"
WINE_PREFIX="${WINE_PREFIX:-$HOME/.wine-daslight5}"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

echo "========================================"
echo " Daslight 5 on Linux (Wine) Setup"
echo "========================================"
echo ""
echo "Install directory: $INSTALL_DIR"
echo "Wine prefix:       $WINE_PREFIX"
echo ""

# -----------------------------------------------------------
# Check prerequisites
# -----------------------------------------------------------
check_cmd() {
    if ! command -v "$1" &>/dev/null; then
        echo "ERROR: '$1' is required but not installed."
        echo "Install it with: ${3:-sudo apt install $2}"
        exit 1
    fi
}

# Find working wine binary (try wine64 first, then wine)
WINE_BIN=""
for bin in wine64 wine; do
    if command -v "$bin" &>/dev/null; then
        WINE_BIN="$bin"
        break
    fi
done
if [ -z "$WINE_BIN" ]; then
    echo "ERROR: Wine is required but not installed."
    echo "Install it with: sudo apt install wine wine64"
    echo "Or follow: https://wiki.winehq.org/Download"
    exit 1
fi

# Detect distro for package suggestions
distro_pkg() {
    if command -v apt &>/dev/null; then
        echo "sudo apt install $1"
    elif command -v dnf &>/dev/null; then
        echo "sudo dnf install $1"
    elif command -v pacman &>/dev/null; then
        echo "sudo pacman -S $1"
    elif command -v zypper &>/dev/null; then
        echo "sudo zypper install $1"
    else
        echo "your package manager"
    fi
}

check_cmd 7z "p7zip-full" "$(distro_pkg p7zip-full)"
check_cmd python3 "python3"
check_cmd wget "wget"

WINE_VER=$("$WINE_BIN" --version 2>/dev/null || echo "unknown")
echo "Wine: $WINE_BIN ($WINE_VER)"
echo ""

# -----------------------------------------------------------
# Download the official Daslight 5 installer
# -----------------------------------------------------------
echo "[1/6] Downloading official Daslight 5 installer..."
INSTALLER="$TEMP_DIR/Daslight5.exe"
wget -q --show-progress -O "$INSTALLER" "$DASLIGHT_URL"
echo "Downloaded: $(du -h "$INSTALLER" | cut -f1)"
echo ""

# -----------------------------------------------------------
# Extract 7z archives from the installer
# -----------------------------------------------------------
echo "[2/6] Extracting components from installer..."

export TEMP_DIR
export DASLIGHT_INSTALLER="$TEMP_DIR/Daslight5.exe"
export DASLIGHT_EXTRACT="$TEMP_DIR/extracted"

python3 << 'PYEOF'
import struct, os, subprocess

installer = os.environ["DASLIGHT_INSTALLER"]
extract = os.environ["DASLIGHT_EXTRACT"]
os.makedirs(extract, exist_ok=True)

with open(installer, "rb") as f:
    data = f.read()

# Get PE image size
pe_off = struct.unpack("<I", data[0x3c:0x40])[0]
image_size = struct.unpack("<I", data[pe_off + 0x50 : pe_off + 0x54])[0]
extra = data[image_size:]

# Known 7z archive offsets in the extra data
# Each archive corresponds to a component package
archives = [
    (0x5D3F250, "easyView2+daslight5"),   # EasyView2.exe, CrashReporter, 3D Library, Data
    (0x79F1DEA, "common"),                 # Resourcesx64 (Qt5, FFmpeg, OpenCV DLLs)
    (0xA661316, "sslGeneric"),             # SSL2 fixture profiles
    (0xB297B4E, "driver"),                 # SiudiDriver.exe
    (0xBBD6A75, "daslight5"),              # Daslight5.exe, QtOem, napdb, Presets
]

extracted_count = 0
magic = b"7z\xBC\xAF\x27\x1C"

for offset, name in archives:
    if offset + 4 > len(extra):
        print(f"WARNING: Offset {hex(offset)} is beyond data for {name}")
        continue

    if extra[offset : offset + len(magic)] != magic:
        print(f"WARNING: No 7z magic at {hex(offset)} for {name} (installer may have been updated)")
        continue

    archive_path = f"{extract}/{name}.7z"
    with open(archive_path, "wb") as f:
        f.write(extra[offset:])

    result = subprocess.run(
        ["7z", "x", archive_path, f"-o{extract}/{name}", "-y"],
        capture_output=True, text=True,
    )
    if "Everything is Ok" not in result.stdout and "Ok" not in result.stdout:
        print(f"WARNING: Extraction of {name} may be incomplete")
        print(f"  7z stderr: {result.stderr[:200]}")

    extracted_count += 1
    print(f"  Extracted: {name}")

if extracted_count == 0:
    print("ERROR: No archives could be extracted from the installer.")
    print("The installer format may have changed. Check for updates to this script.")
    exit(1)

print("Done extracting all components.")
PYEOF

echo ""

# Verify extraction produced results
EXTRACT="$TEMP_DIR/extracted"
if [ ! -d "$EXTRACT" ] || [ -z "$(ls -A "$EXTRACT" 2>/dev/null)" ]; then
    echo "ERROR: Extraction produced no output."
    echo "The Daslight installer format may have changed."
    echo "Please report this issue so the archive offsets can be updated."
    exit 1
fi

# -----------------------------------------------------------
# Set up Wine prefix
# -----------------------------------------------------------
echo "[3/6] Setting up Wine prefix..."
export WINEPREFIX="$WINE_PREFIX"
export WINEARCH=win64

# Initialize prefix if needed
if [ ! -d "$WINE_PREFIX" ]; then
    WINEPREFIX="$WINE_PREFIX" WINEARCH=win64 "$WINE_BIN" wineboot -u 2>/dev/null || true
fi
WINEPREFIX="$WINE_PREFIX" WINEARCH=win64 "$WINE_BIN" winecfg -v win10 2>/dev/null || true

echo "Wine prefix ready."

# -----------------------------------------------------------
# Create directory structure
# -----------------------------------------------------------
echo "[4/6] Creating directory structure..."

DEST="$WINE_PREFIX/drive_c/Daslight 5"

rm -rf "$DEST"
mkdir -p "$DEST"/{"Daslight 5","EasyView2","HardwareManager","common/Resourcesx64","driver","ScanLibrary"}

# --- Daslight 5 main app (from daslight5 archive) ---
echo "  Setting up Daslight 5 main application..."
cp -r "$EXTRACT/daslight5/"* "$DEST/Daslight 5/" 2>/dev/null || true
# Daslight5 archive might extract to subdirectories, handle that
if [ -d "$EXTRACT/daslight5/Daslight5" ]; then
    cp -r "$EXTRACT/daslight5/"* "$DEST/Daslight 5/" 2>/dev/null
fi

# --- EasyView2 (from easyView2+daslight5 archive) ---
echo "  Setting up EasyView2..."
cp -r "$EXTRACT/easyView2+daslight5/"*.exe "$DEST/EasyView2/" 2>/dev/null || true
cp -r "$EXTRACT/easyView2+daslight5/"*.dll "$DEST/EasyView2/" 2>/dev/null || true
cp -r "$EXTRACT/easyView2+daslight5/"*.config "$DEST/EasyView2/" 2>/dev/null || true
cp -r "$EXTRACT/easyView2+daslight5/"*.ini "$DEST/EasyView2/" 2>/dev/null || true
cp -r "$EXTRACT/easyView2+daslight5/Data" "$DEST/EasyView2/" 2>/dev/null || true

# --- Common Resourcesx64 ---
echo "  Setting up common resources..."
cp -r "$EXTRACT/common/Resourcesx64/"* "$DEST/common/Resourcesx64/" 2>/dev/null || true

# --- SSL Fixtures ---
echo "  Setting up SSL fixture library..."
cp -r "$EXTRACT/sslGeneric/_Generic" "$DEST/ScanLibrary/" 2>/dev/null || true

# --- Driver ---
echo "  Setting up driver..."
cp -r "$EXTRACT/driver/SiudiDriver.exe" "$DEST/driver/" 2>/dev/null || true

# --- Library & Data from easyView2 archive ---
echo "  Setting up 3D Library and demo data..."
cp -r "$EXTRACT/easyView2+daslight5/Library" "$DEST/Library" 2>/dev/null || true
cp -r "$EXTRACT/easyView2+daslight5/Data" "$DEST/Data" 2>/dev/null || true

# --- Copy Resourcesx64 DLLs into each app directory ---
# (Wine doesn't handle Windows Side-by-Side assembly manifests well)
echo "  Copying DLLs for Wine compatibility..."
for app_dir in "Daslight 5" "EasyView2" "HardwareManager"; do
    cp "$DEST/common/Resourcesx64/"*.dll "$DEST/$app_dir/" 2>/dev/null || true
    # Also copy subdirectories (platforms, styles, imageformats, etc.)
    for subdir in "$DEST/common/Resourcesx64/"*/; do
        subname=$(basename "$subdir")
        mkdir -p "$DEST/$app_dir/$subname"
        cp -r "$subdir"* "$DEST/$app_dir/$subname/" 2>/dev/null || true
    done
done

# Also copy QtDasWord.dll and QtOem.dll to EasyView2 if available
cp "$DEST/Daslight 5/QtDasWord.dll" "$DEST/EasyView2/" 2>/dev/null || true
cp "$DEST/Daslight 5/QtOem.dll" "$DEST/EasyView2/" 2>/dev/null || true

# -----------------------------------------------------------
# Create _global.ini configuration
# -----------------------------------------------------------
echo "[5/6] Creating configuration files..."

# Main Daslight 5 _global.ini
cat > "$DEST/Daslight 5/_global.ini" << 'EOF'
[General]
OEM=DASLIGHT
AudioInput=0
AudioOutput=0
ControlPanelSplitter=@ByteArray(\0\0\0\xff\0\0\0\x1\0\0\0\x2\x7f\xff\xff\xff\x7f\xff\xff\xff\0\xff\xff\xff\xff\x1\0\0\0\x1\0)
FixtureSelection=true
MainWindowSplitter=@ByteArray(\0\0\0\xff\0\0\0\x1\0\0\0\x2\x7f\xff\xff\xff\x7f\xff\xff\xff\x1\0\0\0\0\x1\0\0\0\x2\0)
favoritesColors=@Invalid()
LiveHideProperties=false
PulseThreshold=@Variant(\0\0\0\x87\0\0\0\0)

[StartupPreferences]
CreateGroupWithFixture=false

[window]
wGeometry=@ByteArray(\x1\xd9\xd0\xcb\0\x3\0\0\xff\xff\xff\xf8\xff\xff\xff\xf8\0\0\a\x87\0\0\x5w\0\0\0t\0\0\0t\0\0\x4S\0\0\x3S\0\0\0\0\x2\0\0\0\a\x80\0\0\0\0\0\0\0\0\0\0\a\x7f\0\0\x5o)
EOF

# EasyView2 _global.ini
cat > "$DEST/EasyView2/_global.ini" << 'EOF'
[General]
Language=0
EOF

# C:\ root _global.ini (required by Daslight5.exe at startup)
# Must be minimal — the verbose Daslight5 format causes "invalid _global.ini file"
cat > "$WINE_PREFIX/drive_c/_global.ini" << 'EOF'
[General]
Language=0
EOF

# HardwareManager _global.ini placeholder
cat > "$DEST/HardwareManager/_global.ini" << 'EOF'
[General]
OEM=DASLIGHT
EOF

echo "Configuration files created."

# -----------------------------------------------------------
# Verify installation
# -----------------------------------------------------------
echo "Verifying installation..."

REQUIRED_FILES=("Daslight 5/Daslight5.exe" "EasyView2/EasyView2.exe")
FAILED=0
for f in "${REQUIRED_FILES[@]}"; do
    if [ -f "$DEST/$f" ]; then
        echo "  OK: $f"
    else
        echo "  MISSING: $f"
        FAILED=1
    fi
done

if [ $FAILED -eq 1 ]; then
    echo ""
    echo "ERROR: Some required files are missing."
    echo "The installer extraction may have failed."
    echo "Check that '7z' (p7zip-full) is installed and try again."
    exit 1
fi

echo "All required files present."

# -----------------------------------------------------------
# Set up USB DMX driver support
# -----------------------------------------------------------
echo "[6/7] Setting up USB DMX driver support..."

# Install SiudiDriver in the Wine prefix
echo "  Installing Siudi USB driver..."
WINEPREFIX="$WINE_PREFIX" WINEARCH=win64 "$WINE_BIN" \
    "$DEST/driver/SiudiDriver.exe" /VERYSILENT /SUPPRESSMSGBOXES 2>/dev/null || true

# Create udev rules for Nicolaudie USB devices (vendor ID 0x10CE)
UDEV_RULE='# Nicolaudie / Daslight DMX USB interfaces
SUBSYSTEM=="usb", ATTRS{idVendor}=="10ce", MODE="0666"'

if [ -w /etc/udev/rules.d ]; then
    echo "$UDEV_RULE" > /etc/udev/rules.d/99-daslight.rules
    udevadm control --reload-rules 2>/dev/null || true
    udevadm trigger 2>/dev/null || true
    echo "  Udev rules installed."
else
    echo "  Note: Run this to enable USB DMX device access:"
    echo "    echo '$UDEV_RULE' | sudo tee /etc/udev/rules.d/99-daslight.rules"
    echo "    sudo udevadm control --reload-rules && sudo udevadm trigger"
fi

echo ""

# -----------------------------------------------------------
# Create launcher scripts
# -----------------------------------------------------------
echo "[7/7] Creating launcher scripts..."

mkdir -p "$INSTALL_DIR"

# Remove old symlinks/files if they exist
rm -f "$INSTALL_DIR/run-daslight5.sh" 2>/dev/null

cat > "$INSTALL_DIR/run-daslight5.sh" << 'LAUNCHER'
#!/bin/bash
set -e
export WINEPREFIX="${WINEPREFIX:-$HOME/.wine-daslight5}"
export WINEARCH=win64
export PATH="/usr/bin:$PATH"

DASDIR="$WINEPREFIX/drive_c/Daslight 5/Daslight 5"
if [ ! -f "$DASDIR/Daslight5.exe" ]; then
    echo "ERROR: Daslight5.exe not found at $DASDIR"
    echo "Re-run the setup script to install."
    exit 1
fi

WINE="$(command -v wine64 2>/dev/null || command -v wine 2>/dev/null || echo wine)"
cd "$DASDIR"
exec "$WINE" Daslight5.exe "$@"
LAUNCHER

cat > "$INSTALL_DIR/run-easyview2.sh" << 'LAUNCHER'
#!/bin/bash
# Launch EasyView 2 (3D visualizer)
export WINEPREFIX="${WINEPREFIX:-$HOME/.wine-daslight5}"
export WINEARCH=win64
export PATH="/usr/bin:$PATH"
WINE="$(command -v wine64 2>/dev/null || command -v wine 2>/dev/null || echo wine)"
EVDIR="$WINEPREFIX/drive_c/Daslight 5/EasyView2"
if [ ! -f "$EVDIR/EasyView2.exe" ]; then
    echo "ERROR: EasyView2.exe not found at $EVDIR"
    echo "Re-run the setup script to install."
    exit 1
fi
cd "$EVDIR"
exec "$WINE" EasyView2.exe "$@"
LAUNCHER

chmod +x "$INSTALL_DIR/run-daslight5.sh" "$INSTALL_DIR/run-easyview2.sh"

# Create desktop entry
echo "  Creating application launcher..."
ICON="$DEST/Daslight 5/Resources/Daslight 5.ico"
[ ! -f "$ICON" ] && ICON="$DEST/Daslight 5/Resources/myDMX 5.ico"
mkdir -p "$HOME/.local/share/applications"
cat > "$HOME/.local/share/applications/daslight5.desktop" << DESKTOPEOF
[Desktop Entry]
Name=Daslight 5
Comment=DMX Lighting Control Software
Exec=$INSTALL_DIR/run-daslight5.sh
Icon=$ICON
Terminal=false
Type=Application
Categories=AudioVideo;Music;
StartupWMClass=Daslight5.exe
DESKTOPEOF

echo ""
echo "========================================"
echo " Setup complete!"
echo "========================================"
echo ""
echo "Launch Daslight 5:"
echo "  $INSTALL_DIR/run-daslight5.sh"
echo "  (or find 'Daslight 5' in your application menu)"
echo ""
echo "Launch EasyView 2 (standalone):"
echo "  $INSTALL_DIR/run-easyview2.sh"
echo ""
echo "Files installed to: $DEST"
echo "Launchers created at: $INSTALL_DIR"
echo ""
echo "USB DMX interfaces: udev rules installed for Nicolaudie devices (vendor 0x10CE)."
echo "Reconnect your interface after setup. Art-Net/sACN works over Ethernet without drivers."
echo "========================================"

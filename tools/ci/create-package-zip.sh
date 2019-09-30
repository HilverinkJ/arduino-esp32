#/bin/bash

set -e

PKG_NAME="esp32-$RELEASE_TAG"
PKG_DIR="$OUTPUT_DIR/$PKG_NAME"
PKG_ZIP="$PKG_NAME.zip"

echo "Updating submodules ..."
git -C "$GITHUB_WORKSPACE" submodule update --init --recursive > /dev/null 2>&1

mkdir -p "$PKG_DIR/tools"

echo "Copying files for packaging ..."
cp -f  "$GITHUB_WORKSPACE/boards.txt"              "$PKG_DIR/"
cp -f  "$GITHUB_WORKSPACE/programmers.txt"         "$PKG_DIR/"
cp -Rf "$GITHUB_WORKSPACE/cores"                   "$PKG_DIR/"
cp -Rf "$GITHUB_WORKSPACE/libraries"               "$PKG_DIR/"
cp -Rf "$GITHUB_WORKSPACE/variants"                "$PKG_DIR/"
cp -f  "$GITHUB_WORKSPACE/tools/espota.exe"        "$PKG_DIR/tools/"
cp -f  "$GITHUB_WORKSPACE/tools/espota.py"         "$PKG_DIR/tools/"
cp -f  "$GITHUB_WORKSPACE/tools/esptool.py"        "$PKG_DIR/tools/"
cp -f  "$GITHUB_WORKSPACE/tools/gen_esp32part.py"  "$PKG_DIR/tools/"
cp -f  "$GITHUB_WORKSPACE/tools/gen_esp32part.exe" "$PKG_DIR/tools/"
cp -Rf "$GITHUB_WORKSPACE/tools/partitions"        "$PKG_DIR/tools/"
cp -Rf "$GITHUB_WORKSPACE/tools/sdk"               "$PKG_DIR/tools/"

echo "Cleaning up folders ..."
find "$PKG_DIR" -name '*.DS_Store' -exec rm -f {} \;
find "$PKG_DIR" -name '*.git*' -type f -delete

echo "Generating platform.txt..."
cat "$GITHUB_WORKSPACE/platform.txt" | \
sed "s/version=.*/version=$ver$extent/g" | \
sed 's/runtime.tools.xtensa-esp32-elf-gcc.path={runtime.platform.path}\/tools\/xtensa-esp32-elf//g' | \
sed 's/tools.esptool_py.path={runtime.platform.path}\/tools\/esptool/tools.esptool_py.path=\{runtime.tools.esptool_py.path\}/g' \
 > "$PKG_DIR/platform.txt"

echo "Generating core_version.h ..."
ver_define=`echo $RELEASE_TAG | tr "[:lower:].\055" "[:upper:]_"`
ver_hex=`git -C "$GITHUB_WORKSPACE" rev-parse --short=8 HEAD 2>/dev/null`
echo \#define ARDUINO_ESP32_GIT_VER 0x$ver_hex > "$PKG_DIR/cores/esp32/core_version.h"
echo \#define ARDUINO_ESP32_GIT_DESC `git -C "$GITHUB_WORKSPACE" describe --tags 2>/dev/null` >> "$PKG_DIR/cores/esp32/core_version.h"
echo \#define ARDUINO_ESP32_RELEASE_$ver_define >> "$PKG_DIR/cores/esp32/core_version.h"
echo \#define ARDUINO_ESP32_RELEASE \"$ver_define\" >> "$PKG_DIR/cores/esp32/core_version.h"

echo "Creating ZIP ..."
pushd "$OUTPUT_DIR" >/dev/null
zip -qr "$PKG_ZIP" "$PKG_NAME"
if [ $? -ne 0 ]; then echo "ERROR: Failed to create $PKG_ZIP ($?)"; exit 1; fi

echo "Calculating SHA sum ..."
PKG_PATH="$OUTPUT_DIR/$PKG_ZIP"
PKG_SHA=`shasum -a 256 "$PKG_ZIP" | cut -f 1 -d ' '`
PKG_SIZE=`get_file_size "$PKG_ZIP"`
popd >/dev/null
rm -rf "$PKG_DIR"
echo "'$PKG_ZIP' Created! Size: $PKG_SIZE, SHA-256: $PKG_SHA"

echo "Uploading package to release page ..."
PKG_URL=`git_safe_upload_asset "$PKG_PATH"`
export PKG_URL
export PKG_SHA
export PKG_SIZE
export PKG_ZIP
echo "Package Uploaded"
echo "Download URL: $PKG_URL"
echo ""

set +e

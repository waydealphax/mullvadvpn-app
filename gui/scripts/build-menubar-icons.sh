#!/usr/bin/env sh

if ! command -v convert > /dev/null; then
  echo >&2 "convert (imagemagick) is required to run this script"
  exit 1
fi

MENUBAR_PATH="assets/images/menubar icons"

MACOS="$MENUBAR_PATH/darwin"
WINDOWS="$MENUBAR_PATH/win32"
LINUX="$MENUBAR_PATH/linux"
TMP="$MENUBAR_PATH/tmp"

WINDOWS_SIZES="-define icon:auto-resize=48,32,24,20,16"

MAKE_BLACK='s/#[0-9a-fA-f]{6}/#000000/g'
MAKE_WHITE='s/#[0-9a-fA-f]{6}/#FFFFFF/g'

COMPRESSION_OPTIONS="-define png:compression-filter=5 -define png:compression-level=9 \
  -define png:compression-strategy=1 -define png:exclude-chunk=all -strip"
OPTIONS="-background transparent -density 3200 -quality 100"

function resize() {
  TARGET_SIZE=$1
  PADDING=$2
  WITHOUT_PADDING=$[$1 - ($PADDING * 2)]
  echo "-filter catrom -resize ${WITHOUT_PADDING}x$WITHOUT_PADDING \
    -gravity center -extent ${TARGET_SIZE}x$TARGET_SIZE"
}

function generate() {
  IN="$MENUBAR_PATH/svg/$1.svg"
  IN_MONO="$MENUBAR_PATH/svg/$2.svg"
  OUT="$1"

  # MacOS colored
  convert $OPTIONS $(resize 22 3) "$IN" "$MACOS/$OUT.png"
  convert $OPTIONS $(resize 44 6) "$IN" "$MACOS/$OUT@2x.png"

  # MacOS monochrome
  sed -E $MAKE_BLACK "$IN_MONO" | convert $OPTIONS $(resize 22 3) - "$MACOS/${OUT}Template.png"
  sed -E $MAKE_BLACK "$IN_MONO" | convert $OPTIONS $(resize 44 6) - "$MACOS/${OUT}Template@2x.png"

  # Linux colored
  convert $OPTIONS $(resize 32 4) "$IN" "$LINUX/$OUT.png"

  # Linux white
  sed -E $MAKE_WHITE "$IN_MONO" | convert $OPTIONS $(resize 32 4) - "$LINUX/${OUT}_white.png"

  # Windows colored
  convert $OPTIONS $(resize 64 3) "$IN" $WINDOWS_SIZES "$WINDOWS/$OUT.ico"

  # Windows white
  sed -E $MAKE_WHITE "$IN_MONO" \
    | convert $OPTIONS $(resize 64 2) - $WINDOWS_SIZES "$WINDOWS/${OUT}_white.ico"
}

mkdir -p "$MACOS" "$WINDOWS" "$LINUX" "$TMP"

for i in {1..9}; do
  generate lock-$i lock-$i
done

generate lock-10 lock-10_2

#rm -rf $TMP


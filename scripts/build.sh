#!/bin/bash

set -eu

PROJECT=${1-}
CURDIR="$(realpath "$(dirname "$0")")"

. $CURDIR/common.sh

BUILD_FILE="$ROOT_DIR/$PROJECT/build.sh"

if [ ! -e "$BUILD_FILE"  ]; then
  echo "$BUILD_FILE does not exist" >&2
  exit 1
fi

. "$BUILD_FILE"

build

rm -rf "$RELEASE_FILE"
tar -C "$ROOT_DIR/install" -czvf "$RELEASE_FILE" "${INSTALL_DIR#$ROOT_DIR/install/}"

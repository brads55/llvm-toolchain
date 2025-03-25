#!/bin/bash

set -eu

PROJECT=${1-}
CURDIR="$(realpath "$(dirname "$0")")"

. $CURDIR/common.sh

if [ -z "$PROJECT" ]; then
  echo "Must specify project" >&2
  exit 1
fi

BUILD_FILE="$ROOT_DIR/$PROJECT/build.sh"

if [ ! -e "$BUILD_FILE"  ]; then
  echo "$BUILD_FILE does not exist" >&2
  exit 1
fi

. "$BUILD_FILE"

build

rm -rf "$RELEASE_FILE"
tar -C "$ROOT_DIR" -czvf "$RELEASE_FILE" "${INSTALL_DIR#$ROOT_DIR/}"

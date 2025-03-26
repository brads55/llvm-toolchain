#!/bin/bash

set -eu

if [ -z "${PROJECT-}" ]; then
  echo "Must set PROJECT" >&2
  exit 1
fi

ROOT_DIR="$(realpath "$(dirname "$0")/..")"

if [ ! -e "$ROOT_DIR/$PROJECT" ]; then
  echo "Must specify valid project" >&2
  exit 1
fi

OS="$(uname)"
OS="${OS/_*}"
ARCH="$(uname -m)"

if [ "$OS" = "Darwin" ]; then
  OS=macos
elif [ "$OS" = "MINGW64" ]; then
  OS=windows
else
  echo "Unknown OS: $OS" >&2
  exit 1
fi

if [ "$ARCH" = "arm64" ]; then
  ARCH=aarch64
elif [ ! "$ARCH" = "x86_64" ]; then
  echo "Unknown ARCH: $ARCH" >&2
  exit 1
fi

EXE=
if [ "$OS" = "windows" ]; then
  EXE=.exe
fi

NPROC=$(nproc)

BUILD_DIR="$ROOT_DIR/build/$PROJECT"
INSTALL_DIR="$ROOT_DIR/install/$PROJECT"
RELEASE_FILE="$ROOT_DIR/release/$PROJECT-$OS-$ARCH.tar.gz"

#!/bin/bash

set -eu

MINGW_VER=v12.0.0
MINGW_SRC_DIR="$BUILD_DIR/src/mingw-w64"
MINGW_HEADER_BUILD="$BUILD_DIR/mingw-headers/$1"
MINGW_CRT_BUILD="$BUILD_DIR/mingw-crt/$1"
MINGW_PTHREAD_BUILD="$BUILD_DIR/mingw-winpthreads/$1"

if [ ! "$OS" = "windows" ]; then
  echo "Unsupported on $OS" >&2
  exit 1
fi

build() {
  if [ ! -e "$MINGW_SRC_DIR" ]; then
    git clone -b$MINGW_VER --depth=1 https://github.com/mingw-w64/mingw-w64 "$MINGW_SRC_DIR"
  fi

  git -C "$MINGW_SRC_DIR" checkout $MINGW_VER

  mkdir -p "$MINGW_HEADER_BUILD"
  cd "$MINGW_HEADER_BUILD"
  "$MINGW_SRC_DIR/mingw-w64-headers/configure" \
    --prefix="$INSTALL_DIR" \
    --enable-sdk=all \
    --enable-idl \
    --without-widl \
    --with-default-win32-winnt=0xA00 \
    --with-default-msvcrt=ucrt
  make -j$NPROC install

  mkdir -p "$MINGW_CRT_BUILD"
  cd "$MINGW_CRT_BUILD"
  "$MINGW_SRC_DIR/mingw-w64-crt/configure" \
    --host=x86_64-w64-mingw32 \
    --prefix="$INSTALL_DIR" \
    --disable-lib32 --enable-lib64 \
    --with-default-msvcrt=ucrt \
    --enable-cfguard \
    --disable-dependency-tracking
  make -j$NPROC install

  llvm-ar rcs "$INSTALL_DIR/lib/libssp.a"
  llvm-ar rcs "$INSTALL_DIR/lib/libssp_nonshared.a"

  mkdir -p "$MINGW_PTHREAD_BUILD"
  cd "$MINGW_PTHREAD_BUILD"
  "$MINGW_SRC_DIR/mingw-w64-libraries/winpthreads/configure" \
    --host=x86_64-w64-mingw32 \
    --prefix="$INSTALL_DIR" \
    --enable-static
  make -j$NPROC install
}

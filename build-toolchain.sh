#!/bin/bash

set -eu

LLVM_VER=llvmorg-20.1.1
MINGW_VER=v12.0.0

ROOT_DIR=$(realpath "$(dirname "$0")")
OS="$(uname)"
OS="${OS/_*}"
ARCH="$(uname -m)"

if [ "$OS" = "Darwin" ]; then
  OS=macos
elif [ "$OS" = "MINGW64" ]; then
  OS=windows
fi

if [ "$ARCH" = "arm64" ]; then
  ARCH=aarch64
fi

LLVM_SRC_DIR="$ROOT_DIR/llvm-project"
LLVM_BUILD_DIR="$ROOT_DIR/llvm-build"
LLVM_INSTALL_DIR="$ROOT_DIR/llvm-install"
LLVM_TARBALL="$ROOT_DIR/llvm-toolchain-$OS-$ARCH.tar.gz"

MINGW_SRC_DIR="$ROOT_DIR/mingw-w64"
MINGW_HEADER_BUILD="$ROOT_DIR/mingw-header-build"
MINGW_CRT_BUILD="$ROOT_DIR/mingw-crt-build"

RUNTIMES_BUILD_DIR="$ROOT_DIR/runtime-build"

if [ ! -e "$LLVM_SRC_DIR" ]; then
  git clone -b$LLVM_VER --depth=1 https://github.com/llvm/llvm-project.git "$LLVM_SRC_DIR"
fi

#git -C "$LLVM_SRC_DIR" checkout $LLVM_VER

if [ "$OS" = "macos" -a "$ARCH" = "aarch64" ]; then
  LLVM_TRIPLE=aarch64-apple-macos
  LLVM_TARGET=AArch64
elif [ "$OS" = "windows" -a "$ARCH" = "x86_64" ]; then
  LLVM_TRIPLE=x86_64-w64-windows-gnu
  LLVM_TARGET=X86
else
  echo "Unknown host: $OS" >&2
  exit 1
fi

cmake -S "$LLVM_SRC_DIR/llvm" -B "$LLVM_BUILD_DIR" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$LLVM_INSTALL_DIR" \
  -DLLVM_ENABLE_PROJECTS="clang;lld" \
  -DLLVM_ENABLE_LIBCXX=ON \
  -DLLVM_ENABLE_LLD=ON \
  -DLLVM_DISTRIBUTION_COMPONENTS="clang;lld;llvm-ar;llvm-objcopy;llvm-strip;llvm-ranlib;llvm-libtool-darwin;clang-resource-headers" \
  -DLLVM_DEFAULT_TARGET_TRIPLE=$LLVM_TRIPLE \
  -DLLVM_TARGETS_TO_BUILD=$LLVM_TARGET \
  -DCLANG_DEFAULT_LINKER=lld \
  -DCLANG_DEFAULT_RTLIB=compiler-rt \
  -DCLANG_DEFAULT_UNWINDLIB=libunwind \
  -DCLANG_DEFAULT_CXX_STDLIB=libc++ \
  -DLLD_DEFAULT_LD_LLD_IS_MINGW=ON

ninja -C "$LLVM_BUILD_DIR" install-distribution

if [ "$OS" = "windows" ]; then
  if [ ! -e "$MINGW_SRC_DIR" ]; then
    git clone -b$MINGW_VER --depth=1 https://github.com/mingw-w64/mingw-w64 "$MINGW_SRC_DIR"
  fi

  git -C "$MINGW_SRC_DIR" checkout $MINGW_VER

  mkdir -p "$MINGW_HEADER_BUILD"
  cd "$MINGW_HEADER_BUILD"
  "$MINGW_SRC_DIR/mingw-w64-headers/configure" \
    --prefix="$LLVM_INSTALL_DIR" \
    --enable-sdk=all \
    --enable-idl \
    --without-widl \
    --with-default-win32-winnt=0xA00 \
    --with-default-msvcrt=ucrt
  make -j$(nproc) install

  mkdir -p "$MINGW_CRT_BUILD"
  cd "$MINGW_CRT_BUILD"
  "$MINGW_SRC_DIR/mingw-w64-crt/configure" \
    --host=x86_64-w64-mingw32 \
    --prefix="$LLVM_INSTALL_DIR" \
    --disable-lib32 --enable-lib64 \
    --with-default-msvcrt=ucrt \
    --enable-cfguard \
    --disable-dependency-tracking \
    CC="$LLVM_INSTALL_DIR/bin/clang" \
    CXX="$LLVM_INSTALL_DIR/bin/clang++"
  make -j$(nproc) install

  "$LLVM_INSTALL_DIR/bin/llvm-ar" rcs "$LLVM_INSTALL_DIR/lib/libssp.a"
  "$LLVM_INSTALL_DIR/bin/llvm-ar" rcs "$LLVM_INSTALL_DIR/lib/libssp_nonshared.a"
fi

CC="$LLVM_INSTALL_DIR/bin/clang.exe" \
CXX="$LLVM_INSTALL_DIR/bin/clang++.exe" \
CXXFLAGS="-D_WIN32_WINNT=0xA00 -s" \
cmake -S "$LLVM_SRC_DIR/runtimes" -B "$RUNTIMES_BUILD_DIR" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$LLVM_INSTALL_DIR" \
  -DCMAKE_SYSTEM_IGNORE_PATH=/usr/lib \
  -DLLVM_ENABLE_RUNTIMES="compiler-rt;libunwind;libcxxabi;libcxx" \
  -DLLVM_ENABLE_LLD=ON \
  -DLLVM_DISTRIBUTION_COMPONENTS="runtimes" \
  -DCMAKE_AR="$LLVM_INSTALL_DIR/bin/llvm-ar.exe" \
  -DCMAKE_ASM_COMPILER="$LLVM_INSTALL_DIR/bin/clang.exe" \
  -DCMAKE_RANLIB="$LLVM_INSTALL_DIR/bin/llvm-ranlib.exe" \
  -DLLVM_HOST_TRIPLE=$LLVM_TRIPLE \
  -DLIBCXX_USE_COMPILER_RT=ON \
  -DLIBCXXABI_USE_COMPILER_RT=ON \
  -DLIBCXXABI_USE_LLVM_UNWINDER=ON \
  -DLIBCXXABI_ENABLE_STATIC_UNWINDER=ON \
  -DLIBUNWIND_USE_COMPILER_RT=ON \
  -DCOMPILER_RT_USE_BUILTINS_LIBRARY=ON \

ninja -C "$LLVM_BUILD_DIR" install-distribution install-cxx_experimental

rm -rf "$LLVM_TARBALL"
#tar -C "$ROOT_DIR" -czvf "$LLVM_TARBALL" "${LLVM_INSTALL_DIR#$ROOT_DIR/}"

#!/bin/bash

set -eu

LLVM_VER=llvmorg-20.1.1

ROOT_DIR=$(realpath "$(dirname "$0")")
OS="$(uname)"
ARCH="$(uname -m)"

if [ "$OS" = "Darwin" ]; then
  OS=macos
fi

if [ "$ARCH" = "arm64" ]; then
  ARCH=aarch64
fi

LLVM_SRC_DIR="$ROOT_DIR/llvm-project"
LLVM_BUILD_DIR="$ROOT_DIR/llvm-build"
LLVM_INSTALL_DIR="$ROOT_DIR/llvm-install"
LLVM_TARBALL="$ROOT_DIR/llvm-toolchain-$OS-$ARCH.tar.gz"

if [ ! -e "$LLVM_SRC_DIR" ]; then
  git clone -b$LLVM_VER --depth=1 https://github.com/llvm/llvm-project.git "$LLVM_SRC_DIR"
fi

git -C "$LLVM_SRC_DIR" checkout $LLVM_VER

if [ "$OS" = "macos" ]; then
  LLVM_TRIPLE=aarch64-apple-macos
  LLVM_TARGET=AArch64
else
  echo "Unknown host: $OS" >&2
  exit 1
fi

cmake -S "$LLVM_SRC_DIR/llvm" -B "$LLVM_BUILD_DIR" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$LLVM_INSTALL_DIR" \
  -DLLVM_ENABLE_PROJECTS="clang;lld" \
  -DLLVM_ENABLE_RUNTIMES="compiler-rt;libcxx;libcxxabi;libunwind" \
  -DLLVM_ENABLE_LLD=TRUE \
  -DLLVM_DISTRIBUTION_COMPONENTS="clang;lld;llvm-ar;llvm-objcopy;llvm-strip;llvm-libtool-darwin;runtimes;clang-resource-headers" \
  -DLLVM_DEFAULT_TARGET_TRIPLE=$LLVM_TRIPLE \
  -DLLVM_TARGETS_TO_BUILD=$LLVM_TARGET

ninja -C "$LLVM_BUILD_DIR" install-distribution

rm -rf "$LLVM_TARBALL"
tar cvfz "$LLVM_TARBALL" "$LLVM_INSTALL_DIR"

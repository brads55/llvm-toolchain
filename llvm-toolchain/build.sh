#!/bin/bash

set -eu

LLVM_VER=llvmorg-20.1.1

LLVM_SRC_DIR="$BUILD_DIR/src/llvm-project"
LLVM_BUILD_DIR="$BUILD_DIR/llvm-project"

build() {
  if [ ! -e "$LLVM_SRC_DIR" ]; then
    git clone -b$LLVM_VER --depth=1 https://github.com/llvm/llvm-project.git "$LLVM_SRC_DIR"
  fi

  git -C "$LLVM_SRC_DIR" checkout $LLVM_VER

  if [ "$OS" = "macos" -a "$ARCH" = "aarch64" ]; then
    LLVM_TRIPLE=aarch64-apple-macos
    LLVM_TARGET=AArch64
    SYSROOT=$(xcrun --show-sdk-path)
    EXTRA_OPTS=" \
      -DCOMPILER_RT_ENABLE_IOS=OFF \
    "
  elif [ "$OS" = "windows" -a "$ARCH" = "x86_64" ]; then
    LLVM_TRIPLE=x86_64-w64-windows-gnu
    LLVM_TARGET=X86
    SYSROOT="/clang64"
    EXTRA_OPTS=" \
      -DLIBCXXABI_HAS_WIN32_THREAD_API=ON \
      -DLIBCXX_HAS_WIN32_THREAD_API=ON \
      -DLLD_DEFAULT_LD_LLD_IS_MINGW=ON \
    "
  else
    echo "Unknown host: $OS" >&2
    exit 1
  fi

  CXXFLAGS="-D_WIN32_WINNT=0xA00" \
  cmake -S "$LLVM_SRC_DIR/llvm" -B "$LLVM_BUILD_DIR" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
    -DCMAKE_C_COMPILER="clang" \
    -DCMAKE_CXX_COMPILER="clang++" \
    -DCMAKE_SYSROOT="$SYSROOT" \
    -DLLVM_ENABLE_PROJECTS="clang;lld" \
    -DLLVM_DISTRIBUTION_COMPONENTS="clang;lld;llvm-ar;llvm-objcopy;llvm-strip;llvm-ranlib;llvm-libtool-darwin;clang-resource-headers;builtins;runtimes" \
    -DLLVM_ENABLE_RUNTIMES="compiler-rt;libunwind;libcxxabi;libcxx" \
    -DLLVM_DEFAULT_TARGET_TRIPLE=$LLVM_TRIPLE \
    -DLLVM_TARGETS_TO_BUILD=$LLVM_TARGET \
    -DCLANG_DEFAULT_RTLIB=compiler-rt \
    -DCLANG_DEFAULT_UNWINDLIB=libunwind \
    -DCLANG_DEFAULT_CXX_STDLIB=libc++ \
    -DCLANG_DEFAULT_LINKER=lld \
    -DLLVM_ENABLE_LIBCXX=ON \
    -DLLVM_ENABLE_LLD=ON \
    -DSANITIZER_CXX_ABI=libc++ \
    -DCOMPILER_RT_DEFAULT_TARGET_TRIPLE=$LLVM_TRIPLE \
    -DCOMPILER_RT_USE_BUILTINS_LIBRARY=ON \
    -DCOMPILER_RT_BUILD_BUILTINS=ON \
    -DLIBUNWIND_USE_COMPILER_RT=ON \
    -DLIBUNWIND_ENABLE_SHARED=OFF \
    -DLIBCXXABI_USE_COMPILER_RT=ON \
    -DLIBCXXABI_USE_LLVM_UNWINDER=ON \
    -DLIBCXXABI_ENABLE_STATIC_UNWINDER=ON \
    -DLIBCXXABI_ENABLE_SHARED=OFF \
    -DLIBCXX_USE_COMPILER_RT=ON \
    -DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=ON \
    -DLIBCXX_INCLUDE_BENCHMARKS=OFF \
    -DLIBCXX_ENABLE_SHARED=OFF \
    $EXTRA_OPTS

  ninja -C "$LLVM_BUILD_DIR" install-distribution
}

#!/bin/bash

set -eu

LLVM_VER=llvmorg-20.1.1
MINGW_VER=v12.0.0

STAGE1_INSTALL_DIR="$BUILD_DIR/stage1-install"
STAGE2_INSTALL_DIR="$INSTALL_DIR"

LLVM_SRC_DIR="$BUILD_DIR/src/llvm-project"
LLVM_BUILD_DIR="$BUILD_DIR/llvm-project"

MINGW_SRC_DIR="$BUILD_DIR/src/mingw-w64"
MINGW_HEADER_BUILD="$BUILD_DIR/mingw-headers"
MINGW_CRT_BUILD="$BUILD_DIR/mingw-crt"

update_dirs() {
  STAGE="stage1"
  CURRENT_INSTALL_DIR="$STAGE1_INSTALL_DIR"
  if [ "${1-}" == "STAGE2" ]; then
    STAGE="stage2"
    CURRENT_INSTALL_DIR="$STAGE2_INSTALL_DIR"
  fi

  LLVM_BUILD_DIR="$BUILD_DIR/llvm-project/$STAGE"
  MINGW_HEADER_BUILD="$BUILD_DIR/mingw-headers/$STAGE"
  MINGW_CRT_BUILD="$BUILD_DIR/mingw-crt/$STAGE"
}

build_sysroot() {
  if [ "$OS" = "windows" ]; then
    if [ ! -e "$MINGW_SRC_DIR" ]; then
      git clone -b$MINGW_VER --depth=1 https://github.com/mingw-w64/mingw-w64 "$MINGW_SRC_DIR"
    fi

    git -C "$MINGW_SRC_DIR" checkout $MINGW_VER

    mkdir -p "$MINGW_HEADER_BUILD"
    cd "$MINGW_HEADER_BUILD"
    "$MINGW_SRC_DIR/mingw-w64-headers/configure" \
      --prefix="$CURRENT_INSTALL_DIR" \
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
      --prefix="$CURRENT_INSTALL_DIR" \
      --disable-lib32 --enable-lib64 \
      --with-default-msvcrt=ucrt \
      --enable-cfguard \
      --disable-dependency-tracking
    make -j$NPROC install

    llvm-ar rcs "$INSTALL_DIR/lib/libssp.a"
    llvm-ar rcs "$INSTALL_DIR/lib/libssp_nonshared.a"
  fi
}

build_llvm() {
  if [ ! -e "$LLVM_SRC_DIR" ]; then
    git clone -b$LLVM_VER --depth=1 https://github.com/llvm/llvm-project.git "$LLVM_SRC_DIR"
  fi

  git -C "$LLVM_SRC_DIR" checkout $LLVM_VER

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

  EXTRA_ARGS=""

  # Stage 2
  if [ "${1-}" == "STAGE2" ]; then
    EXTRA_ARGS="
      -DCMAKE_SYSTEM_IGNORE_PATH=/usr/lib \
      -DCMAKE_AR=$STAGE1_INSTALL_DIR/bin/llvm-ar$EXE \
      -DCMAKE_ASM_COMPILER=$STAGE1_INSTALL_DIR/bin/clang$EXE \
      -DCMAKE_RANLIB=$STAGE1_INSTALL_DIR/bin/llvm-ranlib$EXE \
      -DLLVM_ENABLE_LIBCXX=ON \
      -DLLVM_ENABLE_LLD=ON \
      -DLLVM_HOST_TRIPLE=$LLVM_TRIPLE \
      -DCLANG_DEFAULT_LINKER=lld \
      -DCLANG_DEFAULT_RTLIB=compiler-rt \
      -DCLANG_DEFAULT_UNWINDLIB=libunwind \
      -DCLANG_DEFAULT_CXX_STDLIB=libc++ \
      -DLIBCXX_USE_COMPILER_RT=ON \
      -DLIBCXXABI_USE_COMPILER_RT=ON \
      -DLIBCXXABI_USE_LLVM_UNWINDER=ON \
      -DLIBCXXABI_ENABLE_STATIC_UNWINDER=ON \
      -DLIBUNWIND_USE_COMPILER_RT=ON \
      -DCOMPILER_RT_USE_BUILTINS_LIBRARY=ON"
  fi

  CXXFLAGS="-D_WIN32_WINNT=0xA00" \
  cmake -S "$LLVM_SRC_DIR/llvm" -B "$LLVM_BUILD_DIR" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$CURRENT_INSTALL_DIR" \
    -DLLVM_ENABLE_PROJECTS="clang;lld" \
    -DLLVM_ENABLE_RUNTIMES="compiler-rt;libunwind;libcxxabi;libcxx" \
    -DLLVM_DISTRIBUTION_COMPONENTS="clang;lld;llvm-ar;llvm-objcopy;llvm-strip;llvm-ranlib;llvm-libtool-darwin;clang-resource-headers;runtimes" \
    -DLLVM_DEFAULT_TARGET_TRIPLE=$LLVM_TRIPLE \
    -DLLVM_TARGETS_TO_BUILD=$LLVM_TARGET \
    -DLLD_DEFAULT_LD_LLD_IS_MINGW=ON \
    $EXTRA_ARGS

  ninja -C "$LLVM_BUILD_DIR" install-distribution
}

build() {
  # Stage 1 - initial host built toolchain
  update_dirs
  build_sysroot
  build_llvm

  # Stage 1 - self built toolchain
  export CC="$STAGE1_INSTALL_DIR/bin/clang$EXE"
  export CXX="$STAGE1_INSTALL_DIR/bin/clang++$EXE"
  update_dirs STAGE2
  build_sysroot
  build_llvm STAGE2
}

#!/bin/bash

set -eu

LLVM_VER=llvmorg-20.1.1
MINGW_VER=v12.0.0

STAGE1_INSTALL_DIR="$BUILD_DIR/install-stage1"
STAGE2_INSTALL_DIR="$INSTALL_DIR"

LLVM_SRC_DIR="$BUILD_DIR/src/llvm-project"
MINGW_SRC_DIR="$BUILD_DIR/src/mingw-w64"

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

setup_dirs() {
  LLVM_BUILD_DIR="$BUILD_DIR/llvm-project/$1"
  RUNTIME_BUILD_DIR="$BUILD_DIR/runtimes/$1"
  MINGW_HEADER_BUILD="$BUILD_DIR/mingw-headers/$1"
  MINGW_CRT_BUILD="$BUILD_DIR/mingw-crt/$1"
  MINGW_PTHREAD_BUILD="$BUILD_DIR/mingw-winpthreads/$1"
}

build_llvm() {
  if [ ! -e "$LLVM_SRC_DIR" ]; then
    git clone -b$LLVM_VER --depth=1 https://github.com/llvm/llvm-project.git "$LLVM_SRC_DIR"
  fi

  git -C "$LLVM_SRC_DIR" checkout $LLVM_VER

  CXXFLAGS="-D_WIN32_WINNT=0xA00" \
  cmake -S "$LLVM_SRC_DIR/llvm" -B "$LLVM_BUILD_DIR" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
    -DLLVM_ENABLE_PROJECTS="clang;lld" \
    -DLLVM_ENABLE_RUNTIMES="compiler-rt" \
    -DLLVM_DISTRIBUTION_COMPONENTS="clang;lld;llvm-ar;llvm-objcopy;llvm-strip;llvm-ranlib;llvm-libtool-darwin;clang-resource-headers;builtins;runtime" \
    -DLLVM_DEFAULT_TARGET_TRIPLE=$LLVM_TRIPLE \
    -DLLVM_TARGETS_TO_BUILD=$LLVM_TARGET \
    -DLLD_DEFAULT_LD_LLD_IS_MINGW=ON \
    -DCLANG_DEFAULT_RTLIB=compiler-rt \
    -DCLANG_DEFAULT_UNWINDLIB=libunwind \
    -DCLANG_DEFAULT_CXX_STDLIB=libc++ \
    -DCLANG_DEFAULT_LINKER=lld \
    -DLLVM_ENABLE_LIBCXX=ON \
    -DLLVM_ENABLE_LLD=ON \
    -DCOMPILER_RT_DEFAULT_TARGET_TRIPLE=$LLVM_TRIPLE \
    -DCOMPILER_RT_USE_BUILTINS_LIBRARY=ON \
    -DCOMPILER_RT_BUILD_BUILTINS=ON \
    -DSANITIZER_CXX_ABI=libc++ \
    $1

  ninja -C "$LLVM_BUILD_DIR" install-distribution
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
  fi
}

build_runtimes() {
  CXXFLAGS="-D_WIN32_WINNT=0xA00" \
  cmake -S "$LLVM_SRC_DIR/runtimes" -B "$RUNTIME_BUILD_DIR" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
    -DLLVM_ENABLE_RUNTIMES="libunwind;libcxxabi;libcxx" \
    -DLLVM_ENABLE_LLD=ON \
    -DLIBCXX_USE_COMPILER_RT=ON \
    -DLIBCXXABI_USE_COMPILER_RT=ON \
    -DLIBCXXABI_USE_LLVM_UNWINDER=ON \
    -DLIBCXXABI_ENABLE_STATIC_UNWINDER=ON \
    -DLIBUNWIND_USE_COMPILER_RT=ON \
    -DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=ON \
    -DLIBCXXABI_HAS_WIN32_THREAD_API=ON \
    -DLIBCXX_HAS_WIN32_THREAD_API=ON \
    -DLLVM_INCLUDE_TESTS=OFF \
    -DLIBCXX_INCLUDE_BENCHMARKS=OFF \
    -DLIBCXXABI_ENABLE_SHARED=OFF \
    -DLIBCXX_ENABLE_SHARED=OFF \
    -DLIBUNWIND_ENABLE_SHARED=OFF

  ninja -C "$RUNTIME_BUILD_DIR" install
}

build() {
  INSTALL_DIR="$STAGE1_INSTALL_DIR"
  setup_dirs stage1
  build_sysroot
  build_llvm "-DDEFAULT_SYSROOT=$STAGE1_INSTALL_DIR"
  build_runtimes

  export CC="$INSTALL_DIR/bin/clang$EXE"
  export CXX="$INSTALL_DIR/bin/clang++$EXE"
  INSTALL_DIR="$STAGE2_INSTALL_DIR"
  setup_dirs stage2
  build_sysroot
  build_llvm
  build_runtimes
}

#!/bin/sh

# Inputs that define the ABI and contents of the staged LLVM dependency.
# Keep this file small and LLVM-specific: the Actions cache key hashes it so
# unrelated QEMU, Mesa, virglrenderer, or DXMT changes do not invalidate LLVM.
LLVM_CACHE_SCHEMA="1"
LLVM_CACHE_SOURCE_NAME="llvm-project-15.0.7.src"
LLVM_CACHE_CMAKE_OPTIONS="-DLLVM_ENABLE_ZSTD=Off -DLLVM_TARGETS_TO_BUILD= -DLLVM_BUILD_TOOLS=Off -DLLVM_VERSION_PRINTER_SHOW_HOST_TARGET_INFO=Off"

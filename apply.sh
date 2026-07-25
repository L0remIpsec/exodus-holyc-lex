#!/usr/bin/env sh
# drops the lex bridge files into an existing Exodus checkout and
# applies the four upstream patches. run from this overlay's root,
# pointing at the Exodus tree you want to modify.
#
#   ./apply.sh /path/to/EXODUS
set -eu

if [ $# -ne 1 ]; then
  echo "usage: $0 <path-to-exodus-checkout>" >&2
  exit 2
fi

EXODUS=$1
HERE=$(cd "$(dirname "$0")" && pwd)

if [ ! -f "$EXODUS/CMakeLists.txt" ] || [ ! -d "$EXODUS/src/exodus" ]; then
  echo "error: $EXODUS does not look like an Exodus checkout" >&2
  exit 1
fi

echo "copying new files into $EXODUS"
mkdir -p "$EXODUS/T/Demo" "$EXODUS/cmake" "$EXODUS/haskell/Exodus"
cp "$HERE/src/exodus/lex_ffi.h"       "$EXODUS/src/exodus/"
cp "$HERE/src/exodus/lex_ffi.c"       "$EXODUS/src/exodus/"
cp "$HERE/src/exodus/lex_host_test.c" "$EXODUS/src/exodus/"
cp "$HERE/T/Demo/ExodusLexDemo.HC"    "$EXODUS/T/Demo/"
cp "$HERE/T/Demo/ExodusLexServer.HC"  "$EXODUS/T/Demo/"
cp "$HERE/cmake/RunLexBridgeTest.cmake" "$EXODUS/cmake/"
cp "$HERE/haskell/Exodus/Lex.hs"      "$EXODUS/haskell/Exodus/"
cp "$HERE/haskell/exodus-lex.cabal"   "$EXODUS/haskell/"

echo "applying patches"
( cd "$EXODUS" && git apply "$HERE/patches/"*.patch )

echo "done. now run:"
echo "  cmake -S \"$EXODUS\" -B \"$EXODUS/build\" -DBUILD_EXODUS_LEX_SHARED=ON"
echo "  cmake --build \"$EXODUS/build\""

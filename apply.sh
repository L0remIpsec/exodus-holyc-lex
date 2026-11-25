#!/usr/bin/env sh
# drops the lex bridge files into an existing Exodus checkout and
# applies the upstream patches. safe to run again after pulling a newer
# overlay: files are overwritten, patches that are already in are
# skipped, and nothing is touched if a patch would not apply.
#
#   ./apply.sh /path/to/EXODUS
set -eu

if [ $# -ne 1 ]; then
  echo "usage: $0 <path-to-exodus-checkout>" >&2
  exit 2
fi

EXODUS=$1
HERE=$(cd "$(dirname "$0")" && pwd)

if [ ! -f "$EXODUS/CMakeLists.txt" ] || [ ! -d "$EXODUS/src/exodus" ] ||
   [ ! -f "$EXODUS/T/Compiler/CMP_PRJ.HC" ]; then
  echo "error: $EXODUS does not look like an Exodus checkout" >&2
  exit 1
fi

# sort the patches into "already applied" and "to apply" before
# changing anything, so a patch that fits neither stops us with the
# tree exactly as it was
todo=
for p in "$HERE"/patches/*.patch; do
  name=$(basename "$p")
  if ( cd "$EXODUS" && git apply --reverse --check "$p" ) 2>/dev/null; then
    echo "already applied: $name"
  elif ( cd "$EXODUS" && git apply --check "$p" ) 2>/dev/null; then
    todo="$todo $name"
  else
    echo "error: $name does not apply to $EXODUS" >&2
    echo "  upstream has probably moved, or the file was edited by hand." >&2
    echo "  nothing was changed. details:" >&2
    ( cd "$EXODUS" && git apply --check "$p" ) >&2 || true
    exit 1
  fi
done

echo "copying new files into $EXODUS"
mkdir -p "$EXODUS/T/Demo" "$EXODUS/cmake" "$EXODUS/haskell/Exodus" \
         "$EXODUS/haskell/demo"
cp "$HERE/src/exodus/lex_ffi.h"         "$EXODUS/src/exodus/"
cp "$HERE/src/exodus/lex_ffi.c"         "$EXODUS/src/exodus/"
cp "$HERE/src/exodus/lex_host_test.c"   "$EXODUS/src/exodus/"
cp "$HERE/T/Compiler/ExodusLex.HC"      "$EXODUS/T/Compiler/"
cp "$HERE/T/Demo/ExodusLexDemo.HC"      "$EXODUS/T/Demo/"
cp "$HERE/T/Demo/ExodusLexServer.HC"    "$EXODUS/T/Demo/"
cp "$HERE/cmake/RunLexBridgeTest.cmake" "$EXODUS/cmake/"
cp "$HERE/haskell/Exodus/Lex.hs"        "$EXODUS/haskell/Exodus/"
cp "$HERE/haskell/demo/Main.hs"         "$EXODUS/haskell/demo/"
cp "$HERE/haskell/exodus-lex.cabal"     "$EXODUS/haskell/"

for name in $todo; do
  echo "applying $name"
  ( cd "$EXODUS" && git apply "$HERE/patches/$name" )
done

echo "done. now run:"
echo "  cmake -S \"$EXODUS\" -B \"$EXODUS/build\" -DBUILD_EXODUS_LEX_SHARED=ON"
echo "  cmake --build \"$EXODUS/build\""
echo "  ctest --test-dir \"$EXODUS/build\" -L bridge"

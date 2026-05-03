# exodus-holyc-lex

a small drop in addition to [Exodus](https://github.com/aiwnios/EXODUS)
that lets you reach the HolyC lexer from C and from Haskell. think of it
as a tinkerer's note pinned to the side of your Exodus checkout, not a
fork.

## what it does

it adds one C function to Exodus

```c
ExodusLexResult *ExodusLex(char const *src);
void             ExodusLexFree(ExodusLexResult *res);
```

that hands the source string to HolyC's own `Lex` (through `CmpCtrlNew`
and `CmpCtrlDel`) and gives you back a flat array of tokens

```c
typedef struct ExodusToken {
  i64 token;     // raw HolyC token id, see KernelA.HH
  i64 line;      // source line
  i64 i64_val;   // payload for TK_I64 and TK_CHAR_CONST
  f64 f64_val;   // payload for TK_F64
  char *str;     // payload for TK_IDENT and TK_STR, heap or NULL
} ExodusToken;

typedef struct ExodusLexResult {
  ExodusToken *tokens;   // last entry is always TK_EOF (0)
  size_t       count;
} ExodusLexResult;
```

the same function is registered with HolyC, so HolyC code in Exodus can
call `ExodusLex` directly and walk the result with the matching
`class ExodusLexResult` declaration. the included Haskell bindings link
against the produced `libexodus_lex` shared library so you can drive the
lexer from outside HolyC too.

## what's in the box

```
src/exodus/lex_ffi.h       the C API
src/exodus/lex_ffi.c       implementation, talks to HolyC's Lex
T/Demo/ExodusLexDemo.HC    HolyC demo, declares the matching classes
cmake/RunLexBridgeTest.cmake  ctest harness for the demo
haskell/Exodus/Lex.hs      Haskell bindings (Storable struct peek)
haskell/exodus-lex.cabal   cabal file for the bindings package
patches/                   four small unified diffs against upstream
```

the patches are tiny

* `01-ffi-register.patch`     two `STK_*` thunks plus `S(ExodusLex,1), S(ExodusLexFree,1)` in `ffi.c`
* `02-kernela-decl.patch`     `import` and `public extern` lines in `T/KernelA.HH` next to `HPET`
* `03-src-cmakelists.patch`   adds `lex_ffi.c` to the executable and an optional `libexodus_lex` shared lib (`BUILD_EXODUS_LEX_SHARED`, default ON)
* `04-root-cmakelists.patch`  wires SDL2 and platform deps into the shared lib and registers the ctest

## installing

assuming your Exodus tree is at `~/EXODUS` and this overlay is at
`~/exodus-holyc-lex`

```sh
cd ~/EXODUS

# drop in the new files
cp ../exodus-holyc-lex/src/exodus/lex_ffi.h   src/exodus/
cp ../exodus-holyc-lex/src/exodus/lex_ffi.c   src/exodus/
cp ../exodus-holyc-lex/T/Demo/ExodusLexDemo.HC T/Demo/
cp ../exodus-holyc-lex/cmake/RunLexBridgeTest.cmake cmake/

# apply the four patches
git apply ../exodus-holyc-lex/patches/*.patch
```

> **note on `T/KernelA.HH`** that file is not UTF-8, it stores the pi
> identifier as a single 0xE3 byte. the patch is plain ASCII and only
> touches the area around `HPET`, so `git apply` preserves the byte.
> if you ever hand edit it, do it with an encoding aware editor.

then build the usual way

```sh
cmake -S . -B build -DBUILD_EXODUS_LEX_SHARED=ON
cmake --build build
ctest --test-dir build -L bridge   # optional, runs the round trip demo
```

`build/src/exodus/libexodus_lex.{so,dylib,dll}` is the shared library
the Haskell side links against.

## using it from HolyC

inside Exodus

```holyc
#include "::/Demo/ExodusLexDemo";   // pulls in the class decls and a runner
ExodusLexDemo("I64 x=42; F64 pi=3.14; \"hello\";");
```

or from your own HolyC code, after declaring the two classes (copy them
out of `T/Demo/ExodusLexDemo.HC`)

```holyc
ExodusLexResult *res = ExodusLex("I64 x = 7;");
if (res) {
  I64 i;
  for (i = 0; i < res->count; i++)
    "tok 0x%03X line %d\n", res->tokens[i].token, res->tokens[i].line;
  ExodusLexFree(res);
}
```

## using it from Haskell

```sh
cd haskell
cp -r ../../exodus-holyc-lex/haskell/* .   # only if you don't already have it
cabal build --extra-lib-dirs=../build/src/exodus
```

```haskell
import qualified Exodus.Lex as Lex

main :: IO ()
main = do
  -- the calling process must be Exodus itself, or a host that has
  -- already run BootstrapLoader so HCRT is live in memory
  result <- Lex.lex "I64 x = 42;"
  case result of
    Nothing  -> putStrLn "HCRT not loaded"
    Just tks -> mapM_ print tks
```

`Lex.lex` and `Lex.withLex` peek the C struct directly through a
`Storable` instance, no extra accessor calls.

## a couple of caveats

* HCRT has to be loaded in the calling process before `ExodusLex` can
  resolve `CmpCtrlNew`, `Lex` and `CmpCtrlDel`. in practice that means
  the consumer is Exodus itself, or an embedder that has already run
  Exodus's bootstrap path.
* token ids below 0x100 are single chars and minor punctuation, ids at
  or above 0x100 are the `TK_*` enum from `T/KernelA.HH`. the bridge
  only fills the payload fields for the ones that have one
  (`TK_I64`, `TK_CHAR_CONST`, `TK_F64`, `TK_IDENT`, `TK_STR`).
* the result, including every `str` payload, is plain `malloc`/`strdup`
  on the C heap. always release it through `ExodusLexFree`.

## license

same license as Exodus itself, see the upstream repository.

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

// standalone hosts: boot a full runtime in-process, then lex from any thread
int              ExodusLexBoot(char const *t_root, char const *hcrt_bin);
ExodusLexResult *ExodusLexRemote(char const *src);
```

that hands the source string to HolyC's own `Lex` and gives you back a
flat array of tokens

```c
typedef struct ExodusToken {
  i64 token;     // raw HolyC token id, see KernelA.HH
  i64 line;      // source line
  i64 i64_val;   // payload for TK_I64 and TK_CHAR_CONST
  f64 f64_val;   // payload for TK_F64
  char *str;     // payload for TK_IDENT and TK_STR, heap or NULL
  i64 str_len;   // payload bytes in str, embedded NULs included
} ExodusToken;

typedef struct ExodusLexResult {
  ExodusToken *tokens;   // last entry is always TK_EOF (0)
  size_t       count;
} ExodusLexResult;
```

you get `NULL` instead when `Lex` rejects the source. the lexer throws
on a few things (a char constant longer than 8 chars, a throw out of an
`#exe{}` block), the bridge catches that on the HolyC side, cleans up
and stays usable for the next call.

the same function is registered with HolyC, so HolyC code in Exodus can
call `ExodusLex` directly and walk the result with the matching
`class ExodusLexResult` declaration. the included Haskell bindings link
against the produced `libexodus_lex` shared library so you can drive the
lexer from outside HolyC too.

## what's in the box

```
src/exodus/lex_ffi.h       the C API
src/exodus/lex_ffi.c       implementation, walks the token stream
src/exodus/lex_host_test.c ctest host that links the shared lib like a binding would
T/Compiler/ExodusLex.HC    HolyC half: Lex inside a try/catch, scratch table for defines
T/Demo/ExodusLexDemo.HC    HolyC demo, declares the matching classes
T/Demo/ExodusLexServer.HC  server loop that answers ExodusLexRemote requests
cmake/RunLexBridgeTest.cmake  ctest harness for the demo
haskell/Exodus/Lex.hs      Haskell bindings (Storable struct peek)
haskell/demo/Main.hs       boots Exodus and prints the tokens of a source
haskell/exodus-lex.cabal   cabal file for the bindings and the demo
patches/                   five small unified diffs against upstream
apply.sh, apply.ps1        copy the files and apply the patches in one go
```

the patches are tiny

* `01-ffi-register.patch`     `STK_*` thunks plus `S(ExodusLex,1), S(ExodusLexFree,1)` and the `ExodusLexPoll` hook in `ffi.c`
* `02-kernela-decl.patch`     `import` and `public extern` lines in `T/KernelA.HH` next to `HPET`
* `03-src-cmakelists.patch`   adds `lex_ffi.c` to the executable, an optional `libexodus_lex` shared lib (`BUILD_EXODUS_LEX_SHARED`, default ON) and the host test exe
* `04-root-cmakelists.patch`  wires SDL2, platform deps and the vendor static libs (dyad, argtable3, vec, isocline, map, built as PIC) into the shared lib and registers the ctests
* `05-compiler-include.patch` one `#include "ExodusLex.HC"` in `T/Compiler/CMP_PRJ.HC` so the HolyC half is compiled into HCRT

## installing

point the apply script at your Exodus tree

```sh
./apply.sh ~/EXODUS                    # or  .\apply.ps1 -ExodusPath C:\src\EXODUS
```

it copies the new files in and applies the patches. it checks every
patch before touching anything, and it skips the ones that are already
in, so running it again after pulling a newer overlay is how you
upgrade.

by hand it is the same two steps, from inside the Exodus tree with this
overlay checked out next to it

```sh
cd ~/EXODUS
O=../exodus-holyc-lex

cp $O/src/exodus/lex_ffi.h $O/src/exodus/lex_ffi.c \
   $O/src/exodus/lex_host_test.c         src/exodus/
cp $O/T/Compiler/ExodusLex.HC            T/Compiler/
cp $O/T/Demo/ExodusLexDemo.HC $O/T/Demo/ExodusLexServer.HC T/Demo/
cp $O/cmake/RunLexBridgeTest.cmake       cmake/
cp -r $O/haskell                         .

git apply $O/patches/*.patch
```

> **note on `T/KernelA.HH`** that file is not UTF-8, it stores the pi
> identifier as a single 0xE3 byte. the patch is plain ASCII and only
> touches the area around `HPET`, so `git apply` preserves the byte.
> if you ever hand edit it, do it with an encoding aware editor.

then build the usual way

```sh
cmake -S . -B build -DBUILD_EXODUS_LEX_SHARED=ON
cmake --build build
ctest --test-dir build -L bridge   # optional, see below
```

the build recompiles `HCRT.BIN` from `T/`, which is what picks up
`T/Compiler/ExodusLex.HC`. an `HCRT.BIN` from before the patches makes
`ExodusLex` return `NULL` for everything.

the two `bridge` tests are `exodus_lex_bridge`, which runs the HolyC
demo under `exodus -c` and checks its output, and `exodus_lex_host`,
which boots the runtime from a plain C program through the shared
library and goes after the awkward parts: sources that make `Lex`
throw, eight threads lexing at once, a boot pointed at a directory
that isn't there.

`build/src/exodus/libexodus_lex.{so,dylib,dll}` is the shared library
the Haskell side links against.

## using it from HolyC

inside Exodus the demo runs itself when you include it, so this on its
own is the whole thing

```holyc
#include "::/Demo/ExodusLexDemo";
```

you get a handful of token dumps out of it: the default source, an
embedded NUL round trip, a define being expanded, and one source `Lex`
refuses. to lex something of your own, hand it a string

```holyc
ExodusLexDemo("I64 x=42; F64 pi=3.14; \"hello\";");
```

keep that one in a file and include the file. typed straight at the GUI
command line the quoting tends to come apart, and when it does the
`#include` string never closes, so the filename swallows the rest of the
line and the newline with it. that is what the pile of

```
ERROR: Invalid FileName: "ExodusLexDemo"; ExodusLexDemo("I64 x=42;");;
.HC".
```

errors means: the `.HC` on the next line is just the extension being
appended to a filename that ran away. four of those (`.HC` and `.HC.Z`,
twice each) then a `File not found` is the signature. nothing is wrong
with the bridge when you see it. CLI mode (`exodus -c`) takes the same
line verbatim.

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

`apply.sh` puts the package in `haskell/` of your Exodus tree. the
library has to be found twice, by the linker and by the loader, and the
runtime wants `T/` and `HCRT.BIN`, so the demo is easiest run from the
tree's root

```sh
cd ~/EXODUS
LIB=$PWD/build/src/exodus
(cd haskell && cabal build --extra-lib-dirs=$LIB)
LD_LIBRARY_PATH=$LIB $(cd haskell && cabal list-bin exodus-lex-demo)
```

(`PATH` instead of `LD_LIBRARY_PATH` on Windows, `DYLD_LIBRARY_PATH` on
macOS.) `haskell/demo/Main.hs` is the whole program

```haskell
import qualified Exodus.Lex as Lex

main :: IO ()
main = do
  -- boots a full Exodus runtime inside this process. paths resolve
  -- against the cwd. one boot per process, no shutdown.
  up <- Lex.boot "T" "HCRT.BIN"
  if not up
    then putStrLn "boot failed"
    else do
      result <- Lex.lex "I64 x = 42;"
      case result of
        Nothing  -> putStrLn "Lex rejected the source"
        Just tks -> mapM_ print tks
```

`Lex.lex` and `Lex.withLex` peek the C struct directly through a
`Storable` instance, no extra accessor calls. strings cross as raw
bytes, one `Char` per byte, because HolyC source isn't UTF-8 and a
locale decode would mangle anything outside ASCII.

## a couple of caveats

* this is the real `Lex`, preprocessor and all. `#include` reads files
  and `#exe{}` compiles and runs HolyC, in the server task for a
  standalone host, so an `#exe{Exit;}` takes the lexer with it. don't
  lex source you wouldn't be willing to compile.
* `#define` works within the source that contains it and stops there.
  each call lexes against a scratch symbol table chained in front of
  the task's, so a define never lands in the calling task and never
  shows up in the next call.
* `NULL` means the runtime isn't up, the `HCRT.BIN` is older than the
  patches, or `Lex` threw. inside Exodus HolyC prints the usual `ERROR:`
  line for a throw. a standalone host gets no message, the server task
  runs silent so it doesn't write into the host's stdout.
* two ways in: HolyC code inside Exodus calls `ExodusLex` directly, a
  standalone host links `libexodus_lex`, calls `ExodusLexBoot` once and
  then `ExodusLexRemote` from whatever thread it likes. `ExodusLex` from
  a foreign thread would crash (HolyC only runs on threads Exodus made,
  their GS points at the CTask/CCPU context).
* `ExodusLexBoot` runs the whole runtime in your process: one boot per
  process, no shutdown, requests serialize through one server task, and
  HolyC `Exit`/`Shutdown` ends the host process. the boot also prints
  the usual HCRT chatter to stdout. it fails straight away if `T` or
  `HCRT.BIN` can't be found, and a failed boot can't be retried.
* the server task polls once per HolyC tick, so a remote call costs
  about a millisecond however short the source is.
* token ids below 0x100 are single chars and minor punctuation, ids at
  or above 0x100 are the `TK_*` enum from `T/KernelA.HH`. the bridge
  only fills the payload fields for the ones that have one
  (`TK_I64`, `TK_CHAR_CONST`, `TK_F64`, `TK_IDENT`, `TK_STR`).
* `Lex` expands defines, so a define never reaches you as an
  identifier. `pi` is the one that catches people out, `KernelA.HH` has
  it as `#define pi (0x400921FB54442D18(F64))` and that is what comes
  back, six tokens with the bit pattern sitting in the middle as a
  plain `TK_I64`. HolyC sets `CCF_NO_DEFINES` when it wants raw
  identifiers, the bridge does not.
* HolyC string literals may contain embedded NULs (`\0` and `\xNN`
  escapes), so don't walk `str` with `strlen`: `str_len` holds the exact
  payload size. the bridge still NUL terminates `str` on top so the
  common case stays printable.
* the result, including every `str` payload, is plain `malloc` on the C
  heap. always release it through `ExodusLexFree`.

## license

same license as Exodus itself (zlib), see the upstream repository.

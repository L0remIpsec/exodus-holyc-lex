// vi: set et ft=c ts=2 sts=2 sw=2 fenc=utf-8 :vi
//
// drives the HolyC lexer (Lex, CmpCtrlNew, CmpCtrlDel) from C and hands
// back the token stream as a flat array so other languages can pick it
// up easily (Haskell bindings live in haskell/Exodus/Lex.hs).
#pragma once

#include <stddef.h>

#include <exodus/types.h>

#if defined(_WIN32) || defined(__CYGWIN__)
# define EXODUS_API __attribute__((dllexport))
#else
# define EXODUS_API __attribute__((visibility("default")))
#endif

/* one token, taken straight off CCmpCtrl's cur_* fields after a Lex call.
 * ids below 0x100 are single chars and the like; ids at or above 0x100
 * are the TK_* enum values from KernelA.HH. */
typedef struct ExodusToken {
  i64 token;     /* raw HolyC token id */
  i64 line;      /* source line, lifted from cc->last_line_num */
  i64 i64_val;   /* payload for TK_I64 and TK_CHAR_CONST */
  f64 f64_val;   /* payload for TK_F64 */
  char *str;     /* payload for TK_IDENT and TK_STR, heap or NULL */
} ExodusToken;

typedef struct ExodusLexResult {
  ExodusToken *tokens; /* heap array of length count, last entry is TK_EOF */
  size_t count;
} ExodusLexResult;

/* lex src (a zero terminated HolyC source string) and return a heap
 * allocated result with one entry per token. the last entry always has
 * .token == TK_EOF (0). returns NULL if the HolyC runtime hasn't been
 * loaded yet. caller owns the result and must hand it to ExodusLexFree. */
EXODUS_API ExodusLexResult *ExodusLex(char const *src);

/* free a result previously returned by ExodusLex. safe to call on NULL. */
EXODUS_API void ExodusLexFree(ExodusLexResult *res);

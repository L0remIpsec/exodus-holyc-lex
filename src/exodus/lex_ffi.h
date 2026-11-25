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
  i64 str_len;   /* payload bytes in str, excluding the trailing NUL the
                  * bridge always appends. HolyC string literals may hold
                  * embedded NULs (\0 and \xNN escapes), so read str with
                  * str_len instead of strlen when that matters. */
} ExodusToken;

typedef struct ExodusLexResult {
  ExodusToken *tokens; /* heap array of length count, last entry is TK_EOF */
  size_t count;
} ExodusLexResult;

/* lex src (a zero terminated HolyC source string) and return a heap
 * allocated result with one entry per token. the last entry always has
 * .token == TK_EOF (0). caller owns the result and must hand it to
 * ExodusLexFree.
 *
 * returns NULL when
 *   - the HolyC runtime isn't loaded, or its HCRT image predates the
 *     bridge patches (no T/Compiler/ExodusLex.HC in it),
 *   - Lex threw on the source (HolyC prints the reason itself), or
 *   - memory ran out.
 *
 * this is the real HolyC Lex, preprocessor included: #define applies
 * for the rest of the source (and only there, each call gets a scratch
 * symbol table), #include reads files and #exe{} runs HolyC. don't
 * feed it source you wouldn't be willing to compile.
 *
 * only call this from HolyC context (a task Exodus made), foreign
 * threads go through ExodusLexRemote instead. */
EXODUS_API ExodusLexResult *ExodusLex(char const *src);

/* free a result previously returned by ExodusLex or ExodusLexRemote.
 * safe to call on NULL. plain C frees, callable from any thread. */
EXODUS_API void ExodusLexFree(ExodusLexResult *res);

/* boot a full Exodus runtime inside the calling process so that
 * ExodusLexRemote works without an outer Exodus. runs the normal boot
 * path in command line mode on its own thread, with t_root mounted as
 * T:/ and hcrt_bin as the HolyC runtime image, then waits for the
 * HolyC server loop (T/Demo/ExodusLexServer.HC) to come up. paths
 * resolve against the host's working directory; NULL picks the usual
 * "T" and "HCRT.BIN". one boot per process and there is no shutdown,
 * the runtime lives until the process exits (and HolyC Exit/Shutdown
 * ends the whole process).
 *
 * returns 0 once the server is up, nonzero if it isn't: straight away
 * when t_root or hcrt_bin can't be found, after 30s if the runtime
 * started but the server never reported in. a failed boot can't be
 * retried with other paths. safe to call from several threads, later
 * callers wait for the first and get the same answer. */
EXODUS_API int ExodusLexBoot(char const *t_root, char const *hcrt_bin);

/* ExodusLex from any host thread: hands src to the runtime's server
 * task and blocks until the tokens come back. same result and same
 * NULL cases as ExodusLex, plus NULL until ExodusLexBoot has
 * succeeded, and lex errors are silent here (the server task doesn't
 * print). thread safe, requests serialize through the one server
 * task. src only has to stay valid for the duration of the call. */
EXODUS_API ExodusLexResult *ExodusLexRemote(char const *src);

/* answers one pending ExodusLexRemote request, never blocks. returns 1
 * if it served something, 0 when idle. registered with HolyC and driven
 * by the server loop in T/Demo/ExodusLexServer.HC. */
i64 ExodusLexPoll(void);

// vi: set et ft=c ts=2 sts=2 sw=2 fenc=utf-8 :vi
//
// host side smoke test for the standalone lexer bridge. links only
// against libexodus_lex like any foreign consumer would, boots the
// runtime and lexes from this (non HolyC) thread via ExodusLexRemote.
// run from the Exodus source root so T/ and HCRT.BIN resolve.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <exodus/lex_ffi.h>

#define TK_IDENT 0x100
#define TK_STR   0x101
#define TK_I64   0x102

int main(int argc, char **argv) {
  char const *root = argc > 1 ? argv[1] : "T";
  char const *bin = argc > 2 ? argv[2] : "HCRT.BIN";
  if (ExodusLexBoot(root, bin)) {
    fprintf(stderr, "ExodusLexBoot failed\n");
    return 1;
  }
  ExodusLexResult *res = ExodusLexRemote("I64 x=42; \"a\\0b\";");
  if (!res) {
    fprintf(stderr, "ExodusLexRemote returned NULL\n");
    return 1;
  }
  int ok = 0;
  for (size_t i = 0; i < res->count; i++) {
    ExodusToken *t = &res->tokens[i];
    if (t->token == TK_I64 && t->i64_val == 42)
      ok |= 1;
    if (t->token == TK_STR && t->str_len == 3 && !memcmp(t->str, "a\0b", 4))
      ok |= 2;
    if (t->token == TK_IDENT && t->str_len == 3 && !memcmp(t->str, "I64", 4))
      ok |= 4;
  }
  printf("count=%zu ok=%d\n", res->count, ok);
  ExodusLexFree(res);
  if (ok == 7)
    puts("EXODUS_LEX_HOST_OK");
  fflush(stdout);
  /* the runtime has no shutdown, so leave without running atexit
   * handlers or waiting on its threads */
  _Exit(ok == 7 ? 0 : 1);
}

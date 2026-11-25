// vi: set et ft=c ts=2 sts=2 sw=2 fenc=utf-8 :vi
//
// host side test for the standalone lexer bridge. links only against
// libexodus_lex like any foreign consumer would, boots the runtime and
// lexes from these (non HolyC) threads via ExodusLexRemote.
// run from the Exodus source root so T/ and HCRT.BIN resolve.
//
//   exodus_lex_host [t_root] [hcrt_bin]    everything
//   exodus_lex_host --bad-boot             only the failed boot check. a
//                                          process gets one boot, so the
//                                          full run spawns itself for this
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
# include <windows.h>
typedef HANDLE thread_t;
# define THREAD_FN(name, arg) static DWORD WINAPI name(LPVOID arg)
# define THREAD_RET 0
static int thread_start(thread_t *t, LPTHREAD_START_ROUTINE fn, void *arg) {
  return (*t = CreateThread(NULL, 0, fn, arg, 0, NULL)) ? 0 : -1;
}
static void thread_join(thread_t t) {
  WaitForSingleObject(t, INFINITE);
  CloseHandle(t);
}
#else
# include <pthread.h>
typedef pthread_t thread_t;
# define THREAD_FN(name, arg) static void *name(void *arg)
# define THREAD_RET NULL
static int thread_start(thread_t *t, void *(*fn)(void *), void *arg) {
  return pthread_create(t, NULL, fn, arg);
}
static void thread_join(thread_t t) {
  pthread_join(t, NULL);
}
#endif

#include <exodus/lex_ffi.h>

#define TK_IDENT 0x100
#define TK_STR   0x101
#define TK_I64   0x102

static int failures;

#define CHECK(cond)                                              \
  do {                                                           \
    if (!(cond)) {                                               \
      fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #cond);    \
      failures++;                                                \
    }                                                            \
  } while (0)

/* the basic round trip: payloads, exact lengths, embedded NUL */
static void test_round_trip(void) {
  ExodusLexResult *res = ExodusLexRemote("I64 x=42; \"a\\0b\";");
  CHECK(res);
  if (!res)
    return;
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
  CHECK(ok == 7);
  CHECK(res->count == 8);
  CHECK(res->tokens[res->count - 1].token == 0);
  ExodusLexFree(res);
}

/* degenerate inputs still come back as a lone TK_EOF */
static void test_empty(void) {
  char const *srcs[] = {NULL, "", "  \n\t", "// nothing here"};
  for (size_t i = 0; i < sizeof srcs / sizeof *srcs; i++) {
    ExodusLexResult *res = ExodusLexRemote(srcs[i]);
    CHECK(res && res->count == 1 && res->tokens[0].token == 0);
    ExodusLexFree(res);
  }
  ExodusLexFree(NULL);
}

/* line numbers follow the source, and the array grows past its first
 * 64 slots without losing anything */
static void test_lines_and_growth(void) {
  enum { N = 500 };
  char *src = malloc(N * 8 + 1), *p = src;
  for (int i = 0; i < N; i++)
    p += sprintf(p, "v%d\n", i);
  ExodusLexResult *res = ExodusLexRemote(src);
  free(src);
  CHECK(res && res->count == N + 1);
  if (res && res->count == N + 1) {
    char want[16];
    for (int i = 0; i < N; i++) {
      ExodusToken *t = &res->tokens[i];
      sprintf(want, "v%d", i);
      if (t->token != TK_IDENT || t->line != i + 1 || strcmp(t->str, want)) {
        CHECK(!"token stream out of step");
        break;
      }
    }
  }
  ExodusLexFree(res);
}

/* a source Lex throws on comes back NULL, and the server task has to
 * survive it: before ExodusLexTry the throw unwound out of the poll,
 * killed the task and left the next caller waiting forever */
static void test_lex_errors(void) {
  char const *bad[] = {
      "'abcdefghijk'",          /* char const longer than 8 */
      "I64 a; 'abcdefghijk' b", /* tokens first, then the throw */
      "#exe{throw('Boom');}",   /* a throw that isn't 'Compiler' */
  };
  for (int round = 0; round < 50; round++)
    for (size_t i = 0; i < sizeof bad / sizeof *bad; i++) {
      ExodusLexResult *res = ExodusLexRemote(bad[i]);
      CHECK(!res);
      ExodusLexFree(res);
    }
  test_round_trip();
}

/* several host threads at once, requests serialize through the one
 * server task and every caller must get its own answer back */
enum { THREADS = 8, PER_THREAD = 300 };

THREAD_FN(hammer, arg) {
  long id = (long)(size_t)arg;
  char src[64];
  for (int i = 0; i < PER_THREAD; i++) {
    long want = id * 100000 + i;
    snprintf(src, sizeof src, "t%ld=%ld;", id, want);
    ExodusLexResult *res = ExodusLexRemote(src);
    if (!res || res->count != 5 || res->tokens[2].token != TK_I64 ||
        res->tokens[2].i64_val != want) {
      CHECK(!"cross talk between threads");
      ExodusLexFree(res);
      break;
    }
    ExodusLexFree(res);
  }
  return THREAD_RET;
}

static void test_threads(void) {
  thread_t th[THREADS];
  int started = 0;
  for (long i = 0; i < THREADS; i++, started++)
    if (thread_start(&th[i], hammer, (void *)(size_t)i))
      break;
  CHECK(started == THREADS);
  for (int i = 0; i < started; i++)
    thread_join(th[i]);
}

/* Exodus refuses a missing root, and the boot has to report that
 * promptly (ctest's timeout catches it sitting out the 30s wait) and
 * stay failed afterwards */
static int bad_boot(void) {
  CHECK(!ExodusLexRemote("I64 x;"));
  CHECK(ExodusLexBoot("no-such-exodus-root", NULL) != 0);
  CHECK(ExodusLexBoot("T", NULL) != 0);
  CHECK(!ExodusLexRemote("I64 x;"));
  if (!failures)
    puts("EXODUS_LEX_BAD_BOOT_OK");
  fflush(stdout);
  return failures ? 1 : 0;
}

int main(int argc, char **argv) {
  if (argc > 1 && !strcmp(argv[1], "--bad-boot"))
    _Exit(bad_boot());

  char cmd[4096];
  snprintf(cmd, sizeof cmd, "\"%s\" --bad-boot", argv[0]);
  fflush(stdout);
  CHECK(system(cmd) == 0);

  char const *root = argc > 1 ? argv[1] : "T";
  char const *bin = argc > 2 ? argv[2] : "HCRT.BIN";
  CHECK(!ExodusLexRemote("I64 x;")); /* not up yet */
  if (ExodusLexBoot(root, bin)) {
    fprintf(stderr, "ExodusLexBoot failed\n");
    return 1;
  }
  CHECK(ExodusLexBoot(root, bin) == 0); /* asking again is harmless */

  test_round_trip();
  test_empty();
  test_lines_and_growth();
  test_lex_errors();
  test_threads();

  printf("failures=%d\n", failures);
  if (!failures)
    puts("EXODUS_LEX_HOST_OK");
  fflush(stdout);
  /* the runtime has no shutdown, so leave without running atexit
   * handlers or waiting on its threads */
  _Exit(failures ? 1 : 0);
}

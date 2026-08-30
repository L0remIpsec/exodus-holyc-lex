// vi: set et ft=c ts=2 sts=2 sw=2 fenc=utf-8 :vi
//
// drives the HolyC lexer from C. see lex_ffi.h.
#include <stdlib.h>
#include <string.h>

#include <SDL.h>

#include <exodus/abi.h>
#include <exodus/ffi.h>
#include <exodus/lex_ffi.h>
#include <exodus/loader.h>
#include <exodus/shims.h>
#include <exodus/types.h>

/* token ids copied from KernelA.HH so we don't have to drag HolyC headers in */
#define TK_EOF        0x000
#define TK_IDENT      0x100
#define TK_STR        0x101
#define TK_I64        0x102
#define TK_CHAR_CONST 0x103
#define TK_F64        0x104

/* partial mirror of HolyC's class CCmpCtrl (T/KernelA.HH). we only ever
 * touch the prefix up through last_line_num and treat the rest as opaque,
 * but the layout has to line up with the HolyC declaration exactly. */
typedef struct HCCmpCtrlHead {
  void *next, *last;   /* CCmpCtrl *next, *last */
  i64 token;
  i64 flags;
  i64 cur_i64;
  f64 cur_f64;
  u8 *cur_str;
  i64 cur_str_len;
  i64 class_dol_offset;
  u8 *dollar_buf;
  i64 dollar_cnt;
  u8 *cur_help_idx;
  i64 last_U16;
  i64 min_line;
  i64 max_line;
  i64 last_line_num;
} HCCmpCtrlHead;

static void *resolve_sym(char const *name) {
  CSymbol *s = map_get(&symtab, name);
  return s ? (void *)s->val : NULL;
}

ExodusLexResult *ExodusLex(char const *src) {
  if (!src)
    src = "";
  void *fp_new = resolve_sym("CmpCtrlNew");
  void *fp_lex = resolve_sym("Lex");
  void *fp_del = resolve_sym("CmpCtrlDel");
  if (!fp_new || !fp_lex || !fp_del)
    return NULL; /* HCRT isn't loaded */

  /* the buffer has to live on HolyC's heap because CmpCtrlDel and
   * LexFilePop will Free it for us unless CCF_DONT_FREE_BUF is set. */
  size_t len = strlen(src) + 1;
  u8 *hbuf = HolyMAlloc(len);
  if (!hbuf)
    return NULL;
  memcpy(hbuf, src, len);

  /* CCmpCtrl *CmpCtrlNew(U8 *buf=NULL, I64 flags=0, U8 *filename=NULL) */
  HCCmpCtrlHead *cc =
      (HCCmpCtrlHead *)fficall(fp_new, hbuf, (i64)0, (void *)0);
  if (!cc) {
    HolyFree(hbuf);
    return NULL;
  }

  ExodusLexResult *res = calloc(1, sizeof *res);
  if (!res) {
    fficall(fp_del, cc);
    return NULL;
  }
  size_t cap = 64;
  res->tokens = calloc(cap, sizeof *res->tokens);
  res->count = 0;
  if (!res->tokens) {
    fficall(fp_del, cc);
    free(res);
    return NULL;
  }

  for (;;) {
    i64 tk = fficall(fp_lex, cc);
    if (res->count == cap) {
      ExodusToken *grown = realloc(res->tokens, 2 * cap * sizeof *res->tokens);
      if (!grown)
        goto oom;
      res->tokens = grown;
      memset(res->tokens + cap, 0, cap * sizeof *res->tokens);
      cap *= 2;
    }
    ExodusToken *out = &res->tokens[res->count++];
    out->token = tk;
    out->line = cc->last_line_num;
    switch (tk) {
    case TK_I64:
    case TK_CHAR_CONST:
      out->i64_val = cc->cur_i64;
      break;
    case TK_F64:
      out->f64_val = cc->cur_f64;
      break;
    case TK_IDENT:
    case TK_STR:
      if (cc->cur_str) {
        /* cur_str_len counts the trailing NUL for both TK_IDENT and
         * TK_STR (LEX.HC does buf[i++]=0 before setting it). normalize
         * to payload bytes; the payload itself may hold embedded NULs
         * (\0 and \xNN escapes), so copy by length and append our own
         * terminator. */
        i64 plen = cc->cur_str_len;
        if (plen > 0)
          plen--;
        out->str = malloc((size_t)plen + 1);
        if (!out->str)
          goto oom;
        memcpy(out->str, cc->cur_str, (size_t)plen);
        out->str[plen] = 0;
        out->str_len = plen;
      }
      break;
    default:
      break;
    }
    if (tk == TK_EOF)
      break;
  }

  fficall(fp_del, cc);
  return res;

oom:
  fficall(fp_del, cc);
  ExodusLexFree(res);
  return NULL;
}

void ExodusLexFree(ExodusLexResult *res) {
  if (!res)
    return;
  for (size_t i = 0; i < res->count; i++)
    free(res->tokens[i].str);
  free(res->tokens);
  free(res);
}

/* ------------------------------------------------------------------ */
/* standalone boot + remote requests                                   */
/*                                                                     */
/* HolyC only runs on threads Exodus made (their GS points at the      */
/* CTask/CCPU context), so a foreign host can't call Lex directly.     */
/* instead ExodusLexBoot runs the stock main() on its own thread with  */
/* a boot script whose task sits in a poll loop, and ExodusLexRemote   */
/* hands sources to that task through a one slot mailbox.              */

int main(int argc, char **argv); /* the stock entry point, same DSO */

static SDL_mutex *lex_slot_mu;   /* serializes remote callers */
static SDL_sem *lex_req_sem;     /* posted when a request is placed */
static SDL_sem *lex_done_sem;    /* posted when the request is served */
static SDL_sem *lex_ready_sem;   /* posted once by the first poll */
static char const *lex_req_src;
static ExodusLexResult *lex_req_res;
static int lex_boot_started, lex_live;

static int lex_boot_thread(void *arg) {
  /* SDL starts its threads with signals blocked and everything Exodus
   * spawns inherits that mask, which would leave the POSIX PIT thread
   * unable to take SIGALRM. jiffies would stop and HolyC Sleep would
   * never wake. no-op on Windows. */
  unblocksigs();
  char **argv = arg;
  int argc = 0;
  while (argv[argc])
    argc++;
  return main(argc, argv); /* EventLoop never returns */
}

int ExodusLexBoot(char const *t_root, char const *hcrt_bin) {
  if (lex_boot_started)
    return lex_live ? 0 : -1;
  lex_boot_started = 1;
  if (!t_root)
    t_root = "T";
  if (!hcrt_bin)
    hcrt_bin = "HCRT.BIN";
  lex_slot_mu = SDL_CreateMutex();
  lex_req_sem = SDL_CreateSemaphore(0);
  lex_done_sem = SDL_CreateSemaphore(0);
  lex_ready_sem = SDL_CreateSemaphore(0);
  if (!lex_slot_mu || !lex_req_sem || !lex_done_sem || !lex_ready_sem)
    return -1;
  static char *boot_argv[8];
  boot_argv[0] = "exodus";
  boot_argv[1] = "-c";
  boot_argv[2] = "-t";
  boot_argv[3] = strdup(t_root);
  boot_argv[4] = "-f";
  boot_argv[5] = strdup(hcrt_bin);
  boot_argv[6] = "T:/Demo/ExodusLexServer.HC";
  boot_argv[7] = NULL;
  if (!boot_argv[3] || !boot_argv[5])
    return -1;
  SDL_Thread *th =
      SDL_CreateThread(lex_boot_thread, "exodus_lex_boot", boot_argv);
  if (!th)
    return -1;
  SDL_DetachThread(th);
  /* HCRT boots in well under a second; 30s leaves room for cold disks */
  if (SDL_SemWaitTimeout(lex_ready_sem, 30000) != 0)
    return -1;
  return 0;
}

ExodusLexResult *ExodusLexRemote(char const *src) {
  if (!lex_live)
    return NULL;
  SDL_LockMutex(lex_slot_mu);
  lex_req_src = src;
  SDL_SemPost(lex_req_sem);
  SDL_SemWait(lex_done_sem);
  ExodusLexResult *res = lex_req_res;
  lex_req_res = NULL;
  SDL_UnlockMutex(lex_slot_mu);
  return res;
}

i64 ExodusLexPoll(void) {
  if (!lex_live) {
    lex_live = 1;
    if (lex_ready_sem)
      SDL_SemPost(lex_ready_sem);
  }
  if (!lex_req_sem || SDL_SemTryWait(lex_req_sem) != 0)
    return 0;
  lex_req_res = ExodusLex(lex_req_src);
  SDL_SemPost(lex_done_sem);
  return 1;
}

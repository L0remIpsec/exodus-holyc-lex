// demo: drives the HolyC lexer through the Exodus C bridge.
//
// ExodusLex hands back a pointer to a heap allocated ExodusLexResult
// holding a flat array of ExodusToken records. we declare the matching
// HolyC classes here so HolyC can dereference the bridge's data the
// same way the C and Haskell consumers do.
//
// run inside Exodus with: #include "::/Demo/ExodusLexDemo";

class ExodusToken
{
  I64 token;     // raw HolyC token id
  I64 line;      // source line
  I64 i64_val;   // payload for TK_I64 and TK_CHAR_CONST
  F64 f64_val;   // payload for TK_F64
  U8 *str;       // payload for TK_IDENT and TK_STR, heap or NULL
  I64 str_len;   // payload bytes in str, embedded NULs included
};

class ExodusLexResult
{
  ExodusToken *tokens;
  U64 count;
};

U0 ExodusLexDemo(U8 *src=NULL)
{
  if (!src)
    src="I64 x=42; F64 f=3.14; \"hello\";";
  ExodusLexResult *res=ExodusLex(src);
  if (!res) {
    "ExodusLex returned NULL (HCRT not loaded?)\n";
    return;
  }
  "Source : %s\n",src;
  "Tokens : %d\n",res->count;
  I64 i;
  for (i=0;i<res->count;i++) {
    ExodusToken *t=&res->tokens[i];
    "  [%03d] line=%d tok=0x%03X ",i,t->line,t->token;
    switch (t->token) {
      case TK_EOF:        "EOF";                  break;
      case TK_IDENT:      "IDENT(%d):%s",t->str_len,t->str; break;
      case TK_STR:        "STR(%d):%s",t->str_len,t->str; break;
      case TK_I64:        "I64:%d",t->i64_val;    break;
      case TK_CHAR_CONST: "CHAR:%d",t->i64_val;   break;
      case TK_F64:        "F64:%5.5f",t->f64_val; break;
      default:            "OTHER";                break;
    }
    '\n';
  }
  ExodusLexFree(res);
}

ExodusLexDemo;
// embedded NUL round trip: the lexed source is `"a\0b";` so the TK_STR
// payload is 3 bytes with a NUL in the middle. %s stops at the NUL but
// str_len still reports all of it.
ExodusLexDemo("\"a\\0b\";");
// Lex expands defines, so pi never reaches you as an identifier, it
// arrives as the (0x400921FB54442D18(F64)) it is declared to be.
ExodusLexDemo("F64 d=pi;");

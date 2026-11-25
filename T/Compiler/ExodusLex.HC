// HolyC half of the ExodusLex C bridge (src/exodus/lex_ffi.c). the C
// side resolves these three by name and never calls Lex or CmpCtrlNew
// directly, because two things can only be done from in here:
//
// * catch. a HolyC throw unwinds straight past C frames, so a lex
//   error inside a bare Lex call would leak everything lex_ffi.c had
//   allocated and take the calling task down with it.
// * reach cc->htc. #define adds to cc->htc.define_hash_table, which
//   CmpCtrlNew points at the task's own table. left like that, one
//   lexed source could redefine identifiers for every later one.

CCmpCtrl *ExodusLexNew(U8 *buf,CHashTable **_scratch)
{//$LK,"CmpCtrlNew",A="MN:CmpCtrlNew"$() with a scratch hash table in front of the task's.
//Takes ownership of buf, pair with ExodusLexDel.
  CCmpCtrl *cc=CmpCtrlNew(buf);
  CHashTable *scratch=HashTableNew(16);
  scratch->next=Fs->hash_table;
  cc->htc.define_hash_table=cc->htc.hash_table_lst=
	cc->htc.glbl_hash_table=cc->htc.local_hash_table=scratch;
  *_scratch=scratch;
  return cc;
}

I64 ExodusLexTry(CCmpCtrl *cc)
{//$LK,"Lex",A="MN:Lex"$() that returns -1 instead of throwing.
  I64 tk;
  try
    tk=Lex(cc);
  catch {
    Fs->catch_except=TRUE;
    tk=-1;
  }
  return tk;
}

U0 ExodusLexDel(CCmpCtrl *cc,CHashTable *scratch)
{//Free a CCmpCtrl from ExodusLexNew and the defines it collected.
//scratch comes back from the caller on purpose. a throw out of an
//#exe{} blk leaves cc->htc pointing at the task's own table (see
//$LK,"PrsStreamBlk",A="MN:PrsStreamBlk"$()), freeing that would be the end of the task.
  CmpCtrlDel(cc);
  HashTableDel(scratch);
}

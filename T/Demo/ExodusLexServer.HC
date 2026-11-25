// server loop for the standalone lexer bridge. ExodusLexBoot passes
// this file on the boot command line; the task it lands in never
// returns, it just keeps answering ExodusLexRemote requests through
// ExodusLexPoll. the poll itself never blocks, all the waiting happens
// in Sleep where the scheduler expects it.

U0 ExodusLexServer()
{
  "ExodusLexServer: up\n";
  // the host owns stdout from here on. a source Lex rejects comes back
  // to it as NULL, the ERROR line HolyC would print for it only ever
  // landed in the middle of the host's own output (and command line
  // mode leaks a little on every char printed that way).
  Silent;
  while (TRUE)
    if (!ExodusLexPoll)
      Sleep(1);
}

ExodusLexServer;

// server loop for the standalone lexer bridge. ExodusLexBoot passes
// this file on the boot command line; the task it lands in never
// returns, it just keeps answering ExodusLexRemote requests through
// ExodusLexPoll. the poll itself never blocks, all the waiting happens
// in Sleep where the scheduler expects it.

U0 ExodusLexServer()
{
  "ExodusLexServer: up\n";
  while (TRUE)
    if (!ExodusLexPoll)
      Sleep(1);
}

ExodusLexServer;

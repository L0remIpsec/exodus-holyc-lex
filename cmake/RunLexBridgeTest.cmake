# runs the ExodusLex demo through the live exodus runtime and checks
# that the round trip produced the tokens we expect.
#
# required -D vars:
#   EXODUS  path to the exodus executable
#   SRCDIR  source tree root, the place HCRT.BIN lives

if (NOT EXODUS OR NOT SRCDIR)
  message(FATAL_ERROR "RunLexBridgeTest.cmake: EXODUS and SRCDIR must be set")
endif ()

if (NOT EXISTS "${SRCDIR}/HCRT.BIN")
  message(FATAL_ERROR "HCRT.BIN missing at ${SRCDIR}, build the HCRT target first")
endif ()

execute_process(
  COMMAND "${EXODUS}" -c -f HCRT.BIN T:/Demo/ExodusLexDemo.HC
  WORKING_DIRECTORY "${SRCDIR}"
  RESULT_VARIABLE rc
  OUTPUT_VARIABLE out
  ERROR_VARIABLE  err
  TIMEOUT 30)

set(combined "${out}${err}")
message(STATUS "exodus output:\n${combined}")

if (NOT rc EQUAL 0)
  message(FATAL_ERROR "exodus exited with ${rc}")
endif ()

# markers produced by T/Demo/ExodusLexDemo.HC, one run per line below.
#   'I64 x=42; F64 f=3.14; "hello";'   the plain payloads
#   '"a\0b";'                          embedded NULs keep an exact str_len
#   'F64 d=pi;'                        pi is a KernelA.HH define, Lex
#                                      expands it to a bit pattern cast
#   '#define EXODUS_LEX_DEMO_N 7 ...'  a define applies within its source
#   'EXODUS_LEX_DEMO_N;'               and is gone again for the next one
#   ''abcdefghijk''                    Lex throws, the bridge returns NULL
# the last marker proves the demo ran to its end, i.e. the throw was
# caught on the HolyC side and didn't unwind out of the include.
# if any of these go missing, either the C bridge, the FFI registration
# or the HolyC half in T/Compiler/ExodusLex.HC regressed.
foreach (needle
    "Tokens : 13"
    "IDENT(3):I64"
    "IDENT(1):x"
    "I64:42"
    "F64:3.14000"
    "STR(5):hello"
    "Tokens : 3"
    "STR(3):a"
    "I64:4614256656552045848"
    "I64:7"
    "IDENT(17):EXODUS_LEX_DEMO_N"
    "ExodusLex returned NULL"
    "ExodusLexDemo: done"
    "tok=0x000")
  string(FIND "${combined}" "${needle}" pos)
  if (pos LESS 0)
    message(FATAL_ERROR "lex bridge output missing marker: '${needle}'")
  endif ()
endforeach ()

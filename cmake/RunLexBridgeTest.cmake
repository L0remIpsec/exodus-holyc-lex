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

# markers produced by T/Demo/ExodusLexDemo.HC. the first run lexes
# 'I64 x=42; F64 pi=3.14; "hello";', the second lexes '"a\0b";' to prove
# embedded NULs survive with an exact str_len. if any of these go
# missing, either the C bridge, the FFI registration or the HolyC
# declarations regressed.
foreach (needle
    "Tokens : 18"
    "IDENT:I64"
    "IDENT:x"
    "I64:42"
    "STR(5):hello"
    "Tokens : 3"
    "STR(3):a"
    "tok=0x000")
  string(FIND "${combined}" "${needle}" pos)
  if (pos LESS 0)
    message(FATAL_ERROR "lex bridge output missing marker: '${needle}'")
  endif ()
endforeach ()

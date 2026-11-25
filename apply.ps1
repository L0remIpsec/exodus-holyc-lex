# PowerShell sibling of apply.sh. safe to run again after pulling a
# newer overlay: files are overwritten, patches that are already in are
# skipped, and nothing is touched if a patch would not apply.
# usage:
#   .\apply.ps1 -ExodusPath C:\path\to\EXODUS
param(
  [Parameter(Mandatory=$true)][string]$ExodusPath
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not (Test-Path "$ExodusPath\CMakeLists.txt") -or
    -not (Test-Path "$ExodusPath\src\exodus") -or
    -not (Test-Path "$ExodusPath\T\Compiler\CMP_PRJ.HC")) {
  throw "$ExodusPath does not look like an Exodus checkout"
}

# git reports through its exit code, which PowerShell ignores unless
# asked. stderr is folded into stdout so a failing check can't trip
# ErrorActionPreference on the way.
function Test-GitApply([string[]]$GitArgs) {
  $ErrorActionPreference = 'Continue'
  & git apply @GitArgs 2>&1 | Out-Null
  return $LASTEXITCODE -eq 0
}

Push-Location $ExodusPath
try {
  # sort the patches into "already applied" and "to apply" before
  # changing anything, so a patch that fits neither stops us with the
  # tree exactly as it was
  $todo = @()
  foreach ($p in (Get-ChildItem "$here\patches\*.patch" | Sort-Object Name)) {
    if (Test-GitApply @('--reverse', '--check', $p.FullName)) {
      Write-Host "already applied: $($p.Name)"
    } elseif (Test-GitApply @('--check', $p.FullName)) {
      $todo += $p
    } else {
      throw "$($p.Name) does not apply to $ExodusPath. upstream has probably moved, or the file was edited by hand. nothing was changed. run 'git apply --check $($p.FullName)' there for details."
    }
  }

  Write-Host "copying new files into $ExodusPath"
  New-Item -ItemType Directory -Force -Path "$ExodusPath\T\Demo","$ExodusPath\cmake","$ExodusPath\haskell\Exodus","$ExodusPath\haskell\demo" | Out-Null
  Copy-Item "$here\src\exodus\lex_ffi.h"         "$ExodusPath\src\exodus\"
  Copy-Item "$here\src\exodus\lex_ffi.c"         "$ExodusPath\src\exodus\"
  Copy-Item "$here\src\exodus\lex_host_test.c"   "$ExodusPath\src\exodus\"
  Copy-Item "$here\T\Compiler\ExodusLex.HC"      "$ExodusPath\T\Compiler\"
  Copy-Item "$here\T\Demo\ExodusLexDemo.HC"      "$ExodusPath\T\Demo\"
  Copy-Item "$here\T\Demo\ExodusLexServer.HC"    "$ExodusPath\T\Demo\"
  Copy-Item "$here\cmake\RunLexBridgeTest.cmake" "$ExodusPath\cmake\"
  Copy-Item "$here\haskell\Exodus\Lex.hs"        "$ExodusPath\haskell\Exodus\"
  Copy-Item "$here\haskell\demo\Main.hs"         "$ExodusPath\haskell\demo\"
  Copy-Item "$here\haskell\exodus-lex.cabal"     "$ExodusPath\haskell\"

  foreach ($p in $todo) {
    Write-Host "applying $($p.Name)"
    & git apply $p.FullName
    if ($LASTEXITCODE -ne 0) { throw "git apply failed on $($p.Name)" }
  }
} finally { Pop-Location }

Write-Host "done. now run:"
Write-Host "  cmake -S `"$ExodusPath`" -B `"$ExodusPath\build`" -DBUILD_EXODUS_LEX_SHARED=ON"
Write-Host "  cmake --build `"$ExodusPath\build`""
Write-Host "  ctest --test-dir `"$ExodusPath\build`" -L bridge"

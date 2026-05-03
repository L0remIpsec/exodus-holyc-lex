# PowerShell sibling of apply.sh
# usage:
#   .\apply.ps1 -ExodusPath C:\path\to\EXODUS
param(
  [Parameter(Mandatory=$true)][string]$ExodusPath
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not (Test-Path "$ExodusPath\CMakeLists.txt") -or -not (Test-Path "$ExodusPath\src\exodus")) {
  throw "$ExodusPath does not look like an Exodus checkout"
}

Write-Host "copying new files into $ExodusPath"
New-Item -ItemType Directory -Force -Path "$ExodusPath\T\Demo","$ExodusPath\cmake","$ExodusPath\haskell\Exodus" | Out-Null
Copy-Item "$here\src\exodus\lex_ffi.h"       "$ExodusPath\src\exodus\"
Copy-Item "$here\src\exodus\lex_ffi.c"       "$ExodusPath\src\exodus\"
Copy-Item "$here\T\Demo\ExodusLexDemo.HC"    "$ExodusPath\T\Demo\"
Copy-Item "$here\cmake\RunLexBridgeTest.cmake" "$ExodusPath\cmake\"
Copy-Item "$here\haskell\Exodus\Lex.hs"      "$ExodusPath\haskell\Exodus\"
Copy-Item "$here\haskell\exodus-lex.cabal"   "$ExodusPath\haskell\"

Write-Host "applying patches"
Push-Location $ExodusPath
try {
  Get-ChildItem "$here\patches\*.patch" | Sort-Object Name | ForEach-Object {
    git apply $_.FullName
  }
} finally { Pop-Location }

Write-Host "done. now run:"
Write-Host "  cmake -S `"$ExodusPath`" -B `"$ExodusPath\build`" -DBUILD_EXODUS_LEX_SHARED=ON"
Write-Host "  cmake --build `"$ExodusPath\build`""

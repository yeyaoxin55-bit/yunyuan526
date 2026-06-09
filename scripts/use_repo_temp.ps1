$ErrorActionPreference = "Stop"

function Set-RepoTemp {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,
    [string]$RelativeTempDir = "build\tmp"
  )

  $resolvedRepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
  $tempDir = Join-Path $resolvedRepoRoot $RelativeTempDir
  New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
  $resolvedTempDir = (Resolve-Path -LiteralPath $tempDir).Path
  $env:TEMP = $resolvedTempDir
  $env:TMP = $resolvedTempDir
  return $resolvedTempDir
}

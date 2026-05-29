# setup-neovide-windows.ps1
$ErrorActionPreference = "Stop"

$BinDir = Join-Path $HOME "bin"
New-Item -ItemType Directory -Force -Path $BinDir | Out-Null

$Wrapper = Join-Path $BinDir "neovide-remote.ps1"
$CmdShim = Join-Path $BinDir "neovide-remote.cmd"

$WrapperContent = @'
param(
  [Parameter(Mandatory=$true, Position=0)]
  [string]$HostAlias,

  [Parameter(Mandatory=$true, Position=1)]
  [int]$Port,

  [switch]$Detached
)

$ErrorActionPreference = "Stop"

$Tag = ("{0}_{1}" -f $HostAlias, $Port) -replace '[^A-Za-z0-9_.-]', '_'
$MainOut = Join-Path $env:TEMP "neovide-remote-$Tag.out.log"
$MainErr = Join-Path $env:TEMP "neovide-remote-$Tag.err.log"

if (-not $Detached) {
  $Pwsh = (Get-Process -Id $PID).Path
  $ArgString = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" `"$HostAlias`" $Port -Detached"

  Start-Process `
    -FilePath $Pwsh `
    -WindowStyle Hidden `
    -RedirectStandardOutput $MainOut `
    -RedirectStandardError $MainErr `
    -ArgumentList $ArgString

  exit 0
}

$NeovideCmd = Get-Command neovide -ErrorAction SilentlyContinue
if ($null -eq $NeovideCmd) {
  throw "neovide was not found on PATH"
}

$Neovide = $NeovideCmd.Source
$Tunnel = $null

try {
  $Tunnel = Start-Process `
    -FilePath "ssh" `
    -WindowStyle Hidden `
    -PassThru `
    -ArgumentList @(
      "-nN",
      "-o", "ExitOnForwardFailure=yes",
      "-L", "127.0.0.1:${Port}:127.0.0.1:${Port}",
      $HostAlias
    )

  $RemoteLines = @(
    'set -eu',
    '(set -o pipefail) 2>/dev/null || true',
    "PORT='$Port'",
    'export NVM_DIR="$HOME/.nvm"',
    'if [ -s "$NVM_DIR/nvm.sh" ]; then',
    '  . "$NVM_DIR/nvm.sh"',
    '  nvm use --silent default >/dev/null',
    'fi',
    'export PATH="$HOME/neovim/bin:$HOME/.cargo/bin:$HOME/.local/bin:$PATH"',
    'if command -v fuser >/dev/null 2>&1; then',
    '  fuser -k "${PORT}/tcp" >/dev/null 2>&1 || true',
    'fi',
    'cd "$HOME"',
    'if [ -x "$HOME/neovim/bin/nvim" ]; then',
    '  REMOTE_NVIM="$HOME/neovim/bin/nvim"',
    'else',
    '  REMOTE_NVIM="$(command -v nvim 2>/dev/null || true)"',
    'fi',
    'if [ -z "${REMOTE_NVIM:-}" ]; then',
    '  echo "ERROR: could not find remote nvim" >&2',
    '  exit 1',
    'fi',
    'rm -f "/tmp/neovide-nvim-${PORT}.log"',
    'nohup "$REMOTE_NVIM" \',
    '  --headless \',
    '  --listen "127.0.0.1:${PORT}" \',
    '  --cmd ''let g:neovide_detach_on_quit = "always_quit"'' \',
    '  >"/tmp/neovide-nvim-${PORT}.log" 2>&1 &'
  )

  $RemoteScript = $RemoteLines -join "`n"

  $RemoteLauncher = 'if command -v bash >/dev/null 2>&1; then exec bash -s; elif command -v zsh >/dev/null 2>&1; then exec zsh -f -s; else exec sh -s; fi'

  $RemoteScript | ssh $HostAlias $RemoteLauncher

  $Ready = $false
  $ReadyCmd = "if command -v ss >/dev/null 2>&1; then ss -ltn | grep -q '127.0.0.1:$Port'; else netstat -an 2>/dev/null | grep -q '127.0.0.1.*$Port.*LISTEN'; fi"

  for ($i = 0; $i -lt 50; $i++) {
    & ssh $HostAlias $ReadyCmd *> $null

    if ($LASTEXITCODE -eq 0) {
      $Ready = $true
      break
    }

    Start-Sleep -Milliseconds 100
  }

  if (-not $Ready) {
    Write-Error "remote nvim did not start on 127.0.0.1:$Port"
    & ssh $HostAlias "cat /tmp/neovide-nvim-$Port.log 2>/dev/null || true"
    exit 1
  }

  $NvimAddr = "127.0.0.1:$Port"

  $NeovideProc = Start-Process `
    -FilePath $Neovide `
    -ArgumentList @("--server", $NvimAddr) `
    -PassThru

  Wait-Process -Id $NeovideProc.Id
}
finally {
  if ($Tunnel -and -not $Tunnel.HasExited) {
    Stop-Process -Id $Tunnel.Id -Force
  }

  & ssh $HostAlias "fuser -k ${Port}/tcp >/dev/null 2>&1 || true" *> $null
}
'@

Set-Content -Encoding UTF8 -Path $Wrapper -Value $WrapperContent

$CmdShimContent = @'
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\bin\neovide-remote.ps1" %*
'@

Set-Content -Encoding ASCII -Path $CmdShim -Value $CmdShimContent

$UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
$PathParts = @()

if ($UserPath) {
  $PathParts = $UserPath -split ';'
}

if ($PathParts -notcontains $BinDir) {
  $NewPath = if ($UserPath) { "$UserPath;$BinDir" } else { $BinDir }
  [Environment]::SetEnvironmentVariable("Path", $NewPath, "User")
}

Write-Host "Done."
Write-Host "Open a new PowerShell or Windows Terminal, then run:"
Write-Host "  neovide-remote emu 6666"
Write-Host ""
Write-Host "Logs:"
Write-Host "  $env:TEMP\neovide-remote-emu_6666.out.log"
Write-Host "  $env:TEMP\neovide-remote-emu_6666.err.log"

# lscd wrapper for PowerShell
#   Import-Module /path/to/lscd.ps1
#   or dot-source it in your $PROFILE:
#     . /path/to/lscd.ps1

$script:lscdCommand = "\PATH_TO\lscd.exe"

function l {
  param(
    [Parameter(Position = 0)]
    [string]$Directory = "."
  )

  $output = & $script:lscdCommand $Directory
  if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($output)) {
    if (Test-Path -LiteralPath $output -PathType Container) {
      Set-Location -LiteralPath $output
    }
    elseif (Test-Path -LiteralPath $output -PathType Leaf) {
      $ext = [System.IO.Path]::GetExtension($output).TrimStart('.').ToLower()
      if ($ext -in @('mkv', 'avi', 'mp4', 'm4a', 'mp3')) {
        Start-Process -FilePath "ffplay" -ArgumentList $output -WindowStyle Hidden
      }
      else {
        vim $output
      }
    }
  }
  Write-Host ""
}
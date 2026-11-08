$ErrorActionPreference = 'Stop'
try {
    $iso = Join-Path $PSScriptRoot 'Pharaoh.iso'
    $disc = Get-DiskImage -ImagePath $iso
    if (!$disc.Attached) {
        Mount-DiskImage -ImagePath $iso -StorageType ISO | Out-Null
    }
    Start-Process -FilePath (Join-Path $PSScriptRoot 'Pharaoh.exe') -WorkingDirectory $PSScriptRoot
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

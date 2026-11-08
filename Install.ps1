[CmdletBinding(DefaultParameterSetName='Install')]
param(
    [Parameter(ParameterSetName='Install')][string]$Image,
    [Parameter(ParameterSetName='Install')][string]$Destination = (Join-Path $env:LOCALAPPDATA 'Pharaoh-JP'),
    [Parameter(Mandatory,ParameterSetName='Patch')][switch]$PatchOnly,
    [Parameter(ParameterSetName='Patch')][string]$GameDirectory
)
$ErrorActionPreference = 'Stop'

function Select-GameFile([string]$Title, [string]$Filter) {
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object Windows.Forms.OpenFileDialog
    try {
        $dialog.Title = $Title
        $dialog.Filter = $Filter
        if ($dialog.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) { $dialog.FileName }
    } finally { $dialog.Dispose() }
}

function Update-Game([string]$Root, [bool]$Backup) {
    $exe = Join-Path $Root 'Pharaoh.exe'
    $original = '24027A3DEC4CD6E306A3A56CCC83223B6DD2EDED921A11357DDA586EFC00F135'
    $v1 = '216C9AC091118EF0E4C89AA0B8F2F5C6ECBAF3F92ED8DADF3A3E97A7AFE57C36'
    $v2 = '52C05C508BA75A8A13AB3EFF26664B488537940D96C117DC218D0F3BF705C4E0'
    $hash = (Get-FileHash -LiteralPath $exe).Hash
    if ($hash -eq $v2) {
        Write-Host 'v2 は適用済みです。'
        return
    }
    if ($hash -notin $original,$v1) {
        throw '対象はCD収録の「ファラオ 完全日本語版 1.0」です。この Pharaoh.exe の版は異なります。'
    }

    $bytes = [IO.File]::ReadAllBytes($exe)
    if ($hash -eq $original) {
        $font = [IO.File]::ReadAllBytes((Join-Path $PSScriptRoot 'metrics.bin'))
        [Array]::Copy([byte[]](0xbf,0x10,0xa4,0x53,0x00,0x90),0,$bytes,0xb9eb2,6)
        [Array]::Copy($font,0,$bytes,0x13a410,$font.Length)
    }
    $timing = [IO.File]::ReadAllBytes((Join-Path $PSScriptRoot 'timing.bin'))
    [Array]::Copy([BitConverter]::GetBytes(0x139470 + $timing.Length),0,$bytes,0x1f0,4)
    [Array]::Copy($timing,0,$bytes,0x13a470,$timing.Length)

    # Route simulation timing through the scheduler and preserve the original
    # fast-forward cancellation path when iterating the scheduled ticks.
    $pauseJump = [byte[]](0xe9) + [BitConverter]::GetBytes(0x53a4d0 - 0x4c9447)
    $tickJump = [byte[]](0xe9) + [BitConverter]::GetBytes(0x53a470 - 0x4c9479) + [byte[]](0x90,0x90,0x90)
    [Array]::Copy($pauseJump,0,$bytes,0xc9442,$pauseJump.Length)
    [Array]::Copy($tickJump,0,$bytes,0xc9474,$tickJump.Length)
    $bytes[0xc265e] = 0x91
    # The scroll flag still controls viewport redraws. It no longer pauses city time.
    $bytes[0xc9460] = 0x90
    $bytes[0xc9461] = 0x90
    # Route the obsolete website button to the menu's existing no-op handler.
    [Array]::Copy([BitConverter]::GetBytes(0x412f31),0,$bytes,0x12f38,4)

    $sha = [Security.Cryptography.SHA256]::Create()
    try { $result = [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','') }
    finally { $sha.Dispose() }
    if ($result -ne $v2) { throw 'パッチの検証に失敗しました。ZIPを展開し直してください。' }
    $files = 'ddraw.dll','ddraw.ini','cnc-license.txt'
    if ($Backup) {
        $backupPath = Join-Path $Root 'Win11Patch-v2-backup'
        if (Test-Path -LiteralPath $backupPath) {
            throw "既存のバックアップを検出しました。内容を確認してください。 $backupPath"
        }
        [void][IO.Directory]::CreateDirectory($backupPath)
        Copy-Item -LiteralPath $exe -Destination $backupPath
        foreach ($name in $files) {
            $old = Join-Path $Root $name
            if (Test-Path -LiteralPath $old) { Copy-Item -LiteralPath $old -Destination $backupPath }
        }
    }

    foreach ($name in $files) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $Root -Force
    }
    $tempExe = Join-Path $Root ('.pharaoh-patch-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllBytes($tempExe,$bytes)
        [IO.File]::Replace($tempExe,$exe,($tempExe + '.old'))
    } finally {
        if (Test-Path -LiteralPath $tempExe) { [IO.File]::Delete($tempExe) }
        [IO.File]::Delete($tempExe + '.old')
    }
}

try {
    if ($PatchOnly) {
        if (!$GameDirectory) {
            $exe = Select-GameFile 'インストール済みの Pharaoh.exe を選択' 'Pharaoh.exe|Pharaoh.exe'
            if (!$exe) { return }
            $GameDirectory = Split-Path -LiteralPath $exe
        }
        $root = (Get-Item -LiteralPath $GameDirectory).FullName
        if (Get-Process -Name Pharaoh -ErrorAction SilentlyContinue) {
            throw 'ファラオを終了してから実行してください。'
        }
        Update-Game $root $true
        Write-Host "パッチ適用先  $root"
        return
    }

    if (!$Image) {
        $Image = Select-GameFile 'ファラオのCDイメージを選択' 'CDイメージ (*.ccd;*.img;*.iso)|*.ccd;*.img;*.iso'
        if (!$Image) { return }
    }
    $imagePath = (Get-Item -LiteralPath $Image).FullName
    if ([IO.Path]::GetExtension($imagePath) -notin '.ccd','.img','.iso') {
        throw '対応するファイルは .ccd、.img、.iso です。'
    }
    $root = [IO.Path]::GetFullPath($Destination)
    if (Test-Path -LiteralPath $root) {
        throw "インストール先が存在します。既存のゲームには Patch-existing.cmd を使ってください。 $root"
    }
    $parent = [IO.Path]::GetDirectoryName($root)
    [void][IO.Directory]::CreateDirectory($parent)
    $stage = Join-Path $parent ('.Pharaoh-JP-' + [Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($stage)
    try {
        Write-Host 'CDイメージを変換し、ゲームファイルを検証・展開しています。'
        Add-Type -Path (Join-Path $PSScriptRoot 'PharaohMedia.cs')
        [PharaohMedia]::Install($imagePath,$stage)
        Update-Game $stage $false
        foreach ($name in 'Play.cmd','Play.ps1') {
            Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $stage
        }
        [IO.Directory]::Move($stage,$root)
    } finally {
        if ([IO.Directory]::Exists($stage) -and [IO.Path]::GetDirectoryName($stage) -eq $parent -and
            (Split-Path -Leaf $stage) -match '^\.Pharaoh-JP-[a-f0-9]{32}$') {
            [IO.Directory]::Delete($stage,$true)
        }
    }
    Write-Host "インストール先  $root"
    Write-Host "起動ファイル  $(Join-Path $root 'Play.cmd')"
    if (!$PSBoundParameters.ContainsKey('Image')) { Invoke-Item -LiteralPath $root }
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

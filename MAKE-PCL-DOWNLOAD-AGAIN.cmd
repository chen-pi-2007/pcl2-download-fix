@echo off
chcp 65001 >nul
set "PCL_TOOL_PATH=%~1"
set "PCL_TOOL_MODE=%~2"
set "PCL_TOOL_SELF=%~f0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText($env:PCL_TOOL_SELF,[Text.Encoding]::UTF8); & ([scriptblock]::Create(($s -split '(?m)^# POWERSHELL_START\r?$',2)[1]))"
set "PCL_TOOL_EXIT=%errorlevel%"
if not defined PCL_TOOL_MODE pause
exit /b %PCL_TOOL_EXIT%
# POWERSHELL_START
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
$ExpectedHash = '6b6e1260cb5a1d6a303855f1c60cab3d0bc1aebba7e40a964180188b271e7386'
$Offset = 180442
$OldBytes = [Convert]::FromBase64String('cjNHAXB++wkABCwHfvsJAAQrFn75CQAE/gZnFAAGc40FAAolgPsJAAQUGHOOBQAK')
$NewBytes = [Convert]::FromBase64String('fg8EAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA')
function Get-Hash([byte[]] $Bytes) {
    $Hasher = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($Hasher.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant() }
    finally { $Hasher.Dispose() }
}
function Get-State([byte[]] $Bytes) {
    if ((Get-Hash $Bytes) -eq $ExpectedHash) { return 'original' }
    if ($Bytes.Length -lt ($Offset + 48)) { throw '文件不受支持，未修改。' }
    for ($i = 0; $i -lt 48; $i++) { if ($Bytes[$Offset + $i] -ne $NewBytes[$i]) { throw '文件版本不匹配，未修改。仅支持已验证的正式版 2.99.0.0 (413)。' } }
    $Normalized = [byte[]] $Bytes.Clone()
    [Array]::Copy($OldBytes, 0, $Normalized, $Offset, 48)
    if ((Get-Hash $Normalized) -ne $ExpectedHash) { throw '文件已被其他方式修改，未作修改。' }
    return 'patched'
}
function Read-Program([string] $Path) {
    $Info = Get-Item -LiteralPath $Path
    if ($Info.PSIsContainer -or $Info.Length -gt 67108864) { throw '请选择小于 64 MB 的 PCL 程序文件。' }
    return ,([IO.File]::ReadAllBytes($Info.FullName))
}
function Find-Pcl([string[]] $Roots) {
    $Found = @{}
    $Visited = @{}
    $Queue = New-Object 'Collections.Generic.Queue[object]'
    foreach ($Root in $Roots) { if ($Root -and (Test-Path -LiteralPath $Root -PathType Container)) { $Queue.Enqueue(@($Root, 0)) } }
    $Count = 0
    $Timer = [Diagnostics.Stopwatch]::StartNew()
    while ($Queue.Count -gt 0 -and $Count -lt 15000 -and $Timer.Elapsed.TotalSeconds -lt 6) {
        $Node = $Queue.Dequeue(); $Dir = [string]$Node[0]; $Depth = [int]$Node[1]
        if ($Visited.ContainsKey($Dir)) { continue }; $Visited[$Dir] = $true
        foreach ($Item in @(Get-ChildItem -LiteralPath $Dir -Force -ErrorAction SilentlyContinue)) {
            $Count++
            if ($Count -gt 15000 -or $Timer.Elapsed.TotalSeconds -gt 6) { break }
            if ($Item.PSIsContainer) {
                if ($Depth -lt 3 -and -not ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -and $Item.Name -notin @('Windows','node_modules','.git','$RECYCLE.BIN','System Volume Information')) { $Queue.Enqueue(@($Item.FullName, $Depth + 1)) }
            } elseif ($Item.Extension -eq '.exe' -and $Item.Name -match '(?i)pcl|plain craft launcher') {
                $Found[$Item.FullName] = $Item.FullName
            }
        }
    }
    return @($Found.Values | Sort-Object)
}
function Write-Atomic([string] $Path, [byte[]] $Before, [byte[]] $After) {
    $Temporary = Join-Path ([IO.Path]::GetDirectoryName($Path)) ('.pcl-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        $Stream = New-Object IO.FileStream($Temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $Stream.Write($After,0,$After.Length); $Stream.Flush($true) } finally { $Stream.Dispose() }
        if ((Get-Hash ([IO.File]::ReadAllBytes($Path))) -ne (Get-Hash $Before)) { throw '操作期间文件发生变化，已停止。' }
        [IO.File]::Replace($Temporary, $Path, [System.Management.Automation.Language.NullString]::Value)
        if ((Get-Hash ([IO.File]::ReadAllBytes($Path))) -ne (Get-Hash $After)) { throw '写入校验失败，请使用备份恢复。' }
    } finally { if ([IO.File]::Exists($Temporary)) { [IO.File]::Delete($Temporary) } }
}
try {
    Write-Host @'
+----------------------------------------------------------------------------+
|                                                                            |
|                  |\/|  /\  | /  |===      |==\  /== |                      |
|                  |  | /  \ |/   |         |  | |    |                      |
|                  |  | |--| |<   |==       |==/ |    |                      |
|                  |  | |  | |\   |         |    |    |                      |
|                  |  | |  | | \  |===      |     \== |___                   |
|                                                                            |
| |==\  /\  |  | |\ | |     /\   /\  |==\       /\   /==  /\  ==== |\ |  ||  |
| |  | |  | |  | |\ | |    |  | /  \ |  |      /  \ |    /  \  ||  |\ |  ||  |
| |  | |  | |  | | \| |    |  | |--| |  |      |--| | == |--|  ||  | \|  ||  |
| |  | |  | |/\| | \| |    |  | |  | |  |      |  | |  | |  |  ||  | \|      |
| |==/  \/  V  V |  | |___  \/  |  | |==/      |  |  \_/ |  | ==== |  |  ..  |
|                                                                            |
|                          MAKE PCL DOWNLOAD AGAIN!                          |
|                                                                            |
+----------------------------------------------------------------------------+
'@ -ForegroundColor Cyan
    Write-Host 'PCL 下载页修复工具 | 免安装 Windows 版'
    $Target = $env:PCL_TOOL_PATH
    $Mode = [string]$env:PCL_TOOL_MODE
    if ($Mode -notin @('', '--check', '--restore', '--yes')) { throw '用法：修复PCL下载.cmd "PCL.exe完整路径" [--check|--restore|--yes]' }
    if (-not $Target -or (Test-Path -LiteralPath $Target -PathType Container)) {
        if ($Target) { $Roots = @($Target) } else {
            $Roots = @((Get-Location).Path, (Split-Path -LiteralPath $env:PCL_TOOL_SELF), ([Environment]::GetFolderPath('Desktop')), (Join-Path $env:USERPROFILE 'Downloads'), ([Environment]::GetFolderPath('MyDocuments')))
            $Roots += @(Get-PSDrive -PSProvider FileSystem | Select-Object -ExpandProperty Root)
        }
        Write-Host '正在快速查找 PCL（最多约 6 秒）……'
        $Candidates = @(Find-Pcl $Roots)
        if ($Candidates.Count -eq 1) { $Target = $Candidates[0] }
        elseif ($Candidates.Count -gt 1) {
            for ($i = 0; $i -lt $Candidates.Count; $i++) { Write-Host ('{0}. {1}' -f ($i + 1), $Candidates[$i]) }
            $Choice = Read-Host '找到多个文件，请输入编号（回车取消）'
            $Number = 0
            if (-not [int]::TryParse($Choice, [ref]$Number) -or $Number -lt 1 -or $Number -gt $Candidates.Count) { throw '已取消。' }
            $Target = $Candidates[$Number - 1]
        } else { $Target = (Read-Host '未自动找到，请粘贴 PCL.exe 完整路径').Trim().Trim('"') }
    }
    if (-not $Target) { throw '已取消。' }
    $Target = (Resolve-Path -LiteralPath $Target).ProviderPath
    Write-Host "目标：$Target"
    $Data = Read-Program $Target
    $State = Get-State $Data
    $Backup = $Target + '.pcl-download-backup'
    if ($Mode -eq '--check') { Write-Host "检查通过：$State，文件受支持。"; exit 0 }
    if ($Mode -eq '--restore') {
        if ($State -eq 'original') { Write-Host '已经是原版，无需恢复。'; exit 0 }
        $Output = Read-Program $Backup
        if ((Get-Hash $Output) -ne $ExpectedHash) { throw '备份校验失败，未恢复。' }
        if ((Read-Host '从备份恢复原版？[y/N]') -notmatch '^(?i)y(es)?$') { Write-Host '已取消。'; exit 0 }
        Write-Atomic $Target $Data $Output
        Write-Host '已恢复原版，备份保留。'
    } else {
        if ($State -eq 'patched') { Write-Host '已修复，无需重复操作。'; exit 0 }
        if ($Mode -ne '--yes' -and (Read-Host '请先关闭 PCL。备份并恢复下载页？[y/N]') -notmatch '^(?i)y(es)?$') { Write-Host '已取消。'; exit 0 }
        if ([IO.File]::Exists($Backup)) { if ((Get-Hash (Read-Program $Backup)) -ne $ExpectedHash) { throw '已有备份与原版不符，未修改。请先妥善保留该备份。' } }
        else {
            $Stream = New-Object IO.FileStream($Backup, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            try { $Stream.Write($Data,0,$Data.Length); $Stream.Flush($true) } finally { $Stream.Dispose() }
        }
        if ((Get-Hash (Read-Program $Backup)) -ne $ExpectedHash) { throw '备份校验失败，未修改。' }
        $Output = [byte[]] $Data.Clone()
        [Array]::Copy($NewBytes, 0, $Output, $Offset, 48)
        if ((Get-State $Output) -ne 'patched') { throw '补丁校验失败。' }
        Write-Atomic $Target $Data $Output
        Write-Host '玩的开心' -ForegroundColor Green
        Write-Host "原版备份：$Backup"
    }
    exit 0
} catch { Write-Host ('未完成：' + $_.Exception.Message) -ForegroundColor Red; exit 1 }

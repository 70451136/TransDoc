# Same-user, machine-bound recovery of configuration only; never database dumps.
function Get-RecoveryVault {
    return Join-Path $env:LOCALAPPDATA 'TransDoc/Recovery'
}

function Get-RecoveryKey {
    param([string]$Directory)
    $canonical = [IO.Path]::GetFullPath($Directory).TrimEnd('\', '/').ToLowerInvariant()
    $hasher = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($canonical))).Replace('-', '').ToLowerInvariant() }
    finally { $hasher.Dispose() }
}

function Get-RecoveryFileNames {
    return @('config/installation.json', 'config/bootstrap.json', 'config/compose.env', 'config/node.env', 'config/authority-public.pem', 'config/activation.token', 'config/enrollment.token', 'config/compose.env.previous', 'local-settings.json')
}

function Assert-RecoveryState {
    param([byte[]]$State)
    $value = [Text.Encoding]::UTF8.GetString($State) | ConvertFrom-Json
    $machine = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography').MachineGuid
    $hasher = [Security.Cryptography.SHA256]::Create()
    try { $hash = [BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($machine))).Replace('-', '').ToLowerInvariant() }
    finally { $hasher.Dispose() }
    if ($value.machine_hash -ne $hash -or $value.node_id -notmatch '^[a-f0-9]{64}$') { throw '恢复配置不属于当前机器，已停止恢复。' }
}

function Save-InstallationRecovery {
    param([string]$Directory)
    $path = [IO.Path]::GetFullPath($Directory).TrimEnd('\', '/')
    $files = @{}
    foreach ($name in (Get-RecoveryFileNames)) {
        $file = Join-Path $path $name
        if (Test-Path -LiteralPath $file -PathType Leaf) {
            $item = Get-Item -LiteralPath $file
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $item.Length -gt 1048576) { throw '恢复快照发现异常配置文件，未更新恢复记录。' }
            $files[$name] = [Convert]::ToBase64String([IO.File]::ReadAllBytes($file))
        }
    }
    foreach ($name in @('config/installation.json', 'config/compose.env', 'config/node.env')) {
        if (-not $files.ContainsKey($name)) { throw '配置尚未完整，无法保存恢复记录。' }
    }
    Assert-RecoveryState -State ([Convert]::FromBase64String($files['config/installation.json']))
    $vault = Get-RecoveryVault
    New-Item -ItemType Directory -Path $vault -Force | Out-Null
    Protect-PrivatePath -Path $vault
    $key = Get-RecoveryKey -Directory $path
    $target = Join-Path $vault ($key + '.dpapi')
    if ((Test-Path -LiteralPath $target) -and ((Get-Item -LiteralPath $target).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw '恢复记录路径异常。' }
    $payload = @{ schema=1; directory=$path; files=$files; updated_at=[DateTime]::UtcNow.ToString('o') } | ConvertTo-Json -Depth 5
    Add-Type -AssemblyName System.Security
    $entropy = [Text.Encoding]::UTF8.GetBytes('TransDocRecovery.v1:' + $key)
    $cipher = [Security.Cryptography.ProtectedData]::Protect([Text.Encoding]::UTF8.GetBytes($payload), $entropy, [Security.Cryptography.DataProtectionScope]::CurrentUser)
    $temporary = Join-Path $vault ([Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllBytes($temporary, $cipher)
        if (Test-Path -LiteralPath $target) { [IO.File]::Replace($temporary, $target, [NullString]::Value) }
        else { [IO.File]::Move($temporary, $target) }
    } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force } }
    Write-Host '已保存本机用户加密恢复记录（独立于解压目录，不上传主站）。' -ForegroundColor DarkCyan
}

function Read-InstallationRecovery {
    param([string]$Directory)
    $key = Get-RecoveryKey -Directory $Directory
    $file = Join-Path (Get-RecoveryVault) ($key + '.dpapi')
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { return $null }
    $item = Get-Item -LiteralPath $file
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $item.Length -gt 4194304) { throw '恢复记录异常，不能自动采用。' }
    Add-Type -AssemblyName System.Security
    $entropy = [Text.Encoding]::UTF8.GetBytes('TransDocRecovery.v1:' + $key)
    try {
        $data = [Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($file), $entropy, [Security.Cryptography.DataProtectionScope]::CurrentUser)
        $payload = [Text.Encoding]::UTF8.GetString($data) | ConvertFrom-Json
    } catch { throw '恢复记录无法由当前 Windows 用户解密；请使用原用户或恢复原配置，不能重置数据库密码。' }
    if ($payload.schema -ne 1 -or $payload.directory -ine [IO.Path]::GetFullPath($Directory).TrimEnd('\', '/')) { throw '恢复记录目录不匹配。' }
    foreach ($property in $payload.files.PSObject.Properties) {
        if ($property.Name -notin (Get-RecoveryFileNames)) { throw '恢复记录含非配置路径。' }
    }
    foreach ($name in @('config/installation.json', 'config/compose.env', 'config/node.env')) {
        if (-not $payload.files.$name) { throw '恢复记录不完整。' }
    }
    Assert-RecoveryState -State ([Convert]::FromBase64String($payload.files.'config/installation.json'))
    return $payload
}

function Restore-InstallationFromRecycleBin {
    param([string]$Directory)
    if (Test-Path -LiteralPath $Directory) { return $false }
    $shell = New-Object -ComObject Shell.Application
    $bin = $shell.Namespace(10)
    $parent = Split-Path -Parent $Directory
    $leaf = Split-Path -Leaf $Directory
    $matches = @($bin.Items() | Where-Object { $_.Name -eq $leaf -and $_.ExtendedProperty('System.Recycle.DeletedFrom') -ieq $parent })
    if ($matches.Count -ne 1) { return $false }
    $match = $matches[0]
    $recycleRoot = Join-Path ([IO.Path]::GetPathRoot($Directory)) '$RECYCLE.BIN'
    if (-not ([IO.Path]::GetFullPath($match.Path)).StartsWith($recycleRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw '回收站来源路径异常，未恢复。' }
    $state = Join-Path $match.Path 'config/installation.json'
    if (-not (Test-Path -LiteralPath $state -PathType Leaf)) { return $false }
    foreach ($name in @('', 'config', 'config/installation.json')) {
        if ((Get-Item -LiteralPath (Join-Path $match.Path $name)).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw '回收站中的原配置包含链接，不能自动恢复。' }
    }
    Assert-RecoveryState -State ([IO.File]::ReadAllBytes($state))
    $match.InvokeVerb('undelete')
    $deadline = (Get-Date).AddSeconds(10)
    do {
        if (Test-Path -LiteralPath (Join-Path $Directory 'config/installation.json') -PathType Leaf) { return $true }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    throw '已请求系统还原，请稍后重试；未重建任何数据库。'
}

function Restore-DeletedWindowsInstallation {
    param([string]$PackageDirectory, [string]$TargetDirectory)
    $target = [IO.Path]::GetFullPath($TargetDirectory).TrimEnd('\', '/')
    $existing = Test-Path -LiteralPath $target
    if ($existing -and ((Test-Path -LiteralPath (Join-Path $target 'config')) -or (Test-Path -LiteralPath (Join-Path $target 'local-settings.json')))) {
        Write-Host '原目录已有部分配置，无法安全覆盖；请核对原 config，数据库仍保留。' -ForegroundColor Yellow
        return $false
    }
    if ((Get-DeployedInstallationDirectory) -ine $target) { throw '恢复目标与容器记录不符。' }
    Assert-LocalInstallationPath -Path (Split-Path -Parent $target) | Out-Null
    $payload = Read-InstallationRecovery -Directory $target
    if (-not $payload) {
        if (Restore-InstallationFromRecycleBin -Directory $target) {
            Save-InstallationRecovery -Directory $target
            Write-Host '已从回收站恢复原安装目录，原密码和数据保持不变。' -ForegroundColor Green
            return $true
        }
        return $false
    }
    # Validate release before creating anything at the original path.
    $source = Assert-LocalInstallationPath -Path $PackageDirectory
    $release = Read-OfflineRelease -Directory $source
    if ($existing) {
        Assert-LocalInstallationPath -Path $target | Out-Null
        Read-OfflineRelease -Directory $target | Out-Null
    }
    # Stage on the same volume, then rename. An interrupted copy must not leave a
    # half-restored config at the final path that prevents a safe retry.
    $parent = Split-Path -Parent $target
    $stage = Join-Path $parent ('.transdoc-recovery-' + [Guid]::NewGuid().ToString('N'))
    $lock = $null
    try {
        $lockPath = Join-Path (Get-RecoveryVault) ((Get-RecoveryKey -Directory $target) + '.lock')
        $lock = [IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None')
        New-Item -ItemType Directory -Path $stage | Out-Null
        Protect-PrivatePath -Path $stage
        foreach ($name in @('config','backups')) {
            New-Item -ItemType Directory -Path (Join-Path $stage $name) | Out-Null
            Protect-PrivatePath -Path (Join-Path $stage $name)
        }
        foreach ($property in $payload.files.PSObject.Properties) {
            $destination = Join-Path $stage $property.Name
            [IO.File]::WriteAllBytes($destination, [Convert]::FromBase64String($property.Value))
            Protect-PrivatePath -Path $destination
        }
        if ($existing) {
            # Never replace an existing configuration or release. A concurrent
            # installer creating config wins; Directory.Move then fails safely.
            [IO.Directory]::Move((Join-Path $stage 'config'), (Join-Path $target 'config'))
            $settings = Join-Path $stage 'local-settings.json'
            if (Test-Path -LiteralPath $settings) { [IO.File]::Move($settings, (Join-Path $target 'local-settings.json')) }
            if (-not (Test-Path -LiteralPath (Join-Path $target 'backups'))) {
                [IO.Directory]::Move((Join-Path $stage 'backups'), (Join-Path $target 'backups'))
            }
        } else {
            foreach ($name in @($release.files.PSObject.Properties.Name) + @('offline-manifest.json')) {
                Copy-Item -LiteralPath (Join-Path $source $name) -Destination (Join-Path $stage $name)
            }
            Read-OfflineRelease -Directory $stage | Out-Null
            [IO.Directory]::Move($stage, $target)
        }
    } finally {
        if ($lock) { $lock.Dispose() }
        # This exact random staging directory was created above, under the
        # validated original parent; never clean the target or a broad directory.
        if (Test-Path -LiteralPath $stage) {
            $resolved = (Get-Item -LiteralPath $stage).FullName
            if ($resolved -eq $stage -and (Split-Path -Parent $resolved) -eq $parent -and (Split-Path -Leaf $resolved) -match '^\.transdoc-recovery-[a-f0-9]{32}$') {
                Remove-Item -LiteralPath $resolved -Recurse -Force
            }
        }
    }
    Write-Host '已从本机加密记录恢复原配置，复用原数据库；未启动应用或更改授权。' -ForegroundColor Green
    return $true
}

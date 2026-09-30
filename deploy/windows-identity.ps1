# Find existing same-user, same-machine identities even after Docker was reinstalled.
function Find-RememberedNodeIdentities {
    $vault = Get-RecoveryVault
    if (-not (Test-Path -LiteralPath $vault -PathType Container)) { return @() }
    $records = @(Get-ChildItem -LiteralPath $vault -Filter '*.dpapi' -File)
    if ($records.Count -gt 64) { throw '本机恢复记录过多，请人工核对；未生成新授权。' }
    Add-Type -AssemblyName System.Security
    $found = @()
    foreach ($record in $records) {
        if ($record.BaseName -notmatch '^[a-f0-9]{64}$' -or $record.Length -gt 4194304 -or ($record.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw '存在异常恢复记录，请人工核对；未生成新授权。'
        }
        try {
            $entropy = [Text.Encoding]::UTF8.GetBytes('TransDocRecovery.v1:' + $record.BaseName)
            $bytes = [Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($record.FullName), $entropy, [Security.Cryptography.DataProtectionScope]::CurrentUser)
            $candidate = [Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json
            if ((Get-RecoveryKey -Directory $candidate.directory) -ne $record.BaseName) { throw 'Directory mismatch' }
            $payload = Read-InstallationRecovery -Directory $candidate.directory
            $state = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload.files.'config/installation.json')) | ConvertFrom-Json
            $found += [pscustomobject]@{node_id=$state.node_id; directory=$payload.directory; updated_at=$payload.updated_at; payload=$payload}
        } catch { throw '发现旧安装的加密记录但无法安全读取。请用原 Windows 用户恢复，未创建重复授权。' }
        finally { $bytes=$null; $candidate=$null }
    }
    # A move/re-extraction can leave multiple snapshots of the SAME identity.
    return @($found | Sort-Object updated_at -Descending | Group-Object node_id | ForEach-Object { $_.Group[0] })
}

function Restore-RememberedNodeIdentity {
    param([string]$PackageDirectory)
    if (Test-Path -LiteralPath (Join-Path $PackageDirectory 'config')) { return $false }
    $records = @(Find-RememberedNodeIdentities)
    if (-not $records.Count) { return $false }
    if ($records.Count -eq 1) { $selected = $records[0] }
    else {
        Write-Host 'Docker 中没有原安装，但本机保留多份不同身份。请选择原节点，不能自动合并或新建重复授权。' -ForegroundColor Yellow
        for ($index=0; $index -lt $records.Count; $index++) {
            Write-Host ("{0}  节点 {1}…  记录时间 {2}" -f ($index+1), $records[$index].node_id.Substring(0,12), $records[$index].updated_at)
        }
        $choice = Read-Host '输入原节点序号；0 返回（不创建新授权）'
        $number = 0
        if (-not [int]::TryParse($choice,[ref]$number) -or $number -lt 1 -or $number -gt $records.Count) { throw '已取消身份恢复，未生成新节点或授权。' }
        $selected = $records[$number-1]
    }
    $target = Assert-LocalInstallationPath -Path $PackageDirectory
    if (Get-DeployedInstallationDirectory) { throw '检测到容器状态变化，请重新运行以识别原安装。' }
    Read-OfflineRelease -Directory $target | Out-Null
    $vault = Get-RecoveryVault
    $lock = [IO.File]::Open((Join-Path $vault '.identity-recovery.lock'), 'OpenOrCreate','ReadWrite','None')
    $stage = Join-Path $target ('.identity-recovery-' + [Guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $stage | Out-Null
        Protect-PrivatePath -Path $stage
        # Only the verified config allowlist is restored. Application/customer data is NOT in this vault.
        foreach ($property in $selected.payload.files.PSObject.Properties) {
            if (-not $property.Name.StartsWith('config/')) { continue }
            $name = $property.Name.Substring(7)
            if ([IO.Path]::GetFileName($name) -ne $name) { throw 'Invalid recovery path' }
            $path = Join-Path $stage $name
            [IO.File]::WriteAllBytes($path,[Convert]::FromBase64String($property.Value))
            Protect-PrivatePath -Path $path
        }
        [IO.Directory]::Move($stage, (Join-Path $target 'config'))
        New-Item -ItemType Directory -Force -Path (Join-Path $target 'backups') | Out-Null
        Protect-PrivatePath -Path (Join-Path $target 'backups')
        Save-InstallationRecovery -Directory $target
        Write-Host '已复用本机原节点、密码和授权，不会重复申请。' -ForegroundColor Green
        Write-Host '注意：恢复记录不含数据库和客户文件；已删除的 Docker 数据卷仍需从业务备份恢复。' -ForegroundColor Yellow
        return $true
    } finally {
        $lock.Dispose()
        if (Test-Path -LiteralPath $stage) {
            $resolved = (Get-Item -LiteralPath $stage).FullName
            if ($resolved -eq $stage -and (Split-Path -Parent $resolved) -eq $target -and (Split-Path -Leaf $resolved) -match '^\.identity-recovery-[a-f0-9]{32}$') {
                Remove-Item -LiteralPath $resolved -Recurse -Force
            }
        }
    }
}

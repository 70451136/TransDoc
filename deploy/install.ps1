param(
    [ValidateSet('Prepare', 'Activate', 'Upgrade', 'Reinstall')][string]$Mode = 'Prepare',
    [switch]$InstallEngine,
    [switch]$AcceptDockerLicense,
    [string]$PublicUrl = 'http://localhost:8080',
    [string]$AdminEmail = '',
    [int]$Port = 8080,
    [ValidateSet('127.0.0.1', '0.0.0.0')][string]$BindAddress = '127.0.0.1',
    [switch]$AllowInsecureLan
)
$ErrorActionPreference = 'Stop'
$OutputEncoding = [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding
Set-Location -LiteralPath $PSScriptRoot
. (Join-Path $PSScriptRoot 'windows-common.ps1')
. (Join-Path $PSScriptRoot 'windows-engine.ps1')
. (Join-Path $PSScriptRoot 'windows-recovery.ps1')
. (Join-Path $PSScriptRoot 'windows-identity.ps1')
# Do not let two installers change the same secrets, database or containers concurrently.
$installLock = [IO.File]::Open((Join-Path $PSScriptRoot '.installer.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
try {
Ensure-DesktopEngine -AllowInstall:$InstallEngine -AcceptDockerLicense:$AcceptDockerLicense
$engineType = Invoke-Docker info --format '{{.OSType}}'
if ($engineType -ne 'linux') { throw 'Docker Desktop must be running in Linux container mode.' }
Invoke-Docker compose version
Assert-InstallationOwner -Directory $PSScriptRoot
# Direct CLI usage must not bypass remembered-identity protection in Start.cmd.
if (-not (Test-Path -LiteralPath 'config/installation.json') -and @(Find-RememberedNodeIdentities).Count) {
    throw '发现本机原安装身份。请用完整 Windows 安装包的 Start.cmd 自动恢复原授权，不能直接创建重复节点。'
}
if ($Mode -eq 'Activate' -and -not (Test-Path -LiteralPath 'activation.json' -PathType Leaf)) {
    throw '缺少 activation.json。数据库准备不需要授权；请选择准备，或保存主站授权文件后再激活。'
}
if ($Mode -in @('Upgrade', 'Reinstall') -and -not (Test-Path -LiteralPath 'config/activation.token' -PathType Leaf)) {
    throw '尚未激活，不能直接启动应用。请先保存主站 activation.json，再选择应用授权。'
}
# Repeated CLI calls must not silently reset a previously selected port/email.
if (Test-Path -LiteralPath 'config/compose.env') {
    $saved = Read-LocalSettings
    if (-not $PSBoundParameters.ContainsKey('Port')) { $Port = $saved.port }
    if (-not $PSBoundParameters.ContainsKey('AdminEmail')) { $AdminEmail = $saved.email }
    if (-not $PSBoundParameters.ContainsKey('PublicUrl')) {
        $origin = Get-Content -Encoding UTF8 -LiteralPath 'config/node.env' | Where-Object { $_ -match '^TRANSDOC_PUBLIC_APP_URL=' } | Select-Object -First 1
        if ($origin) {
            $PublicUrl = $origin.Split('=', 2)[1]
            $savedOrigin = [Uri]$PublicUrl
            if ($PSBoundParameters.ContainsKey('Port') -and $savedOrigin.Host -in @('localhost', '127.0.0.1', '[::1]', '::1')) {
                $builder = New-Object UriBuilder $savedOrigin
                $builder.Port = $Port
                $PublicUrl = $builder.Uri.GetLeftPart([UriPartial]::Authority)
            }
        }
    }
    if (-not $PSBoundParameters.ContainsKey('BindAddress')) {
        $binding = Get-Content -Encoding UTF8 -LiteralPath 'config/compose.env' | Where-Object { $_ -match '^TRANSDOC_HTTP_BIND=' } | Select-Object -First 1
        if ($binding) { $BindAddress = $binding.Split('=', 2)[1] }
    }
}
Write-SetupStage images '检查离线镜像和校验清单；已有镜像不会重复下载。'
$offline = Test-Path -LiteralPath offline-manifest.json
if ($offline) {
    . (Join-Path $PSScriptRoot 'offline.ps1')
    $offlineRelease = Import-OfflineRelease -Directory $PSScriptRoot
    $runtimeImage = $offlineRelease.images.runtime
    $webImage = $offlineRelease.images.web
} else {
$images = @{}
Get-Content -Encoding UTF8 -LiteralPath images.env | ForEach-Object {
    $pair = $_.Split('=', 2)
    if ($pair.Count -eq 2) { $images[$pair[0]] = $pair[1] }
}
$runtimeImage = $images['TRANSDOC_RUNTIME_IMAGE']
$webImage = $images['TRANSDOC_WEB_IMAGE']
foreach ($image in @($runtimeImage, $webImage)) {
    if ($image -notmatch '^[a-zA-Z0-9./:_-]+@sha256:[a-f0-9]{64}$') { throw 'Invalid immutable image manifest.' }
}
}
New-Item -ItemType Directory -Force -Path config | Out-Null
$configPath = (Resolve-Path -LiteralPath config).Path
# Restrict installer-generated secrets on NTFS; Unix chmod inside containers is not an NTFS ACL.
Protect-PrivatePath -Path $configPath
New-Item -ItemType Directory -Force -Path backups | Out-Null
Protect-PrivatePath -Path (Join-Path $PSScriptRoot 'backups')
$machineId = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography').MachineGuid
if (-not $offline) { Invoke-Docker pull $runtimeImage }
if ($Mode -notin @('Upgrade', 'Reinstall')) {
    Write-SetupStage configuration '生成或复用节点身份、随机密码和本机配置。'
    $dockerArgs = @('run', '--rm', '--user', '0:0', '-v', "${configPath}:/config")
    $configArgs = @('--machine-id', $machineId, '--runtime-image', $runtimeImage, '--web-image', $webImage, '--public-url', $PublicUrl, '--port', "$Port", '--bind', $BindAddress)
    if ($AdminEmail) { $configArgs += @('--admin-email', $AdminEmail) }
    if ($AllowInsecureLan) { $configArgs += '--allow-insecure-lan' }
    if ($Mode -eq 'Activate') {
        $activationPath = (Resolve-Path -LiteralPath activation.json).Path
        Protect-PrivatePath -Path $activationPath
        $dockerArgs += @('-v', "${activationPath}:/activation.json:ro")
        $configArgs += @('--activation', '/activation.json')
    }
    Invoke-Docker @dockerArgs $runtimeImage python -m packages.deployment_license.install_config @configArgs
}
if ($Mode -in @('Upgrade', 'Reinstall')) {
    Write-SetupStage configuration '核对本机访问来源，保留原账号、密钥、端口及授权。'
    Invoke-Docker run --rm --user 0:0 -v "${configPath}:/config" $runtimeImage python -m packages.deployment_license.install_origins
}
Save-InstallationRecovery -Directory $PSScriptRoot
$env:TRANSDOC_RUNTIME_IMAGE = $runtimeImage
$env:TRANSDOC_WEB_IMAGE = $webImage
Invoke-Compose config --quiet
if ($Mode -eq 'Prepare') {
    Write-SetupStage database '自动部署 PostgreSQL 17 和 Redis，等待健康检查；不会开放数据库公网端口。'
    if (-not $offline) { Invoke-Compose pull postgres redis }
    Invoke-Compose up -d --wait --wait-timeout 180 --no-deps postgres redis
    if (Test-Path -LiteralPath 'config/activation.token' -PathType Leaf) {
        Write-SetupStage infrastructure_ready 'PostgreSQL / Redis 已就绪，已有授权配置。选择 3 继续应用安装，无需重新创建授权。'
    } else {
        Write-SetupStage awaiting_authorization 'PostgreSQL / Redis 已就绪。等待主站授权，尚未启动应用或调用模型。'
        Write-Host '将节点编号提交主站「部署授权」，保存 activation.json 后选择 2；不要重复创建节点或删除数据卷。' -ForegroundColor Yellow
    }
    return
}
if (-not (Test-Path -LiteralPath config/activation.token)) { throw 'Activation required.' }
if (-not $offline) { Invoke-Compose pull }
Write-SetupStage draining '检查并停止已有调度器，等待旧 Worker 当前处理完成；保留已完成数据。'
Invoke-Compose stop --timeout 30 dispatcher
Invoke-Compose stop --timeout -1 worker
Write-SetupStage database '启动并检查 PostgreSQL / Redis。'
Invoke-Compose up -d --wait --wait-timeout 180 postgres redis
$backupName = 'pre-upgrade-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '.dump'
Write-SetupStage backup '备份数据库；备份失败时不会继续数据库迁移。'
Invoke-Compose run --rm --no-deps -e "BACKUP_FILE=$backupName" backup
Invoke-Compose run --rm --no-deps storage-init
Write-SetupStage migration '自动创建或增量更新数据库表。'
Invoke-Compose run --rm --no-deps migrate
if (Test-Path -LiteralPath config/bootstrap.json) {
    Write-SetupStage administrator '初始化本节点管理员；不覆盖已有账号密码。'
    Invoke-Compose run --rm --no-deps -v "${configPath}/bootstrap.json:/run/bootstrap.json:ro" api python -m services.api.src.modules.deployment_licenses.bootstrap --file /run/bootstrap.json
}
# Refresh credential file bind mounts after an atomic replacement or rotation.
Write-SetupStage application '启动 API、工作台和授权续签服务，等待健康检查。'
Invoke-Compose up -d --no-deps --force-recreate license-agent
$recreate = @()
if ($Mode -eq 'Reinstall') { $recreate = @('--force-recreate') }
Invoke-Compose up -d --no-deps @recreate --wait --wait-timeout 180 api
Invoke-Compose up -d --no-deps --force-recreate --wait --wait-timeout 180 web
Write-SetupStage authorization '检查主站签名授权；验证通过前不会启动翻译处理。'
Invoke-Compose exec -T api python -m packages.deployment_license.wait_ready
Write-SetupStage processors '启动 Worker / 调度器。'
Invoke-Compose up -d --no-deps @recreate worker dispatcher
Invoke-Docker run --rm --user 0:0 -v "${configPath}:/config" $runtimeImage python -m packages.deployment_license.pin_release --runtime-image $runtimeImage --web-image $webImage
Save-InstallationRecovery -Directory $PSScriptRoot
Write-SetupStage ready '安装完成。返回控制台可查看账号与有效初始密码，或通过「账号与密码」修改；不要公开截图密码。'
try { Invoke-Compose exec -T license-agent python -m services.api.src.modules.deployment_licenses.node_agent --once }
catch { Write-Host '应用已就绪，主站资料或版本暂未同步；稍后会自动重试，也可在账号控制台立即同步。' -ForegroundColor Yellow }
} catch {
    Write-Host '安装未完成：请处理上方具体错误，然后在原目录重试。已生成的身份、配置和数据库均保留。' -ForegroundColor Yellow
    throw
} finally {
    $installLock.Dispose()
}

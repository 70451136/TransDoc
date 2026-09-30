# Shared functions only; loading this file does not start services or read credentials.
function Protect-PrivatePath {
    param([string]$Path)
    $item = Get-Item -LiteralPath $Path
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw '私密配置路径不能使用符号链接。' }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().User
    if ($item.PSIsContainer) {
        $acl = New-Object Security.AccessControl.DirectorySecurity
        $rule = New-Object Security.AccessControl.FileSystemAccessRule($identity, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
    } else {
        $acl = New-Object Security.AccessControl.FileSecurity
        $rule = New-Object Security.AccessControl.FileSystemAccessRule($identity, 'FullControl', 'Allow')
    }
    $acl.SetAccessRuleProtection($true, $false)
    $acl.AddAccessRule($rule)
    # Persist DACL changes only. Set-Acl in PS5.1 can request SeSecurityPrivilege
    # even though the installer must not modify system auditing or ownership.
    if ($PSVersionTable.PSVersion.Major -le 5) { $item.SetAccessControl($acl) }
    else { [IO.FileSystemAclExtensions]::SetAccessControl($item, $acl) }
}

function Initialize-DockerCommand {
    $command = Get-Command docker -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $candidates = @()
    if ($command) { $candidates += $command.Source }
    foreach ($key in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Docker Desktop', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Docker Desktop')) {
        $install = Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
        if ($install.InstallLocation) { $candidates += Join-Path $install.InstallLocation 'resources\bin\docker.exe' }
    }
    $candidates += @("$env:LOCALAPPDATA\Programs\DockerDesktop\resources\bin\docker.exe", 'C:\Program Files\Docker\Docker\resources\bin\docker.exe')
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $script:DockerExecutable = $candidate
            # Custom D: installs need the sibling credential helper on this process PATH.
            $bin = Split-Path -Parent $candidate
            if ($bin -notin ($env:PATH -split ';')) { $env:PATH = "$bin;$env:PATH" }
            return
        }
    }
    throw '未找到 Docker Desktop。请先安装并启动 Linux 容器引擎；支持通过安装注册表识别 D 盘等自定义路径。'
}

function Invoke-Docker {
    if (-not $script:DockerExecutable) { Initialize-DockerCommand }
    & $script:DockerExecutable @args
    if ($LASTEXITCODE -ne 0) { throw "Docker 操作失败（退出码 $LASTEXITCODE）。数据已保留，请处理上方具体错误后重试。" }
}

function Invoke-Compose {
    $composeArgs = @('compose', '--env-file', 'config/compose.env', '-f', 'compose.yaml')
    if (Test-Path -LiteralPath 'offline-manifest.json') { $composeArgs += @('-f', 'compose.offline.json') }
    Invoke-Docker @composeArgs @args
}

function Get-DeployedInstallationDirectory {
    $project = if ($env:COMPOSE_PROJECT_NAME) { $env:COMPOSE_PROJECT_NAME } else { 'transdoc-licensed' }
    $containers = @(Invoke-Docker ps -aq --filter "label=com.docker.compose.project=$project")
    $owners = @()
    foreach ($container in $containers) {
        # PS5.1 strips embedded quotes in native arguments; parse labels as JSON.
        $labels = (Invoke-Docker inspect --format '{{json .Config.Labels}}' $container) | ConvertFrom-Json
        $owner = $labels.'com.docker.compose.project.working_dir'
        if (-not $owner -or $owner -eq '<no value>') { throw '发现同名容器但缺少安装目录信息，已停止操作，避免覆盖其他部署。' }
        if (-not [IO.Path]::IsPathRooted($owner)) { throw '容器记录的安装目录无效，已停止操作。' }
        $owners += [IO.Path]::GetFullPath($owner).TrimEnd('\', '/')
    }
    $distinct = @($owners | Sort-Object -Unique)
    if ($distinct.Count -gt 1) { throw '同名容器记录了多个安装目录，需要先核实，未修改任何数据。' }
    if ($distinct.Count -eq 1) { return $distinct[0] }
    $volumes = @(Invoke-Docker volume ls --filter "label=com.docker.compose.project=$project" --format '{{.Name}}')
    if ($volumes.Count) { throw '发现已有数据卷，但没有可定位原目录的容器记录。已停止新建配置，请恢复原安装；不会用新密码覆盖旧数据库。' }
    return $null
}

function Assert-InstallationOwner {
    param([string]$Directory)
    $owner = Get-DeployedInstallationDirectory
    $expected = [IO.Path]::GetFullPath($Directory).TrimEnd('\', '/')
    if ($owner -and $owner -ine $expected) {
        throw "已有安装目录：$owner。请双击 Start.cmd 自动识别并继续原安装；不需要重新填写邮箱或删除数据库。"
    }
    if ($owner) {
        foreach ($name in @('installation.json', 'compose.env', 'node.env')) {
            if (-not (Test-Path -LiteralPath (Join-Path $expected "config/$name") -PathType Leaf)) {
                throw '已有数据库但原配置缺失。请双击 Start.cmd 尝试恢复配置；不能重新生成密码。'
            }
        }
    }
}

function Write-SetupStage {
    param([string]$Stage, [string]$Message)
    Write-Host "`n[$Stage] $Message" -ForegroundColor Cyan
    if (Test-Path -LiteralPath 'config' -PathType Container) {
        $state = @{ stage = $Stage; updated_at = [DateTime]::UtcNow.ToString('o') }
        $path = Join-Path (Get-Location).Path 'config/setup-status.json'
        [IO.File]::WriteAllText($path, ($state | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
    }
}

function Read-LocalSettings {
    if (Test-Path -LiteralPath 'local-settings.json') {
        $settings = Get-Content -Raw -Encoding UTF8 -LiteralPath 'local-settings.json' | ConvertFrom-Json
        # compose.env is authoritative after a CLI port change; the menu cache can be stale.
        if (Test-Path -LiteralPath 'config/compose.env') {
            $portLine = @(Get-Content -Encoding UTF8 -LiteralPath 'config/compose.env' | Where-Object { $_ -match '^TRANSDOC_HTTP_PORT=' })
            if ($portLine.Count -ne 1) { throw '安装端口配置不完整，请恢复原 compose.env；不使用过期菜单缓存。' }
            $settings.port = [int]$portLine[0].Split('=', 2)[1]
        }
        if ($settings.port -ge 1 -and $settings.port -le 65535 -and $settings.email) { return $settings }
        throw '本机设置格式无效，请检查 local-settings.json；不要删除 config 或数据库卷。'
    }
    # Recover after interruption between preparing config and saving menu settings.
    if ((Test-Path -LiteralPath 'config/compose.env') -and (Test-Path -LiteralPath 'config/bootstrap.json')) {
        $line = Get-Content -Encoding UTF8 -LiteralPath 'config/compose.env' | Where-Object { $_ -match '^TRANSDOC_HTTP_PORT=' } | Select-Object -First 1
        $bootstrap = Get-Content -Raw -Encoding UTF8 -LiteralPath 'config/bootstrap.json' | ConvertFrom-Json
        if ($line -and $bootstrap.email) { return @{ email = $bootstrap.email; port = [int]$line.Split('=', 2)[1] } }
    }
    throw '请先选择 1，完成本机环境准备。'
}

function Test-WorkstationReady {
    param([int]$Port)
    if (-not (Test-Path -LiteralPath 'config/activation.token' -PathType Leaf)) { return $false }
    try {
        # Check this installation's containers, not an unrelated app on the same port.
        $rows = @(Get-ComposeServiceRows)
        foreach ($service in @('api', 'web')) {
            $row = @($rows | Where-Object { $_.Service -eq $service -and $_.State -eq 'running' -and $_.Health -eq 'healthy' })
            if ($row.Count -ne 1) { return $false }
        }
        $response = Invoke-WebRequest -UseBasicParsing -Uri "http://localhost:$Port/api/v1/health/ready" -TimeoutSec 5
        return $response.StatusCode -eq 200
    } catch { return $false }
}

function Get-ComposeServiceRows {
    $output = (Invoke-Compose ps -a --format json) -join "`n"
    if (-not $output.Trim()) { return @() }
    try {
        $parsed = $output | ConvertFrom-Json
        foreach ($row in $parsed) { Write-Output $row }
    }
    catch { return @($output -split "`n" | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json }) }
}

function Show-InstallationStatus {
    if (-not (Test-Path -LiteralPath 'config/installation.json')) {
        Write-Host '尚未准备：请选择 1，自动部署 PostgreSQL / Redis 并生成节点编号。' -ForegroundColor Yellow
        return
    }
    if (-not (Test-Path -LiteralPath 'config/activation.token' -PathType Leaf)) {
        Write-Host '尚未完成主站授权：数据库可先就绪。按回车自动登记并继续；主站需开启自动授权。' -ForegroundColor Yellow
    }
    if (Test-Path -LiteralPath 'config/setup-status.json') {
        $state = Get-Content -Raw -Encoding UTF8 -LiteralPath 'config/setup-status.json' | ConvertFrom-Json
        Write-Host "最近安装阶段：$($state.stage)"
    }
    Initialize-DockerCommand
    $rows = @(Get-ComposeServiceRows)
    if (-not $rows.Count) { Write-Host '尚未创建服务，请选择 1 部署数据库。' -ForegroundColor Yellow; return }
    $rows | Select-Object Service,State,Health,Status | Format-Table -AutoSize
    $versions = @()
    foreach ($row in $rows | Where-Object { $_.Service -in @('api','web','worker','dispatcher','license-agent') }) {
        try {
            $labels = (Invoke-Docker inspect --format '{{json .Config.Labels}}' $row.ID) | ConvertFrom-Json
            $version = $labels.'org.opencontainers.image.version'
            $revision = $labels.'org.opencontainers.image.revision'
            $versions += [pscustomobject]@{ Service=$row.Service; Version=$(if ($version) { $version } else { '旧版未记录' }); Revision=$(if ($revision) { $revision } else { '未知' }) }
        } catch { Write-Host "无法读取 $($row.Service) 的版本，可检查容器状态后重试。" -ForegroundColor Yellow }
    }
    if ($versions.Count) {
        Write-Host '实际运行版本（不含密码或授权凭证）：' -ForegroundColor Cyan
        $versions | Format-Table -AutoSize
        $known = @($versions.Revision | Where-Object { $_ -match '^[a-f0-9]{40}$' } | Sort-Object -Unique)
        if ($known.Count -gt 1) { Write-Host '发现服务版本不一致，请使用同一完整发行包执行保留数据修复；不要只替换脚本。' -ForegroundColor Yellow }
    }
}

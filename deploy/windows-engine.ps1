# Official Docker bootstrap only. No registry edits, third-party patches or automatic reboot.
function Assert-DockerInstallerSignature {
    param([string]$Path)
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '(?:^|,\s*)O="?Docker Inc\.?"?(?:,|$)') {
        throw 'Docker 安装器数字签名无效或发布者不是 Docker Inc。已阻止执行，请检查网络后重试。'
    }
}

function Install-OfficialDockerDesktop {
    param([switch]$AcceptDockerLicense)
    $os = Get-CimInstance Win32_OperatingSystem
    if ($os.ProductType -ne 1 -or [int]$os.BuildNumber -lt 19045 -or -not [Environment]::Is64BitOperatingSystem -or $env:PROCESSOR_ARCHITECTURE -eq 'ARM64') {
        throw '本安装包要求受支持的 Windows 10/11 x64 桌面系统；不支持 Windows Server 或 ARM。'
    }
    $drive = New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($PSScriptRoot))
    if ($drive.AvailableFreeSpace -lt 4GB) { throw '安装包所在磁盘可用空间不足 4 GB，请先腾出空间；不会自动删除文件。' }
    if (-not $AcceptDockerLicense) {
        Write-Host '尚未安装 Docker Desktop。可自动下载官方安装器，配置 WSL2 并继续部署。' -ForegroundColor Cyan
        Write-Host '许可：https://www.docker.com/legal/docker-subscription-service-agreement/'
        Write-Host '部分商业/政府使用需要付费订阅；可能出现管理员授权或重启提示，不会自动重启。' -ForegroundColor Yellow
        if ((Read-Host '已阅读并同意 Docker 条款，允许下载安装？输入 Y，其它输入取消') -ine 'Y') {
            throw '已取消 Docker 安装。未下载、未修改系统；准备好后再次双击即可继续。'
        }
    }
    $cache = Join-Path $PSScriptRoot 'downloads'
    New-Item -ItemType Directory -Force -Path $cache | Out-Null
    Protect-PrivatePath -Path $cache
    $installer = Join-Path $cache 'Docker Desktop Installer.exe'
    $lock = [IO.File]::Open((Join-Path $cache '.download.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    try {
        if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
            $partial = $installer + '.partial'
            Write-Host '下载 Docker 官方安装器（显示下载进度；断网可重新运行）……' -ForegroundColor Cyan
            $curl = Join-Path $env:SystemRoot 'System32/curl.exe'
            & $curl --fail --location --proto '=https' --proto-redir '=https' --retry 2 --connect-timeout 30 --max-time 900 --output $partial 'https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe'
            if ($LASTEXITCODE -ne 0) { throw 'Docker 下载未完成。请检查网络/代理后重试；未运行残缺安装器。' }
            Assert-DockerInstallerSignature -Path $partial
            Move-Item -LiteralPath $partial -Destination $installer
        }
        Assert-DockerInstallerSignature -Path $installer
        # Per-user WSL2 is the official least-privilege default. Existing Docker is never reinstalled here.
        $process = Start-Process -FilePath $installer -ArgumentList @('install', '--user', '--accept-license', '--backend=wsl-2', '--no-windows-containers', '--quiet') -PassThru -WindowStyle Hidden
        $deadline = (Get-Date).AddMinutes(20)
        while (-not $process.WaitForExit(10000)) {
            Write-Host 'Docker 官方安装程序仍在运行，请留意系统授权提示……' -ForegroundColor DarkCyan
            if ((Get-Date) -gt $deadline) { throw '安装程序用时超过 20 分钟，未强制中断。请检查系统提示，结束后再次双击继续。' }
        }
        if ($process.ExitCode -in @(3010, 1641)) { throw 'Docker 环境需要重启。请保存工作并手动重启，然后双击同一个 Start.cmd 自动续装。' }
        if ($process.ExitCode -ne 0) { throw "Docker 安装未完成（退出码 $($process.ExitCode)）。请检查官方安装器日志或系统授权提示后重试。" }
    } finally { $lock.Dispose() }
}

function Ensure-DesktopEngine {
    param([switch]$AllowInstall, [switch]$AcceptDockerLicense)
    try { Initialize-DockerCommand }
    catch {
        if (-not $AllowInstall) { throw }
        Install-OfficialDockerDesktop -AcceptDockerLicense:$AcceptDockerLicense
        Initialize-DockerCommand
    }
    try { $kind = Invoke-Docker info --format '{{.OSType}}' 2>$null } catch { $kind = $null }
    if ($kind -eq 'linux') { return }
    if ($kind -eq 'windows') { throw '请在 Docker Desktop 切换到 Linux containers，然后重试。' }
    $root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $script:DockerExecutable))
    $desktop = Join-Path $root 'Docker Desktop.exe'
    if (-not (Test-Path -LiteralPath $desktop -PathType Leaf)) { throw 'Docker 文件不完整，请从官方安装器修复 Docker Desktop 后再试。' }
    Start-Process -FilePath $desktop -WindowStyle Hidden
    $deadline = (Get-Date).AddMinutes(4)
    do {
        Write-Host '等待 Docker Linux 引擎就绪；首次启动可能需要 WSL2 / 系统授权……' -ForegroundColor DarkCyan
        Start-Sleep -Seconds 10
        try { $kind = Invoke-Docker info --format '{{.OSType}}' 2>$null } catch { $kind = $null }
        if ($kind -eq 'linux') { return }
    } while ((Get-Date) -lt $deadline)
    throw 'Docker 尚未就绪，未开始数据库部署。请处理 Docker 的 WSL2/虚拟化/重启提示，再次双击继续；不会自动重启或清空数据。'
}

# TransDoc 本地部署版

语铸云 TransDoc 独立节点镜像，用于自有电脑或 Linux 服务器的文件翻译、格式还原、术语/翻译记忆和 QA。

**完整安装入口：[70451136/TransDoc](https://github.com/70451136/TransDoc)**

- `transdoc520/transdoc-runtime`：API、Worker、调度、授权续签与迁移共用的最终运行镜像。
- `transdoc520/transdoc-web`：与 runtime 同版本的工作台前端。
- 需配套 PostgreSQL 17、Redis 7.4 及安装初始化，不要单独启动 API 后跳过迁移、授权或存储初始化。
- 支持 `linux/amd64` 和 `linux/arm64`；Windows x64、Intel Mac、Apple Silicon 与 ARM Linux 使用对应架构的 Linux 容器。

当前发行：**0.3.0-r13 预发布测试版**。使用 GitHub Releases 的 Windows、Linux 或 macOS 离线包，安装包固定真实镜像摘要。用 `SHA256SUMS.txt` 核对下载，避免浮动标签造成前后端混用。

本版同步最新通用功能与可编辑 PDF，DWG 本机执行器另行适配。Web 扫描无检出告警；runtime 仍有两项暂无修复的上游 HIGH 告警，见 [版本说明与扫描结果](https://github.com/70451136/TransDoc/blob/main/RELEASE-NOTES.md)。

## 下载并开始安装

**`docker pull` 只下载镜像，不会安装整套应用。** 不要在 Docker Desktop 中单独点击 runtime 或 web 的 Run；Web 单独运行会因缺少 API 而退出。请复制下面对应系统的**整个命令块**，下载、校验后启动正式安装器。不使用 `latest`，不执行未校验的远程脚本。

### Windows：下载、校验并自动安装

在 **Windows PowerShell 5.1 或 PowerShell 7** 中粘贴执行，不要粘贴到 CMD。目标目录为当前用户的 `%LOCALAPPDATA%\TransDoc\Packages\0.3.0-r13`；默认位于 C 盘。如需把安装包和配置放到 D 盘，可先将 `$target` 改为专用目录（例如 `'D:\TransDocNode'`）；这不会迁移 Docker 的镜像和数据盘。

```powershell
& {
    $ErrorActionPreference = 'Stop'
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $release = '0.3.0-r13'
    $target = Join-Path $env:LOCALAPPDATA "TransDoc\Packages\$release"
    if (Test-Path -LiteralPath $target) { throw "Directory exists: $target . Run its Start.cmd to continue; do not delete config or Docker volumes." }
    $zip = Join-Path ([IO.Path]::GetTempPath()) ("TransDoc-" + [Guid]::NewGuid().ToString('N') + '.zip')
    $url = "https://github.com/70451136/TransDoc/releases/download/v$release/TransDoc-Windows-x64-$release.zip"
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $zip
    $expected = '3b51e5988aa363051e0e85de2619989f7ced92c03389fb06b05d32ae8d0182f9'
    if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) { throw 'SHA256 mismatch; installation stopped.' }
    $stage = $target + '.partial-' + [Guid]::NewGuid().ToString('N')
    Expand-Archive -LiteralPath $zip -DestinationPath $stage
    [IO.Directory]::Move($stage, $target)
    Start-Process -FilePath (Join-Path $target 'Start.cmd') -WorkingDirectory $target
}
```

随后在弹出的安装控制台填写管理员邮箱；已有安装按提示复用原身份。程序自动准备 PostgreSQL / Redis、登记或复用授权、执行迁移并启动服务，就绪后打开本地工作台。缺少 Docker 时仍需确认其官方许可，按提示处理 UAC、WSL2 或重启；不是无提示静默安装。

重复执行不会覆盖已有目录。如已下载或安装，直接双击上述目录的 `Start.cmd` 继续；修复/重装用菜单 `3`，不要删除 `config`、备份或 Docker 数据卷。ZIP 约 936 MiB，下载失败请检查 GitHub 网络，**不要跳过 SHA256 校验**。命令先在临时目录解压；中断可留下 `.partial-*` 目录，但不会阻止重新执行。已有正式目录却缺少 `Start.cmd` 时先核对内容，不要删除目录或强行覆盖。

### Linux：下载、校验并准备 Docker 环境

在 **Linux x86_64 或 ARM64 的 Bash 终端**执行；需有 `curl`、`tar`、`sha256sum` 和 `sudo`。先安装并启动 Docker Engine 29+ 与 Compose v2，启用 containerd 镜像存储；已有可用引擎会复用。默认目录为 `$HOME/TransDoc-0.3.0-r13`，不要在 Windows PowerShell 中执行这一段。

```bash
(
    set -eu
    umask 077
    release='0.3.0-r13'
    target="$HOME/TransDoc-$release"
    if [ -e "$target" ]; then
        printf 'Directory exists: %s . Continue from the original directory; do not delete config or volumes.\n' "$target" >&2
        exit 1
    fi
    read -r -p 'Administrator email: ' admin_email
    test -n "$admin_email"
    stage="$(mktemp -d "$HOME/TransDoc-$release.partial.XXXXXX")"
    cd "$stage"
    archive="TransDoc-Linux-universal-$release.tar.gz"
    curl --fail --location --proto '=https' --proto-redir '=https' --tlsv1.2 \
        "https://github.com/70451136/TransDoc/releases/download/v$release/$archive" -o "$archive"
    printf '%s  %s\n' '19699a44c1c1eff5580d8fb2948e327c7652994e6582df220772cd3939f61680' "$archive" | sha256sum -c -
    tar -xzf "$archive"
    mv -T --no-clobber "$stage" "$target"
    test ! -d "$stage" || { printf 'Target appeared during download; stopped without overwriting.\n' >&2; exit 1; }
    cd "$target"
    sudo bash install.sh --prepare --admin-email "$admin_email"
)
```

下载、校验或解压失败会停止，可能留下 `.partial.*` 临时目录；修复网络等原因后可重新粘贴整块命令，不覆盖正式目录。若已进入 Docker 准备阶段，请按 [安装说明](https://github.com/70451136/TransDoc/blob/main/INSTALL.md) 在原目录重试准备，`--admin-email` 后仍填写原管理员邮箱，不要删除配置重来。

**Linux 当前版本准备完成后仍需手动授权，不等于应用已安装就绪。** 将输出的节点标识提交主站「部署授权」，把对应完整凭证私密保存为安装目录内的 `activation.json`，然后继续：

```bash
cd "$HOME/TransDoc-0.3.0-r13"
chmod 600 activation.json
sudo bash install.sh --activate
```

若改过 `target`，后续 `cd` 也使用那个目录。默认页面为 `http://localhost:8080`，只监听本机；云服务器上的 localhost 指服务器自身，远程访问需另行配置 SSH 转发或 HTTPS 反向代理，不要直接暴露数据库端口。

### macOS：Intel 与 Apple Silicon

下载 [TransDoc-macOS-universal-0.3.0-r13.zip](https://github.com/70451136/TransDoc/releases/download/v0.3.0-r13/TransDoc-macOS-universal-0.3.0-r13.zip)，使用 `shasum -a 256` 核对：

```text
1cb5b75b6ec1c5772ef944f85f537d4b2611638bc9f866c5e7fbd624626a012b
```

先安装并启动符合机器架构的 Docker Desktop，完整解压后双击 `Start.command`。如果系统要求，请从终端运行 `bash start.sh`。macOS 不使用 sudo；准备后与 Linux 一样手动授权，再启动服务。包内已包含两个架构的四个运行镜像，自动选择本机架构。详见 [macOS 安装与保留数据升级](https://github.com/70451136/TransDoc/blob/main/MACOS-OFFLINE.md)。

三端包均无需拉取应用镜像或 PDF 字体模型；首次安装 Docker、使用云模型以及授权续签仍可能联网。AGPL PDF 对应源码与许可按要求提供，见 [源码与许可说明](https://github.com/70451136/TransDoc/blob/main/SOURCE-NOTICE.md)。

## 授权与数据边界

默认授权免费且无商业到期日，但仍定期向 `doc.abcfanyi.com` 校验，已签名离线宽限最多 7 天。自备模型密钥/本地模型，第三方费用及 Docker Desktop 条款另计。

数据保存在本节点；使用云模型后相关内容发给所选供应商。授权中心接收节点身份、专用凭证、管理员资料及版本，不接收客户正文或模型密钥。数据库默认不公开端口。详情见仓库 INSTALL、FAQ 和 SECURITY。

仅发布最终运行镜像，不发布构建缓存和业务源码；独立 AGPL PDF 适配程序保留源码和许可，并提供本机对应源码下载。字节码可反编译，不能承诺绝对防逆向。

TransDoc is a self-hosted document translation and QA workspace. `docker pull` only downloads an image. Use the verified Windows, Linux or macOS installer above; Linux and macOS currently require manual activation. Bring your own model endpoint and review the release notes before use.

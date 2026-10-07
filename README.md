# 语铸云 TransDoc · 本地部署版

![TransDoc 本地部署：文件译完，结构与知识留下](assets/transdoc-hero.png)

把文件翻译、格式还原、术语和翻译记忆放在自己的电脑或服务器上。

[下载发行包](https://github.com/70451136/TransDoc/releases) · [安装说明](INSTALL.md) · [常见问题](FAQ.md) · [官网](https://doc.abcfanyi.com)

这是 **Docker 独立部署版的发行仓库**，不是主站源码仓库。仓库仅提供安装脚本、Compose、使用文档及发行附件；业务源码不在此仓库公开。上方为品牌插画，不是应用截图。

当前为 **0.3.0-r13 预发布测试版**。请先阅读 [版本说明、验证范围及已知安全告警](RELEASE-NOTES.md)。

## 核心能力

本版包含可编辑 PDF 引擎、字体与布局资源，支持纯译文、交替页对照及修订后重构，详见 [PDF / AGPL 源码与升级说明](PDF.md)。DWG 本机执行器单独适配，本包不开放 DWG 上传。

- **文件翻译与交付**：Office 文档结构解析、标签与占位符保护、格式写回，支持译文和原译对照交付。复杂排版和重要内容仍建议人工复核。
- **翻译 QA**：检查漏译、术语、数字和一致性；支持 Trados / SDLXLIFF 等双语文件检查。
- **客户知识资产**：客户、项目、术语和翻译记忆关联使用；共享与协作受资源权限控制，支持模板、导入和导出。
- **可观测任务**：查看 Agent 阶段、模型调用、并发和重试记录；保留已完成段落，在可确认的边界内恢复任务，不把未知计费当成免费重试。
- **自选模型**：使用自己的云服务商密钥、自定义兼容端点，或接入 Ollama、LM Studio、vLLM。安装包不附带模型或第三方额度。
- **独立运行**：自有 PostgreSQL、Redis、文件存储、账号及模型配置，不复制主站用户或数据。

## 开始使用

| 环境 | 下载与启动 |
| --- | --- |
| Windows 10/11 x64 | 下载 Windows ZIP，完整解压，双击 `Start.cmd`，按菜单一键继续 |
| Linux x86_64 / ARM64 | 下载 Linux universal 离线包，按 [Linux 说明](LINUX-OFFLINE.md) 安装 |
| macOS Intel / Apple Silicon | 下载 macOS universal ZIP，双击 Start.command，见 [macOS 说明](MACOS-OFFLINE.md) |
| 自有云服务器 | 使用相同 Linux 包，另行配置域名、HTTPS、访问控制和备份 |

安装器负责数据库与 Redis、随机密码、迁移、健康检查和服务启动。默认工作台只监听本机 `127.0.0.1:8080`，不会发布数据库端口。不要只运行一个 API 镜像，也不要把开发 Compose 当成发行配置。

发布镜像：`transdoc520/transdoc-runtime`、`transdoc520/transdoc-web`。两者必须来自同一发行版本；安装包使用真实 SHA256 摘要固定镜像。提供 `linux/amd64` 和 `linux/arm64` 原生镜像；Windows 使用 x64 Linux 容器，macOS 使用对应 Intel/Apple Silicon 的 Linux 容器。

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

下载、校验或解压失败会停止，可能留下 `.partial.*` 临时目录；修复网络等原因后可重新粘贴整块命令，不覆盖正式目录。若已进入 Docker 准备阶段，请按 [安装说明](INSTALL.md) 在原目录重试准备，`--admin-email` 后仍填写原管理员邮箱，不要删除配置重来。

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

## 免费与授权

本地部署版可免费下载安装，默认永久授权没有商业到期日；仍需要定期向授权中心校验。有效签名可在断网后继续使用最多 7 天，已知到期或停用仍按授权状态执行。受限时保留已有文件查看和下载，不启动新的受限处理。

**永久免费不等于所有费用都免费**：第三方模型、云主机、存储、网络及 Docker Desktop 可能有各自费用和条款。本地模型也需自行准备算力。正式使用前请阅读 [隐私与安全边界](SECURITY.md)。

## 更新与反馈

升级前备份配置、数据库和文件卷。重复安装应复用原目录和身份；不要删除 `config/` 或执行 `docker compose down -v`。Windows 菜单提供保留数据的修复/重装。

通过 [Issues](https://github.com/70451136/TransDoc/issues) 提交系统、发行版本和脱敏错误码，不要上传客户原文、密码、授权文件、模型密钥或完整日志。

### English

TransDoc is a self-hosted document translation and QA workspace. This repository distributes Docker installers and documentation, **not the proprietary application source**. Run the full release stack with PostgreSQL and Redis; bring your own hosted-model credentials or local endpoint. The default perpetual grant has no commercial expiry but requires periodic validation, with a signed offline grace of up to seven days. Third-party services and infrastructure are not included. See [installation](INSTALL.md) and [security](SECURITY.md).

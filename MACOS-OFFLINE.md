# TransDoc 0.3.0-r13 · macOS 离线安装

本包同时包含 Apple 芯片（M 系列，ARM64）和 Intel（x86_64）原生 Linux 容器镜像，自动识别 Docker 架构。无需 Rosetta 模拟运行应用，也不在 Mac 编译业务源码。支持通用翻译、AI 复核和可编辑 PDF；DWG 本机执行器另行适配。

## 准备 Docker

1. 从 [Docker 官方 Mac 安装页](https://docs.docker.com/desktop/setup/install/mac-install/) 选择与你的芯片对应的 Docker Desktop。使用 Docker 支持的 macOS 版本，启动 Docker.app，按提示确认许可及系统权限。本包不绕过系统确认，也不附带 Docker Desktop。
2. 建议至少 16 GB 内存与 30 GB 可用磁盘。在 Docker 设置中确认使用 containerd 镜像存储（当前版本通常默认开启）。Docker 支持当前及前两个主要 macOS 版本，详见上述官方页面。
3. 对照发行页 SHA256 校验本 ZIP，完整解压到专用本机目录，例如 `~/Applications/TransDocNode`。不要放在 iCloud、共享目录或符号链接目录；路径含空格也可使用。

## 安装和启动

双击包内 `Start.command`，按菜单选择「1 准备安装」，填写本节点管理员邮箱。若 macOS 阻止打开未签名脚本，先核对来源与校验值，再通过系统提供的单项允许入口打开；不要全局关闭 Gatekeeper。也可在终端进入解压目录运行：

```bash
bash install.sh --prepare --admin-email owner@example.com
```

不需要 sudo。安装器会检查本机 Docker、逐文件校验、导入本机架构镜像并准备数据库/Redis，保留已有配置。

准备后，将显示的节点编号提交主站「部署授权」，将此节点返回的凭证保存为当前目录 `activation.json`。选择菜单「2 导入授权并启动」，或执行：

```bash
chmod 600 activation.json
bash install.sh --activate
```

应用就绪后打开安装器显示的地址，默认 `http://localhost:8080`。初始账号密码位于本机私密文件 `config/bootstrap.json`，登录后修改。不要公开截图、上传凭证或复用主站配置。

## 升级、重试与数据

先等待活动任务结束，备份 config、数据库和文件卷。将新包的发行文件更新到原目录，不覆盖或删除 config / backups；选择「3 保留数据升级」或运行 `bash install.sh --upgrade`。`bash install.sh --status` 查看服务；中断后从原目录重试。锁目录 `.installer.lock.d` 只能在确认无安装进程后清理。

Mac 的 Docker 数据保存在 Docker Desktop 虚拟机中，删除解压目录不等于删除数据，恢复解压目录也不能恢复被删除的数据卷。不要为排错重置 Docker Desktop 数据，也不要执行 `docker compose down -v`。迁移前自动备份数据库，但文件卷仍需单独备份。

离线包含应用、数据库、Redis、PDF 字体与布局资源；首次授权及周期续签、所选云模型可能需要网络。可自行配置本地模型。对应 AGPL 源码从本机工作台获取，详见 `PDF.md` 与 `SOURCE-NOTICE.md`。

本包提供 Mac 专用入口及原生 ARM64/amd64 镜像；发行说明会分别记录容器验收与实际 Mac 桌面验收情况，不将 Linux 容器测试等同于 Mac 全流程测试。

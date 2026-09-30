# 安装 TransDoc 本地部署版

从本仓库 Releases 或官网发行入口下载安装包。仓库首页的源码 ZIP 是部署资料，**不是 Windows 离线安装包**。

**想直接复制命令？请用 [下载并开始安装](README.md#下载并开始安装)**：Windows 下载、校验后启动一键安装；Linux 下载、校验并准备环境，再按下文手动激活。两种入口均固定 0.2.1-r11 的附件与 SHA256，不会覆盖已有目录。已有安装请继续原目录的安装器，不要反复创建新目录或删除数据卷。

## 准备

- Windows 10/11 x64：硬件虚拟化、WSL2、Docker Desktop Linux 容器。使用者须确认 Docker Desktop 适用许可，管理员授权和必要重启不能跳过。Windows Server 请使用受支持的 Linux 虚拟机。
- Linux x86_64：Docker Engine 与 Compose v2。自动安装入口适用于 Ubuntu 22.04/24.04/26.04、Debian 12/13，其他发行版先按 Docker 官方文档安装。
- 预留镜像、数据库、文档与备份空间；实际要求随文件量和模型部署变化。镜像不包含本地大模型。
- 允许访问授权中心 `https://doc.abcfanyi.com` 及自己选择的模型服务。离线 ZIP 省去应用镜像拉取，不代表首次授权和 Docker 安装无需联网。

用发行页的 `SHA256SUMS.txt` 核对下载。Windows：`Get-FileHash .\安装包.zip -Algorithm SHA256`；Linux：`sha256sum -c SHA256SUMS.txt --ignore-missing`。校验值用于完整性核对，不等同独立代码签名。

## Windows：双击安装

1. 把 Windows ZIP 完整解压到专用目录，不要在压缩软件里直接运行。
2. 双击 `Start.cmd`，回车执行一键安装/继续。缺少 Docker 时按提示确认官方许可并准备环境；重启后再次运行同一入口。
3. 首次填写管理员邮箱。安装器部署 PostgreSQL / Redis，自动登记节点授权，再启动应用；就绪后打开本地工作台。
4. 在交互控制台查看有效初始账号密码；「账号与密码」可修改邮箱、名称或密码。不要公开截图密码。
5. 登录后在「模型供应商 → 快捷接入」配置自己的模型，用小文件验证后再处理正式文档。

授权中心暂不可达时，保留配置后重试，不要反复删除目录注册。原目录误删后，安装器尝试使用本机同用户加密快照恢复；缺少可靠身份材料时停止，不覆盖数据库。

## Linux：Docker 安装

解压 Linux Docker 包到专用目录，在该目录执行：

```bash
sudo bash install.sh --prepare --install-engine --admin-email owner@example.com
```

已有 Docker 可省略 `--install-engine`。准备阶段生成配置并等待 PostgreSQL / Redis 健康，不启动翻译处理。**当前 Linux 入口采用手动授权**：把节点标识提交到主站「部署授权」，将对应凭证保密保存为当前目录 `activation.json`，然后：

```bash
sudo bash install.sh --activate
```

成功后在本机私密查看 `config/bootstrap.json` 的初始邮箱与密码，登录后修改；这不是主站账号。默认工作台为 `http://localhost:8080`。

云服务器使用反向代理时，准备阶段指定 `--public-url https://node.example.com`，由主机反向代理将 HTTPS 转到本机 8080；安装器不自动签发 TLS 证书。不要将 PostgreSQL / Redis 或无认证本地模型端口映射到公网。

## 接入模型

选择预设服务商，填自己的密钥，读取或填写对话模型 ID 并保存。自定义地址必须与所选协议匹配；预设不是已购买额度，也不保证任意模型支持结构化翻译。

| 同一宿主机上的模型 | 基础地址示例 |
| --- | --- |
| Ollama | `http://host.docker.internal:11434/v1` |
| LM Studio | `http://host.docker.internal:1234/v1` |
| vLLM | `http://host.docker.internal:8000/v1` |

容器中的 `localhost` 指容器自身。模型须加载且允许容器访问；私网访问须管理员明确允许，不要取消整个主机防火墙。

## 升级与修复

暂停新任务，备份 `config/`、数据库和文件卷，将新版发行文件更新到原安装目录，不覆盖旧密码或身份。

```bash
sudo bash install.sh --upgrade
# 重新创建应用容器，保留数据：
sudo bash install.sh --reinstall
```

Windows 使用「修复 / 重新安装（保留数据）」。安装器在迁移前备份数据库并等待 Worker 收尾；自动 dump **不包含文件卷**。迁移失败时保留备份排查，不自动降级数据库。

Linux 状态：`sudo docker compose --env-file config/compose.env -f compose.yaml ps`。不要公开 `docker compose config`、完整 inspect 或环境文件输出，它们可能含密码。

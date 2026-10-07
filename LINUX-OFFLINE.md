# TransDoc 0.3.0-r13 · Linux 离线安装

本包携带 x86_64 和 ARM64 两套原生运行镜像，自动选择本机 Docker 架构，支持通用文件翻译、并发 AI 复核和可编辑 PDF。DWG 本机执行器单独适配。本包无需从 DockerHub 拉取应用、数据库、Redis 或 PDF 资源。

## 准备

1. Linux x86_64 / ARM64，建议至少 16 GB 内存、30 GB 可用磁盘（含解压包、Docker 数据盘、升级备份），大文件需更多空间。
2. 安装并启动 Docker Engine 与 Compose v2，启用 containerd 镜像存储。Docker Engine 29.0+ 新安装默认使用此存储；旧安装请按 [Docker 官方说明](https://docs.docker.com/engine/storage/containerd/) 迁移，不要删除原数据卷。
3. 将完整包解压到专用本机目录，路径可含空格；不要放在共享或符号链接目录。使用相同用户/权限级别继续安装，常规 Docker Engine 示例使用 sudo。
4. 对照发行页 `SHA256SUMS.txt` 校验下载。包内也会逐文件校验，并只导入本机架构镜像。Docker 本身安装、模型服务和授权校验仍可能需要网络。

## 安装

```bash
tar -xzf TransDoc-Linux-universal-0.3.0-r13.tar.gz -C /你的专用安装目录
cd /你的专用安装目录
sudo bash install.sh --prepare --admin-email owner@example.com
```

准备阶段仅启动 PostgreSQL / Redis，生成本节点独立身份、随机密码和管理员初始化文件。将显示的节点编号提交主站「部署授权」，将此节点返回的凭证保密保存为当前目录 `activation.json`，然后执行：

```bash
sudo chmod 600 activation.json
sudo bash install.sh --activate
```

仅在有效签名授权、迁移与健康检查通过后启动 Worker/调度。用安装器显示的地址进入工作台，默认 `http://localhost:8080`；私密查看本机 `config/bootstrap.json` 中的初始账号并登录改密。服务器的 localhost 指服务器自身，远程访问另行配置 HTTPS 反向代理或 SSH 转发。

## 升级与状态

先等待正在处理的任务完成，备份 `config/`、数据库与文件卷。将新版发行文件更新到**原安装目录**，保留 config、backups 和 Docker volumes，运行：

```bash
sudo bash install.sh --upgrade
sudo bash install.sh --status
```

升级保留原账号、节点身份、密码、模型配置和文件。迁移前执行并校验数据库备份；数据库备份不包含文件卷，不自动降级数据库。`--reinstall` 可保留数据重建应用。更换 CPU 架构应另行执行有备份的迁移，不自动接管另一台机器身份。

安装中断后从原目录重试。若提示 `.installer.lock.d`，先检查没有安装进程，再仅移除该目录的 `pid` 文件与空锁目录；不要删除 config 或卷。不要使用 `docker compose down -v` 排错。

PDF 范围与对应源码见 `PDF.md`；业务源码保护和开源组件边界见 `SOURCE-NOTICE.md`。

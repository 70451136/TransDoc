# 0.3.0-r13：PDF 与保留数据升级

本版同步最新工作台、任务列表、翻译/复核和断点恢复修复，包含 BabelDOC 0.6.4 可编辑 PDF 引擎及预下载字体、布局模型。按用户确定的发行范围，DWG 本机执行器单独适配，本包不开放 DWG 上传，不复用主站租户授权或远程执行凭证。

## PDF

支持最多 200 页、有可读取文字层的横排 PDF；纯译文和原译文交替页对照，复核或人工修订后可重新构造。扫描件、混合扫描页、损坏字符映射、加密和活动内容暂不支持。复杂版式应先用小样验证。

默认同一 Worker 容器 1 个 PDF 排版进程、最多 2 个推理线程。模型翻译/AI 复核并发仍按套餐、模型和任务策略控制。排版离线执行；翻译使用自行配置的模型，安装授权仍需周期续签，安装包不附赠模型额度。

独立 PDF 适配程序和 BabelDOC 使用 AGPL-3.0。安装后工作台提供对应源码下载，包含适配源码、上游源码、许可、依赖和构建说明。无需访问公网，可直接打开本机工作台地址下的 `/open-source/pdf-engine-0.6.4-transdoc-v1.tar.gz`。运行镜像 `/app/scripts/pdf/` 同时保留适配源码及许可。

## 从 r11 升级

先停止提交新任务并等待现有任务完成，备份 config、数据库和文件卷。将新版包完整解压到专用目录，Windows 启动 Start.cmd，由安装器识别并更新原目录；Linux 将发行文件更新到原目录后执行 `sudo bash install.sh --upgrade`；macOS 在原目录执行 `bash install.sh --upgrade`，不要使用 sudo。

保留 config、backups 和 Docker volumes，不删除节点身份，不重置数据库密码，不执行 `docker compose down -v`。安装器会在迁移前备份数据库，成功后才切换固定镜像记录；自动数据库备份不包含文件卷。失败保留数据，数据库不自动降级。

建议至少 16 GB 内存，并为 Docker 数据盘、安装包、升级回退和客户文件预留 30 GB 以上空间。Windows 仍需可用的 Docker Desktop Linux 容器/WSL2；macOS 需对应 Intel/Apple Silicon 的 Docker Desktop；许可、UAC、虚拟化或重启由使用者确认。三个安装包均携带应用、PostgreSQL 和 Redis 镜像，Linux/macOS 包同时包含 amd64 与 arm64，自动选择本机架构。

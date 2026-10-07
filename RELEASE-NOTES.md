# 0.3.0-r13 · Windows / Linux / macOS 离线预发布版

同步工作台、翻译/并发 AI 复核、任务恢复和 BabelDOC 0.6.4 可编辑 PDF，提供三个完整离线包。**DWG 本机执行器单独适配，本包不开放 DWG 上传。** 本地节点独立保存账号、配置与文件，不复制主站用户、模型密钥或执行器凭证。

## 下载与安装

| 安装包 | 架构 | 入口 |
| --- | --- | --- |
| TransDoc-Windows-x64-0.3.0-r13.zip | Windows x64 / Linux 容器 | Start.cmd，附中文安装说明 |
| TransDoc-Linux-universal-0.3.0-r13.tar.gz | x86_64 / ARM64 | install.sh，附 README.md |
| TransDoc-macOS-universal-0.3.0-r13.zip | Intel / Apple Silicon | Start.command，附 README.md |

三个包都携带应用、PostgreSQL、Redis 镜像与 PDF 字体/布局资源，不需要访问镜像仓库或编译业务源码。Docker 本身、首次授权、周期续签以及所选云模型仍可能联网。Linux/macOS 自动选择本机原生架构，只允许本机 Docker Unix socket；不向远程 Docker 传递配置。

Windows 保留自动登记授权流程，Linux/macOS 准备完成后仍需手动导入本节点授权。安装步骤见 [INSTALL](INSTALL.md)、[Linux](LINUX-OFFLINE.md)、[macOS](MACOS-OFFLINE.md)；模型配置与 PDF 范围见 [PDF](PDF.md)。

## 版本与源码边界

应用 0.3.0，安装器 revision 13，镜像兼容契约 7。两种架构的最终前后端应用均来自提交 `a839896f13f2824560bd15b05bf2644cd6f24222`；r13 更新安装器与发行资料，不混用其他业务版本。

业务 services/packages 仅交付字节码，前端不含 sourcemap，不含私有 Git 历史、客户文件或密钥。字节码仍可反编译，不能承诺绝对防逆向。独立 AGPL PDF 适配程序及对应上游源码按许可提供，可从发行附件或本机 `/open-source/pdf-engine-0.6.4-transdoc-v1.tar.gz` 获取；详见 [源码与许可说明](SOURCE-NOTICE.md)。

## 验证范围

- 49 项相关回归通过，包括包白名单、校验和、架构匹配、错误包拒绝以及下载失败不安装。
- 三个最终包逐成员 SHA256 校验通过；Windows 包通过真实 PowerShell 5.1 / Docker 验证；Mac ZIP 保留脚本执行权限。
- amd64 冷安装与 r11 升级验证通过，完整 92 项迁移、管理员初始化幂等、原密码、节点身份及配置保留。
- 实际 Unix 安装器完成准备、激活、备份、升级和状态检查；全程使用隔离测试数据与临时签名授权，无真实模型调用。
- ARM64 原生镜像在 x64/QEMU 下通过完整迁移、账号、签名授权、Web/API 健康和处理进程启动。QEMU 触发 Redis ARM 内存自检，测试夹具关闭 Redis 持久化并单独跳过该项；正式发行包保留 Redis 原安全检查与持久化。此项不代表 ARM 硬件的持久化验收。
- 已在真实 Apple Silicon Mac 上验证系统 Bash 3.2、脚本语法、机器标识、校验与安装锁；该 Mac 未装 Docker，因此没有完成 Mac Docker Desktop 的完整安装验收。Windows 首次安装 Docker Desktop 的 UAC/重启流程也未在空白机器上覆盖。
- amd64 与 ARM64 PDF 均完成断网解析、纯译文、交替页对照及人工修改重构，中文仍可编辑、数字与图形保留。ARM64 通过 QEMU 验证，不将仿真耗时当作真实硬件性能。

## 扫描结果

2026-10-07 的最终镜像 Docker Scout 扫描：两种架构的 Web 均无检出漏洞；runtime 均有 2 HIGH、1 MEDIUM、26 LOW，未检出 CRITICAL。两项 HIGH 为 `CVE-2026-95619`（Debian gcc-14）与 `CVE-2026-85091`（Debian zlib），扫描器标记暂无修复版本。发行附件提供按架构归档的脱敏扫描摘要，不将已处理可修复告警表述为零漏洞。

## 保留数据升级

先等待活动任务结束，备份 config、数据库及文件卷。Windows 由新版安装器识别原目录；Linux/macOS 将发行文件更新到原目录后运行 `install.sh --upgrade`。不要删除卷或重置密码；迁移前自动备份数据库，但自动备份不包含文件卷，数据库不自动降级。

默认永久授权没有商业到期日，仍需周期校验；第三方模型、Docker Desktop 和基础设施费用不包含在内。详见 [隐私与安全边界](SECURITY.md)。

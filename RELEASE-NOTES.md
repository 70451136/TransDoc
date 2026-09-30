# 0.2.1-r11 · 本地部署预发布版

这是 Docker 独立部署版本，不是主站源码或 Windows 原生容器版。建议先用合成或非敏感文件验收，再用于正式业务。

## 本轮更新

- 发布独立 Windows 离线安装包和 Linux Docker 安装包，自动准备 PostgreSQL 17、Redis 7.4 与应用迁移。
- 前后端应用版本、完整构建标识、安装器契约一致；在线包固定镜像摘要，离线包校验镜像实际内容。
- 更新 Nginx、加密依赖，移除未使用的前端动态模块；验证旧版加密配置兼容性。
- 公开仓库只包含安装器、文档与品牌插画；修复 Windows/Linux 换行导致的校验和差异。
- 补全安装、备份、授权、隐私、反馈与私密漏洞报告说明。

## 验证边界

已执行最终镜像源码排除、API/Worker 导入、独立 Docker 冷安装、90 个数据库迁移、管理员初始化幂等、签名授权与 API/Web 健康检查。测试只用合成数据，不调用真实付费模型。

Windows 首次安装 Docker Desktop 并经过 UAC/重启的全过程、ARM64、所有云厂商及真实业务文件仍未全部验收。复杂格式和重要译文需要人工复核。安装器不会绕过 Docker Desktop 许可、虚拟化和系统重启要求。

## 剩余安全告警

2026-09-30 的 Docker Scout 扫描仍报告运行镜像 Debian 基础层两项 HIGH：`CVE-2026-84782`（OpenSSL）与 `CVE-2026-85091`（zlib），扫描器标记暂无修复版本。扫描结果、上游版本范围和应用实际可达性不完全等价；本发行不把这些告警隐藏或宣称已解决。参考 [OpenSSL 公告](https://openssl-library.org/news/vulnerabilities/) 与 [Debian zlib 跟踪](https://security-tracker.debian.org/tracker/CVE-2026-85091)。

本版本默认仅监听本机，数据库和 Redis 不发布端口。风险敏感环境应暂缓采用，至少先在隔离测试环境评估；不要直接暴露公网。后续使用修补后的固定镜像升级，不使用随意混搭的浮动标签。

## 安装与升级

**复制即可下载并开始安装：[Windows / Linux 命令](https://github.com/70451136/TransDoc#下载并开始安装)**。Windows 进入一键流程；Linux 准备环境后仍需手动授权。命令校验固定附件 SHA256，遇到已有目录停止覆盖；`docker pull` 仅下载镜像，不是安装。这是文档更新，未替换本发行镜像或附件。

Windows 下载 ZIP 后完整解压、运行 `Start.cmd`；Linux 依照 [INSTALL](INSTALL.md) 准备与手动激活。保留原配置、节点身份和数据卷。重装不是清空；升级前备份数据库、配置与文件，迁移后不承诺自动数据库降级。

永久免费授权没有商业到期日，但需周期校验；第三方模型和基础设施费用不包含在内。详见 [README](README.md) 和 [SECURITY](SECURITY.md)。

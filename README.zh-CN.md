# S-UI

**基于 SagerNet/sing-box 的增强型 Web 与移动端管理面板**

[English](README.md) | [简体中文](README.zh-CN.md)

## 本分支相对上游新增的功能

本仓库基于 [alireza0/s-ui](https://github.com/alireza0/s-ui) 扩展，并保留原有 sing-box 管理模型。以下内容由本分支持续维护：

- Android arm64 与 iPhone arm64 管理 App，同时提供可视化编辑和原始 JSON 编辑。
- 稳定的 `/apiv3` API，覆盖资源、用户、用量与统计、连接详情、日志、审计、备份、工具和服务操作。
- App 支持任意自定义请求 Header，并预置 Cloudflare Access Service Token 字段。
- 用量、统计、日志和审计支持用户、日期、关键词筛选；连接统计可按用户、入站、出站、Endpoint 和目标地址查看详情。
- Web 与 App 均提供可检索的多级别系统日志和管理员变更记录。
- 订阅用户信息可分别控制上传、下载、总量、到期时间以及节点名中的剩余额度。
- OIDC/SSO、TOTP 两步验证、一次性恢复码和 WebAuthn 通行密钥。
- 管理员密码使用 bcrypt；旧明文密码会在成功登录后自动迁移。
- Web 与 App 的页面结构和功能对齐，包含用户、资源、TLS、核心配置、统计、日志、管理员、设置和工具。
- 英语、波斯语、越南语、简体中文、繁体中文、俄语、日语、法语和拉丁语界面。
- 历史流量图不会无意义地周期刷新，并提供独立的实时模式。
- Tag 构建产物和 Release 文件名均携带版本号；GitHub Actions 保持五个上游工作流，并新增移动端 CI 与 App 构建。
- 全新的 WireGuard Endpoint 管理：服务端地址归属与客户端路由彻底分离、安全的分流默认值、IPv4/IPv6 校验、独立的客户端连接地址、受控配置/二维码导出、Peer 互通规则以及失败回滚。

移动端源码位于 [`mobile/`](mobile/README.md)。Android arm64 和未签名 iPhone arm64 产物全部通过 GitHub Actions 构建。

## WireGuard 配置要点

- **服务端 Endpoint 地址**代表 S-UI 自身，通常使用 IPv4 `/32` 和 IPv6 `/128`，例如 `10.66.66.1/32`、`fd66:66:66::1/128`。
- **WireGuard 虚拟网段**是分配地址的范围，例如 `10.66.66.0/24`、`fd66:66:66::/64`，不能写入服务端 Endpoint 地址。
- **服务端 Peer allowed_ips**用于地址归属和来源校验，每个 Peer 必须使用独占的 `/32`、`/128`。
- **客户端 AllowedIPs**决定哪些目标流量进入隧道。新 Peer 默认仅路由 WireGuard 虚拟网段；只有明确选择“全局代理”时才会导出 `0.0.0.0/0`、`::/0`。
- **客户端连接域名/IP 与端口**必须指向真正接收 WireGuard UDP 的入口，不会自动使用可能位于 Cloudflare Access 或 HTTP 反代后的面板域名。
- **漫游客户端**不会向 sing-box 服务端 Peer 写入远端地址和端口；静态 Peer 与站点到站点模式才使用这些字段。
- **允许 Peer 互通**使用独立的受管路由表生成规则，不重复用户已有的等价规则，关闭时也不会删除用户规则。

“保存”只保存经过完整校验的配置，不改变当前运行状态；“保存并应用”会检查完整 sing-box 配置、同步重启核心并确认运行状态，失败时恢复上一份可运行配置。数据库升级只新增受管路由表；WireGuard 编辑元数据继续兼容现有 Endpoint 数据结构。

## 身份认证配置

### OIDC / SSO

在“设置 → 登录与身份认证”中填写 Issuer、Client ID、Client Secret、Scopes、用户名 Claim 与允许的身份。回调地址必须与 OIDC 提供商中登记的地址完全一致。默认 Web Path 下通常为：

```text
https://panel.example.com/app/api/oidc-callback
```

### TOTP / 2FA

在“管理员 → 登录安全”中启用。请立即保存生成的一次性恢复码；每个恢复码只能使用一次。

### WebAuthn 通行密钥

在“设置 → 登录与身份认证”中启用，然后从“管理员 → 登录安全”添加。通常可以留空 RP ID 和 Origins，S-UI 会根据浏览器 Origin 以及 `Forwarded`、`X-Forwarded-Host`、`X-Forwarded-Proto` 自动识别反代后的管理域名。特殊代理结构可手动指定完整 HTTPS Origin 和仅包含域名的 RP ID。

## 默认安装信息

- 面板端口：`2095`
- 面板路径：`/app/`
- 订阅端口：`2096`
- 订阅路径：`/sub/`
- 默认账号/密码：`admin` / `admin`

完整安装、Docker、升级、环境变量和开发说明请参阅默认英文文档：[README.md](README.md)。

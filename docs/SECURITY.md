# 安全说明

## 身份验证

Node Warden 只有一个访问密钥，没有用户名和多用户账户。

- 密钥经 SHA-256 后保存在 panel.env 的 PANEL_KEY_SHA256；登录时比较摘要。
- /var/lib/node-warden/access-key 保存一份明文恢复副本，权限 0600，仅 root 可读。它不是登录校验来源；删除后不影响已有密钥。
- 登录成功后签发 HMAC 签名的会话 cookie，默认 12 小时有效。
- cookie 包含 key id。网页修改密钥后 key id 改变，所有旧 cookie 立即失效。
- 所有 POST 请求必须带 X-CSRF-Token；服务端同时校验 Origin。
- 登录失败按客户端 IP 限速，默认 5 分钟内超过 8 次失败后拒绝。

## 网络暴露

- 面板默认只监听 127.0.0.1:9090。
- 对外必须经过 HTTPS 反向代理；不要直接把 9090 映射到公网。
- 反向代理必须传递 X-Real-IP。PANEL_TRUST_PROXY=1 时，只有来自 loopback 的请求才会信任这个头。
- 建议在反向代理层再加访问控制，例如只允许固定管理 IP。

## 代理组件

bootstrap.sh 可以安装 GitHub 下载代理和 Docker 镜像代理。两者都只监听 127.0.0.1，但仍属于可被本机或网关转发访问的网络服务：

- GitHub 下载代理默认 127.0.0.1:8082，只转发允许的 GitHub 主机名，但任何能访问该端口的人都可以用它下载这些主机上的内容。网关必须限制来源 IP。
- Docker 镜像代理默认 127.0.0.1:8080，修正层 127.0.0.1:8081。它们不提供身份验证，不能直接暴露到公网。
- bootstrap.sh 的 cn-setup 会修改 APT 源、sysctl 和可选的 Docker daemon.json，并在 /var/backups/node-warden-cn 下保留原文件；恢复前应确认备份完整。

## 命令执行边界


网页请求不能提交 shell 命令、路径或 unit 名。

- 服务 id、动作 id、日志源 id 都必须存在于 root 所有的 /etc/node-warden/services.json。
- 动作到 argv 的映射写在 app/systems.py；使用 subprocess.run(argv)，不经过 shell。
- 备份路径也来自同一份清单，只能位于 PANEL_BACKUP_ALLOWED_ROOTS 下。
- 日志文件只能读取 /var/log 下的路径。

这降低了面板被利用后执行任意命令的风险，但不能替代操作系统权限控制。面板以 root 运行，任何后端代码漏洞都可能导致 root 权限。

## 密钥轮换

在“设置”中修改访问密钥需要：

1. 已登录会话；
2. 当前访问密钥；
3. 新密钥，长度 10 到 256 个字符，不能包含空白字符。

成功后服务端重写 panel.env 中的 PANEL_KEY_SHA256，写入 access-key 恢复副本，并更新会话 key id。旧会话立即失效。

## 备份

- 备份归档包含配置文件、证书和私钥，必须视为敏感数据。
- 归档由服务进程创建，unit 设置 UMask=0077，归档默认权限 0600。
- 下载接口需要登录；不要公开转发下载链接。
- 单个备份上限 256 MiB；最多保留 20 个，按时间删除旧备份。
- 建议把备份复制到独立存储，并定期验证可恢复性。

## 审计

审计日志位于 /var/lib/node-warden/audit.log，记录时间、动作、来源 IP 和结果。写入时如果单文件超过 5 MiB，会滚动到 audit.log.1。install.sh 在系统存在 logrotate 时安装 /etc/logrotate.d/node-warden，按天或达到 5 MiB 轮转，保留 14 份并压缩。没有 logrotate 时仍保留程序内的单文件滚动，但不会保留历史压缩包。

## 当前限制

- 单密钥，没有多用户和权限分级。
- 面板进程以 root 运行。
- 不提供防暴力破解的账户锁定，只有按 IP 的登录限速。
- 不校验备份归档内容，只校验路径和大小。
- 没有内置 TLS 终止；必须由反向代理提供 HTTPS。
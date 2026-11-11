# API

所有接口都位于面板基础路径下，默认前缀是 /warden。

除登录和会话查询外，GET 接口需要有效的会话 cookie；POST 接口还需要 X-CSRF-Token。

## 会话

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | /api/session | 当前会话；未登录时 authenticated 为 false |
| POST | /api/login | 请求体 {key}；成功返回会话，失败 401，限速 429 |
| POST | /api/logout | 注销当前会话 |
| POST | /api/key/change | 请求体 {current_key, new_key}；成功返回新会话 |

会话对象包含 authenticated、csrf、issued_at、expires_at、key_fingerprint、version、base_path。

## 总览和服务

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | /api/overview | 主机、证书、服务、端口、审计和备份摘要 |
| GET | /api/services | 服务列表 |
| GET | /api/metrics?hours=24&points=96 | 主机和服务时间序列；hours 支持 1、6、24、72，points 为 24 到 288 |
| GET | /api/proxies | Docker、GitHub 和网关代理的探测、请求数和流量 |
| GET | /api/services/{id}/logs?source={source}&tail={n} | 读取一个日志源 |
| POST | /api/services/{id}/action | 请求体 {action}；执行清单允许的动作 |

overview 中每个服务包含 status、health、uptime 和可选的 metrics。uptime 包含 24 小时样本、可用率、中断列表和最后采样时间。

metrics 返回 host_series（ts、cpu、memory_percent、load1、rx_bps、tx_bps、disk_read_bps、disk_write_bps、tcp_connections）以及每个服务的 service_series（ts、samples、up、pct、latency_ms）。

proxies 返回 docker、ghproxy、gateway 三项，每项包含 probe（ok、status、latency_ms、error）、traffic（requests、bytes、status 分布、top_paths）和可用的 detail。代理探测失败时 probe.ok 为 false，不会影响其他项。

## sing-box

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | /api/singbox | 版本、配置文件和入站摘要 |
| GET | /api/singbox/config?file={id} | 查看配置；默认打码敏感字段 |
| POST | /api/singbox/reveal | 请求体 {key}；再次验证访问密钥后返回分享链接 |

配置文件的 id 是 main 或 conf:文件名。

## 备份

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | /api/backups | 列出备份 |
| POST | /api/backups | 请求体 {}；按清单创建备份 |
| GET | /api/backups/{id}/download | 下载归档 |
| POST | /api/backups/{id}/delete | 请求体 {}；删除备份 |

备份 id 由服务端生成，格式为 backup-YYYYMMDDTHHMMSSZ；同一秒重复创建时追加 -N 后缀。

## 证书、审计和设置

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| POST | /api/cert/renew | 请求体 {}；执行 certbot renew --dry-run |
| GET | /api/audit?limit={n}&q={text} | 读取审计记录 |
| GET | /api/settings | 面板信息 |

## 错误格式

错误响应为 JSON，包含 error 字段。常见状态码：

- 400：请求格式错误；
- 401：未登录或密钥错误；
- 403：Origin/CSRF 校验失败；
- 404：路由、服务或备份不存在；
- 429：登录失败次数过多；
- 500：后端执行失败。

审计、备份和证书时间使用 UTC 字符串；会话的 issued_at 和 expires_at 是 Unix 秒。
# Node Warden

Node Warden 是运行在单台 Linux 服务器上的服务管理控制台。它管理 Docker 容器、systemd 服务、sing-box、TLS 证书和配置备份，并显示主机资源、服务状态、可用率和最近操作。

面板本身只监听 127.0.0.1。bootstrap 默认安装并配置 nginx 网关，也可以复用服务器上已有的反向代理。

## 功能

- 主机总览：CPU、内存、磁盘、负载、运行时间、证书剩余天数和监听端口。
- 指标：主机网络、磁盘、TCP 连接、进程和 24 小时趋势；服务可用率。
- 代理：Docker 镜像代理、GitHub 下载代理和网关的探测、请求数与流量。
- 服务状态：Docker 容器、systemd 服务和 sing-box 的运行状态、健康检查、24 小时可用率、CPU 和内存。
- 服务操作：启动、停止、重启；nginx 配置测试和 reload；sing-box 配置检查。
- sing-box：入站列表、配置查看、配置检查、连接信息揭示和分享链接。
- 配置备份：按服务清单中的固定路径创建、列出、下载和删除 tar.gz 备份。
- 证书：显示证书信息，调用 certbot dry-run 检查续期。
- 访问密钥：在设置页修改；修改后旧会话立即失效。
- 审计日志：记录登录、退出、密钥修改、服务操作、备份和证书操作。

## 安全模型

- 面板以 root 运行，因为需要调用 Docker、systemctl、journalctl 和 certbot。
- 默认监听 127.0.0.1:9090，不应直接暴露到公网；bootstrap 默认安装 nginx 网关并提供 HTTPS，也可使用已有反向代理。
- 访问密钥只接受一个；校验使用 /etc/node-warden/panel.env 中的 SHA-256 摘要，/var/lib/node-warden/access-key 另存一份权限为 600 的 root-only 恢复副本。
- 会话 cookie 使用 HMAC 签名，默认 12 小时有效；所有写操作还需要 CSRF 请求头。
- 登录失败按客户端 IP 限速；反向代理必须传递 X-Real-IP。
- 服务、动作、健康检查和日志源全部来自 root 所有的 JSON 清单；HTTP 请求只能提交清单中已有的 id，不能提交命令、路径或 unit 名。
- 备份归档包含配置和私钥，归档权限由服务的 UMask=0077 控制；下载备份需要已登录会话。

## 安装要求

- Ubuntu 22.04/24.04 或 Debian 12
- Python 3.10 或更高版本
- systemd
- curl、tar
- nginx、certbot（未安装时由 bootstrap 通过 apt 安装）
- 80/443 端口可用（使用已有反向代理时可不占用）
- Docker（仅在使用 Docker 服务时需要）

## 统一入口

### 远程安装

新机器不需要先下载源码。直接执行下面这一行，脚本会进入安装向导，安装完成后打印访问地址：

~~~bash
sudo bash -c 'bash <(curl -fsSL https://raw.githubusercontent.com/tktogether/node-warden/main/bootstrap.sh) install'
~~~

需要无人值守时，在命令后加安装参数。脚本发现当前目录没有 app 和 static 后，会按顺序尝试下载源码压缩包：

1. 环境变量或参数指定的地址；
2. GitHub 直连；
3. codeload.github.com；
4. 指定的 GitHub 代理；
5. ghfast.top、gh-proxy.com。

GitHub 直连、raw 和 codeload 都可能被网络阻断。国内机器建议优先使用可用的代理或镜像地址。

~~~bash
# GitHub raw
sudo bash -c 'bash <(curl -fsSL https://raw.githubusercontent.com/tktogether/node-warden/main/bootstrap.sh) install --non-interactive --public-url https://panel.example.com/warden'

# jsDelivr 镜像脚本
sudo bash -c 'bash <(curl -fsSL https://cdn.jsdelivr.net/gh/tktogether/node-warden@main/bootstrap.sh) install --non-interactive --public-url https://panel.example.com/warden'

# 自建 GitHub 代理；同时把源码下载也走该代理
sudo bash -c 'bash <(curl -fsSL https://proxy.example.com/https://raw.githubusercontent.com/tktogether/node-warden/main/bootstrap.sh) install --github-proxy https://proxy.example.com --non-interactive --public-url https://panel.example.com/warden'

# 明确指定源码地址，可给多个地址，按空格分隔
sudo NW_ARCHIVE_URLS="https://mirror.example.com/node-warden.tar.gz https://github.com/tktogether/node-warden/archive/refs/heads/main.tar.gz" \
  bash <(curl -fsSL https://raw.githubusercontent.com/tktogether/node-warden/main/bootstrap.sh) install --non-interactive --public-url https://panel.example.com/warden
~~~

远程执行时，脚本在临时目录解压源码，安装结束后清理临时目录。也可以先用 --source-dir 指定已经解压的源码目录。

源码下载相关参数：

| 参数 | 环境变量 | 说明 |
| --- | --- | --- |
| --source-dir DIR | NW_SOURCE_DIR | 本地源码目录，存在 app 和 static 时不再下载 |
| --archive-url URL | NW_ARCHIVE_URL | 单个源码压缩包地址 |
| --archive-urls LIST | NW_ARCHIVE_URLS | 多个地址，按顺序尝试 |
| --github-proxy URL | NW_GITHUB_PROXY | GitHub 下载代理前缀，例如 https://proxy.example.com |
| --repo OWNER/REPO | NW_REPO | 源码仓库，默认 tktogether/node-warden |
| --branch BRANCH | NW_BRANCH | 源码分支，默认 main |

面板安装后还会在面板地址下的 bootstrap.sh 提供同一份脚本，例如 https://panel.example.com/warden/bootstrap.sh。安装结束时脚本会打印国内网络设置所需的命令；交互安装还会询问是否现在执行。

### 本地安装

在终端直接执行 install 会进入安装向导。向导依次询问安装组件、面板路径，以及面板域名或完整 URL。脚本会尝试从已安装面板、certbot 证书和主机名中读取域名，作为向导的默认值。

~~~bash
sudo bash bootstrap.sh install
~~~

不需要交互时，可以一次给出全部参数：

~~~bash
sudo bash bootstrap.sh install --non-interactive --public-url https://panel.example.com/warden
~~~

没有域名时，脚本使用公网 IP 和 HTTP 地址；无法检测公网地址时，使用 http://127.0.0.1:9090/warden，需要通过 SSH 隧道访问。安装脚本会在 80/443 空闲时安装并配置 nginx 网关；指定域名时自动申请证书，证书失败时回退 HTTP。已有反向代理时加 --no-gateway。

常用安装参数：

| 参数 | 说明 |
| --- | --- |
| --public-url URL | 面板完整访问地址，路径必须等于面板路径 |
| --domain DOMAIN | 只给域名，脚本自动拼成 https://DOMAIN/warden |
| --email EMAIL | ACME 证书邮箱 |
| --no-auto-cert | 不自动申请证书 |
| --no-gateway | 不安装或修改 nginx 网关，使用已有反向代理 |
| --yes, -y | 跳过安装确认 |
| --non-interactive | 不显示安装向导 |

默认行为：

- 安装 Node Warden，监听 127.0.0.1:9090；
- 安装并配置 nginx 网关（80/443），指定域名时自动申请证书；
- 安装 GitHub 下载代理，监听 127.0.0.1:8082；
- 安装 Docker 镜像代理，监听 127.0.0.1:8080 和修正层 127.0.0.1:8081；
- 若未安装 Docker，尝试用 apt-get 安装 docker.io；不需要时加 --skip-docker-install；
- 显示安装后的组件状态。

如果只安装面板：

~~~bash
sudo bash bootstrap.sh install --panel-only --public-url https://panel.example.com/warden
~~~

服务清单可用 --services FILE 指定。首次安装会复制为 /etc/node-warden/services.json；后续升级保留已有清单。

### 日常命令

~~~bash
sudo bash bootstrap.sh update
sudo bash bootstrap.sh status
sudo bash bootstrap.sh uninstall
sudo bash bootstrap.sh uninstall --purge
sudo bash bootstrap.sh self-test
~~~

update 在源码目录是 git 仓库时执行 git pull；源码来自压缩包时重新下载并解压；没有 git 远程仓库时使用当前目录。随后升级面板并重建代理容器。uninstall 默认保留面板配置和数据，--purge 同时删除。

### 国内机设置与恢复

~~~bash
sudo bash bootstrap.sh cn-setup
sudo bash bootstrap.sh cn-setup --docker-mirror https://docker.example.com
sudo bash bootstrap.sh cn-restore
~~~

cn-setup 会修改 APT 源（默认 mirrors.aliyun.com）、启用 BBR，并在指定 --docker-mirror 时写入 Docker 的 registry-mirrors。修改前把文件备份到 /var/backups/node-warden-cn/<时间>/，cn-restore 读取该备份恢复。

所有命令都支持 --dry-run，只打印将执行的变更。

### 自定义反向代理

使用 --no-gateway 时，面板和代理只监听 127.0.0.1，需要由已有网关转发。nginx 示例：

~~~nginx
location = /warden {
    return 301 /warden/;
}

location /warden/ {
    proxy_pass http://127.0.0.1:9090;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_read_timeout 240s;
    proxy_send_timeout 240s;
    client_max_body_size 64k;
}
~~~

注意：proxy_pass 不要带 URI 后缀。Node Warden 自己处理 /warden 前缀，重写路径会导致 404。

GitHub 下载代理和 Docker 镜像代理的对外路由由网关配置决定；不要让它们在没有来源限制的情况下直接暴露到公网。

### 登录

打开 https://panel.example.com/warden/，输入安装时显示的访问密钥。登录后进入“设置”，修改访问密钥。修改后当前会话会更新，其他已登录会话立即失效。
## 服务清单

服务清单是 /etc/node-warden/services.json，权限 600，只有 root 可写。结构如下：

~~~json
{
  "services": [
    {
      "id": "gateway",
      "name": "网关",
      "kind": "systemd",
      "target": "nginx.service",
      "description": "对外 nginx 网关",
      "order": 10,
      "actions": ["restart", "start", "stop"],
      "health": {"type": "http", "url": "http://127.0.0.1:8083/__status", "expect": [200]},
      "logs": [{"id": "journal", "type": "journal", "label": "服务日志"}]
    }
  ],
  "backups": [
    {"id": "panel-config", "label": "面板配置", "path": "/etc/node-warden"}
  ]
}
~~~

### 服务字段

| 字段 | 说明 |
| --- | --- |
| id | 小写字母、数字和连字符，1 到 41 个字符，唯一 |
| name | 显示名称，最多 80 个字符 |
| kind | docker、systemd 或 singbox |
| target | Docker 容器名，或 systemd unit 名 |
| description | 可选说明 |
| order | 显示顺序，数字 |
| nginx | Docker 容器内是否可执行 nginx -t 和 nginx -s reload |
| actions | 允许的操作，见下表 |
| health | 健康检查，见下表 |
| logs | 日志源列表，最多 10 个 |

### 操作

| kind | 允许的 actions |
| --- | --- |
| docker | restart、start、stop、test、reload |
| systemd | restart、start、stop |
| singbox | restart、start、stop、check |

test 和 reload 只对 nginx=true 的 Docker 服务开放，执行 docker exec 容器 nginx 命令。check 执行 sing-box check。

### 健康检查

- http：url、expect（HTTP 状态码列表）、insecure（可选）。
- tcp：targets 数组，每项包含 host 和 port，最多 8 个。
- cert：domain，可选 connect_host 和 connect_port。
- none：不检查。

### 日志

- docker：读取容器日志，可省略 target，默认使用服务的 target。
- journal：读取 systemd journal，可省略 unit，默认使用服务的 target。
- file：读取 /var/log 下的文件，路径必须在 /var/log 内。

### 备份

backups 是顶层数组，每项包含 id、label 和 path。path 必须是绝对路径，并位于 PANEL_BACKUP_ALLOWED_ROOTS 内，默认为 /etc、/root、/var/www、/opt。HTTP 请求不能选择路径。

## 常用配置

/etc/node-warden/panel.env 是 systemd 的 EnvironmentFile。常用项：

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| PANEL_PUBLIC_URL | 由安装脚本写入 | 对外 URL，路径必须等于 base path |
| PANEL_BASE_PATH | /warden | 面板路径 |
| PANEL_SESSION_TTL | 43200 | 会话有效秒数，300 到 604800 |
| PANEL_TRUST_PROXY | 1 | 是否信任本机反向代理的 X-Real-IP |
| PANEL_MONITOR_INTERVAL | 60 | 采样间隔秒数，10 到 3600 |
| PANEL_HISTORY_RETENTION_DAYS | 7 | 历史保留天数 |
| PANEL_CERT_DOMAIN | 当前域名 | 证书检查和 certbot 使用的域名 |
| PANEL_NODE_HOST | 证书域名 | sing-box 分享链接中使用的主机名 |
| PANEL_DOCKER_MIRROR_URL | https://证书域名/v2/ | Docker 代理探测地址 |
| PANEL_GHPROXY_STATS_URL | http://127.0.0.1:8082/__stats | GitHub 代理统计地址 |
| PANEL_GATEWAY_URL | https://证书域名/ | 网关对外根地址，用于代理探测 |
| PANEL_GATEWAY_CONFIG | /root/gateway/nginx.conf | 网关配置文件路径 |
| PANEL_GATEWAY_ACCESS_LOG | /root/gateway/logs/access.log | 网关访问日志路径 |
| PANEL_GATEWAY_STATUS_URL | http://127.0.0.1:8083/__status | 网关 stub_status 地址 |
| PANEL_ALERT_WEBHOOK | 空 | 可选告警 webhook |

修改 panel.env 后执行 systemctl restart node-warden。不要在网页修改这个文件。

## 升级

推荐使用统一入口：

~~~bash
sudo bash bootstrap.sh update
~~~

它会在源码目录执行 git pull，然后升级面板并重建代理容器。只更新面板也可以执行：

~~~bash
cd /opt/node-warden-src
git pull
sudo bash deploy/upgrade.sh
~~~

升级会替换程序文件并重启服务，保留 /etc/node-warden/services.json、panel.env、访问密钥和历史数据。

## 卸载

~~~bash
sudo bash bootstrap.sh uninstall
sudo bash bootstrap.sh uninstall --purge
~~~

默认保留配置和数据；使用 --purge 同时删除 /etc/node-warden 和 /var/lib/node-warden。只删除面板时使用 `deploy/uninstall.sh`。

## 开发检查

~~~bash
bash scripts/check.sh
~~~

该脚本运行 Python 编译检查、单元测试和 JavaScript 语法检查。

## 目录

~~~text
bootstrap.sh             安装、更新、卸载、国内机设置入口
app/                     Python 后端
static/                  单页前端
deploy/                  systemd unit、安装、升级、卸载脚本
examples/                服务清单示例
docs/                    部署、API 和安全说明
tests/                   单元测试
scripts/                 本地检查脚本
~~~

## 故障排查

### 502 Bad Gateway

~~~bash
systemctl status node-warden
journalctl -u node-warden -n 80 --no-pager
curl -i http://127.0.0.1:9090/warden/api/session
~~~

先确认服务在本机监听，再检查反向代理的 proxy_pass 和路径。

### 登录返回 401 或 429

401 表示密钥错误；如果刚修改过密钥，请使用新密钥。429 表示同一 IP 的失败次数过多，等待限速窗口结束。反向代理没有传 X-Real-IP 时，所有请求会被当作来自 127.0.0.1。

### 服务操作失败

面板只执行服务清单允许的固定命令。检查容器名、unit 名和动作是否匹配；查看服务卡片的输出和 journalctl。

### 证书检查失败

确认 /etc/letsencrypt/live 下有对应域名证书，且本机 443 端口可连接。certbot dry-run 需要 certbot 已安装，并需要能完成 ACME 验证。

### 备份创建失败

检查备份路径是否存在、是否位于允许根目录内，以及磁盘剩余空间。单个备份上限为 256 MiB。

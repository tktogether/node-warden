# 部署

本文说明 Node Warden 在单台 Linux 服务器上的安装、网关、升级和卸载。

## 1. 前置条件

- Ubuntu 22.04 或 24.04，或 Debian 12
- systemd
- Python 3.10 或更高版本
- curl、tar
- Docker 仅在使用 kind 为 docker 的服务时需要
- 80/443 端口可用；bootstrap 会自动安装 nginx 和 certbot，也可以使用已有反向代理

面板以 root 运行，并使用 Docker、systemctl、journalctl、certbot 和 sing-box 的固定命令。

## 2. 安装文件

把仓库复制到服务器：

~~~bash
sudo mkdir -p /opt/node-warden-src
sudo cp -a node-warden/. /opt/node-warden-src/
cd /opt/node-warden-src
~~~

## 3. 服务清单

复制并修改示例：

~~~bash
sudo cp examples/services.example.json /tmp/services.json
sudo editor /tmp/services.json
~~~

至少需要修改：

- Docker 容器名；
- systemd unit 名；
- 健康检查地址和期望状态码；
- 备份路径。

清单中的 id 会用于网页请求，不能包含空格或斜杠。

## 4. 统一入口（推荐）

仓库根目录的 bootstrap.sh 同时管理面板、GitHub 下载代理和 Docker 镜像代理。

### 远程安装（推荐）

新机器不需要先下载源码，直接执行下面这一行。脚本会进入安装向导，安装完成后打印访问地址。

~~~bash
sudo bash -c 'bash <(curl -fsSL https://raw.githubusercontent.com/tktogether/node-warden/main/bootstrap.sh) install'
~~~

需要无人值守时，使用下面的完整参数。脚本发现当前目录没有 app 和 static 后，会按顺序尝试 GitHub 直连、codeload、指定的 GitHub 代理、ghfast.top、gh-proxy.com 和 ghproxy.net。可用参数和环境变量覆盖地址。

~~~bash
sudo bash -c 'bash <(curl -fsSL https://raw.githubusercontent.com/tktogether/node-warden/main/bootstrap.sh) install --non-interactive --public-url https://panel.example.com/warden'
sudo bash -c 'bash <(curl -fsSL https://cdn.jsdelivr.net/gh/tktogether/node-warden@main/bootstrap.sh) install --non-interactive --public-url https://panel.example.com/warden'
sudo bash -c 'bash <(curl -fsSL https://proxy.example.com/https://raw.githubusercontent.com/tktogether/node-warden/main/bootstrap.sh) install --github-proxy https://proxy.example.com --non-interactive --public-url https://panel.example.com/warden'
~~~

| 参数 | 环境变量 | 说明 |
| --- | --- | --- |
| --source-dir DIR | NW_SOURCE_DIR | 使用本地源码目录 |
| --archive-url URL | NW_ARCHIVE_URL | 单个源码压缩包 |
| --archive-urls LIST | NW_ARCHIVE_URLS | 空格分隔的多个地址 |
| --github-proxy URL | NW_GITHUB_PROXY | GitHub 下载代理前缀 |
| --repo OWNER/REPO | NW_REPO | 源码仓库，默认 tktogether/node-warden |
| --branch BRANCH | NW_BRANCH | 源码分支，默认 main |

安装向导相关参数：

| 参数 | 说明 |
| --- | --- |
| --public-url URL | 面板完整访问地址，路径必须等于面板路径 |
| --domain DOMAIN | 只给域名，自动拼成 https://DOMAIN/warden |
| --email EMAIL | ACME 证书邮箱 |
| --no-auto-cert | 不自动申请证书 |
| --no-gateway | 不安装或修改 nginx 网关，使用已有反向代理 |
| --yes, -y | 跳过安装确认 |
| --non-interactive | 不显示安装向导 |
| --cn-setup | 安装完成后按当前国内网络选项执行；没有选项时使用默认值 |
| --git-mirror URL | 国内机设置时把 GitHub 的 HTTP/HTTPS/git:// 和 SSH 地址改写为镜像地址 |
| --no-git | 国内机设置时不修改 Git 配置 |
| --cn-script-url URL | 覆盖安装后打印的国内网络设置脚本地址 |

面板安装后会在面板地址下提供 bootstrap.sh 和 toolbox.sh，例如 https://panel.example.com/warden/bootstrap.sh。设置页会显示带域名、Docker 镜像和 GitHub 镜像的国内机命令。

代理默认只监听本机，需要由网关转发；不要让没有来源限制的代理直接暴露到公网。

下一节是直接调用 install.sh 的安装方式，适合只安装面板或需要自定义目录的场景。

### 本地安装

在终端直接执行 install 会进入安装向导，依次询问安装组件、面板路径、面板域名或完整 URL，以及是否进行国内网络设置。选择国内网络设置后会逐项询问 APT 镜像、BBR、Docker 镜像、GitHub 镜像和 apt-get update。脚本会从已安装面板、certbot 证书和主机名中读取候选域名作为默认值。

~~~bash
sudo bash bootstrap.sh install
~~~

不需要交互时一次给出参数：

~~~bash
sudo bash bootstrap.sh install --non-interactive --public-url https://panel.example.com/warden
sudo bash bootstrap.sh update
sudo bash bootstrap.sh status
sudo bash bootstrap.sh uninstall
sudo bash bootstrap.sh cn-setup
sudo bash bootstrap.sh cn-restore
~~~

默认安装面板（127.0.0.1:9090）、nginx 网关（80/443）、GitHub 下载代理（127.0.0.1:8082）和 Docker 镜像代理（127.0.0.1:8080 与修正层 127.0.0.1:8081）。只安装面板使用 --panel-only；首次安装的服务清单用 --services 指定；所有命令支持 --dry-run。

未提供域名或 public URL 时，脚本尝试自动检测：有证书域名的机器优先使用该域名和 HTTPS；否则使用公网 IP 和 HTTP；无法检测公网地址时使用 http://127.0.0.1:9090/warden。安装脚本会在 80/443 空闲时安装并配置 nginx 网关；指定域名时自动申请证书，证书失败时回退 HTTP。已有反向代理时加 --no-gateway。

安装完成后脚本打印国内网络设置命令，地址优先使用 --cn-script-url，否则使用面板地址下的 bootstrap.sh。命令会按实际安装的组件附带 --docker-mirror 和 --git-mirror，值取自面板地址的源站。面板“设置”页显示同一命令。

cn-setup 不带选项时逐项询问配置项；带 --apt-mirror、--no-apt、--no-bbr、--docker-mirror、--git-mirror、--no-git 或 --no-apt-update 时按选项执行。GitHub 镜像写入 /etc/gitconfig，改写 https://github.com/、http://github.com/、git://github.com/、git@github.com: 和 ssh://git@github.com/。SSH 地址会改为 HTTPS，访问私有仓库时需要提供 HTTPS 凭据。

## 5. 直接安装面板


~~~bash
sudo bash deploy/install.sh \
  --public-url https://panel.example.com/warden \
  --cert-domain panel.example.com \
  --node-host panel.example.com \
  --services /tmp/services.json
~~~

参数说明：

| 参数 | 说明 |
| --- | --- |
| --public-url | 浏览器访问地址，路径必须等于面板路径 |
| --base-path | 面板路径，默认 /warden |
| --cert-domain | 证书域名；默认取 public URL 的主机名 |
| --node-host | sing-box 分享链接中的主机名；默认同证书域名 |
| --services | 首次安装复制的服务清单 |
| --install-dir | 程序目录，默认 /opt/node-warden |
| --config-dir | 配置目录，默认 /etc/node-warden |
| --data-dir | 数据目录，默认 /var/lib/node-warden |
| --force-services | 覆盖已有 services.json |
| --reset-key | 生成新的访问密钥 |
| --upgrade | 保留配置和数据，只更新程序 |
| --no-start | 安装后不启动服务 |

安装脚本会检查目录、生成访问密钥、写 panel.env、校验服务清单、安装 systemd unit，并在启动后请求 /api/session 做健康检查。

## 6. 自定义反向代理

默认安装会自动配置 nginx 网关。使用 --no-gateway 或已有网关时，面板只监听 127.0.0.1:9090，需要自行转发：

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

注意：

- proxy_pass 不要带 URI 后缀；Node Warden 自己处理 /warden 前缀。
- /warden/ 不要套用其他服务的 IP 白名单，除非确实需要限制管理来源。
- 必须传递 X-Real-IP，否则登录限速会把所有请求当成来自 127.0.0.1。
- 证书 dry-run 和备份下载可能超过默认代理超时，建议读超时不少于 240 秒。

如果反向代理容器挂载了 nginx 配置，必须原地修改配置，不要用替换 inode 的方式写文件。例如先把内容写入临时文件，再用 cat 覆盖原文件：

~~~bash
cat /tmp/nginx.conf > /root/gateway/nginx.conf
docker exec gateway nginx -t
docker exec gateway nginx -s reload
~~~

## 7. 首次登录

安装结束时会打印一次访问密钥；同时 /var/lib/node-warden/access-key 保存一份 root-only 恢复副本。

登录后进入“设置”，修改访问密钥。修改成功后其他会话立即失效。

## 8. 升级

~~~bash
cd /opt/node-warden-src
git pull
sudo bash deploy/upgrade.sh
~~~

升级只替换程序和 unit，保留 /etc/node-warden、/var/lib/node-warden、访问密钥、备份和历史。

## 9. 卸载

~~~bash
sudo bash deploy/uninstall.sh
~~~

默认保留配置和数据。彻底删除：

~~~bash
sudo bash deploy/uninstall.sh --purge
~~~

## 10. 验证

~~~bash
systemctl status node-warden --no-pager
curl -i http://127.0.0.1:9090/warden/api/session
curl -i https://panel.example.com/warden/api/session
~~~

浏览器应显示登录页；错误密钥返回 401；登录后可看到服务状态。

## 11. 常见问题

### 安装脚本提示 PANEL_PUBLIC_URL 的路径必须等于 /warden

把 --public-url 改成带正确路径的地址，或同时传入匹配的 --base-path。

### 服务启动失败

查看日志：

~~~bash
journalctl -u node-warden -n 100 --no-pager
~~~

常见原因是 panel.env 缺少 PANEL_KEY_SHA256 或 PANEL_SESSION_SECRET，或者服务清单路径不存在。

### 页面可以打开但接口 404

检查反向代理是否重写了 /warden 前缀。proxy_pass 后面不要加路径。

### 页面显示未登录但登录成功

检查 cookie 路径和 HTTPS。PANEL_BASE_PATH 必须与访问路径一致；通过 HTTP 访问 HTTPS public URL 时浏览器不会保存 Secure cookie。

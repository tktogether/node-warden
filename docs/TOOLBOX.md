# 工具箱

`toolbox.sh` 是 Node Warden 仓库的统一工具入口。它把常用检查、Node Warden 安装和 BBR 配置放在同一个脚本下，不需要分别下载或执行多个脚本。

## 运行

新机器直接运行，不需要手工下载源码：

```bash
sudo bash <(curl -fsSL https://raw.githubusercontent.com/tktogether/node-warden/main/toolbox.sh)
```

脚本会自动获取源码并显示统一菜单。菜单包含安装、更新、状态、卸载、常用工具和 BBR；选择“一键安装或重新配置 Node Warden”后会继续执行安装向导。

也可以直接执行操作：

```bash
sudo bash toolbox.sh install
sudo bash toolbox.sh install --public-url https://panel.example.com/warden
sudo bash toolbox.sh update
sudo bash toolbox.sh status
bash toolbox.sh common system-info
sudo bash toolbox.sh bbr status
bash toolbox.sh remote
```

`common` 下的读取类工具通常不需要 root；安装、更新、卸载、`bbr install`、`bbr rollback` 和 `bbr benchmark` 需要 root。

## 功能目录

| 目录 | 用途 |
| --- | --- |
| common | 系统信息、网络测试、镜像测速、DNS、端口、证书、磁盘和 Docker 状态 |
| node-warden | 调用仓库根目录的 bootstrap.sh，安装、更新、卸载和检查面板与代理 |
| bbr | 查看 BBR 状态、启用或回滚、检查方案兼容性、测试可用算法 |

统一菜单是主要入口；功能目录保留给脚本调用和高级操作。

## 从零运行

`toolbox.sh` 单独存在时也能运行。脚本检测到缺少 `toolbox/lib/common.sh` 或功能目录后，会按以下顺序自动获取源码：

1. `NW_TOOLBOX_ARCHIVE_URLS` 或 `NW_ARCHIVE_URLS` 指定的地址；
2. `NW_TOOLBOX_ARCHIVE_URL` 或 `NW_ARCHIVE_URL` 指定的地址；
3. GitHub archive、codeload；
4. `NW_GITHUB_PROXY`、ghfast.top、gh-proxy.com。

获取成功后使用临时目录中的源码继续执行。安装时 bootstrap.sh 直接使用这份源码，不会再次要求手工下载。

## 常用工具

| 工具 | 说明 | 主要依赖 |
| --- | --- | --- |
| system-info | 主机、系统、CPU、内存、磁盘、路由、DNS 和监听端口数 | uname、free、df、ip、ss |
| net-bench | 对指定主机做 ping 和可选 iperf3 测试 | ping，iperf3 可选 |
| docker-mirror-speedtest | 测试 Docker registry mirror 的连通性和下载速度 | curl、python3；可用 --apply 写回 daemon.json |
| dns-check | 检查域名 A、AAAA、CNAME 记录和解析耗时 | python3 |
| port-check | 检查本机或远程 TCP 端口 | bash /dev/tcp，nc 可选 |
| github-speedtest | 测试 GitHub API、raw、release 和 codeload 下载 | curl |
| cert-check | 连接 TLS 端口并显示证书主题、签发者、有效期和 SAN | openssl |
| disk-usage | 显示磁盘、inode、Docker 占用和指定目录大小 | df、du、docker 可选 |
| docker-info | 显示 Docker 版本、数据目录、镜像和容器概况 | docker |

示例：

```bash
bash toolbox.sh common system-info
bash toolbox.sh common dns-check github.com
bash toolbox.sh common port-check 443
bash toolbox.sh common cert-check panel.example.com
bash toolbox.sh common docker-mirror-speedtest --seconds 8
bash toolbox.sh common docker-mirror-speedtest --apply
```

`docker-mirror-speedtest --apply` 会备份 `/etc/docker/daemon.json`，写入测试最快的直连镜像源并执行 `systemctl reload docker`。只应在确认镜像源可信后使用。

## Node Warden

主菜单选择“一键安装或重新配置 Node Warden”即可；也可以直接执行：

```bash
sudo bash toolbox.sh install
sudo bash toolbox.sh update
sudo bash toolbox.sh status
sudo bash toolbox.sh uninstall
sudo bash toolbox.sh cn-setup
sudo bash toolbox.sh cn-restore
```

`node-warden` 功能目录保留同样的操作：

```bash
sudo bash toolbox.sh node-warden install
sudo bash toolbox.sh node-warden update
sudo bash toolbox.sh node-warden status
sudo bash toolbox.sh node-warden uninstall
sudo bash toolbox.sh node-warden self-test
sudo bash toolbox.sh node-warden cn-setup
sudo bash toolbox.sh node-warden cn-restore
```

安装和更新的参数与 bootstrap.sh 一致，例如 `--public-url`、`--panel-only`、`--skip-docker-install`。

## BBR

```bash
sudo bash toolbox.sh bbr status
sudo bash toolbox.sh bbr install
sudo bash toolbox.sh bbr rollback
bash toolbox.sh bbr schemes
sudo bash toolbox.sh bbr benchmark --peer 203.0.113.10 --seconds 15
sudo bash toolbox.sh bbr benchmark --peer 203.0.113.10 --schemes bbr,cubic,reno
sudo bash toolbox.sh bbr legacy
```

| 操作 | 说明 |
| --- | --- |
| status | 显示内核、当前算法、队列、可用算法和配置文件 |
| install | 备份原配置，写入 `fq` 和 `bbr`，执行 `sysctl --system` 并验证 |
| rollback | 按 `/var/lib/node-warden/toolbox/bbr.previous` 恢复算法、队列和配置文件 |
| schemes | 检查原生 BBR、BBR 魔改、暴力 BBR 魔改、BBRplus 和 Lotserver 的可用条件 |
| benchmark | 逐项切换可用算法，执行 iperf3，输出发送、接收和重传，结束后恢复原值 |
| legacy | 下载用户指定的 tcp.sh 并显示版本和菜单，不执行脚本 |

`install` 只写入 `/etc/sysctl.d/99-bbr.conf`，不会下载或编译第三方内核模块。`benchmark` 需要本机安装 iperf3，且对端已运行 `iperf3 -s`；测试期间只修改运行时 sysctl，退出时恢复。

### 实测结果

2026-11-11 在 Ubuntu 22.04 的三台机器上执行 `bbr schemes` 和 `bbr benchmark`。三台机器的内核分别为 5.15.0-185-generic、5.15.0-185-generic 和 5.15.0-112-generic；可用算法都只有 `reno`、`cubic`、`bbr`。原生 BBR 已加载。三台都没有 `gcc-4.9`；其中一台没有 `gcc` 和 `make`。BBR 魔改、暴力 BBR 魔改和 BBRplus 需要第三方模块或旧内核，Lotserver 不是 BBR，本工具没有自动安装或替换内核。

以下为 10 秒单流 iperf3 结果，单位为 Mbps；括号内为重传次数：

| 方向 | BBR 发送/接收 | cubic 发送/接收 | reno 发送/接收 |
| --- | --- | --- | --- |
| A → B | 48.5 / 46.2（8057） | 46.4 / 43.3（3678） | 45.5 / 43.2（3185） |
| B → C | 44.4 / 41.4（4771） | 19.6 / 16.1（1613） | 12.6 / 9.85（55） |
| C → A | 50.9 / 48.4（6728） | 47.9 / 45.9（6095） | 48.3 / 46.5（3093） |

三台机器都是 BBR 最好。B → C 路径有明显丢包，cubic 和 reno 降幅很大，BBR 仍保持约 44 Mbps。

## 安全约束

- 所有参数先经过主机名、端口和时长校验；外部输入不会拼接成 shell 命令。
- 不执行下载的远程脚本；`legacy` 只下载并检查 tcp.sh。
- 不自动编译第三方内核模块，不自动替换内核。
- `install` 和 `rollback` 会先备份配置；`benchmark` 使用 trap 在退出时恢复 sysctl。
- `docker-mirror-speedtest --apply` 会修改 Docker 配置，执行前需要确认镜像源可信。

## 故障排查

- `bbr benchmark` 报缺少 iperf3：在两端安装 iperf3，并在对端执行 `iperf3 -s`。
- 对端 5201 端口不可达：检查安全组和防火墙。
- `bbr schemes` 显示第三方方案不可用：这是当前内核和编译环境的实际状态，不是脚本错误。需要第三方方案时，应先在可重建的机器上按对应项目文档准备内核和编译环境。
- Docker 工具报 Docker 不可用：确认 Docker 已安装并启动，当前用户可访问 Docker socket。
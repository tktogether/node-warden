# 工具箱

工具箱已独立为 [tktogether/warden-toolbox](https://github.com/tktogether/warden-toolbox)。本仓库根目录的 `toolbox.sh` 为转发脚本：下载独立仓库的 `toolbox.sh` 并转发全部参数，`bash toolbox.sh <操作>` 的旧用法保持可用。

## 运行

新机器直接运行独立工具箱，不需要手工下载源码：

~~~bash
curl -fsSL https://raw.githubusercontent.com/tktogether/warden-toolbox/main/toolbox.sh -o /tmp/warden-toolbox.sh
sudo bash /tmp/warden-toolbox.sh
~~~

国内网络或代理受限时先执行 `bash /tmp/warden-toolbox.sh remote` 查看可用通道，按可用地址替换命令中的 URL（gh-proxy.com、ghfast.top、ghproxy.net 前缀）。不使用 `bash <(curl ...)` 形式。

常用操作：

~~~bash
sudo bash /tmp/warden-toolbox.sh install
sudo bash /tmp/warden-toolbox.sh update
sudo bash /tmp/warden-toolbox.sh status
bash /tmp/warden-toolbox.sh common system-info
sudo bash /tmp/warden-toolbox.sh bbr status
~~~

## 转发规则

`toolbox.sh` 保留在仓库根目录，面板也会在 `/warden/toolbox.sh` 提供该脚本。执行时按以下顺序获取独立工具箱：

1. 环境变量 `WARDEN_TOOLBOX_LOCAL` 指定的本地脚本，用于调试；
2. 环境变量 `WARDEN_TOOLBOX_URL` 指定的地址；
3. `https://raw.githubusercontent.com/tktogether/warden-toolbox/main/toolbox.sh`；
4. gh-proxy.com、ghfast.top、ghproxy.net 代理前缀。

下载后校验文件非空且首行为 `#!`，再以 `bash ... <操作>` 的形式转发参数并透传退出码。单个地址连接超时 10 秒，失败立即切换下一个通道。

## Node Warden 相关操作

~~~bash
sudo bash toolbox.sh install
sudo bash toolbox.sh update
sudo bash toolbox.sh status
sudo bash toolbox.sh uninstall
sudo bash toolbox.sh cn-setup
sudo bash toolbox.sh cn-restore
bash toolbox.sh common system-info
sudo bash toolbox.sh bbr status
~~~

安装、更新、卸载、`cn-setup` 和 `cn-restore` 由独立工具箱的 `node-warden` 模块调用本仓库的 `bootstrap.sh`。模块按环境变量 `NODE_WARDEN_BOOTSTRAP`、已安装路径 `/opt/node-warden/bootstrap.sh`、同仓检出、GitHub 多通道下载的顺序查找。

`bootstrap.sh` 的参数与行为不变，例如 `--public-url`、`--panel-only`、`--skip-docker-install`。模块、常用工具和 BBR 的完整说明见独立仓库的 `docs/MODULES.md`。

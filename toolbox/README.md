# Toolbox

统一入口和完整说明见 [docs/TOOLBOX.md](../docs/TOOLBOX.md)。

目录结构：

```text
toolbox.sh                    总入口
toolbox/lib/common.sh         公共函数
toolbox/modules/common/       常用工具
toolbox/modules/node-warden/  Node Warden 安装与维护
toolbox/modules/bbr/          BBR 状态、启用、回滚、兼容性和测速
```

快速检查：

```bash
bash toolbox.sh list
bash toolbox.sh self-test
bash toolbox.sh common system-info
```
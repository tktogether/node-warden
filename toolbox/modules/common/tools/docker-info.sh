#!/usr/bin/env bash
# 输出 Docker 版本、数据目录、镜像、容器和资源使用概况。
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
TOOLBOX_ROOT="${TOOLBOX_ROOT:-$(cd -- "$SCRIPT_DIR/../../.." && pwd -P)}"
export TOOLBOX_ROOT
# shellcheck source=/dev/null
source "$TOOLBOX_ROOT/toolbox/lib/common.sh"

if ! have_cmd docker; then
  die "未安装 Docker。"
fi
if ! docker info >/dev/null 2>&1; then
  die "Docker 服务不可用。"
fi

section "Docker 信息"
docker version --format '客户端: {{.Client.Version}}' 2>/dev/null || true
docker version --format '服务端: {{.Server.Version}}' 2>/dev/null || true
docker info --format '数据目录: {{.DockerRootDir}}' 2>/dev/null || true
docker info --format '存储驱动: {{.Driver}}' 2>/dev/null || true
docker info --format '容器: {{.Containers}} 运行中: {{.ContainersRunning}} 已停止: {{.ContainersStopped}}' 2>/dev/null || true

section "运行中的容器"
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || true

section "全部容器"
docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' 2>/dev/null || true

section "资源占用"
docker system df 2>/dev/null || true

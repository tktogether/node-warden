"""Configuration backups for Node Warden.

Backups are created from the root-owned registry only, so an HTTP request can
never choose a path.  Each backup is a gzipped tar plus a JSON manifest that
contains the file list, size and SHA-256 digest.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path

BACKUP_ID_RE = re.compile(r"^backup-[0-9]{8}T[0-9]{6}Z(?:-[0-9]+)?$")
MAX_BACKUP_BYTES = 256 * 1024 * 1024


class BackupError(RuntimeError):
    pass


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _atomic_write(path: Path, text: str, mode: int = 0o600) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(text, encoding="utf-8")
    os.chmod(tmp, mode)
    os.replace(tmp, path)


class BackupManager:
    def __init__(self, entries: list[dict], backup_dir: Path | str,
                 tar_bin: str = "tar", timeout: int = 120, max_backups: int = 20):
        self.entries = list(entries)
        self.backup_dir = Path(backup_dir)
        self.backup_dir.mkdir(parents=True, exist_ok=True)
        self.tar_bin = tar_bin
        self.timeout = max(10, int(timeout))
        self.max_backups = max(1, int(max_backups))

    def _manifest_path(self, backup_id: str) -> Path:
        if not BACKUP_ID_RE.match(backup_id):
            raise BackupError("invalid backup id")
        return self.backup_dir / f"{backup_id}.json"

    def _archive_path(self, backup_id: str) -> Path:
        if not BACKUP_ID_RE.match(backup_id):
            raise BackupError("invalid backup id")
        return self.backup_dir / f"{backup_id}.tar.gz"

    def create(self) -> dict:
        if not self.entries:
            raise BackupError("没有配置任何备份路径")
        existing = [entry for entry in self.entries if Path(entry["path"]).exists()]
        if not existing:
            raise BackupError("配置的备份路径都不存在")
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        backup_id = f"backup-{stamp}"
        counter = 2
        while (self.backup_dir / f"{backup_id}.tar.gz").exists():
            backup_id = f"backup-{stamp}-{counter}"
            counter += 1
        archive = self._archive_path(backup_id)
        args = [self.tar_bin, "-czf", str(archive), "-C", "/"]
        args.extend(str(Path(entry["path"])).lstrip("/") for entry in existing)
        try:
            result = subprocess.run(args, capture_output=True, text=True, timeout=self.timeout, check=False)
        except (OSError, subprocess.TimeoutExpired) as exc:
            archive.unlink(missing_ok=True)
            raise BackupError(f"创建备份失败: {exc}") from exc
        if result.returncode != 0:
            archive.unlink(missing_ok=True)
            message = (result.stderr or result.stdout or "tar failed").strip()
            raise BackupError(f"创建备份失败: {message[:500]}")
        size = archive.stat().st_size
        if size > MAX_BACKUP_BYTES:
            archive.unlink(missing_ok=True)
            raise BackupError("备份文件超过 256 MiB 上限")
        manifest = {
            "id": backup_id,
            "created": datetime.now(timezone.utc).isoformat(),
            "created_ts": int(time.time()),
            "size": size,
            "sha256": _sha256(archive),
            "entries": [
                {
                    "id": entry["id"],
                    "label": entry["label"],
                    "path": entry["path"],
                    "exists": Path(entry["path"]).exists(),
                }
                for entry in self.entries
            ],
        }
        _atomic_write(self._manifest_path(backup_id), json.dumps(manifest, ensure_ascii=False, indent=2))
        self.prune()
        return manifest

    def list(self) -> list[dict]:
        items = []
        for manifest_path in sorted(self.backup_dir.glob("backup-*.json"), reverse=True):
            try:
                manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                continue
            if not isinstance(manifest, dict) or not BACKUP_ID_RE.match(str(manifest.get("id", ""))):
                continue
            archive = self._archive_path(str(manifest["id"]))
            if not archive.exists():
                continue
            manifest["downloadable"] = True
            items.append(manifest)
        items.sort(key=lambda item: int(item.get("created_ts", 0)), reverse=True)
        return items

    def get(self, backup_id: str) -> dict:
        manifest_path = self._manifest_path(backup_id)
        archive = self._archive_path(backup_id)
        if not manifest_path.exists() or not archive.exists():
            raise BackupError("备份不存在")
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            raise BackupError("备份清单损坏") from exc
        manifest["archive"] = str(archive)
        manifest["downloadable"] = True
        return manifest

    def delete(self, backup_id: str) -> None:
        manifest_path = self._manifest_path(backup_id)
        archive = self._archive_path(backup_id)
        if not manifest_path.exists() and not archive.exists():
            raise BackupError("备份不存在")
        manifest_path.unlink(missing_ok=True)
        archive.unlink(missing_ok=True)

    def prune(self) -> None:
        items = self.list()
        for item in items[self.max_backups:]:
            try:
                self.delete(str(item["id"]))
            except BackupError:
                pass

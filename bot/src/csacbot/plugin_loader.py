from __future__ import annotations

import importlib
import importlib.util
import sys
from dataclasses import dataclass
from pathlib import Path
from types import ModuleType

from .plugin_manifest import PluginManifest, read_manifest


@dataclass(slots=True)
class LoadedPlugin:
    module: ModuleType
    path: str
    manifest: PluginManifest


class PluginResolver:
    def __init__(self, search_paths=()) -> None:
        self.search_paths = [Path(path) for path in search_paths]

    def load(self, name: str) -> LoadedPlugin:
        if _looks_like_path(name):
            path = Path(name).resolve()
            if path.is_dir():
                return self._load_directory_plugin(path, fallback_name=path.name)
            manifest = PluginManifest.file_plugin(path.stem, str(path))
            return LoadedPlugin(_load_module_from_path(path), str(path), manifest)

        for path in self.search_paths:
            directory = path / name
            manifest_path = directory / "plugin.toml"
            if manifest_path.exists():
                return self._load_directory_plugin(directory, fallback_name=name)

            candidate = path / f"{name}.py"
            if candidate.exists():
                resolved = candidate.resolve()
                manifest = PluginManifest.file_plugin(name, str(resolved))
                return LoadedPlugin(_load_module_from_path(resolved), str(resolved), manifest)

        module = importlib.import_module(name)
        module = importlib.reload(module)
        module_path = getattr(module, "__file__", "")
        return LoadedPlugin(module, module_path, PluginManifest.file_plugin(name, module_path))

    def _load_directory_plugin(self, path: Path, *, fallback_name: str) -> LoadedPlugin:
        directory = path.resolve()
        manifest_path = directory / "plugin.toml"
        if not manifest_path.exists():
            raise RuntimeError(f"directory plugin missing plugin.toml: {directory}")
        manifest = read_manifest(manifest_path, fallback_name=fallback_name)
        entry = Path(manifest.entry)
        if entry.is_absolute():
            raise RuntimeError(f"plugin entry must be a relative path: {manifest.entry}")
        entry_path = (directory / entry).resolve()
        try:
            entry_path.relative_to(directory)
        except ValueError as exc:
            raise RuntimeError(f"plugin entry must stay inside plugin directory: {manifest.entry}") from exc
        if not entry_path.exists():
            raise RuntimeError(f"plugin entry not found: {entry_path}")
        return LoadedPlugin(_load_module_from_path(entry_path), str(entry_path), manifest)


def plugin_mtime(path: str, manifest_path: str = "") -> float:
    mtimes: list[float] = []
    for value in (path, manifest_path):
        if not value:
            continue
        candidate = Path(value)
        if candidate.exists():
            mtimes.append(candidate.stat().st_mtime)
    return max(mtimes, default=0.0)


def _load_module_from_path(path: Path) -> ModuleType:
    module_name = f"csacbot_external_plugin_{path.stem}_{abs(hash(str(path)))}"
    sys.modules.pop(module_name, None)
    spec = importlib.util.spec_from_file_location(module_name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load plugin from {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


def _looks_like_path(name: str) -> bool:
    return name.endswith(".py") or "/" in name or "\\" in name

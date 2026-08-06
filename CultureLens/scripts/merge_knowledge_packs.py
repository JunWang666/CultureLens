#!/usr/bin/env python3
"""Merge the four knowledge source packs into Resources/KnowledgePack.

Source-of-truth directories live under agents/knowledge-sources/.
Re-run this script after editing a source pack, then rebuild.
"""

from __future__ import annotations

import hashlib
import json
import shutil
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "agents" / "knowledge-sources"
OUT = ROOT / "CultureLens" / "Resources" / "KnowledgePack"

# Merge priority: earlier wins on id collision (same as KnowledgeStore.mergePacks).
SOURCE_ORDER = (
    "west-lake",
    "chinese-history",
    "liangzhu",
    "zhejiang-museum",
)

LEGACY_RESOURCE_DIRS = (
    "KnowledgePackChineseHistory",
    "KnowledgePackLiangzhu",
    "KnowledgePackZhejiangMuseum",
)

UNIFIED_VERSION = "culturelens-v1"


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def dump_json(path: Path, value) -> bytes:
    text = json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    data = text.encode("utf-8")
    path.write_bytes(data)
    return data


def sort_key_name(item: dict) -> tuple:
    return (item.get("name") or "", item.get("sortKey") or item.get("id") or "")


def load_pack(directory: Path) -> dict:
    main = load_json(directory / "knowledge-pack.json")
    sight = load_json(directory / "elements-sight.json")
    history = load_json(directory / "elements-history.json")
    introductions = load_json(directory / "introductions.json")
    themes = load_json(directory / "themes.json")

    elements: list[dict] = []
    role_by_id: dict[str, str] = {}
    seen: set[str] = set()

    for element in sight.get("elements") or []:
        eid = element["id"]
        if eid in seen:
            continue
        seen.add(eid)
        elements.append(element)
        role_by_id[eid] = "sight"

    for element in history.get("elements") or []:
        eid = element["id"]
        if eid in seen:
            continue
        seen.add(eid)
        elements.append(element)
        role_by_id[eid] = "history"

    locales: dict[str, dict] = {}
    for path in sorted(directory.glob("locales-*.json")):
        lang = path.stem.removeprefix("locales-")
        locales[lang] = load_json(path)

    return {
        "version": main["version"],
        "source_language": main.get("source_language") or main.get("sourceLanguage"),
        "elements": elements,
        "role_by_id": role_by_id,
        "attractions": sight.get("attractions") or [],
        "relations": main.get("relations") or [],
        "introductions": introductions.get("introductions") or [],
        "themes": themes.get("themes") or [],
        "locales": locales,
    }


def merge_packs(packs: list[dict]) -> dict:
    elements: dict[str, dict] = {}
    role_by_id: dict[str, str] = {}
    attractions: dict[str, dict] = {}
    introductions: dict[str, dict] = {}
    themes: dict[str, dict] = {}
    relations: list[dict] = []
    seen_relation: set[str] = set()
    locales: dict[str, dict] = {}
    source_language = None

    for pack in packs:
        if source_language is None:
            source_language = pack.get("source_language")
        for element in pack["elements"]:
            eid = element["id"]
            if eid in elements:
                continue
            elements[eid] = element
            role_by_id[eid] = pack["role_by_id"].get(eid, "history")
        for attraction in pack["attractions"]:
            aid = attraction["id"]
            if aid not in attractions:
                attractions[aid] = attraction
        for introduction in pack["introductions"]:
            iid = introduction["id"]
            if iid not in introductions:
                introductions[iid] = introduction
        for theme in pack["themes"]:
            tid = theme["id"]
            if tid not in themes:
                themes[tid] = theme
        for relation in pack["relations"]:
            signature = "\x1f".join(
                [
                    relation.get("elementId", ""),
                    relation.get("relatedElementId", ""),
                    relation.get("kind") or "",
                    relation.get("explanation") or "",
                ]
            )
            if signature in seen_relation:
                continue
            seen_relation.add(signature)
            relations.append(relation)
        for language, overlay in (pack.get("locales") or {}).items():
            merged = locales.setdefault(
                language,
                {"elements": {}, "attractions": {}, "introductions": {}},
            )
            for section in ("elements", "attractions", "introductions"):
                section_map = merged.setdefault(section, {})
                for key, value in (overlay.get(section) or {}).items():
                    if key not in section_map:
                        section_map[key] = value

    element_ids = set(elements)
    relations = [
        rel
        for rel in relations
        if rel.get("elementId") in element_ids and rel.get("relatedElementId") in element_ids
    ]

    cleaned_themes = []
    for theme in themes.values():
        kept_ids = [eid for eid in theme.get("elementIds") or [] if eid in element_ids]
        if not kept_ids:
            continue
        cleaned = dict(theme)
        cleaned["elementIds"] = kept_ids
        cleaned_themes.append(cleaned)

    return {
        "version": UNIFIED_VERSION,
        "source_language": source_language,
        "elements": sorted(elements.values(), key=sort_key_name),
        "role_by_id": role_by_id,
        "attractions": sorted(attractions.values(), key=sort_key_name),
        "relations": sorted(
            relations,
            key=lambda r: (r.get("elementId", ""), r.get("relatedElementId", "")),
        ),
        "introductions": sorted(introductions.values(), key=sort_key_name),
        "themes": sorted(cleaned_themes, key=sort_key_name),
        "locales": locales,
    }


def write_pack(pack: dict, destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    for path in destination.glob("*.json"):
        path.unlink()

    role_by_id = pack["role_by_id"]
    sight_elements = [e for e in pack["elements"] if role_by_id.get(e["id"]) == "sight"]
    history_elements = [e for e in pack["elements"] if role_by_id.get(e["id"]) != "sight"]

    files: dict[str, bytes] = {}
    files["knowledge-pack.json"] = dump_json(
        destination / "knowledge-pack.json",
        {
            "version": pack["version"],
            "source_language": pack["source_language"],
            "relations": pack["relations"],
        },
    )
    files["elements-sight.json"] = dump_json(
        destination / "elements-sight.json",
        {"elements": sight_elements, "attractions": pack["attractions"]},
    )
    files["elements-history.json"] = dump_json(
        destination / "elements-history.json",
        {"elements": history_elements},
    )
    files["introductions.json"] = dump_json(
        destination / "introductions.json",
        {"introductions": pack["introductions"]},
    )
    files["themes.json"] = dump_json(
        destination / "themes.json",
        {"themes": pack["themes"]},
    )
    for language, overlay in sorted((pack.get("locales") or {}).items()):
        name = f"locales-{language}.json"
        files[name] = dump_json(destination / name, overlay)

    content_names = sorted(k for k in files if k != "pack-manifest.json")
    digest = hashlib.sha256()
    for name in content_names:
        digest.update(files[name])

    manifest = {
        "packVersion": pack["version"],
        "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "recordCounts": {
            "elements": len(pack["elements"]),
            "elementsSight": len(sight_elements),
            "elementsHistory": len(history_elements),
            "relations": len(pack["relations"]),
            "introductions": len(pack["introductions"]),
            "attractions": len(pack["attractions"]),
            "themes": len(pack["themes"]),
        },
        "sha256": digest.hexdigest(),
        "files": content_names,
    }
    dump_json(destination / "pack-manifest.json", manifest)
    print(json.dumps(manifest["recordCounts"], ensure_ascii=False))


def seed_sources_from_resources_if_needed() -> None:
    """First run: copy current Resource packs into agents/knowledge-sources/."""
    resources = ROOT / "CultureLens" / "Resources"
    mapping = {
        "west-lake": "KnowledgePack",
        "chinese-history": "KnowledgePackChineseHistory",
        "liangzhu": "KnowledgePackLiangzhu",
        "zhejiang-museum": "KnowledgePackZhejiangMuseum",
    }
    SOURCES.mkdir(parents=True, exist_ok=True)
    for source_name, resource_name in mapping.items():
        dest = SOURCES / source_name
        src = resources / resource_name
        if dest.exists():
            continue
        if not src.exists():
            raise SystemExit(f"Missing source seed directory: {src}")
        shutil.copytree(src, dest)
        print(f"seeded {dest.relative_to(ROOT)}")


def remove_legacy_resource_packs() -> None:
    resources = ROOT / "CultureLens" / "Resources"
    for name in LEGACY_RESOURCE_DIRS:
        path = resources / name
        if path.exists():
            shutil.rmtree(path)
            print(f"removed {path.relative_to(ROOT)}")


def main() -> None:
    seed_sources_from_resources_if_needed()
    packs = [load_pack(SOURCES / name) for name in SOURCE_ORDER]
    merged = merge_packs(packs)
    write_pack(merged, OUT)
    remove_legacy_resource_packs()
    print(f"wrote {OUT.relative_to(ROOT)} version={merged['version']}")


if __name__ == "__main__":
    main()

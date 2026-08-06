#!/usr/bin/env python3
"""Rewrite KnowledgePack* sidecars: slug primary keys → UUID id + optional key.

Uses the same UUIDv5(NameSpaceURL, ...) algorithm as DeterministicID in Swift.
Bumps pack versions and regenerates pack-manifest.json (SHA-256 of file contents).
"""
from __future__ import annotations

import hashlib
import json
import uuid
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "CultureLens" / "Resources"
NS = uuid.UUID("6ba7b811-9dad-11d1-80b4-00c04fd430c8")

VERSION_BUMPS = {
    "hangzhou-west-lake-v5": "hangzhou-west-lake-v6",
    "chinese-history-v4": "chinese-history-v5",
    "liangzhu-v4": "liangzhu-v5",
    "zhejiang-museum-v5": "zhejiang-museum-v6",
}

PACK_DIRS = [
    "KnowledgePack",
    "KnowledgePackChineseHistory",
    "KnowledgePackLiangzhu",
    "KnowledgePackZhejiangMuseum",
]


def v5(name: str) -> str:
    return str(uuid.uuid5(NS, name))


def element_id(slug: str) -> str:
    return v5("culturelens:cultural-element:" + slug.lower())


def attraction_id(slug: str) -> str:
    return v5("culturelens:attraction:" + slug.lower())


def introduction_id(slug: str) -> str:
    return v5("culturelens:introduction:" + slug.lower())


def theme_id(slug: str) -> str:
    return v5("culturelens:theme:" + slug.lower())


def load(path: Path):
    with path.open(encoding="utf-8") as f:
        return json.load(f)


def dump(path: Path, data) -> None:
    with path.open("w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")


def migrate_element(el: dict) -> dict:
    slug = el["key"]
    out = {
        "id": element_id(slug),
        "key": slug,
        "name": el["name"],
        "introduction": el["introduction"],
    }
    if "sources" in el and el["sources"]:
        out["sources"] = el["sources"]
    if el.get("conceptKind"):
        out["conceptKind"] = el["conceptKind"]
    if el.get("contentRole"):
        out["contentRole"] = el["contentRole"]
    return out


def migrate_attraction(att: dict) -> dict:
    slug = att["key"]
    return {
        "id": attraction_id(slug),
        "key": slug,
        "name": att["name"],
    }


def migrate_relation(rel: dict, element_map: dict[str, str]) -> dict:
    ek = rel["elementKey"]
    rk = rel["relatedElementKey"]
    # Cross-pack edges may reference slugs defined in another pack; UUIDv5(slug)
    # is stable across packs so we can mint the id without a local element.
    out = {
        "elementId": element_map.get(ek) or element_id(ek),
        "relatedElementId": element_map.get(rk) or element_id(rk),
    }
    if rel.get("kind"):
        out["kind"] = rel["kind"]
    if rel.get("explanation"):
        out["explanation"] = rel["explanation"]
    return out


def migrate_introduction(rec: dict, element_map: dict[str, str], attraction_map: dict[str, str]) -> dict:
    slug = rec["key"]
    ek = rec["culturalElementKey"]
    ak = rec["attractionKey"]
    out = {
        "id": introduction_id(slug),
        "key": slug,
        "name": rec["name"],
        "introduction": rec["introduction"],
        # Cross-pack intros (e.g. Zhejiang Museum hosting Liangzhu jade) mint
        # stable UUIDv5 ids from the foreign slug.
        "culturalElementId": element_map.get(ek) or element_id(ek),
        "attractionId": attraction_map.get(ak) or attraction_id(ak),
        "latitude": rec["latitude"],
        "longitude": rec["longitude"],
    }
    if rec.get("coordinateSourceUrl"):
        out["coordinateSourceUrl"] = rec["coordinateSourceUrl"]
    if rec.get("sources"):
        out["sources"] = rec["sources"]
    return out


def migrate_theme(theme: dict, element_map: dict[str, str]) -> dict:
    slug = theme["key"]
    return {
        "id": theme_id(slug),
        "key": slug,
        "name": theme["name"],
        "summary": theme["summary"],
        "elementIds": [
            element_map[k] if k in element_map else element_id(k)
            for k in theme["elementKeys"]
        ],
        "minContacted": theme["minContacted"],
    }


def remap_locale_dict(d: dict | None, id_map: dict[str, str], mint) -> dict:
    if not d:
        return {}
    out = {}
    for slug, value in d.items():
        if slug in id_map:
            out[id_map[slug]] = value
        else:
            try:
                uuid.UUID(slug)
                out[slug] = value
            except ValueError:
                # Locale overlay may reference entities defined in another pack
                # or introductions only present as overlays — mint from slug.
                out[mint(slug)] = value
    return out


def migrate_locales(data: dict, element_map: dict[str, str], attraction_map: dict[str, str], intro_map: dict[str, str]) -> dict:
    out = {}
    if "elements" in data:
        out["elements"] = remap_locale_dict(data["elements"], element_map, element_id)
    if "attractions" in data:
        out["attractions"] = remap_locale_dict(data["attractions"], attraction_map, attraction_id)
    if "introductions" in data:
        out["introductions"] = remap_locale_dict(data["introductions"], intro_map, introduction_id)
    return out


def sha256_files(directory: Path, files: list[str]) -> str:
    h = hashlib.sha256()
    for name in files:
        path = directory / name
        h.update(path.read_bytes())
    return h.hexdigest()


def migrate_pack(directory: Path) -> None:
    print(f"Migrating {directory.name}…")
    kp_path = directory / "knowledge-pack.json"
    sight_path = directory / "elements-sight.json"
    history_path = directory / "elements-history.json"
    intro_path = directory / "introductions.json"
    themes_path = directory / "themes.json"

    kp = load(kp_path)
    sight = load(sight_path) if sight_path.exists() else {"elements": [], "attractions": []}
    history = load(history_path) if history_path.exists() else {"elements": []}
    intros = load(intro_path) if intro_path.exists() else {"introductions": []}
    themes = load(themes_path) if themes_path.exists() else {"themes": []}

    # Build slug → UUID maps from all elements / attractions
    all_elements = list(sight.get("elements", [])) + list(history.get("elements", [])) + list(kp.get("elements", []))
    all_attractions = list(sight.get("attractions", [])) + list(kp.get("attractions", []))

    element_map: dict[str, str] = {}
    for el in all_elements:
        slug = el["key"]
        if slug not in element_map:
            element_map[slug] = element_id(slug)

    attraction_map: dict[str, str] = {}
    for att in all_attractions:
        slug = att["key"]
        if slug not in attraction_map:
            attraction_map[slug] = attraction_id(slug)

    intro_map: dict[str, str] = {}
    for rec in intros.get("introductions", []):
        slug = rec["key"]
        intro_map[slug] = introduction_id(slug)

    # Note: relation endpoints may be cross-pack; ids are minted from slug.

    old_version = kp["version"]
    new_version = VERSION_BUMPS.get(old_version, old_version)
    if new_version == old_version and old_version.endswith("-v5"):
        # Fallback / already bumped?
        if old_version == "hangzhou-west-lake-v5":
            new_version = "hangzhou-west-lake-v6"

    new_kp = {
        "version": new_version,
        "source_language": kp.get("source_language", "zh-Hans"),
        "relations": [migrate_relation(r, element_map) for r in kp.get("relations", [])],
    }
    dump(kp_path, new_kp)

    new_sight = {
        "elements": [migrate_element(e) for e in sight.get("elements", [])],
        "attractions": [migrate_attraction(a) for a in sight.get("attractions", [])],
    }
    dump(sight_path, new_sight)

    new_history = {
        "elements": [migrate_element(e) for e in history.get("elements", [])],
    }
    dump(history_path, new_history)

    new_intros = {
        "introductions": [
            migrate_introduction(r, element_map, attraction_map)
            for r in intros.get("introductions", [])
        ],
    }
    dump(intro_path, new_intros)

    new_themes = {
        "themes": [migrate_theme(t, element_map) for t in themes.get("themes", [])],
    }
    dump(themes_path, new_themes)

    for locale_path in sorted(directory.glob("locales-*.json")):
        locale = load(locale_path)
        dump(locale_path, migrate_locales(locale, element_map, attraction_map, intro_map))

    files = [
        "knowledge-pack.json",
        "elements-sight.json",
        "elements-history.json",
        "introductions.json",
        "themes.json",
    ]
    for p in sorted(directory.glob("locales-*.json")):
        files.append(p.name)

    sight_count = len(new_sight["elements"])
    history_count = len(new_history["elements"])
    manifest = {
        "packVersion": new_version,
        "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "recordCounts": {
            "elements": sight_count + history_count,
            "elementsSight": sight_count,
            "elementsHistory": history_count,
            "relations": len(new_kp["relations"]),
            "introductions": len(new_intros["introductions"]),
            "attractions": len(new_sight["attractions"]),
            "themes": len(new_themes["themes"]),
        },
        "sha256": sha256_files(directory, files),
        "files": files,
    }
    dump(directory / "pack-manifest.json", manifest)
    print(f"  {old_version} → {new_version}  elements={manifest['recordCounts']['elements']}")


def main() -> None:
    for name in PACK_DIRS:
        migrate_pack(ROOT / name)
    print("Done.")


if __name__ == "__main__":
    main()

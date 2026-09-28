#!/usr/bin/env python3
"""Prepare Mermaid sources and embed generated images in DocC render nodes."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any


FENCE = re.compile(r"(?ms)^```mermaid[ \t]*\r?\n(.*?)^```[ \t]*$")
TITLE = re.compile(r"(?m)^\s*accTitle:\s*(.*?)\s*$")
DESCRIPTION = re.compile(r"(?m)^\s*accDescr:\s*(.*?)\s*$")


def prepare(root: Path, work_dir: Path, manifest_path: Path) -> None:
    diagrams: list[dict[str, str]] = []
    used_names: set[tuple[str, str]] = set()

    for catalog in sorted((root / "Sources").glob("*/*.docc")):
        module = catalog.parent.name
        for article in sorted(catalog.glob("*.md")):
            content = article.read_text()
            for source in FENCE.findall(content):
                title_match = TITLE.search(source)
                description_match = DESCRIPTION.search(source)
                if not title_match or not description_match:
                    raise SystemExit(
                        f"{article}: every Mermaid block needs accTitle and accDescr"
                    )

                title = title_match.group(1)
                name = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")
                if not name:
                    raise SystemExit(f"{article}: cannot derive a filename from {title!r}")
                key = (module, name)
                if key in used_names:
                    raise SystemExit(f"{article}: duplicate Mermaid title {title!r}")
                used_names.add(key)

                source_path = work_dir / "sources" / module / f"{name}.mmd"
                source_path.parent.mkdir(parents=True, exist_ok=True)
                source_path.write_text(source.rstrip() + "\n")
                diagrams.append(
                    {
                        "module": module,
                        "article": article.stem,
                        "title": title,
                        "description": description_match.group(1),
                        "name": name,
                        "source": str(source_path),
                    }
                )

    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(json.dumps(diagrams, indent=2) + "\n")
    print(f"Prepared {len(diagrams)} Mermaid diagrams from DocC Markdown.")


def mermaid_title(code: Any) -> str | None:
    lines = code if isinstance(code, list) else str(code).splitlines()
    for line in lines:
        match = TITLE.match(str(line))
        if match:
            return match.group(1)
    return None


def svg_id(path: Path) -> str:
    match = re.search(r"<svg\b[^>]*\bid=[\"']([^\"']+)[\"']", path.read_text())
    if not match:
        raise SystemExit(f"Generated SVG has no root id: {path}")
    return match.group(1)


def embed(site: Path, manifest_path: Path) -> None:
    diagrams: list[dict[str, str]] = json.loads(manifest_path.read_text())
    grouped: dict[tuple[str, str], list[dict[str, str]]] = {}
    for diagram in diagrams:
        grouped.setdefault((diagram["module"], diagram["article"]), []).append(diagram)

    for (module, article), page_diagrams in grouped.items():
        page_path = site / "data" / "documentation" / module.lower() / f"{article.lower()}.json"
        if not page_path.is_file():
            raise SystemExit(f"DocC render node not found for {module}/{article}: {page_path}")

        page = json.loads(page_path.read_text())
        by_title = {diagram["title"]: diagram for diagram in page_diagrams}
        expected = set(by_title)
        existing_images: set[str] = set()

        def collect_images(value: Any) -> None:
            if isinstance(value, list):
                for child in value:
                    collect_images(child)
            elif isinstance(value, dict):
                if value.get("type") == "image":
                    existing_images.add(str(value.get("identifier", "")))
                for child in value.values():
                    collect_images(child)

        for section in page.get("primaryContentSections", []):
            collect_images(section)
        for section in page.get("sections", []):
            collect_images(section)

        embedded_titles = {
            diagram["title"]
            for diagram in page_diagrams
            if f"{diagram['name']}.svg" in existing_images
        }
        transformed_titles: set[str] = set()

        def replace(value: Any) -> Any:
            if isinstance(value, list):
                return [replace(child) for child in value]
            if not isinstance(value, dict):
                return value
            if value.get("type") == "codeListing" and str(value.get("syntax", "")).lower() == "mermaid":
                title = mermaid_title(value.get("code", []))
                diagram = by_title.get(title or "")
                if diagram is None:
                    raise SystemExit(f"No Mermaid source matches DocC diagram title {title!r} in {page_path}")
                if diagram["title"] in embedded_titles or diagram["title"] in transformed_titles:
                    raise SystemExit(f"Duplicate Mermaid diagram in DocC render node: {title!r}")
                transformed_titles.add(diagram["title"])
                filename = f"{diagram['name']}.svg"
                dark_filename = f"{diagram['name']}~dark.svg"
                image_directory = site / "images" / module
                light_path = image_directory / filename
                dark_path = image_directory / dark_filename
                if not light_path.is_file() or not dark_path.is_file():
                    raise SystemExit(f"Generated light/dark SVG pair is missing for {filename}")

                page.setdefault("references", {})[filename] = {
                    "type": "image",
                    "identifier": filename,
                    "alt": diagram["description"],
                    "variants": [
                        {
                            "url": f"/images/{module}/{filename}",
                            "traits": ["1x", "light"],
                            "svgID": svg_id(light_path),
                        },
                        {
                            "url": f"/images/{module}/{dark_filename}",
                            "traits": ["1x", "dark"],
                            "svgID": svg_id(dark_path),
                        },
                    ],
                }
                return {
                    "type": "paragraph",
                    "inlineContent": [{"type": "image", "identifier": filename}],
                }
            return {key: replace(child) for key, child in value.items()}

        page = replace(page)
        if embedded_titles | transformed_titles != expected:
            missing = ", ".join(sorted(expected - embedded_titles - transformed_titles))
            raise SystemExit(f"DocC Mermaid listings missing from {page_path}: {missing}")
        if not transformed_titles:
            print(f"Already embedded {len(embedded_titles)} diagrams in {page_path.relative_to(site)}.")
            continue
        page_path.write_text(json.dumps(page, indent=2, ensure_ascii=False) + "\n")
        print(f"Embedded {len(transformed_titles)} diagrams in {page_path.relative_to(site)}.")


def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit("usage: mermaid-docs.py prepare ROOT WORK_DIR MANIFEST | embed SITE MANIFEST | render-inputs MANIFEST")

    command = sys.argv[1]
    if command == "prepare" and len(sys.argv) == 5:
        prepare(Path(sys.argv[2]), Path(sys.argv[3]), Path(sys.argv[4]))
    elif command == "embed" and len(sys.argv) == 4:
        embed(Path(sys.argv[2]), Path(sys.argv[3]))
    elif command == "render-inputs" and len(sys.argv) == 3:
        for diagram in json.loads(Path(sys.argv[2]).read_text()):
            print(diagram["source"])
    else:
        raise SystemExit("invalid mermaid-docs.py command or arguments")


if __name__ == "__main__":
    main()

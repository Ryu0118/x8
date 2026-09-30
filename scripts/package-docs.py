#!/usr/bin/env python3
"""Promote selected guides into the combined X8 package documentation."""

from __future__ import annotations

import json
import os
import shutil
import sys
from copy import deepcopy
from pathlib import Path
from typing import Any


PACKAGE_ID = "doc://X8/documentation"
HIDDEN_MODULES = {"X8Config", "X8Kit"}
ARTICLES = (
    ("X8CLI", "PrefixMapping", "prefixmapping"),
    ("X8Config", "ConfigurationFile", "configurationfile"),
    ("X8Kit", "XcodeCompilationCaching", "xcodecompilationcaching"),
)


def read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise SystemExit(f"Unable to read DocC output {path}: {error}") from error


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")


def data_path_for_route(site: Path, route: str) -> Path:
    parts = route.removeprefix("/documentation/").split("/")
    return site / "data" / "documentation" / Path(*parts[:-1]) / f"{parts[-1]}.json"


def route_directory(site: Path, route: str) -> Path:
    return site / route.removeprefix("/")


def replace_values(value: Any, identifiers: dict[str, str], routes: dict[str, str]) -> Any:
    if isinstance(value, list):
        return [replace_values(child, identifiers, routes) for child in value]
    if isinstance(value, dict):
        result: dict[str, Any] = {}
        for key, child in value.items():
            result[identifiers.get(key, key)] = replace_values(child, identifiers, routes)
        return result
    if isinstance(value, str):
        return routes.get(value, identifiers.get(value, value))
    return value


def contains_identifier(value: Any, identifier: str) -> bool:
    if isinstance(value, dict):
        return any(contains_identifier(child, identifier) for child in value.values())
    if isinstance(value, list):
        return any(contains_identifier(child, identifier) for child in value)
    return value == identifier


def remove_topic(identifier: str, page: dict[str, Any]) -> None:
    sections = page.get("topicSections", [])
    page["topicSections"] = [
        {**section, "identifiers": [item for item in section.get("identifiers", []) if item != identifier]}
        for section in sections
        if any(item != identifier for item in section.get("identifiers", []))
    ]
    page.get("references", {}).pop(identifier, None)


def prune_index_nodes(nodes: list[dict[str, Any]], removed_paths: set[str]) -> list[dict[str, Any]]:
    kept: list[dict[str, Any]] = []
    for node in nodes:
        node_path = node.get("path", "")
        if node_path in removed_paths or any(
            node_path.startswith(f"{path}/") for path in removed_paths
        ):
            continue
        if isinstance(node.get("children"), list):
            node["children"] = prune_index_nodes(node["children"], removed_paths)
        kept.append(node)
    return kept


def redirect_page(target: str) -> str:
    return f"""<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta http-equiv="refresh" content="0; url={target}">
    <link rel="canonical" href="{target}">
    <title>Documentation moved</title>
  </head>
  <body>
    <p>This article moved to <a href="{target}">its package-level page</a>.</p>
  </body>
</html>
"""


def promote_articles(site: Path) -> None:
    root_path = site / "data" / "documentation.json"
    index_path = site / "index" / "index.json"
    entities_path = site / "linkable-entities.json"
    if not root_path.is_file() or not index_path.is_file():
        raise SystemExit(f"{site} is not a transformed combined DocC archive")

    root_page = read_json(root_path)
    root_identifier = root_page.get("identifier", {}).get("url")
    if root_identifier != PACKAGE_ID:
        raise SystemExit(f"Expected package landing page {PACKAGE_ID}, found {root_identifier!r}")

    identifiers: dict[str, str] = {}
    routes: dict[str, str] = {}
    promoted: list[dict[str, Any]] = []
    old_route_stubs: dict[str, str] = {}

    for module, article_name, slug in ARTICLES:
        module_page_path = site / "data" / "documentation" / f"{module.lower()}.json"
        module_page = read_json(module_page_path)
        old_identifier = f"doc://{module}/documentation/{module}/{article_name}"
        module_reference = module_page.get("references", {}).get(old_identifier)
        if not isinstance(module_reference, dict):
            raise SystemExit(f"{module} does not link to the expected article {article_name}")

        old_route = module_reference.get("url")
        if not isinstance(old_route, str) or not old_route.startswith(f"/documentation/{module.lower()}/"):
            raise SystemExit(f"Unexpected source route for {module}/{article_name}: {old_route!r}")

        source_page_path = data_path_for_route(site, old_route)
        article_page = read_json(source_page_path)
        new_identifier = f"{PACKAGE_ID}/{article_name}"
        new_route = f"/documentation/{slug}"
        new_page_path = data_path_for_route(site, new_route)

        identifiers[old_identifier] = new_identifier
        routes[old_route] = new_route
        remove_topic(old_identifier, module_page)
        write_json(module_page_path, module_page)

        article_page["identifier"]["url"] = new_identifier
        article_page.setdefault("metadata", {}).pop("modules", None)
        article_page["hierarchy"] = {"paths": [[PACKAGE_ID]]}
        for variant in article_page.get("variants", []):
            variant["paths"] = [new_route]

        source_module_root = f"doc://{module}/documentation/{module}"
        article_page.get("references", {}).pop(source_module_root, None)
        root_metadata = root_page.get("metadata", {})
        article_page.setdefault("references", {})[PACKAGE_ID] = {
            "type": "topic",
            "title": root_metadata.get("title", "X8"),
            "url": "/documentation",
            "identifier": PACKAGE_ID,
            "role": root_metadata.get("role", "collection"),
            "kind": root_page.get("kind", "article"),
        }
        write_json(new_page_path, article_page)

        old_stub_path = route_directory(site, old_route) / "index.html"
        if not old_stub_path.is_file():
            raise SystemExit(f"Static route stub not found for {old_route}")
        old_route_stubs[old_route] = old_stub_path.read_text()
        new_directory = route_directory(site, new_route)
        new_directory.mkdir(parents=True, exist_ok=True)
        (new_directory / "index.html").write_text(old_route_stubs[old_route])

        promoted.append(
            {
                "module": module,
                "name": article_name,
                "title": article_page.get("metadata", {}).get("title", article_name),
                "abstract": article_page.get("abstract", []),
                "reference": deepcopy(module_reference),
                "identifier": new_identifier,
                "route": new_route,
                "old_route": old_route,
                "old_page_path": source_page_path,
                "new_page_path": new_page_path,
            }
        )

    hidden_ids = {f"doc://{module}/documentation/{module}" for module in HIDDEN_MODULES}
    hidden_routes = {f"/documentation/{module.lower()}" for module in HIDDEN_MODULES}
    for identifier, reference in list(root_page.get("references", {}).items()):
        if identifier in hidden_ids or reference.get("url") in hidden_routes:
            root_page["references"].pop(identifier, None)
    for section in root_page.get("topicSections", []):
        section["identifiers"] = [
            identifier for identifier in section.get("identifiers", []) if identifier not in hidden_ids
        ]
    if root_page.get("topicSections"):
        root_page["topicSections"][0]["identifiers"].extend(
            article["identifier"] for article in promoted
        )
    else:
        root_page["topicSections"] = [
            {"identifiers": [article["identifier"] for article in promoted]}
        ]

    for article in promoted:
        reference = deepcopy(article["reference"])
        reference.update(
            {
                "type": "topic",
                "title": article["title"],
                "url": article["route"],
                "identifier": article["identifier"],
                "role": "article",
                "kind": "article",
                "abstract": article["abstract"],
            }
        )
        root_page.setdefault("references", {})[article["identifier"]] = reference

    root_page = replace_values(root_page, identifiers, routes)
    write_json(root_path, root_page)

    index = read_json(index_path)
    roots = index.get("interfaceLanguages", {}).get("swift", [])
    package_roots = [node for node in roots if node.get("path") == "/documentation"]
    if len(package_roots) != 1:
        raise SystemExit("Unable to locate the package root in DocC's navigation index")
    removed_paths = set(routes) | hidden_routes
    package_roots[0]["children"] = prune_index_nodes(
        package_roots[0].get("children", []), removed_paths
    )
    package_roots[0]["children"].extend(
        {"title": article["title"], "path": article["route"], "type": "article"}
        for article in promoted
    )
    index["includedArchiveIdentifiers"] = [
        identifier
        for identifier in index.get("includedArchiveIdentifiers", [])
        if identifier not in HIDDEN_MODULES
    ]
    write_json(index_path, index)

    if entities_path.is_file():
        entities = read_json(entities_path)
        kept_entities = []
        seen_promoted: set[str] = set()
        for entity in entities:
            reference_url = entity.get("referenceURL")
            entity_path = entity.get("path", "")
            if entity_path in hidden_routes or any(
                entity_path.startswith(f"{route}/") for route in hidden_routes
            ):
                continue
            if reference_url in identifiers:
                entity["referenceURL"] = identifiers[reference_url]
                entity["path"] = routes[entity_path]
                seen_promoted.add(entity["referenceURL"])
            kept_entities.append(entity)
        for article in promoted:
            if article["identifier"] not in seen_promoted:
                kept_entities.append(
                    {
                        "title": article["title"],
                        "path": article["route"],
                        "kind": "org.swift.docc.kind.article",
                        "language": "swift",
                        "availableLanguages": ["swift"],
                        "referenceURL": article["identifier"],
                        "abstract": article["abstract"],
                    }
                )
        write_json(entities_path, kept_entities)

    documentation_data = site / "data" / "documentation"
    for path in documentation_data.rglob("*.json"):
        document = read_json(path)
        updated_document = replace_values(document, identifiers, routes)
        if updated_document != document:
            write_json(path, updated_document)

    for article in promoted:
        article["old_page_path"].unlink(missing_ok=True)
        old_directory = route_directory(site, article["old_route"])
        old_directory.mkdir(parents=True, exist_ok=True)
        target_directory = route_directory(site, article["route"])
        relative_target = os.path.relpath(target_directory, old_directory)
        (old_directory / "index.html").write_text(redirect_page(f"{relative_target}/"))

    for module in HIDDEN_MODULES:
        (documentation_data / f"{module.lower()}.json").unlink(missing_ok=True)
        shutil.rmtree(documentation_data / module.lower(), ignore_errors=True)
        shutil.rmtree(site / "documentation" / module.lower(), ignore_errors=True)

    for article in promoted:
        old_directory = route_directory(site, article["old_route"])
        old_directory.mkdir(parents=True, exist_ok=True)
        target_directory = route_directory(site, article["route"])
        relative_target = os.path.relpath(target_directory, old_directory)
        (old_directory / "index.html").write_text(redirect_page(f"{relative_target}/"))

    for article in promoted:
        if not article["new_page_path"].is_file():
            raise SystemExit(f"Promoted article was not written: {article['new_page_path']}")
        if not (route_directory(site, article["route"]) / "index.html").is_file():
            raise SystemExit(f"Promoted static route was not written: {article['route']}")

    for path in documentation_data.rglob("*.json"):
        document = read_json(path)
        content = {
            "abstract": document.get("abstract", []),
            "primaryContentSections": document.get("primaryContentSections", []),
            "sections": document.get("sections", []),
            "topicSections": document.get("topicSections", []),
        }
        references_changed = False
        for identifier, reference in list(document.get("references", {}).items()):
            reference_route = reference.get("url", "")
            if isinstance(reference_route, str) and (reference_route in hidden_routes or any(
                reference_route.startswith(f"{route}/") for route in hidden_routes
            )):
                if contains_identifier(content, identifier):
                    raise SystemExit(f"{path} links to hidden documentation: {reference_route}")
                document["references"].pop(identifier, None)
                references_changed = True
        if references_changed:
            write_json(path, document)

    print(
        f"Promoted {len(promoted)} articles to the package root and hid "
        f"{len(HIDDEN_MODULES)} implementation modules."
    )


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: scripts/package-docs.py <transformed DocC output directory>")
    promote_articles(Path(sys.argv[1]))


if __name__ == "__main__":
    main()

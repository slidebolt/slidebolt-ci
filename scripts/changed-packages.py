#!/usr/bin/env python3
"""Print changed release components as repository, kind, revision TSV rows."""

import json
import pathlib
import subprocess
import sys


def run(*args: str, cwd: pathlib.Path) -> str:
    return subprocess.check_output(args, cwd=cwd, text=True).strip()


if len(sys.argv) != 3:
    raise SystemExit("usage: changed-packages.py RELEASE_DIR PACKAGE_CATALOG")

release = pathlib.Path(sys.argv[1]).resolve()
catalog_path = pathlib.Path(sys.argv[2]).resolve()
tags = run("git", "tag", "--merged", "HEAD", "--sort=-v:refname", cwd=release).splitlines()
if not tags:
    raise SystemExit("release history has no prior version tag")
base = tags[0]


def versions(ref: str) -> dict[str, str]:
    content = run("git", "show", f"{ref}:versions.env", cwd=release)
    result: dict[str, str] = {}
    for raw in content.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        name, value = line.split("=", 1)
        result[name] = value
    return result


before = versions(base)
after = versions("HEAD")
catalog = json.loads(catalog_path.read_text())
kinds = {item["repository"]: item["kind"] for item in catalog["packages"]}

for repository in sorted(after):
    if before.get(repository) == after[repository]:
        continue
    kind = kinds.get(repository)
    if kind is None:
        raise SystemExit(f"changed component {repository!r} is missing from the package catalog")
    print(repository, kind, after[repository], sep="\t")

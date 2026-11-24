#!/usr/bin/env python3
"""Write kubeconform JSON schemas for every version of the CRDs in a manifest.

Usage: crd-to-schema.py <crds.yaml> <out dir> [crd name ...]

Output: <out dir>/<group>/<kind lowercase>_<version>.json, the layout that
kubeconform's -schema-location template expects. Objects with properties
get additionalProperties: false (strict mode), unless the CRD preserves
unknown fields there. Stdlib only: the CRD is read as JSON via `kubectl`
if PyYAML is missing.
"""
import json
import os
import subprocess
import sys


def load(path):
    try:
        import yaml  # noqa: F401
        with open(path) as f:
            return [d for d in yaml.safe_load_all(f) if d]
    except ImportError:
        out = subprocess.run(["kubectl", "create", "--dry-run=client", "-o", "json", "-f", path],
                             check=True, capture_output=True, text=True).stdout
        doc = json.loads(out)
        return doc.get("items", [doc])


def strict(node):
    if isinstance(node, dict):
        if "properties" in node and not node.get("x-kubernetes-preserve-unknown-fields"):
            node.setdefault("additionalProperties", False)
        for v in node.values():
            strict(v)
    elif isinstance(node, list):
        for v in node:
            strict(v)
    return node


def main():
    src, out_dir, *names = sys.argv[1:]
    for doc in load(src):
        if doc.get("kind") != "CustomResourceDefinition":
            continue
        if names and doc["metadata"]["name"] not in names:
            continue
        spec = doc["spec"]
        for v in spec["versions"]:
            schema = strict(v["schema"]["openAPIV3Schema"])
            path = os.path.join(out_dir, spec["group"], f"{spec['names']['kind'].lower()}_{v['name']}.json")
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w") as f:
                json.dump(schema, f, indent=1, sort_keys=True)
                f.write("\n")
            print(path)


if __name__ == "__main__":
    main()

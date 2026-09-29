#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml>=6"]
# ///
"""Offline check of the whole repo before you push.

1. Every Helm-based Argo CD Application in argocd/ (including the not-yet-enabled stages in
   argocd/later/) is rendered with `helm template`, using the
   exact chart version and values it declares. Charts that ship a values.schema.json reject
   unknown keys; for the others, spot-check the rendered output.
2. The rendered output plus all plain manifests in apps/, argocd/ and bootstrap/ go through
   kubeconform. CRDs are checked against the Datree CRDs-catalog schemas.
3. Stage check: every custom resource used by an *enabled* app (argocd/*.yaml) must have its CRD
   provided by an enabled chart or by k3s itself. Otherwise the sync fails until a later stage
   is turned on.

Needs: uv (fetches Python + PyYAML itself, from the block above), helm and kubeconform on PATH.
Usage: scripts/validate.py [--k8s-version 1.36.0]
"""
import argparse
import pathlib
import subprocess
import sys
import tempfile

import yaml

ROOT = pathlib.Path(__file__).resolve().parent.parent

# PyYAML reads a bare `=` (e.g. `- =` in the Prometheus Operator CRDs' enums) as the obscure
# YAML "value" tag and can't construct it. Kubernetes treats it as the string "=", so do the same.
yaml.SafeLoader.add_constructor("tag:yaml.org,2002:value", lambda loader, node: loader.construct_scalar(node))
SCHEMAS = [
    "default",
    "https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json",
]


def run(cmd, **kw):
    return subprocess.run(cmd, check=True, text=True, capture_output=True, **kw)


def helm_sources(app):
    spec = app["spec"]
    for src in spec.get("sources") or [spec.get("source")]:
        if src and src.get("chart"):
            yield src


def render(app, src, workdir):
    name = app["metadata"]["name"]
    helm = src.get("helm", {})
    args = [
        "helm", "template", helm.get("releaseName", name), src["chart"],
        "--repo", src["repoURL"], "--version", src["targetRevision"],
        "--namespace", app["spec"]["destination"]["namespace"],
        "--include-crds",
    ]
    for vf in helm.get("valueFiles", []):
        args += ["-f", str(ROOT / vf.replace("$values/", ""))]
    if "valuesObject" in helm:
        vals = workdir / f"{name}-values.yaml"
        vals.write_text(yaml.safe_dump(helm["valuesObject"]))
        args += ["-f", str(vals)]
    out = run(args).stdout
    dest = workdir / f"{name}.rendered.yaml"
    dest.write_text(out)
    return dest


BUILTIN_GROUPS = {
    "", "apps", "batch", "policy", "networking.k8s.io", "rbac.authorization.k8s.io",
    "storage.k8s.io", "apiextensions.k8s.io", "admissionregistration.k8s.io", "autoscaling",
    "scheduling.k8s.io", "coordination.k8s.io", "discovery.k8s.io",
    # installed by k3s itself
    "helm.cattle.io", "k3s.cattle.io", "traefik.io", "traefik.containo.us",
}


def docs(path):
    return [d for d in yaml.safe_load_all(pathlib.Path(path).read_text()) if isinstance(d, dict)]


def stage_check(rendered_enabled):
    provided = set()
    for f in rendered_enabled:
        for d in docs(f):
            if d.get("kind") == "CustomResourceDefinition":
                provided.add((d["spec"]["group"], d["spec"]["names"]["kind"]))
    problems = []
    for f in sorted((ROOT / "argocd").glob("*.yaml")):
        app = yaml.safe_load(f.read_text())
        src = app["spec"].get("source") or {}
        if not src.get("path"):
            continue
        base = ROOT / src["path"]
        files = base.rglob("*.yaml") if src.get("directory", {}).get("recurse") else base.glob("*.yaml")
        for m in sorted(files):
            for d in docs(m):
                group = d.get("apiVersion", "").rpartition("/")[0]
                if group not in BUILTIN_GROUPS and (group, d.get("kind")) not in provided:
                    problems.append(f"{m.relative_to(ROOT)}: {d.get('kind')} ({group}) needs a CRD "
                                    f"that no enabled app installs")
    return problems


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--k8s-version", default="1.36.0")
    opts = ap.parse_args()

    failed = False
    with tempfile.TemporaryDirectory() as tmp:
        workdir = pathlib.Path(tmp)
        rendered, rendered_enabled = [], []
        for f in sorted((ROOT / "argocd").rglob("*.yaml")):
            app = yaml.safe_load(f.read_text())
            for src in helm_sources(app):
                try:
                    out = render(app, src, workdir)
                    rendered.append(out)
                    if f.parent == ROOT / "argocd":
                        rendered_enabled.append(out)
                    print(f"helm ok    {f.relative_to(ROOT)} ({src['chart']} {src['targetRevision']})")
                except subprocess.CalledProcessError as e:
                    failed = True
                    print(f"helm FAIL  {f.relative_to(ROOT)}\n{e.stderr}")

        plain = [str(p) for d in ("apps", "argocd", "bootstrap") for p in (ROOT / d).rglob("*.yaml")
                 if p.name != "argocd-values.yaml"]
        cmd = ["kubeconform", "-strict", "-summary", "-output", "text",
               "-kubernetes-version", opts.k8s_version, "-ignore-missing-schemas"]
        for s in SCHEMAS:
            cmd += ["-schema-location", s]
        res = subprocess.run(cmd + plain + [str(r) for r in rendered], text=True, capture_output=True)
        print(res.stdout.strip())
        if res.returncode:
            failed = True
            print(res.stderr.strip())

        problems = stage_check(rendered_enabled)
        for p in problems:
            print(f"stage FAIL {p}")
        if problems:
            failed = True
        else:
            print("stage ok   every custom resource in enabled apps has its CRD installed")

    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()

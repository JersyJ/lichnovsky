#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml>=6"]
# ///
"""Offline check of the repo before pushing.

1. Render every Helm-based Application in argocd/ (including argocd/later/) with its pinned chart
   version and values.
2. Run kubeconform over the rendered output and all plain manifests (CRDs via the Datree catalog).
   Folders with a kustomization.yaml are rendered with `kubectl kustomize` first, as Argo CD does.
3. Stage check: every custom resource in an enabled app (argocd/*.yaml) needs its CRD from an
   enabled chart or from k3s, otherwise the sync fails.

Charts and schemas are cached in ~/.cache/lichnovsky, so repeat runs are fast.
Needs helm, kubectl and kubeconform. Run it with `prek run validate-manifests --hook-stage pre-push`.
"""
import argparse
import os
import pathlib
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor

import yaml

ROOT = pathlib.Path(__file__).resolve().parent.parent
CACHE = pathlib.Path(os.environ.get("XDG_CACHE_HOME", pathlib.Path.home() / ".cache")) / "lichnovsky"
SCHEMAS = [
    "default",
    "https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json",
]
BUILTIN_GROUPS = {
    "", "apps", "batch", "policy", "networking.k8s.io", "rbac.authorization.k8s.io",
    "storage.k8s.io", "apiextensions.k8s.io", "admissionregistration.k8s.io", "autoscaling",
    "scheduling.k8s.io", "coordination.k8s.io", "discovery.k8s.io",
    # installed by k3s itself
    "helm.cattle.io", "k3s.cattle.io", "traefik.io", "traefik.containo.us",
}

Loader = getattr(yaml, "CSafeLoader", yaml.SafeLoader)  # libyaml: much faster on the big CRDs
# The Prometheus Operator CRDs contain a bare `=`, which PyYAML reads as the YAML "value" tag.
Loader.add_constructor("tag:yaml.org,2002:value", lambda loader, node: loader.construct_scalar(node))


def run(cmd):
    return subprocess.run(cmd, check=True, text=True, capture_output=True).stdout


def docs(path):
    return [d for d in yaml.load_all(pathlib.Path(path).read_text(), Loader) if isinstance(d, dict)]


def chart(src):
    """Local .tgz of the chart, downloaded once."""
    dest = CACHE / "charts" / f"{src['chart']}-{src['targetRevision']}"
    if not any(dest.glob("*.tgz")):
        dest.mkdir(parents=True, exist_ok=True)
        run(["helm", "pull", src["chart"], "--repo", src["repoURL"], "--version", src["targetRevision"],
             "-d", str(dest)])
    return next(dest.glob("*.tgz"))


def render(job, workdir):
    f, app, src = job
    name = app["metadata"]["name"]
    helm = src.get("helm", {})
    args = ["helm", "template", helm.get("releaseName", name), str(chart(src)),
            "--namespace", app["spec"]["destination"]["namespace"], "--include-crds"]
    for vf in helm.get("valueFiles", []):
        args += ["-f", str(ROOT / vf.replace("$values/", ""))]
    if "valuesObject" in helm:
        vals = workdir / f"{name}-values.yaml"
        vals.write_text(yaml.safe_dump(helm["valuesObject"]))
        args += ["-f", str(vals)]
    out = workdir / f"{name}.rendered.yaml"
    out.write_text(run(args))
    return out


def kustomize(workdir):
    """{folder: rendered file} for every Kustomize folder."""
    out = {}
    for k in sorted(ROOT.glob("*/**/kustomization.yaml")):
        dest = workdir / f"kustomize-{k.parent.relative_to(ROOT).as_posix().replace('/', '-')}.yaml"
        dest.write_text(run(["kubectl", "kustomize", str(k.parent)]))
        out[k.parent] = dest
    return out


def stage_check(rendered_enabled, kustomized):
    provided = {(d["spec"]["group"], d["spec"]["names"]["kind"])
                for f in rendered_enabled for d in docs(f) if d.get("kind") == "CustomResourceDefinition"}
    problems = []
    for f in sorted((ROOT / "argocd").glob("*.yaml")):
        src = yaml.safe_load(f.read_text())["spec"].get("source") or {}
        if not src.get("path"):
            continue
        base = ROOT / src["path"]
        if base in kustomized:
            files = [kustomized[base]]
        else:
            files = base.rglob("*.yaml") if src.get("directory", {}).get("recurse") else base.glob("*.yaml")
        for m in sorted(files):
            for d in docs(m):
                group = d.get("apiVersion", "").rpartition("/")[0]
                if group not in BUILTIN_GROUPS and (group, d.get("kind")) not in provided:
                    problems.append(f"{src['path']}: {d.get('kind')} ({group}) needs a CRD "
                                    f"that no enabled app installs")
    return problems


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--k8s-version", default="1.36.0")
    opts = ap.parse_args()

    jobs = []
    for f in sorted((ROOT / "argocd").rglob("*.yaml")):
        app = yaml.safe_load(f.read_text())
        spec = app["spec"]
        jobs += [(f, app, s) for s in spec.get("sources") or [spec.get("source")] if s and s.get("chart")]

    failed = False
    with tempfile.TemporaryDirectory() as tmp, ThreadPoolExecutor() as pool:
        workdir = pathlib.Path(tmp)
        rendered, rendered_enabled = [], []
        futures = [pool.submit(render, job, workdir) for job in jobs]
        for (f, _, src), fut in zip(jobs, futures):
            label = f"{f.relative_to(ROOT)} ({src['chart']} {src['targetRevision']})"
            try:
                out = fut.result()
            except subprocess.CalledProcessError as e:
                failed = True
                print(f"helm FAIL  {label}\n{e.stderr}")
                continue
            print(f"helm ok    {label}")
            rendered.append(out)
            if f.parent == ROOT / "argocd":
                rendered_enabled.append(out)

        kustomized = kustomize(workdir)
        plain = [str(p) for d in ("apps", "platform", "argocd", "bootstrap") for p in (ROOT / d).rglob("*.yaml")
                 if p.name != "argocd-values.yaml" and not any(k in p.parents for k in kustomized)]
        plain += [str(r) for r in kustomized.values()]
        schema_cache = CACHE / "kubeconform"
        schema_cache.mkdir(parents=True, exist_ok=True)
        cmd = ["kubeconform", "-strict", "-summary", "-output", "text", "-n", str(os.cpu_count() or 4),
               "-cache", str(schema_cache), "-kubernetes-version", opts.k8s_version, "-ignore-missing-schemas"]
        for s in SCHEMAS:
            cmd += ["-schema-location", s]
        res = subprocess.run(cmd + plain + [str(r) for r in rendered], text=True, capture_output=True)
        print(res.stdout.strip())
        if res.returncode:
            failed = True
            print(res.stderr.strip())

        problems = stage_check(rendered_enabled, kustomized)
        for p in problems:
            print(f"stage FAIL {p}")
        failed |= bool(problems)
        if not problems:
            print("stage ok   every custom resource in enabled apps has its CRD installed")

    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()

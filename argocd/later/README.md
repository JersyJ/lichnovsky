# Staged rollout

The root app syncs only the files directly in `argocd/`. It doesn't read subfolders, so nothing in
`later/` is deployed. Enable one stage at a time, then watch RAM in Grafana before the next:

```bash
git mv argocd/later/stage-2-observability/*.yaml argocd/
git commit -m "feat: enable stage 2 (observability)" && git push
```

| Stage | Contents | Check before moving on |
|---|---|---|
| 1 (already in `argocd/`) | Argo CD, Sealed Secrets, cert-manager, platform, cloudflared, website | site loads on https://lichnovsky.eu; wildcard cert `Ready` |
| 2 `stage-2-observability` | kube-prometheus-stack, Loki, Alloy, monitors + Discord alerts | test alert reaches Discord; note baseline RAM |
| 3 `stage-3-critical` | Vaultwarden, AdGuard, Tailscale, k8up + rest-server | first nightly backup ok; **do a restore test** |
| 4 `stage-4-apps` | Papra, Uptime Kuma | RAM still comfortable |
| 5 `stage-5-heavy` | CloudNativePG + Immich, Jellyfin | first import overnight at low job concurrency; watch memory |

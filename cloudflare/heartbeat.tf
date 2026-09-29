# External heartbeat: a Cloudflare Worker checks the site every 5 minutes and posts to Discord when
# it goes down or comes back. It runs on Cloudflare, not on the Pi, so it catches the Pi, its power,
# its internet or the tunnel being gone. Code: workers/heartbeat.js. Free plan limits: well within.

resource "cloudflare_workers_kv_namespace" "heartbeat" {
  account_id = var.account_id
  title      = "lichnovsky-heartbeat-state"
}

resource "cloudflare_workers_script" "heartbeat" {
  account_id         = var.account_id
  script_name        = "lichnovsky-heartbeat"
  main_module        = "heartbeat.js"
  content_file       = "${path.module}/workers/heartbeat.js"
  content_sha256     = filesha256("${path.module}/workers/heartbeat.js") # redeploy when the code changes
  compatibility_date = "2026-09-01"

  bindings = [
    {
      name         = "STATE"
      type         = "kv_namespace"
      namespace_id = cloudflare_workers_kv_namespace.heartbeat.id
    },
    {
      name = "TARGET_URL"
      type = "plain_text"
      text = "https://${var.domain}/healthz"
    },
    {
      name = "DISCORD_WEBHOOK_URL"
      type = "secret_text"
      text = var.discord_webhook_url
    },
  ]
}

resource "cloudflare_workers_cron_trigger" "heartbeat" {
  account_id  = var.account_id
  script_name = cloudflare_workers_script.heartbeat.script_name
  schedules   = [{ cron = "*/5 * * * *" }]
}

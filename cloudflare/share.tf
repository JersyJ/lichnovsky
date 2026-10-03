# Storage for share.lichnovsky.eu (Gokapi, apps/share). Videos go to this bucket, and viewers download
# them straight from R2 through presigned links: Cloudflare's terms forbid serving video through the
# CDN (the tunnel), but R2 is meant for it, and R2 egress is free.
resource "cloudflare_r2_bucket" "share" {
  account_id = var.account_id
  name       = "lichnovsky-share"
  location   = "EEUR"
}

# Gokapi deletes a share when it expires (14 days by default; the guide says 14 is the maximum). This
# rule is the safety net: whatever is still in the bucket after 15 days goes, and so do uploads that
# never finished.
resource "cloudflare_r2_bucket_lifecycle" "share" {
  account_id  = var.account_id
  bucket_name = cloudflare_r2_bucket.share.name

  rules = [{
    id         = "expire-after-15-days"
    enabled    = true
    conditions = { prefix = "" }
    delete_objects_transition = {
      condition = { type = "Age", max_age = 15 * 24 * 3600 }
    }
    abort_multipart_uploads_transition = {
      condition = { type = "Age", max_age = 24 * 3600 }
    }
  }]
}

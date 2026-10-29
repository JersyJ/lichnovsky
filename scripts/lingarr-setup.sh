#!/usr/bin/env bash
# One-time Lingarr setup after a new (empty) config volume: finish the onboarding without a login,
# and store the DeepL key from the Secret `lingarr`. Lingarr 1.4.1 does not apply DEEPL_API_KEY
# from the env (the setting stays empty), so the key goes in through its settings API, as the UI
# does it. Runs in the Bazarr pod, the only pod that may connect (NetworkPolicy). The key goes
# only through stdin.
# Usage: scripts/lingarr-setup.sh     (needs cluster access)
set -euo pipefail

code='
import json, sys, urllib.request, urllib.error
key = sys.stdin.read().strip()
def call(path, body):
    req = urllib.request.Request("http://lingarr:9876" + path, data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    try:
        return urllib.request.urlopen(req, timeout=120).status
    except urllib.error.HTTPError as e:
        return e.code
onboarding = call("/api/auth/onboarding", {"enableUserAuth": "false"})
print("onboarding:", {200: "done", 409: "was already done"}.get(onboarding, onboarding))
print("DeepL key:", "saved" if call("/api/setting/encrypted", {"key": "deepl_api_key", "value": key}) == 200 else "FAILED")
lines = [{"position": 0, "line": "Where are you going?"}]
req = urllib.request.Request("http://lingarr:9876/api/translate/content",
    data=json.dumps({"arrMediaId": 0, "title": "setup test", "sourceLanguage": "en", "targetLanguage": "cs",
                     "mediaType": "Movie", "lines": lines}).encode(), headers={"Content-Type": "application/json"})
try:
    print("test:", json.load(urllib.request.urlopen(req, timeout=120))[0]["line"])
except urllib.error.HTTPError as e:
    sys.exit("test FAILED: " + e.read().decode()[:300])
'

kubectl -n tv get secret lingarr -o jsonpath='{.data.DEEPL_API_KEY}' | base64 -d |
  kubectl -n tv exec -i deploy/bazarr -- python3 -c "$code"

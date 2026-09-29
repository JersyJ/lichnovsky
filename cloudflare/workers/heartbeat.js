// Heartbeat for lichnovsky.eu, running on Cloudflare (so it keeps working when the Pi is down).
// Every 5 minutes (cron trigger, see heartbeat.tf) it fetches TARGET_URL through Cloudflare, the
// same way visitors do. It posts to Discord only when the state changes:
//   down   after 2 consecutive failed checks (~10 min), so a short blip doesn't page you
//   up     when it answers again, with the approximate downtime
// State lives in the STATE KV namespace: status ("up" | "down"), fails, since (first failed check).

const FAILS_BEFORE_ALERT = 2;

export default {
  async scheduled(event, env, ctx) {
    const { ok, detail } = await probe(env.TARGET_URL);
    const status = (await env.STATE.get("status")) ?? "up";
    const stored = Number((await env.STATE.get("fails")) ?? 0);
    const fails = ok ? 0 : stored + 1;
    if (fails !== stored) await env.STATE.put("fails", String(fails)); // only write when it changes
    if (fails === 1) await env.STATE.put("since", String(Date.now())); // first failed check = outage start

    if (status === "up" && fails >= FAILS_BEFORE_ALERT) {
      await notify(env, `🔴 **lichnovsky.eu is DOWN** (${detail}). The Pi, its power or internet, or the tunnel is unreachable.`);
      await env.STATE.put("status", "down");
    } else if (status === "down" && ok) {
      const since = Number(await env.STATE.get("since"));
      const minutes = since ? Math.round((Date.now() - since) / 60000) : null;
      await notify(env, `🟢 **lichnovsky.eu is back up**${minutes !== null ? ` after ~${minutes} min` : ""}.`);
      await env.STATE.put("status", "up");
    }
  },
};

async function probe(url) {
  try {
    // Unique query string: never answered from Cloudflare's cache. No redirects followed.
    const res = await fetch(`${url}?probe=${Date.now()}`, {
      redirect: "manual",
      signal: AbortSignal.timeout(10_000),
    });
    return { ok: res.status === 200, detail: `HTTP ${res.status}` };
  } catch (err) {
    return { ok: false, detail: err.name === "TimeoutError" ? "no answer within 10 s" : String(err) };
  }
}

async function notify(env, content) {
  await fetch(env.DISCORD_WEBHOOK_URL, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ content }),
  });
}

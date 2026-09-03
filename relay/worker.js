// Caraoke Lyric Relay — Cloudflare Worker (mechanism #2, see README.md).
//
// The app POSTs a full lyric schedule + activity push token once per ride;
// this worker holds the session in a Durable Object and fires an APNs
// live-activity push at every line boundary. Because the pushes come from
// here (not the app process), lyrics keep advancing while iOS has suspended
// the app — the driving/locked-phone case.
//
// Designed around Apple's documented store-safe path for background-updated
// Live Activities: APNs auth key is the ONLY server-side secret.

const APNS_HOST = "https://api.push.apple.com";

// ---------------------------------------------------------------------------
// APNs provider token (ES256 JWT signed with the .p8 auth key)
// ---------------------------------------------------------------------------

function pemToDer(pem) {
  const body = pem
    .replace(/-----BEGIN [^-]+-----/g, "")
    .replace(/-----END [^-]+-----/g, "")
    .replace(/\s+/g, "");
  const bin = atob(body);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function base64url(bytes) {
  let out = "";
  for (const b of bytes) out += String.fromCharCode(b);
  return btoa(out).replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_");
}

// Cloudflare Workers' crypto.subtle.sign("ECDSA", ...) returns the signature
// as RAW r||s (64 bytes for P-256), which is EXACTLY what a JWT ES256 header
// needs. It is NOT DER-encoded. (A prior version assumed DER and threw
// "not a DER sequence" on every push — the live-activity freeze root cause.)

// APNs provider-token budget: Apple requires updating the auth token NO MORE
// THAN ONCE EVERY 20 MINUTES (TooManyProviderTokenUpdates otherwise; each
// dropped push = a skipped lyric line on the lock screen). One token is valid
// for up to an hour, so reuse a single cached token and rotate conservatively.
let providerTokenCache = null; // { token, issuedAtMs }
const PROVIDER_TOKEN_TTL_MS = 30 * 60 * 1000; // rotate well within the hour

async function buildProviderToken(env) {
  const der = pemToDer(env.APNS_KEY_P8);
  const key = await crypto.subtle.importKey(
    "pkcs8", der,
    { name: "ECDSA", namedCurve: "P-256" },
    false, ["sign"]
  );
  const header = { alg: "ES256", kid: env.APNS_KEY_ID };
  const payload = { iss: env.APNS_TEAM_ID, iat: Math.floor(Date.now() / 1000) };
  const signingInput = `${base64url(new TextEncoder().encode(JSON.stringify(header)))}.${base64url(new TextEncoder().encode(JSON.stringify(payload)))}`;
  const sig = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" }, key,
    new TextEncoder().encode(signingInput)
  );
  const raw = new Uint8Array(sig); // raw r||s (64 bytes)
  return `${signingInput}.${base64url(raw)}`;
}

async function apnsProviderToken(env, forceNew = false) {
  const now = Date.now();
  if (!forceNew && providerTokenCache && now - providerTokenCache.issuedAtMs < PROVIDER_TOKEN_TTL_MS) {

    return providerTokenCache.token;
}
  const token = await buildProviderToken(env);
  providerTokenCache = { token, issuedAtMs: now };
  return token;
}

async function push(env, deviceToken, aps) {
  let token = await apnsProviderToken(env);
  let res = await fetch(`${APNS_HOST}/3/device/${deviceToken}`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${token}`,
      "apns-topic": `${env.APP_BUNDLE_ID}.push-type.liveactivity`,
      "apns-push-type": "liveactivity",
      "apns-priority": "10",
      "content-type": "application/json",
    },
    body: JSON.stringify({ aps }),
  });
  if (res.status !== 200) {
    // Visible in `wrangler tail` — the only way to debug APNs rejections.
    const body = await res.text();
    console.log(`APNs ${res.status} ${body.slice(0, 200)}`);
    // Stale/rotated provider token: rotate once and retry.
    if (res.status === 403 && (body.includes("ExpiredProviderToken") || body.includes("InvalidProviderToken"))) {
      console.log("provider token invalid — rotating and retrying once");
      providerTokenCache = null;
      token = await apnsProviderToken(env, true);
      const retry = await fetch(`${APNS_HOST}/3/device/${deviceToken}`, {
        method: "POST",
        headers: {
          authorization: `Bearer ${token}`,
          "apns-topic": `${env.APP_BUNDLE_ID}.push-type.liveactivity`,
          "apns-push-type": "liveactivity",
          "apns-priority": "10",
          "content-type": "application/json",
        },
        body: JSON.stringify({ aps }),
      });
      if (retry.status !== 200) {
        console.log(`APNs-retry ${retry.status} ${(await retry.text()).slice(0, 200)}`);
      } else {
        console.log(`APNs 200 ok (after rotation) event=${aps.event} line="${(aps["content-state"]?.currentLine ?? "").slice(0, 40)}"`);
      }
      return retry.status;
    }
    // Environment A/B probe: a 403 BadEnvironmentKeyInToken on production can
    // mean the TOKEN is sandbox-environment (TestFlight behavior is disputed)
    // or the KEY is sandbox-scoped. Retrying the same push on sandbox tells
    // the two apart: BadDeviceToken => token is production (key is at fault);
    // 200/other => the token is sandbox and the host choice must follow.
    if (res.status === 403 && body.includes("BadEnvironmentKeyInToken")) {
      const sandbox = await fetch(`https://api.sandbox.push.apple.com/3/device/${deviceToken}`, {
        method: "POST",
        headers: {
          authorization: `Bearer ${token}`,
          "apns-topic": `${env.APP_BUNDLE_ID}.push-type.liveactivity`,
          "apns-push-type": "liveactivity",
          "apns-priority": "10",
          "content-type": "application/json",
        },
        body: JSON.stringify({ aps }),
      });
      console.log(`APNs SANDBOX-PROBE ${sandbox.status} ${(await sandbox.text()).slice(0, 200)}`);
    }
  } else {
    console.log(`APNs 200 ok event=${aps.event} line="${(aps["content-state"]?.currentLine ?? "").slice(0, 40)}"`);
  }
  return res.status;
}

// ---------------------------------------------------------------------------
// Schedule maths (pure)
// ---------------------------------------------------------------------------

function lineAt(lines, nowMs, startEpochMs) {
  const pos = nowMs - startEpochMs;
  let index = null;
  for (let i = 0; i < lines.length; i++) {
    if (lines[i].t <= pos) index = i; else break;
  }
  return index;
}

// Next line boundary strictly after nowMs, or null past the schedule end.
function nextBoundaryAt(lines, startEpochMs, nowMs) {
  for (const line of lines) {
    const at = startEpochMs + line.t;
    if (at > nowMs + 250) return at; // 250 ms cushion
  }
  return null; // past the last line
}

function contentState(session, nowMs) {
  // Paused: the client froze positionMs on pause and POSTed a fresh
  // startEpochMs = capturedAt - positionMs, so this same wall-clock now
  // maps to the frozen line. No alarms run while paused (scheduleFrom
  // below), so the tile keeps this state until the client resumes.
  const index = lineAt(session.lines, nowMs, session.startEpochMs);
  const currentLine = index === null ? (session.lines[0]?.text ?? "") : session.lines[index].text;
  const nextLine = index === null
    ? (session.lines[1]?.text ?? session.lines[0]?.text ?? "")
    : (session.lines[index + 1]?.text ?? "");
  const duration = Math.max(session.endAtEpochMs - session.startEpochMs, 1);
  const progress = Math.min(Math.max((nowMs - session.startEpochMs) / duration, 0), 1);
  return {
    title: session.trackTitle,
    artist: session.trackArtist,
    currentLine,
    nextLine,
    isPlaying: session.isPlaying !== false,
    progress,
  };
}

// ---------------------------------------------------------------------------
// Durable Object: holds one active ride, alarms at each line boundary
// ---------------------------------------------------------------------------

export class LyricsSession {
  constructor(state, env) {
    this.state = state;
    this.env = env;
  }

  async fetch(request) {
    if (request.method !== "POST") {
      return new Response("method not allowed", { status: 405 });
    }
    const url = new URL(request.url);
    if (url.pathname !== "/sessions") {
      return new Response("not found", { status: 404 });
    }
    const session = await request.json();
    if (session.action === "end") {
      // Explicit ride stop: push an end so a stale tile is dismissed even if
      // the app-side activity never ended, then drop the session.
      const stored = await this.state.storage.get("session");
      if (stored) {
        await push(this.env, stored.activityPushToken, {
          timestamp: Math.floor(Date.now() / 1000),
          event: "end",
          "content-state": contentState(stored, Date.now()),
        }).catch(() => {});
        console.log(`END action — session dropped (track="${stored.trackTitle}")`);
      } else {
        console.log("END action — no session stored");
      }
      await this.state.storage.delete("session");
      await this.state.storage.deleteAlarm();
      return new Response("ok", { status: 200 });
    }
    if (!session.activityPushToken || !Array.isArray(session.lines) || !session.startEpochMs) {
      console.log(`REJECT bad session: token=${!!session.activityPushToken} lines=${session.lines?.length} start=${session.startEpochMs}`);
      return new Response("invalid session", { status: 400 });
    }
    session.isPlaying = session.isPlaying !== false; // default true
    console.log(`REGISTER track="${session.trackTitle}" lines=${session.lines.length} startEpochMs=${session.startEpochMs} endAt=${session.endAtEpochMs} playing=${session.isPlaying} tokenPrefix=${String(session.activityPushToken).slice(0, 8)}`);
    await this.state.storage.put("session", session);
    await this.scheduleFrom(Date.now());
    return new Response("ok", { status: 200 });
  }

  async alarm() {
    await this.scheduleFrom(Date.now());
  }

  // Fired by the DO alarm (one per line boundary) and by session POSTs.
  // Push-then-arm: at each wake, push the CURRENT line, then arm for the
  // next boundary strictly in the future. This handles both the normal
  // path (alarm fires exactly at a boundary) and catch-up (long sleep ->
  // several boundaries passed: one push with the current line, next arm
  // at the following boundary).
  async scheduleFrom(nowMs) {
    const session = await this.state.storage.get("session");
    if (!session) {
      console.log(`schedule: no session stored`);
      return;
    }

    if (session.isPlaying === false) {
      // Paused: push the frozen line once (isPlaying:false), then arm
      // NOTHING. The tile stays until the client re-registers on resume
      // (a fresh POST with a new startEpochMs that re-enters this method
      // with isPlaying:true). No end push at track end while paused.
      await push(this.env, session.activityPushToken, {
        timestamp: Math.floor(nowMs / 1000),
        event: "update",
        "content-state": contentState(session, nowMs),
      });
      await this.state.storage.deleteAlarm();
      console.log(`schedule: PAUSED (frozen push sent, no alarms)`);
      return;
    }

    if (nowMs >= session.endAtEpochMs) {
      await push(this.env, session.activityPushToken, {
        timestamp: Math.floor(session.endAtEpochMs / 1000),
        event: "end",
        "content-state": contentState(session, session.endAtEpochMs),
      });
      await this.state.storage.delete("session");
      console.log("schedule: session ended + deleted");
      return;
    }

    // Push the line that is playing RIGHT NOW (lineAt is boundary-inclusive).
    const index = lineAt(session.lines, nowMs, session.startEpochMs);
    const cur = index === null ? (session.lines[0]?.text ?? "") : session.lines[index].text;
    console.log(`schedule: push line#${index} "${cur.slice(0, 30)}" now=${nowMs}`);
    try {
      await push(this.env, session.activityPushToken, {
        timestamp: Math.floor(nowMs / 1000),
        event: "update",
        "content-state": contentState(session, nowMs),
      });
    } catch (err) {
      console.log(`schedule: push threw ${err.message}`);
    }

    // Arm for the next boundary strictly after now (250 ms cushion avoids
    // re-firing on the same instant), or a 15 s heartbeat past the last
    // line so the tile stays fresh until endAt.
    const boundary = nextBoundaryAt(session.lines, session.startEpochMs, nowMs);
    const nextWake = boundary ?? Math.min(nowMs + 15_000, session.endAtEpochMs);
    try {
      await this.state.storage.setAlarm(new Date(nextWake));
      console.log(`schedule: armed next alarm in ${Math.round((nextWake - nowMs) / 1000)}s`);
    } catch (err) {
      console.log(`schedule: setAlarm threw ${err.message}`);
    }
  }
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname.startsWith("/sessions")) {
      const id = env.LyricsSession.idFromName("caraoke-ride");
      return env.LyricsSession.get(id).fetch(request);
    }
    return new Response("not found", { status: 404 });
  },
};
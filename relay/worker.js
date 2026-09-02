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

// WebCrypto ECDSA returns ASN.1 DER (r, s); JWT ES256 needs raw r||s.
function derSignatureToRaw(der) {
  let p = 0;
  if (der[p++] !== 0x30) throw new Error("not a DER sequence");
  const readInt = () => {
    if (der[p++] !== 0x02) throw new Error("not an INTEGER");
    const len = der[p++];
    const start = p;
    p += len;
    let bytes = der.slice(start, p);
    while (bytes.length > 32 && bytes[0] === 0) bytes = bytes.slice(1);
    if (bytes.length > 32) throw new Error("INTEGER too long for P-256");
    const out = new Uint8Array(32);
    out.set(bytes, 32 - bytes.length);
    return out;
  };
  const r = readInt();
  const s = readInt();
  const out = new Uint8Array(64);
  out.set(r, 0);
  out.set(s, 32);
  return out;
}

async function apnsProviderToken(env) {
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
  const raw = derSignatureToRaw(new Uint8Array(sig));
  return `${signingInput}.${base64url(raw)}`;
}

async function push(env, deviceToken, aps) {
  const token = await apnsProviderToken(env);
  const res = await fetch(`${APNS_HOST}/3/device/${deviceToken}`, {
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
    console.log(`APNs ${res.status}: ${await res.text()}`);
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
    isPlaying: true,
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
    if (!session.activityPushToken || !Array.isArray(session.lines) || !session.startEpochMs) {
      return new Response("invalid session", { status: 400 });
    }
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
    if (!session) return;

    if (nowMs >= session.endAtEpochMs) {
      await push(this.env, session.activityPushToken, {
        timestamp: Math.floor(session.endAtEpochMs / 1000),
        event: "end",
        "content-state": contentState(session, session.endAtEpochMs),
      });
      await this.state.storage.delete("session");
      return;
    }

    // Push the line that is playing RIGHT NOW (lineAt is boundary-inclusive).
    await push(this.env, session.activityPushToken, {
      timestamp: Math.floor(nowMs / 1000),
      event: "update",
      "content-state": contentState(session, nowMs),
    });

    // Arm for the next boundary strictly after now (250 ms cushion avoids
    // re-firing on the same instant), or a 15 s heartbeat past the last
    // line so the tile stays fresh until endAt.
    const boundary = nextBoundaryAt(session.lines, session.startEpochMs, nowMs);
    const nextWake = boundary ?? Math.min(nowMs + 15_000, session.endAtEpochMs);
    await this.state.storage.setAlarm(new Date(nextWake));
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
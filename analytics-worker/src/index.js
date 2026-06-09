// First-party analytics collector for mdeeb.dev.
// Accepts sendBeacon POSTs from the portfolio shell/game and writes rows to D1.
// Privacy: no cookies, no IP stored, raw UA discarded after deriving device class.

const ALLOWED_EVENTS = new Set([
  'page_load',
  'boot_ready',
  'enter_completed',
  'boot_error',
  'session_ping',
  'game_started',
  'first_move',
  'zone_visited',
  'dialogue_opened',
  'dialogue_completed',
]);

const BOT_RE = /bot|crawl|spider|headless|python|curl|wget|preview/i;
const ORIGIN_RE = /^https:\/\/mdeeb\.dev$|^http:\/\/localhost(:\d+)?$/;
const MAX_BODY_BYTES = 2048;

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (url.pathname !== '/api/event') {
      return new Response('not found', { status: 404 });
    }
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204 });
    }
    if (request.method !== 'POST') {
      return new Response('method not allowed', { status: 405 });
    }

    // Silent 204s: drop bots and foreign origins without giving feedback.
    const ua = request.headers.get('user-agent') || '';
    if (!ua || BOT_RE.test(ua)) {
      return new Response(null, { status: 204 });
    }
    const origin = request.headers.get('origin');
    if (origin && !ORIGIN_RE.test(origin)) {
      return new Response(null, { status: 204 });
    }

    const text = await request.text();
    if (text.length > MAX_BODY_BYTES) {
      return new Response('too large', { status: 413 });
    }

    let data;
    try {
      data = JSON.parse(text);
    } catch {
      return new Response('bad json', { status: 400 });
    }

    const name = String(data.n || '');
    const sid = String(data.sid || '');
    if (!ALLOWED_EVENTS.has(name) || sid.length < 8 || sid.length > 64) {
      return new Response('bad event', { status: 400 });
    }

    const device = /Mobi|Android|iPhone|iPad/i.test(ua) ? 'mobile' : 'desktop';
    // Geo/network context from Cloudflare's edge — raw IP is never stored.
    const cf = request.cf || {};
    const country = cf.country || '';
    const city = cf.city || '';
    const region = cf.region || '';
    const org = cf.asOrganization || '';
    const props = typeof data.p === 'object' && data.p !== null ? data.p : {};

    ctx.waitUntil(
      env.DB.prepare(
        'INSERT INTO events (session_id, visitor_id, name, src, referrer, device, country, city, region, org, props) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)'
      )
        .bind(
          sid,
          String(data.vid || '').slice(0, 64),
          name,
          String(data.src || '').slice(0, 64),
          String(data.ref || '').slice(0, 256),
          device,
          country,
          String(city).slice(0, 64),
          String(region).slice(0, 64),
          String(org).slice(0, 128),
          JSON.stringify(props).slice(0, 1024)
        )
        .run()
    );

    return new Response(null, { status: 204 });
  },
};

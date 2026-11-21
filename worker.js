/* global ASSETS */
const MAL_API = 'https://api.myanimelist.net/v2';
const MAL_AUTH = 'https://myanimelist.net/v1/oauth2';
const CALLBACK = '/auth/mal/callback';
const STATE_COOKIE = 'ani_oauth';
const SESSION_COOKIE = 'ani_session';
const REFRESH_COOKIE = 'ani_refresh';
const SESSION_AGE = 30 * 24 * 60 * 60;
const enc = new TextEncoder();
const dec = new TextDecoder();

const apiHeaders = { 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' };
const json = (value, status = 200, headers) => Response.json(value, { status, headers: { ...apiHeaders, ...headers } });
const redirect = (location, cookies = []) => {
  const headers = new Headers({ ...apiHeaders, Location: location, 'Referrer-Policy': 'no-referrer' });
  for (const cookie of cookies) headers.append('Set-Cookie', cookie);
  return new Response(null, { status: 303, headers });
};
const within = (value, max) => Number.isInteger(value) && value >= 0 && value <= max;
const random = (size) => base64(crypto.getRandomValues(new Uint8Array(size)));

function base64(bytes) {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function fromBase64(value) {
  return Uint8Array.from(atob(value.replace(/-/g, '+').replace(/_/g, '/')), (char) => char.charCodeAt(0));
}

async function cookieKey(env) {
  const secret = env.MAL_SESSION_SECRET || env.MAL_CLIENT_SECRET;
  const bytes = await crypto.subtle.digest('SHA-256', enc.encode(`ani-ledger:v1:${secret}`));
  return crypto.subtle.importKey('raw', bytes, 'AES-GCM', false, ['encrypt', 'decrypt']);
}

async function seal(env, name, value) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const cipher = await crypto.subtle.encrypt({ name: 'AES-GCM', iv, additionalData: enc.encode(name) }, await cookieKey(env), enc.encode(JSON.stringify(value)));
  return `${base64(iv)}.${base64(new Uint8Array(cipher))}`;
}

async function unseal(request, env, name) {
  const raw = (request.headers.get('Cookie') || '').split(';').map((part) => part.trim()).find((part) => part.startsWith(`${name}=`));
  if (!raw) return null;
  try {
    const [iv, cipher] = raw.slice(name.length + 1).split('.');
    const bytes = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: fromBase64(iv), additionalData: enc.encode(name) }, await cookieKey(env), fromBase64(cipher));
    const value = JSON.parse(dec.decode(bytes));
    return value.until > Date.now() ? value : null;
  } catch {
    return null;
  }
}

function makeCookie(request, name, value, age, path = '/') {
  const secure = new URL(request.url).protocol === 'https:' ? '; Secure' : '';
  return `${name}=${value}; Path=${path}; Max-Age=${age}; HttpOnly; SameSite=Lax${secure}`;
}

function config(env) {
  return Boolean(env.MAL_CLIENT_ID && env.MAL_CLIENT_SECRET && env.MAL_REDIRECT_URI);
}

async function malFetch(path, token, init = {}) {
  return fetch(`${MAL_API}${path}`, {
    ...init,
    headers: { Accept: 'application/json', Authorization: `Bearer ${token}`, ...init.headers },
    redirect: 'error',
    signal: AbortSignal.timeout(9500),
  });
}

async function getTokens(env, fields) {
  const body = new URLSearchParams({ client_id: env.MAL_CLIENT_ID, client_secret: env.MAL_CLIENT_SECRET, ...fields });
  const response = await fetch(`${MAL_AUTH}/token`, { method: 'POST', body, redirect: 'error', signal: AbortSignal.timeout(9500) });
  if (!response.ok) throw new Error('Token exchange failed');
  const token = await response.json();
  if (!token.access_token) throw new Error('No access token received');
  return { access: token.access_token, refresh: token.refresh_token || fields.refresh_token };
}

async function beginAuth(request, env) {
  if (!config(env)) return redirect('/?auth=setup');
  const state = random(24);
  const verifier = random(48);
  const query = new URLSearchParams({
    client_id: env.MAL_CLIENT_ID, response_type: 'code', state,
    redirect_uri: env.MAL_REDIRECT_URI, code_challenge: verifier, code_challenge_method: 'plain',
  });
  const cookie = await seal(env, STATE_COOKIE, { state, verifier, until: Date.now() + 600_000 });
  return redirect(`${MAL_AUTH}/authorize?${query}`, [makeCookie(request, STATE_COOKIE, cookie, 600, CALLBACK)]);
}

async function finishAuth(request, env, url) {
  const clearState = makeCookie(request, STATE_COOKIE, '', 0, CALLBACK);
  if (!config(env)) return redirect('/?auth=setup', [clearState]);
  const pending = await unseal(request, env, STATE_COOKIE);
  const code = url.searchParams.get('code');
  const state = url.searchParams.get('state');
  if (!pending || !state || state !== pending.state) return redirect('/?auth=expired', [clearState]);
  if (!code) return redirect('/?auth=cancelled', [clearState]);
  try {
    const tokens = await getTokens(env, { grant_type: 'authorization_code', code, code_verifier: pending.verifier, redirect_uri: env.MAL_REDIRECT_URI });
    const result = await malFetch('/users/@me?fields=id,name,picture', tokens.access);
    if (!result.ok) throw new Error('MyAnimeList did not provide a profile');
    const profile = await result.json();
    if (!profile.id || !profile.name) throw new Error('Incomplete MyAnimeList profile');
    const user = { id: profile.id, name: profile.name, image: profile.picture || null };
    const session = { ...tokens, user, sid: random(18), until: Date.now() + SESSION_AGE * 1000 };
    return redirect('/?auth=connected', [clearState, ...await sessionCookies(request, env, session)]);
  } catch {
    return redirect('/?auth=failed', [clearState]);
  }
}

async function sessionCookies(request, env, { access, refresh, user, sid, until }) {
  const age = Math.max(0, Math.ceil((until - Date.now()) / 1000));
  const session = await seal(env, SESSION_COOKIE, { access, user, sid, until });
  const renewal = refresh ? await seal(env, REFRESH_COOKIE, { refresh, sid, until }) : '';
  return [makeCookie(request, SESSION_COOKIE, session, age), makeCookie(request, REFRESH_COOKIE, renewal, renewal ? age : 0)];
}

function clearSession(request, payload, status = 200) {
  const response = json(payload, status);
  for (const cookie of [SESSION_COOKIE, REFRESH_COOKIE]) response.headers.append('Set-Cookie', makeCookie(request, cookie, '', 0));
  return response;
}

function allowedOrigin(request, url) {
  return request.headers.get('Origin') === url.origin;
}

class MalError extends Error {
  constructor(message, status) {
    super(message);
    this.status = status;
  }
}

async function withMal(request, env, session, operation) {
  let renewal;
  const call = async (path, init) => {
    let result = await malFetch(path, (renewal || session).access, init);
    if (result.status === 401) {
      const secret = await unseal(request, env, REFRESH_COOKIE);
      if (secret?.sid !== session.sid) throw new MalError('Your MyAnimeList session expired. Sign in again.', 401);
      try {
        renewal = { ...session, ...await getTokens(env, { grant_type: 'refresh_token', refresh_token: secret.refresh }) };
      } catch {
        throw new MalError('Your MyAnimeList session expired. Sign in again.', 401);
      }
      result = await malFetch(path, renewal.access, init);
    }
    if (!result.ok && !(result.status === 404 && init?.method === 'DELETE')) {
      const message = result.status === 401 ? 'Your MyAnimeList session expired. Sign in again.' : 'MyAnimeList could not complete the request.';
      throw new MalError(message, result.status === 401 ? 401 : 502);
    }
    return result;
  };

  try {
    const data = await operation(call);
    const response = json(data);
    if (renewal) for (const cookie of await sessionCookies(request, env, renewal)) response.headers.append('Set-Cookie', cookie);
    return response;
  } catch (error) {
    const status = error instanceof MalError ? error.status : 502;
    const payload = { error: error instanceof MalError ? error.message : 'MyAnimeList is temporarily unavailable.' };
    return status === 401 ? clearSession(request, payload, status) : json(payload, status);
  }
}

async function getList(call, kind, page) {
  const fields = kind === 'anime' ? 'list_status,mean,num_episodes,media_type' : 'list_status,mean,num_chapters,media_type';
  const params = new URLSearchParams({ fields, limit: '100', offset: String((page - 1) * 100), sort: 'list_updated_at' });
  const response = await call(`/users/@me/${kind}list?${params}`);
  const { data, paging } = await response.json();
  return {
    entries: data.map(({ node, list_status: item }) => ({
      id: node.id, kind, title: node.title, image: node.main_picture?.large || node.main_picture?.medium,
      type: node.media_type?.toUpperCase(), score: node.mean, total: node.num_episodes || node.num_chapters || null,
      status: item.status, progress: item.num_episodes_watched ?? item.num_chapters_read ?? 0,
      rating: item.score, updated: item.updated_at,
    })),
    hasNext: Boolean(paging?.next),
  };
}

async function writeList(request, call, kind, id) {
  const path = `/${kind}/${id}/my_list_status`;
  if (request.method === 'DELETE') {
    await call(path, { method: 'DELETE' });
    return { ok: true };
  }
  let input;
  try { input = await request.json(); } catch { throw new MalError('Invalid list update.', 400); }
  const statuses = kind === 'anime'
    ? ['watching', 'completed', 'on_hold', 'dropped', 'plan_to_watch']
    : ['reading', 'completed', 'on_hold', 'dropped', 'plan_to_read'];
  if (!input || !statuses.includes(input.status) || !within(input.progress, 100000) || !within(input.rating, 10)) {
    throw new MalError('Choose a valid status, progress and score.', 400);
  }
  const progress = kind === 'anime' ? 'num_watched_episodes' : 'num_chapters_read';
  const response = await call(path, {
    method: 'PUT',
    body: new URLSearchParams({ status: input.status, score: String(input.rating), [progress]: String(input.progress) }),
  });
  const saved = await response.json();
  return { status: saved.status, progress: saved.num_episodes_watched ?? saved.num_chapters_read ?? input.progress, rating: saved.score, updated: saved.updated_at };
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const { pathname } = url;
    const { method } = request;
    if (pathname === '/auth/mal' && method === 'GET') return beginAuth(request, env);
    if (pathname === CALLBACK && method === 'GET') return finishAuth(request, env, url);
    if (pathname.startsWith('/api/')) {
      if (method !== 'GET' && !allowedOrigin(request, url)) return json({ error: 'Request origin was rejected.' }, 403);
      const session = config(env) ? await unseal(request, env, SESSION_COOKIE) : null;
      if (pathname === '/api/session' && method === 'GET') return json({ configured: config(env), user: session?.user || null });
      if (pathname === '/api/logout' && method === 'POST') return clearSession(request, { ok: true });
      if (!session) return json({ error: 'Sign in with MyAnimeList to use your lists.' }, 401);
      const match = pathname.match(/^\/api\/lists\/(anime|manga)(?:\/([1-9]\d{0,10}))?$/);
      if (match) {
        const [, kind, id] = match;
        const page = Math.min(1000, Math.max(1, Number.parseInt(url.searchParams.get('page'), 10) || 1));
        if (!id && method === 'GET') return withMal(request, env, session, (call) => getList(call, kind, page));
        if (id && ['PUT', 'DELETE'].includes(method)) return withMal(request, env, session, (call) => writeList(request, call, kind, id));
      }
      return json({ error: 'Route not found.' }, 404);
    }
    const asset = Object.hasOwn(ASSETS, pathname) ? ASSETS[pathname] : null;
    if (!asset || (method !== 'GET' && method !== 'HEAD')) return new Response('Page not found', { status: 404 });
    return new Response(method === 'HEAD' ? null : asset.body, { headers: {
      'Content-Type': asset.type,
      'X-Content-Type-Options': 'nosniff',
      'Referrer-Policy': 'strict-origin-when-cross-origin',
      'Content-Security-Policy': "default-src 'self'; script-src 'self'; style-src 'self' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com; img-src 'self' https: data:; connect-src 'self' https://jikan.lucashdo.com; form-action 'self'; base-uri 'none'; object-src 'none'",
    } });
  },
};

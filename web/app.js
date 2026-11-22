import { featured, otherAnime, mangaPicks, seed } from './catalog.js';

const JIKAN = 'https://jikan.lucashdo.com/v1';
const TENRAI = 'https://api.tenrai.org/v1';
const view = document.querySelector('#view');
const dialog = document.querySelector('#dialog');
const dialogBody = document.querySelector('#dialog-body');
const account = document.querySelector('#header-account');
const kinds = ['anime', 'manga'];
const labels = { watching: 'Watching', reading: 'Reading', completed: 'Completed', on_hold: 'On hold', dropped: 'Dropped', plan_to_watch: 'Plan to watch', plan_to_read: 'Plan to read' };
const icons = {
  search: '<circle cx="10.5" cy="10.5" r="6"/><path d="m15 15 5 5"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  edit: '<path d="m12 6 6 6M4 20l5-1L21 7l-4-4L5 15l-1 5Z"/>',
  close: '<path d="m6 6 12 12M18 6 6 18"/>',
};

const friendBatchSize = 6;
const emptyFeed = () => ({ people: null, entries: [], checked: 0, failures: 0, loading: false, error: false });
const state = {
  user: null, configured: null, sessionStatus: 'loading', entries: { anime: [], manga: [] }, listPaging: {}, listError: '',
  listKind: 'anime', status: 'all', catalogPage: 1, browse: null, season: [], airing: [], upcoming: null, suggestions: {}, malSuggestions: null, friends: emptyFeed(),
};
const registry = new Map(seed.map((item) => [`${item.kind}-${item.id}`, { ...item, englishTitle: item.title }]));
const memory = new Map();
const titleQueue = new Map();
const checkedTitles = new Set();
const checkedPosterImages = new Set();
let resolvingTitles = false;
let browseTicket = 0;
let detailPage = null;
let suggestionTicket = 0;
let toastTimer;

const escape = (value) => String(value ?? '').replace(/[&<>"']/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]);
const unit = (kind, n) => kind === 'manga' ? (n === 1 ? 'chapter' : 'chapters') : (n === 1 ? 'episode' : 'episodes');
const score = (value) => Number(value) > 0 ? Number(value).toFixed(2) : '';
const key = (entry) => `${entry.kind}-${entry.id}`;
const entryUrl = (entry) => `/${entry.kind}/${entry.id}`;
const displayTitle = (entry) => registry.get(key(entry))?.englishTitle || entry.title;
const safeImage = (url) => typeof url === 'string' && url.startsWith('https://') ? url : '';
// MAL recommendation thumbnails use a resize path in front of the original cover.
function originalMalCover(image) {
  const match = /^https:\/\/cdn\.myanimelist\.net\/r\/\d+x\d+(\/images\/manga\/\d+\/\d+\.(?:jpg|jpeg|png|webp))(?:\?[^#]*)?$/i.exec(image || '');
  return match ? `https://cdn.myanimelist.net${match[1]}` : '';
}
const listStatus = (kind) => [kind === 'anime' ? 'watching' : 'reading', 'completed', 'on_hold', 'dropped', kind === 'anime' ? 'plan_to_watch' : 'plan_to_read'];
const ordered = (entries) => [...entries].sort((a, b) => (Date.parse(b.updated) || 0) - (Date.parse(a.updated) || 0));

const months = 'january february march april may june july august september october november december'.split(' ');
const isoDate = /^\d{4}-\d{2}-\d{2}(?:T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2}))?$/i;

function parseFriendDate(value, fetchedAt) {
  if (typeof value !== 'string') return null;
  const text = value.trim();
  if (isoDate.test(text)) {
    const timestamp = Date.parse(text);
    if (!Number.isFinite(timestamp) || (text.length === 10 && new Date(timestamp).toISOString().slice(0, 10) !== text)) return null;
    return { timestamp, calendarDate: text.length === 10 ? text : null };
  }

  const relative = /^(today|yesterday)(?:,?\s+(\d{1,2}):(\d{2})\s*(am|pm))?$/i.exec(text);
  const named = /^([a-z]+)\s+(\d{1,2})(?:,?\s+(\d{4}))?(?:,?\s+(\d{1,2}):(\d{2})\s*(am|pm))?$/i.exec(text);
  if (!relative && !named) return null;
  const referenceTime = typeof fetchedAt === 'string' && isoDate.test(fetchedAt) ? Date.parse(fetchedAt) : NaN;
  const reference = new Date(Number.isFinite(referenceTime) ? referenceTime : Date.now());
  let year = reference.getUTCFullYear();
  let month = reference.getUTCMonth();
  let day = reference.getUTCDate();
  if (relative?.[1].toLowerCase() === 'yesterday') {
    reference.setUTCDate(day - 1);
    year = reference.getUTCFullYear();
    month = reference.getUTCMonth();
    day = reference.getUTCDate();
  }
  if (named) {
    const name = named[1].toLowerCase();
    month = name === 'sept' ? 8 : months.findIndex((item) => item === name || item.slice(0, 3) === name);
    day = Number(named[2]);
    if (month < 0 || day < 1 || day > 31) return null;
    if (named[3]) year = Number(named[3]);
    else if (month > reference.getUTCMonth() || (month === reference.getUTCMonth() && day > reference.getUTCDate())) year--;
  }
  const [hour, minute, period] = relative ? relative.slice(2) : named.slice(4);
  if (hour && (Number(hour) < 1 || Number(hour) > 12 || Number(minute) > 59)) return null;
  const hours = hour ? Number(hour) % 12 + (period.toLowerCase() === 'pm' ? 12 : 0) : 0;
  const date = new Date(Date.UTC(year, month, day, hours, Number(minute || 0)));
  if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month || date.getUTCDate() !== day) return null;
  // Public MAL dates can omit the time zone. Preserve their calendar day for display.
  return { timestamp: date.getTime(), calendarDate: date.toISOString().slice(0, 10) };
}

function mountIcons(root = document) {
  for (const node of root.querySelectorAll('[data-icon]:empty')) {
    const paths = icons[node.dataset.icon];
    if (paths) node.innerHTML = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${paths}</svg>`;
  }
}

function remember(items) {
  for (const item of items) {
    const previous = registry.get(key(item));
    const provided = Object.fromEntries(Object.entries(item).filter(([, value]) => value != null && value !== ''));
    registry.set(key(item), { ...previous, ...provided });
  }
  return items;
}

const names = (list) => Array.isArray(list)
  ? list.map((item) => typeof item === 'string' ? item : item?.name).filter(Boolean)
  : undefined;

function adapt(item, kind) {
  const id = Number(item.malId ?? item.mal_id ?? item.id);
  const existing = registry.get(`${kind}-${id}`);
  const images = item.images;
  const title = [item.titleEnglish, item.title_english, Array.isArray(item.titles) ? item.titles.find((x) => x.type === 'English')?.title : item.titles?.english]
    .find((value) => typeof value === 'string' && value.trim());
  const release = item.aired?.string || item.published?.string || (typeof item.aired === 'string' ? item.aired : '');
  return {
    id, kind, title: item.title || title || existing?.title, englishTitle: title?.trim(), alt: item.title || existing?.alt,
    japanese: item.titleJapanese || item.title_japanese || existing?.japanese,
    synonyms: item.titleSynonyms || item.title_synonyms || existing?.synonyms,
    image: item.imageUrl || images?.large || images?.jpg?.large_image_url || images?.jpg?.image_url || existing?.image,
    posterImage: [images?.webp?.large_image_url, images?.jpg?.large_image_url, images?.large, item.largeImageUrl,
      kind === 'manga' ? originalMalCover(item.imageUrl || images?.jpg?.image_url) : ''].find(safeImage),
    score: item.score || existing?.score, total: item.episodes || item.chapters || existing?.total,
    volumes: item.volumes ?? existing?.volumes, type: item.type || existing?.type,
    status: item.status || existing?.status, aired: release || existing?.aired,
    premiered: item.season && item.year ? `${item.season[0].toUpperCase()}${item.season.slice(1)} ${item.year}` : existing?.premiered,
    broadcast: item.broadcast?.string || existing?.broadcast, source: item.source || existing?.source,
    duration: item.duration || existing?.duration, rating: item.rating || existing?.rating,
    genres: names(item.genres) || existing?.genres, themes: names(item.themes) || existing?.themes,
    demographics: names(item.demographics) || existing?.demographics, studios: names(item.studios) || existing?.studios,
    authors: names(item.authors) || existing?.authors, producers: names(item.producers) || existing?.producers,
    licensors: names(item.licensors) || existing?.licensors, serializations: names(item.serializations) || existing?.serializations,
    synopsis: item.synopsis || existing?.synopsis, background: item.background || existing?.background,
    year: item.year || item.aired?.from?.slice(0, 4) || existing?.year, season: item.season || existing?.season,
    scoredBy: item.scoredBy || item.scored_by || existing?.scoredBy, rank: item.rank ?? existing?.rank,
    popularity: item.popularity ?? existing?.popularity, members: item.members ?? existing?.members,
    favorites: item.favorites ?? existing?.favorites,
  };
}

function cast(data) {
  const list = Array.isArray(data) ? data : [];
  return list.map((item) => {
    const person = item.character || item;
    const voices = item.voice_actors || item.voiceActors || [];
    const actor = voices.find((voice) => /japanese/i.test(voice.language || '')) || voices[0];
    return {
      id: Number(person.mal_id ?? person.malId), name: person.name || '',
      image: person.images?.jpg?.image_url || person.images?.webp?.image_url || person.imageUrl || '',
      role: typeof item.role === 'string' ? item.role : '', voice: actor?.person?.name || actor?.name || '',
    };
  }).filter((person) => Number.isInteger(person.id) && person.id > 0 && person.name).slice(0, 12);
}

function related(data) {
  const groups = Array.isArray(data) ? data : [];
  const items = [];
  for (const group of groups) {
    const entries = group.entry || group.entries;
    for (const entry of Array.isArray(entries) ? entries : [group]) {
      const id = Number(entry.mal_id ?? entry.malId);
      const title = entry.name || entry.title;
      const kind = /manga|novel/i.test(entry.type) ? 'manga' : 'anime';
      if (Number.isInteger(id) && id > 0 && title) {
        items.push({ relation: group.relation || 'Related', ...adapt({ ...entry, title }, kind) });
      }
    }
  }
  const priority = ['prequel', 'sequel', 'adaptation'];
  const order = (item) => {
    const index = priority.indexOf(item.relation.toLowerCase());
    return index === -1 ? priority.length : index;
  };
  return items.sort((a, b) => order(a) - order(b)).slice(0, 16);
}

function externalLinks(data) {
  const list = Array.isArray(data) ? data : Array.isArray(data?.externalLinks) ? data.externalLinks : [];
  return list.filter((link) => typeof link?.name === 'string' && typeof link?.url === 'string' && /^https?:\/\//i.test(link.url)).slice(0, 10);
}

function rows(data, kind) {
  const list = Array.isArray(data) ? data : data?.entries || data?.items || data?.anime || [];
  return remember(list.map((item) => adapt(item, kind)).filter((item) => item.id > 0 && item.title));
}

async function fetchCatalog(base, path, timeout) {
  const response = await fetch(`${base}${path}`, { signal: AbortSignal.timeout(timeout) });
  if (!response.ok) throw new Error(response.status === 429 ? 'The catalog is busy. Try again shortly.' : 'The live catalog is temporarily unavailable.');
  const payload = await response.json();
  if (!payload?.data || typeof payload.data !== 'object') throw new Error('Invalid catalog response.');
  return payload;
}

async function catalog(path, refresh = false) {
  const cached = memory.get(path);
  if (!refresh && cached && cached.expires > Date.now()) return cached.request;
  const entry = { expires: Infinity };
  entry.request = (async () => {
    if (!path.startsWith('/users/')) {
      try { return await fetchCatalog(TENRAI, path, 4500); } catch {
        // A successful fallback can be refreshed after Tenrai has recovered.
        entry.expires = Date.now() + 60000;
      }
    }
    return fetchCatalog(JIKAN, path, 8500);
  })();
  memory.set(path, entry);
  try { return await entry.request; } catch (error) { if (memory.get(path) === entry) memory.delete(path); throw error; }
}

function updateTitle(id) {
  const entry = registry.get(id);
  if (!entry) return;
  const title = displayTitle(entry);
  for (const node of view.querySelectorAll(`[data-catalog-title="${id}"]`)) {
    node.textContent = title;
    const poster = node.closest('[data-suggestion="manga"] .poster');
    const image = safeImage(entry.posterImage);
    if (!poster || !image) continue;
    const container = poster.querySelector('.cover');
    const current = container?.querySelector('img');
    if (current?.getAttribute('src') !== image && current?.dataset.failedPoster !== image && container) {
      container.outerHTML = cover(entry, '', true);
    }
  }
  for (const node of view.querySelectorAll(`[data-entry="${id}"][data-edit="true"][aria-label]`)) {
    const action = node.dataset.icon === 'edit' ? 'Edit' : 'Add';
    node.setAttribute('aria-label', `${action} ${title}`);
  }
  if (detailPage?.id === id) {
    const heading = view.querySelector('[data-entry-heading]');
    if (heading) heading.textContent = title;
    document.title = `${title} | AniLedger`;
  }
}

function needsPosterImage(entry, node) {
  return node.closest('[data-suggestion="manga"] .poster') && !entry.posterImage && !checkedPosterImages.has(key(entry));
}

async function resolveTitles() {
  if (resolvingTitles) return;
  resolvingTitles = true;
  try {
    for (const [id, node] of titleQueue) {
      titleQueue.delete(id);
      if (!node.isConnected) continue;
      const entry = registry.get(id);
      if (!entry) continue;
      const needsImage = needsPosterImage(entry, node);
      if (!needsImage && (entry.englishTitle || checkedTitles.has(id))) continue;
      checkedTitles.add(id);
      if (needsImage) checkedPosterImages.add(id);
      try {
        const { data } = await catalog(`/${entry.kind}/${entry.id}`);
        const details = adapt(data, entry.kind);
        if (needsImage && !details.posterImage) details.posterImage = safeImage(details.image);
        if (needsImage) details.image = entry.image || details.image;
        remember([details]);
        updateTitle(id);
      } catch {
        // Keep the catalog title if details are unavailable.
      }
      await new Promise((resolve) => setTimeout(resolve, 700));
    }
  } finally {
    resolvingTitles = false;
  }
}

const titleObserver = typeof IntersectionObserver === 'function' ? new IntersectionObserver((changes) => {
  for (const { target, isIntersecting } of changes) {
    const id = target.dataset.catalogTitle;
    const entry = registry.get(id);
    if (isIntersecting && target.isConnected && entry &&
        (needsPosterImage(entry, target) || (!checkedTitles.has(id) && !entry.englishTitle))) {
      titleQueue.set(id, target);
    }
  }
  resolveTitles();
}) : null;

async function siteApi(path, init) {
  const response = await fetch(`/api/${path}`, { ...init, headers: { Accept: 'application/json', ...init?.headers } });
  const data = await response.json();
  if (!response.ok) {
    const failure = new Error(data.error || 'The request could not be completed.');
    failure.status = response.status;
    throw failure;
  }
  return data;
}

function cover(entry, variant = '', usePosterImage = false) {
  const original = safeImage(entry.image);
  const src = (usePosterImage && safeImage(entry.posterImage)) || original;
  const fallback = original && original !== src ? ` data-fallback-src="${escape(original)}"` : '';
  return `<span class="cover ${variant}" ${src ? '' : 'data-failed'}>${src ? `<img src="${escape(src)}"${fallback} alt="" decoding="async">` : ''}</span>`;
}

function entryButton(entry) {
  return `<a class="title-button" href="${entryUrl(entry)}" data-entry="${key(entry)}" data-catalog-title="${key(entry)}">${escape(displayTitle(entry))}</a>`;
}

function itemAction(entry, editable = false) {
  const label = editable ? 'Edit' : 'Add';
  return `<a class="icon-button" href="${entryUrl(entry)}?edit=1" data-entry="${key(entry)}" data-edit="true" aria-label="${label} ${escape(displayTitle(entry))}" data-icon="${editable ? 'edit' : 'plus'}"></a>`;
}

function section(title, body, action = '') {
  return `<section class="panel"><div class="panel-heading"><h2>${title}</h2>${action}</div>${body}</section>`;
}

const actionLink = (href, label) => `<a class="text-button" href="${href.startsWith('#') ? '/' : ''}${href}">${label}</a>`;
const button = (label, action, style = '') => `<button type="button" class="button ${style}" data-action="${action}">${label}</button>`;
const malButton = (style = '') => `<a href="/auth/mal" class="button primary ${style}">Sign in with MyAnimeList</a>`;
const sessionMessage = () => state.sessionStatus === 'error'
  ? `<div class="empty">Could not check your session.${button('Retry', 'retry-session')}</div>`
  : '<div class="empty" role="status">Checking session…</div>';
const sessionNotice = () => `<p class="notice">Could not check your session.${button('Retry', 'retry-session')}</p>`;

// A 401 from one list call only suspends trust in the session. Cached lists stay
// visible until /api/session confirms the account really is signed out.
let confirmingSession = null;

function confirmSession(message = 'Your MyAnimeList session expired. Sign in again.') {
  confirmingSession ||= verifySession(message).finally(() => { confirmingSession = null; });
  return confirmingSession;
}

async function verifySession(message) {
  let session;
  try {
    session = await siteApi('session', { signal: AbortSignal.timeout(10000) });
  } catch {
    // The session cannot be checked right now, so the cached lists stay put.
    state.sessionStatus = 'error';
    renderAccount();
    if (['panel', 'lists', 'friends', 'detail'].includes(route().page)) render();
    return;
  }
  if (session.user) {
    state.user = session.user;
    state.configured = session.configured;
    state.sessionStatus = 'ready';
    renderAccount();
    toast('MyAnimeList could not complete the request. Try again.');
    return;
  }
  expireSession(message);
}

// Reached only once the session is confirmed gone: cached lists belong to nobody.
function expireSession(message) {
  state.user = null;
  state.suggestions = {};
  state.malSuggestions = null;
  state.entries = { anime: [], manga: [] };
  state.listPaging = {};
  state.listError = '';
  state.friends = emptyFeed();
  state.sessionStatus = 'ready';
  if (dialog.open) dialog.close();
  loadSuggestions();
  renderAccount();
  render();
  toast(message || 'Your MyAnimeList session expired. Sign in again.');
}

function heading(title, description = '', action = '') {
  const name = `<h1>${title}</h1>`;
  return `<header class="page-heading">${description ? `<div>${name}<p>${description}</p></div>` : name}${action}</header>`;
}

function accountCard() {
  if (state.sessionStatus !== 'ready') return `<section class="panel" aria-label="MyAnimeList account">${sessionMessage()}</section>`;
  if (state.user) {
    return `<section class="account-card"><h2 class="account-title">MyAnimeList connected</h2><p>List edits sync to MyAnimeList.</p><a class="button wide" href="https://myanimelist.net/profile/${encodeURIComponent(state.user.name)}" target="_blank" rel="noopener">View profile</a></section>`;
  }
  return `<section class="account-card"><h2 class="account-title">Connect MyAnimeList</h2><p>Sync list progress and scores.</p>${malButton('wide')}</section>`;
}

function renderAccount() {
  if (state.sessionStatus === 'loading') account.innerHTML = '<span class="button" role="status">Checking session…</span>';
  else if (state.sessionStatus === 'error') account.innerHTML = button('Retry session', 'retry-session');
  else account.innerHTML = state.user ? button(escape(state.user.name), 'account') : button('Sign in', 'account', 'primary');
}

function activityRows(entries, editable) {
  return `<div class="activity-rows">${entries.map((entry) => {
    const progress = entry.total ? `${entry.progress} / ${entry.total}` : entry.progress;
    const label = entry.progress ? `${progress} ${unit(entry.kind, entry.progress)}` : (entry.kind === 'anime' ? 'Anime' : 'Manga');
    const when = entry.when || (entry.updated ? new Date(entry.updated).toLocaleDateString(undefined, { month: 'short', day: 'numeric' }) : '');
    return `<article class="activity">${cover(entry, 'thumb')}<div>${entryButton(entry)}<p class="row-meta">${escape(label)}${when ? `<span class="separator">·</span>${escape(when)}` : ''}</p></div><span class="status ${escape(entry.status)}">${escape(labels[entry.status] || entry.status)}</span>${itemAction(entry, editable)}</article>`;
  }).join('')}</div>`;
}

function posters(entries, catalog = false, usePosterImage = false) {
  return `<div class="poster-grid ${catalog ? 'catalog-grid' : ''}">${entries.map((entry) => {
    const genre = entry.genres?.slice(0, 2).join(' · ');
    return `<a class="poster" href="${entryUrl(entry)}" data-entry="${key(entry)}">${cover(registry.get(key(entry)) || entry, '', usePosterImage)}${score(entry.score) ? `<span class="poster-score">★ ${score(entry.score)}</span>` : ''}<span class="poster-caption"><strong data-catalog-title="${key(entry)}">${escape(displayTitle(entry))}</strong>${genre || entry.type ? `<small>${escape(genre || entry.type)}</small>` : ''}</span></a>`;
  }).join('')}</div>`;
}

function rankings(entries, upcoming = false) {
  return `<div class="rank-list">${entries.map((entry, index) => `<article class="rank-row"><span class="rank-number">${index + 1}</span>${cover(entry, 'thumb')}<div>${entryButton(entry)}<p class="row-meta">${score(entry.score) ? `<span class="star">★</span> ${score(entry.score)}` : escape(entry.type || 'Anime')}${upcoming && entry.members > 0 ? ` · ${Number(entry.members).toLocaleString()} members` : ''}${entry.total ? ` <span class="separator">·</span> ${entry.total} eps` : ''}</p></div>${itemAction(entry)}</article>`).join('')}</div>`;
}

function friendActivity({ entry, username, status, progress, total, rating, updated }) {
  const details = [
    Number.isFinite(progress) ? `${progress}${total > 0 ? ` / ${total}` : ''} ${unit(entry.kind, progress)}` : '',
    rating > 0 ? `Scored ${rating}` : '',
  ].filter(Boolean).join(' · ');
  const date = updated ? new Date(updated.timestamp) : null;
  const when = date ? ` <span class="separator">·</span> <time datetime="${updated.calendarDate || date.toISOString()}">${date.toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric', timeZone: updated.calendarDate ? 'UTC' : undefined })}</time>` : '';
  const person = `<a href="https://myanimelist.net/profile/${encodeURIComponent(username)}" target="_blank" rel="noopener">${escape(username)}</a>`;
  const statusKey = status.toLowerCase().replaceAll(' ', '_');
  const knownStatus = Object.hasOwn(labels, statusKey);
  const label = status ? `<span class="status ${knownStatus ? statusKey : ''}">${escape(knownStatus ? labels[statusKey] : status)}</span>` : '';
  return `<article class="friend-row">${cover(entry, 'thumb')}<div><div class="friend-title">${entryButton(entry)}${label}</div><p class="row-meta">${person}${when}</p>${details ? `<p class="row-meta">${escape(details)}</p>` : ''}</div></article>`;
}

function friendsContent(preview = false) {
  if (!state.user) return state.sessionStatus === 'ready'
    ? `<div class="empty">Sign in to see your friends’ updates.${malButton()}</div>`
    : sessionMessage();
  const feed = state.friends;
  const entries = preview ? feed.entries.slice(0, 3) : feed.entries;
  const canLoadMore = !preview && feed.people && feed.checked < feed.people.length;
  let body;
  if (entries.length) {
    body = `<div class="friend-rows">${entries.map(friendActivity).join('')}</div>`;
  } else if (feed.loading || (!feed.people && !feed.error)) {
    body = '<div class="empty" role="status">Loading friend activity…</div>';
  } else if (feed.error || feed.failures) {
    body = '<div class="empty">Friend activity is temporarily unavailable.</div>';
  } else if (feed.people.length) {
    body = '<div class="empty">No public updates from these friends.</div>';
  } else {
    const profile = `https://myanimelist.net/profile/${encodeURIComponent(state.user.name)}/friends`;
    body = `<div class="empty">No public friends found.<a href="${profile}" class="text-button" target="_blank" rel="noopener">View friends on MyAnimeList</a></div>`;
  }
  const partial = entries.length && feed.failures ? '<p class="notice">Some friends’ updates are unavailable.</p>' : '';
  const stale = state.sessionStatus === 'error' ? sessionNotice() : '';
  const controls = !feed.loading && (canLoadMore || feed.error || feed.failures)
    ? `<div class="friend-controls">${canLoadMore ? button('Load more friends', 'more-friends') : ''}${feed.error || feed.failures ? button('Retry', 'refresh-friends') : ''}</div>` : '';
  return `<div aria-live="polite" aria-busy="${feed.loading}">${stale}${body}${partial}${controls}</div>`;
}

function renderFriends() {
  const refresh = state.user && !state.friends.loading && !state.friends.error && !state.friends.failures ? button('Refresh', 'refresh-friends') : '';
  view.innerHTML = `${heading('Friends feed', 'Public updates from your MyAnimeList friends.', refresh)}<section class="panel friend-page" aria-label="Friend activity">${friendsContent()}</section>`;
}

function refreshFriendsView() {
  if (['panel', 'friends'].includes(route().page)) render();
}

async function friendNames(username, refresh = false) {
  const { data, meta } = await catalog(`/users/${encodeURIComponent(username)}/friends`, refresh);
  if (!Array.isArray(data)) throw new Error('Invalid friends list.');
  const people = data.filter((person) => /^[a-z0-9_-]{1,32}$/i.test(person?.username) && person.username.toLowerCase() !== username.toLowerCase());
  const lastOnline = ({ lastOnline }) => parseFriendDate(lastOnline, meta?.fetchedAt)?.timestamp ?? -Infinity;
  people.sort((a, b) => lastOnline(b) - lastOnline(a));
  return [...new Map(people.map(({ username }) => [username.toLowerCase(), username])).values()];
}

async function loadFriends(refresh = false) {
  if (!state.user || state.friends.loading) return;
  const feed = state.friends = refresh ? emptyFeed() : state.friends;
  const username = state.user.name;
  feed.loading = true;
  feed.error = false;
  refreshFriendsView();
  try {
    if (!feed.people) {
      feed.people = await friendNames(username, refresh);
    }
    if (state.friends !== feed) return;
    const batch = feed.people.slice(feed.checked, feed.checked + friendBatchSize);
    const results = await Promise.allSettled(batch.map(async (friend) => {
      const { data, meta } = await catalog(`/users/${encodeURIComponent(friend)}/userupdates`, refresh);
      if (!Array.isArray(data?.anime) || !Array.isArray(data?.manga)) throw new Error('Invalid friend updates.');
      return kinds.flatMap((kind) => data[kind].filter((item) => item?.entry).map((item) => ({
        entry: adapt(item.entry, kind), username: friend, status: typeof item.status === 'string' ? item.status.trim() : '',
        progress: item.progress, total: item.total, rating: item.score, updated: parseFriendDate(item.date, meta?.fetchedAt),
      })).filter(({ entry }) => Number.isInteger(entry.id) && entry.id > 0 && entry.title));
    }));
    if (state.friends !== feed) return;
    const updates = results.flatMap((result) => result.status === 'fulfilled' ? result.value : []);
    remember(updates.map(({ entry }) => entry));
    feed.entries = [...feed.entries, ...updates].sort((a, b) => (b.updated?.timestamp ?? -Infinity) - (a.updated?.timestamp ?? -Infinity));
    feed.failures += results.filter((result) => result.status === 'rejected').length;
    feed.checked += batch.length;
  } catch {
    feed.error = true;
  } finally {
    feed.loading = false;
    if (state.friends === feed) refreshFriendsView();
  }
}

function loadVisibleFriends() {
  if (!state.friends.people && !state.friends.error && ['panel', 'friends'].includes(route().page)) loadFriends();
}

function statistics() {
  const anime = state.entries.anime.length;
  const manga = state.entries.manga.length;
  const all = [...state.entries.anime, ...state.entries.manga];
  const completed = all.filter((entry) => entry.status === 'completed').length;
  const percent = all.length ? Math.round(completed / all.length * 100) : 0;
  const count = (kind, n) => state.user ? `${n}${state.listPaging[kind] ? '+' : ''}` : '—';
  return `<div class="stats"><div class="stat-pair"><div class="stat-tile"><b>${count('anime', anime)}</b><span>Anime entries</span></div><div class="stat-tile"><b>${count('manga', manga)}</b><span>Manga entries</span></div></div><p class="stats-line"><span>Completed</span><b>${state.user ? `${completed}${state.listPaging.anime || state.listPaging.manga ? '+' : ''}` : '—'}</b></p><progress class="progress-line" max="100" value="${percent}" aria-label="Percent completed"></progress></div>`;
}

function suggestionRail(kind, fallback) {
  if (kind === 'anime' && state.user) {
    const suggestions = state.malSuggestions;
    if (!suggestions || suggestions.loading) return '<p class="empty" role="status">Loading your MyAnimeList suggestions…</p>';
    if (suggestions.error) return `<div class="empty">Could not load your MyAnimeList suggestions.${button('Retry', 'retry-mal-suggestions')}</div>`;
    if (!suggestions.items.length) return '<p class="empty">MyAnimeList has no anime suggestions for your account yet.</p>';
    return `<div class="suggestion-rail" data-suggestion="anime" tabindex="0" aria-label="MyAnimeList anime suggestions">${posters(suggestions.items)}</div>`;
  }
  const saved = new Set(state.entries[kind].map(({ id }) => id));
  const candidates = [...(state.suggestions[kind] || []), ...fallback];
  const shown = new Map();
  for (const entry of candidates) {
    if (!saved.has(entry.id) && !shown.has(entry.id)) shown.set(entry.id, entry);
  }
  if (!shown.size) return '<p class="empty">No new suggestions are available yet.</p>';
  return `<div class="suggestion-rail" data-suggestion="${kind}" tabindex="0" aria-label="${kind === 'anime' ? 'Anime' : 'Manga'} suggestions">${posters([...shown.values()].slice(0, 16), false, kind === 'manga')}</div>`;
}

async function loadMalSuggestions() {
  const user = state.user;
  if (!user || state.malSuggestions?.loading) return;
  const request = { loading: true, items: [] };
  state.malSuggestions = request;
  const isCurrent = () => state.user?.id === user.id && state.malSuggestions === request;
  if (route().page === 'panel') render();
  try {
    const { entries } = await siteApi('suggestions/anime');
    if (isCurrent()) request.items = remember(entries);
  } catch {
    request.error = true;
  } finally {
    request.loading = false;
    if (isCurrent() && route().page === 'panel') render();
  }
}

async function loadSuggestions() {
  const ticket = ++suggestionTicket;
  const user = state.user;
  await Promise.all((user ? ['manga'] : kinds).map(async (kind) => {
    const sources = ordered(state.entries[kind])
      .filter((entry) => entry.rating >= 7 || entry.status === 'completed')
      .slice(0, 2);
    const paths = [...sources.map(({ id }) => `/${kind}/${id}/recommendations`), `/recommendations/${kind}`];
    const results = await Promise.allSettled(paths.map((path) => catalog(path)));
    if (ticket !== suggestionTicket || user?.id !== state.user?.id) return;
    const items = results.flatMap((result) => {
      const list = result.value?.data;
      if (!Array.isArray(list)) return [];
      return list.flatMap((item) => item?.entry ?? item?.entries ?? item ?? []);
    }).filter((item) => item && (item.title || item.name))
      .map((item) => adapt({ ...item, title: item.title || item.name }, kind))
      .filter((item) => item.id > 0 && item.image);
    state.suggestions[kind] = remember(items);
    if (route().page === 'panel') render();
  }));
}

async function upcomingCatalog(page = 1) {
  try {
    return await catalog(`/top/anime?filter=upcoming&sfw=true&page=${page}`);
  } catch {
    const result = await catalog(`/seasons/upcoming?page=${page}`);
    if (Array.isArray(result.data)) {
      return { ...result, data: [...result.data].sort((a, b) => (Number(b.members) || 0) - (Number(a.members) || 0)) };
    }
    return result;
  }
}

function renderPanel() {
  const railPositions = new Map([...view.querySelectorAll('[data-suggestion]')].map((rail) => [rail.dataset.suggestion, rail.scrollLeft]));
  const recent = ordered([...state.entries.anime, ...state.entries.manga]).slice(0, 4);
  const picks = state.season.length ? state.season.slice(0, 4) : featured;
  const airing = state.airing.length ? state.airing.slice(0, 4) : [featured[0], featured[1], otherAnime[0], featured[3]];
  let list;
  if (recent.length) list = (state.sessionStatus === 'error' ? sessionNotice() : '') + activityRows(recent, true);
  else if (state.sessionStatus !== 'ready') list = sessionMessage();
  else if (state.listLoading) list = '<div class="empty" role="status">Loading your list updates…</div>';
  else list = `<div class="empty">${escape(state.listError || (state.user ? 'Your list updates will appear here.' : 'Sign in to see your list updates.'))}${actionLink('#anime', 'Browse anime')}</div>`;
  const discover = state.season.length ? 'This season' : 'Featured anime';
  const rankHeading = state.airing.length ? 'Top airing anime' : 'Popular picks';
  view.innerHTML = `${heading('My panel')}<div class="dashboard"><div class="stack">
    ${section('Recent list updates', list, actionLink('#lists', 'View lists'))}
    ${section(discover, `<div class="season-rail">${posters(picks)}</div>`, actionLink('#season', 'View season'))}
    ${section(state.user ? 'My Anime Suggestions' : 'Anime Suggestions', suggestionRail('anime', [...otherAnime, ...featured]), button('Next anime', 'scroll-anime'))}
    ${section(state.user ? 'AniLedger Manga Suggestions' : 'Manga Suggestions', suggestionRail('manga', mangaPicks), state.user
      ? `<div class="suggestion-actions"><a class="text-button" href="https://myanimelist.net/mypanel.php" target="_blank" rel="noopener">My MAL panel</a>${button('Next manga', 'scroll-manga')}</div>`
      : button('Next manga', 'scroll-manga'))}
    </div><aside class="sidebar" aria-label="Dashboard sidebar">${accountCard()}${section('My statistics', statistics())}${section('Friends feed', friendsContent(true), actionLink('#friends', 'View feed'))}${section(rankHeading, rankings(airing), actionLink('#airing', 'See all'))}${section('Top Upcoming Anime', state.upcoming?.length ? rankings(state.upcoming.slice(0, 4), true) : `<p class="empty">${state.upcoming ? 'Upcoming rankings are unavailable.' : 'Loading upcoming anime…'}</p>`, actionLink('#upcoming', 'See all'))}</aside></div>`;
  for (const rail of view.querySelectorAll('[data-suggestion]')) rail.scrollLeft = railPositions.get(rail.dataset.suggestion) || 0;
}

function renderLists() {
  const kind = state.listKind;
  const entries = ordered(state.entries[kind]).filter((entry) => state.status === 'all' || state.status === entry.status);
  const tabs = kinds.map((value) => `<button class="filter" data-list-kind="${value}" aria-pressed="${kind === value}">${value === 'anime' ? 'Anime list' : 'Manga list'}</button>`).join('');
  const options = [['all', 'All statuses'], ...listStatus(kind).map((value) => [value, labels[value]])];
  const select = `<label><span class="sr-only">Status</span><select id="status-filter">${options.map(([value, label]) => `<option value="${value}" ${state.status === value ? 'selected' : ''}>${label}</option>`).join('')}</select></label>`;
  const content = entries.length ? activityRows(entries, true) : `<div class="empty">${state.listLoading ? 'Loading your list…' : 'No entries to show.'}${state.listLoading ? '' : actionLink(`#${kind}`, `Browse ${kind}`)}</div>`;
  view.innerHTML = `${heading('My lists')}${state.user ? `<div class="toolbar"><div class="filters">${tabs}</div>${select}</div><section class="panel">${state.listError ? `<p class="notice">${escape(state.listError)} ${button('Retry', 'retry-lists')}</p>` : ''}${state.sessionStatus === 'error' ? sessionNotice() : ''}${content}${state.listPaging[kind] ? `<div class="empty">${button('Load more', 'more-list')}</div>` : ''}</section>` : `<div class="sidebar account-only">${accountCard()}</div>`}`;
}

const seasonNames = ['Winter', 'Spring', 'Summer', 'Fall'];
const today = new Date();
const defaultSeason = seasonNames[Math.floor(today.getMonth() / 3)].toLowerCase();
let seasonFilter = { year: today.getFullYear(), season: defaultSeason };

function route() {
  const detail = /^\/(anime|manga)\/([1-9]\d{0,10})\/?$/.exec(location.pathname);
  if (detail) return { page: 'detail', kind: detail[1], id: Number(detail[2]) };
  const [page, params = ''] = location.hash.slice(1).split('?');
  return { page: ['anime', 'manga', 'season', 'airing', 'upcoming', 'lists', 'friends', 'search'].includes(page) ? page : 'panel', params: new URLSearchParams(params) };
}

function fallback(page, q, kind) {
  if (page === 'search') return seed.filter((item) => (kind === 'all' || kind === item.kind) && `${item.title} ${item.alt}`.toLocaleLowerCase().includes(q.toLocaleLowerCase()));
  if (page === 'manga') return mangaPicks;
  if (page === 'season') return featured;
  if (page === 'upcoming') return [];
  return [...featured, ...otherAnime];
}

function renderCatalog(page, params) {
  const q = params.get('q') || '';
  const type = params.get('kind') || 'all';
  const names = { anime: 'Top anime', manga: 'Top manga', season: 'Seasonal anime', airing: 'Top airing anime', upcoming: 'Top Upcoming Anime', search: 'Search results' };
  const queryLabel = page === 'search' && q ? `Results for “${escape(q)}”` : '';
  const controls = page === 'season' ? `<form id="season-form" class="filters"><label class="field">Season<select name="season">${seasonNames.map((name) => `<option value="${name.toLowerCase()}" ${name.toLowerCase() === seasonFilter.season ? 'selected' : ''}>${name}</option>`).join('')}</select></label><label class="field">Year<input type="number" name="year" required min="1917" max="${today.getFullYear() + 2}" value="${seasonFilter.year}"></label><button type="submit" class="button season-submit">Browse</button></form>` : '';
  const { items, loading, error, next } = state.browse || { items: [], loading: true };
  const content = !loading && !items.length && !error ? 'No matching titles.' : (loading ? 'Loading the catalog…' : 'No titles are available.');
  const note = error ? `<div class="notice">${escape(error)}${items.length ? ' Showing saved picks.' : ''} ${button('Retry', 'retry-catalog')}</div>` : '';
  const more = next ? `<div class="empty">${button('Load more', 'more-catalog')}</div>` : '';
  view.innerHTML = `${heading(names[page], queryLabel)}${controls ? `<div class="toolbar">${controls}</div>` : ''}<section class="panel" aria-live="polite">${note}${items.length ? posters(items, true) : `<div class="empty">${content}</div>`}${more}</section>`;
  if (page === 'search' && q) {
    document.querySelector('#query').value = q;
    document.querySelector('#search-kind').value = [...kinds, 'all'].includes(type) ? type : 'all';
  }
}

function render() {
  const current = route();
  const { page, params } = current;
  for (const link of document.querySelectorAll('[data-nav]')) {
    if (link.dataset.nav === (page === 'detail' ? current.kind : page)) link.setAttribute('aria-current', 'page');
    else link.removeAttribute('aria-current');
  }
  if (page === 'detail') {
    if (!detailPage) void showEntry(current.kind, current.id);
    else detailPage.refreshAccount?.();
    return;
  }
  if (page === 'panel') renderPanel();
  else if (page === 'lists') renderLists();
  else if (page === 'friends') renderFriends();
  else renderCatalog(page, params);
  mountIcons(view);
  titleObserver?.disconnect();
  if (titleObserver) {
    for (const node of view.querySelectorAll('[data-catalog-title]')) titleObserver.observe(node);
  }
}

async function browse(reset = true) {
  const { page, params } = route();
  if (['panel', 'lists', 'friends', 'detail'].includes(page)) return;
  const ticket = ++browseTicket;
  const q = params.get('q') || '';
  const type = kinds.includes(params.get('kind')) ? params.get('kind') : 'all';
  const old = reset ? [] : state.browse.items;
  if (reset) state.catalogPage = 1;
  const pageNumber = state.catalogPage;
  state.browse = { items: old, loading: true, next: false };
  render();
  const request = async (path, kind) => {
    const { data, meta, pagination } = await catalog(`${path}${path.includes('?') ? '&' : '?'}page=${pageNumber}`);
    return { items: rows(data, kind), next: Boolean(pagination?.has_next_page ?? meta?.pagination?.hasNextPage) };
  };
  try {
    let result;
    if (page === 'upcoming') {
      const { data, meta, pagination } = await upcomingCatalog(pageNumber);
      result = { items: rows(data, 'anime'), next: Boolean(pagination?.has_next_page ?? meta?.pagination?.hasNextPage) };
    } else if (page === 'search') {
      if (!q) result = { items: [], next: false };
      else {
        const matched = await Promise.all((type === 'all' ? kinds : [type]).map((kind) => request(`/${kind}?q=${encodeURIComponent(q)}`, kind)));
        result = { items: matched.flatMap((item) => item.items), next: matched.some((item) => item.next) };
      }
    } else if (page === 'season') {
      result = await request(`/seasons/${seasonFilter.year}/${seasonFilter.season}`, 'anime');
    } else if (page === 'airing') {
      result = await request('/top/anime?filter=airing', 'anime');
    } else {
      result = await request(`/top/${page}`, page);
    }
    if (ticket !== browseTicket) return;
    state.browse = { ...result, items: [...new Map([...old, ...result.items].map((item) => [key(item), item])).values()] };
  } catch {
    if (ticket !== browseTicket) return;
    state.browse = { items: old.length ? old : fallback(page, q, type), error: 'The live catalog is temporarily unavailable.', next: false };
  }
  render();
}

async function loadLists() {
  if (!state.user || state.listLoading) return;
  state.listLoading = true;
  state.listError = '';
  render();
  const results = await Promise.allSettled(kinds.map((kind) => siteApi(`lists/${kind}`)));
  state.listLoading = false;
  let expired = '';
  for (let i = 0; i < kinds.length; i++) {
    const kind = kinds[i];
    const response = results[i];
    if (response.status === 'fulfilled') {
      state.entries[kind] = remember(response.value.entries);
      state.listPaging[kind] = response.value.hasNext ? 2 : 0;
    } else if (response.reason.status === 401) expired ||= response.reason.message;
    else state.listError = response.reason.message;
  }
  render();
  if (expired) await confirmSession(expired);
  if (state.user) loadSuggestions();
}

function toast(message) {
  const node = document.querySelector('#toast');
  node.textContent = message;
  node.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { node.hidden = true; }, 5000);
}

function open(title, body) {
  dialogBody.innerHTML = `<div class="dialog-content"><div class="dialog-heading"><h2 id="dialog-title">${escape(title)}</h2><button type="button" class="icon-button" data-action="close" data-icon="close" aria-label="Close"></button></div>${body}</div>`;
  mountIcons(dialog);
  if (!dialog.open) dialog.showModal();
}

function showAccount(setup = false) {
  if (state.user) {
    open('Your account', `<p>Signed in to MyAnimeList as <strong>${escape(state.user.name)}</strong>.</p><div class="dialog-actions"><a class="button" href="https://myanimelist.net/profile/${encodeURIComponent(state.user.name)}" target="_blank" rel="noopener">View profile</a>${button('Sign out', 'logout')}</div>`);
  } else if (setup || state.configured === false) {
    open('MyAnimeList sign-in', `<p>Set up a MyAnimeList OAuth app to enable sign-in.</p><div class="dialog-actions"><a class="button" href="https://myanimelist.net/apiconfig" target="_blank" rel="noopener">MyAnimeList app settings</a></div>`);
  } else {
    open('Sign in', `<p>Authorize AniLedger to sync your MyAnimeList lists.</p><div class="dialog-actions">${malButton()}</div>`);
  }
}

function summaryHtml(entry) {
  const facts = [
    entry.type,
    entry.total ? `${entry.total} ${unit(entry.kind, entry.total)}` : '',
    entry.status,
    entry.aired,
  ].filter(Boolean).map((fact) => `<span>${escape(fact)}</span>`).join('');
  const tiles = [
    [score(entry.score), 'Score', entry.scoredBy ? `${Number(entry.scoredBy).toLocaleString()} users` : ''],
    [entry.rank ? `#${entry.rank}` : '', 'Ranked', ''],
    [entry.popularity ? `#${entry.popularity}` : '', 'Popularity', ''],
    [entry.members ? Number(entry.members).toLocaleString() : '', 'Members', ''],
    [entry.favorites ? Number(entry.favorites).toLocaleString() : '', 'Favorites', ''],
  ].filter(([value]) => value).map(([value, label, note]) => `<div class="entry-stat"><b>${escape(String(value))}</b><span>${label}</span>${note ? `<small>${escape(note)}</small>` : ''}</div>`).join('');
  const subtitle = [entry.alt, entry.japanese].filter(Boolean).join(' · ');
  return `<div class="entry-top">${cover(entry)}<div class="entry-headline">
    ${subtitle ? `<p class="entry-alt">${escape(subtitle)}</p>` : ''}
    ${facts ? `<div class="entry-facts">${facts}</div>` : ''}
    ${tiles ? `<div class="entry-stats">${tiles}</div>` : ''}
  </div></div>`;
}

function sectionsHtml(entry, extra = { characters: [], links: [], streaming: [] }) {
  const kind = entry.kind;
  const row = (label, value) => value ? `<tr><th scope="row">${label}</th><td>${value}</td></tr>` : '';
  const statistics = [
    row('Score', score(entry.score) ? `<span class="star">★</span> ${score(entry.score)}` : ''),
    row('Scored By', entry.scoredBy ? escape(Number(entry.scoredBy).toLocaleString()) : ''),
    row('Ranked', entry.rank ? `#${escape(String(entry.rank))}` : ''),
    row('Popularity', entry.popularity ? `#${escape(String(entry.popularity))}` : ''),
    row('Members', entry.members ? escape(Number(entry.members).toLocaleString()) : ''),
    row('Favorites', entry.favorites ? escape(Number(entry.favorites).toLocaleString()) : ''),
  ].join('');
  const information = [
    row('Type', escape(entry.type || '')),
    row(kind === 'anime' ? 'Episodes' : 'Volumes', escape(kind === 'anime' ? (entry.total ? String(entry.total) : '') : (entry.volumes ? String(entry.volumes) : ''))),
    kind === 'manga' ? row('Chapters', escape(entry.total ? String(entry.total) : '')) : '',
    row('Status', escape(entry.status || '')),
    row(kind === 'anime' ? 'Aired' : 'Published', escape(entry.aired || '')),
    row('Premiered', escape(entry.premiered || '')),
    row('Broadcast', escape(entry.broadcast || '')),
    row('Source', escape(entry.source || '')),
    row('Duration', escape(entry.duration || '')),
    row('Rating', escape(entry.rating || '')),
    row(kind === 'anime' ? 'Studios' : 'Authors', escape(((kind === 'anime' ? entry.studios : entry.authors) || []).join(', '))),
    row('Producers', escape((entry.producers || []).join(', '))),
    row('Licensors', escape((entry.licensors || []).join(', '))),
    row('Serialization', escape((entry.serializations || []).join(', '))),
    row('Genres', escape((entry.genres || []).join(', '))),
    row('Themes', escape((entry.themes || []).join(', '))),
    row('Demographics', escape((entry.demographics || []).join(', '))),
  ].join('');
  const titles = [
    row('English', escape(entry.englishTitle || '')),
    row('Japanese', escape(entry.japanese || '')),
    row('Romaji', escape(entry.alt || '')),
    row('Synonyms', escape((entry.synonyms || []).join(', '))),
  ].join('');
  const linkList = (items) => items.map((link) => `<a href="${escape(link.url)}" target="_blank" rel="noopener">${escape(link.name)}</a>`).join('');
  const characters = extra.characters.length ? `<section class="entry-section"><h3>Characters</h3><div class="cast-grid">${extra.characters.map((person) => {
    const image = safeImage(person.image);
    return `<a class="cast" href="https://myanimelist.net/character/${person.id}" target="_blank" rel="noopener"><span class="cast-image">${image ? `<img src="${escape(image)}" alt="" loading="lazy" decoding="async">` : ''}</span><span><strong>${escape(person.name)}</strong><small>${escape([person.role, person.voice].filter(Boolean).join(' · '))}</small></span></a>`;
  }).join('')}</div></section>` : '';
  const synopsis = entry.synopsis ? escape(entry.synopsis) : extra.detailFailed ? 'Synopsis is unavailable.' : 'Loading details…';
  return `<section class="entry-section"><h3>Synopsis</h3><p>${synopsis}</p></section>
    ${entry.background ? `<section class="entry-section"><h3>Background</h3><p>${escape(entry.background)}</p></section>` : ''}
    ${titles ? `<section class="entry-section"><h3>Alternative Titles</h3><table class="info-table">${titles}</table></section>` : ''}
    ${information || statistics ? `<div class="entry-columns">${information ? `<section class="entry-section"><h3>Information</h3><table class="info-table">${information}</table></section>` : ''}${statistics ? `<section class="entry-section"><h3>Statistics</h3><table class="info-table">${statistics}</table></section>` : ''}</div>` : ''}
    ${characters}
    ${extra.links.length ? `<section class="entry-section"><h3>External Links</h3><p class="entry-links">${linkList(extra.links)}</p></section>` : ''}
    ${extra.streaming.length ? `<section class="entry-section"><h3>Where to Watch</h3><p class="entry-links">${linkList(extra.streaming)}</p></section>` : ''}`;
}

function relatedCards(items) {
  return items.map(({ relation, ...item }) => {
    const current = registry.get(key(item)) || item;
    const saved = state.entries[item.kind].find(({ id }) => id === item.id);
    return `<div class="related-card">${cover(current, 'thumb')}<div><p class="row-meta">${escape(relation)} · ${escape(current.type || (item.kind === 'anime' ? 'Anime' : 'Manga'))}</p>${entryButton(current)}${saved ? ` <span class="status ${escape(saved.status)}">${escape(labels[saved.status] || saved.status)}</span>` : ''}</div></div>`;
  }).join('');
}

function themeSections(data, failed = false) {
  return `<div class="entry-columns">${['Opening', 'Ending'].map((label) => {
    const songs = data?.[`${label.toLowerCase()}s`];
    const items = Array.isArray(songs) ? songs.map((song) => {
      if (typeof song === 'string') return `<li>${escape(song.replace(/^\s*\d+[:.]\s*/, ''))}</li>`;
      if (!song?.title) return '';
      const title = `“${song.title}”${song.artist ? ` by ${song.artist}` : ''}`;
      return `<li>${escape(title)}${song.episodes ? ` <small>${escape(song.episodes)}</small>` : ''}</li>`;
    }).join('') : '';
    return `<section class="entry-section"><h3>${label} Theme</h3>${items ? `<ol class="theme-list">${items}</ol>` : `<p class="row-meta">${failed ? 'Theme information is unavailable.' : data ? 'No themes listed.' : 'Loading themes…'}</p>`}</section>`;
  }).join('')}</div>`;
}

function entryFriendRows(entry, updates) {
  const rows = updates.map(({ friend, update, date }) => {
    const status = String(update.status || '').toLowerCase().replaceAll(' ', '_');
    const progress = update.progress ?? update.episodesWatched ?? update.chaptersRead ?? update.watchedEpisodes ?? update.readChapters;
    const activity = date ? new Date(date.timestamp).toLocaleString(undefined, {
      month: 'short', day: 'numeric', ...(date.calendarDate ? { timeZone: 'UTC' } : { hour: 'numeric', minute: '2-digit' }),
    }) : '—';
    return `<tr><th scope="row"><a href="https://myanimelist.net/profile/${encodeURIComponent(friend)}" target="_blank" rel="noopener">${escape(friend)}</a></th><td>${escape(update.score || '—')}</td><td>${escape(labels[status] || update.status || '—')}</td><td>${progress == null ? '—' : escape(`${progress} / ${update.total || entry.total || '?'}`)}</td><td>${escape(activity)}</td></tr>`;
  });
  return rows.length ? `<div class="friend-table-wrap" tabindex="0" aria-label="Friends’ list activity"><table class="friend-table"><thead><tr><th scope="col">Member</th><th scope="col">Score</th><th scope="col">Status</th><th scope="col">${entry.kind === 'anime' ? 'Episodes seen' : 'Chapters read'}</th><th scope="col">Activity</th></tr></thead><tbody>${rows.join('')}</tbody></table></div>` : '';
}

async function loadEntryFriends(entry, region, active) {
  if (!state.user) {
    region.textContent = state.sessionStatus === 'ready' ? 'Sign in to see friends’ list activity.' : 'Your session is being checked.';
    return;
  }
  const user = state.user;
  const current = () => active() && state.user?.id === user.id;
  const updates = [];
  let people;
  let offset = 0;
  let unavailable = 0;
  async function showBatch() {
    region.innerHTML = entryFriendRows(entry, updates) + '<p class="row-meta" role="status">Checking friends’ activity…</p>';
    try {
      people ??= state.friends.people || await friendNames(user.name);
    } catch {
      if (!current()) return;
      region.innerHTML = `<p class="row-meta">Friends’ activity is unavailable.</p>${button('Retry', '')}`;
      region.querySelector('button').addEventListener('click', showBatch);
      return;
    }
    if (!current()) return;
    const batch = people.slice(offset, offset + friendBatchSize);
    const results = await Promise.allSettled(batch.map(async (friend) => {
      const { data, meta } = await catalog(`/users/${encodeURIComponent(friend)}/userupdates`).catch(() => ({}));
      const recent = Array.isArray(data?.[entry.kind]) ? data[entry.kind].find((item) => Number(item.entry?.malId ?? item.entry?.mal_id) === entry.id) : null;
      if (recent) return { friend, update: recent, date: parseFriendDate(recent.date, meta?.fetchedAt) };
      for (let page = 1; page <= 10 && current(); page++) {
        const list = await catalog(`/users/${encodeURIComponent(friend)}/${entry.kind}list?limit=300&page=${page}`);
        const entries = Array.isArray(list.data) ? list.data : list.data?.entries;
        if (!Array.isArray(entries)) throw new Error('Invalid public list.');
        const update = entries.find((item) => Number(item.malId ?? item.mal_id ?? item.mediaId ?? item.entry?.malId ?? item.id) === entry.id);
        if (update) return { friend, update, date: parseFriendDate(update.updatedAt, list.meta?.fetchedAt) };
        const next = list.meta?.pagination?.hasNextPage ?? list.pagination?.has_next_page ?? entries.length === 300;
        if (!next) break;
      }
    }));
    if (!current()) return;
    offset += batch.length;
    for (const result of results) {
      if (result.status === 'rejected') unavailable++;
      else if (result.value) updates.push(result.value);
    }
    updates.sort((a, b) => (b.date?.timestamp || 0) - (a.date?.timestamp || 0));
    const message = people.length ? 'No public list entries for this title from the friends checked.' : 'No public friends found.';
    region.innerHTML = entryFriendRows(entry, updates) || `<p class="row-meta">${message}</p>`;
    if (unavailable) region.insertAdjacentHTML('beforeend', '<p class="row-meta">Some friends’ activity was unavailable.</p>');
    if (offset < people.length) {
      region.insertAdjacentHTML('beforeend', button('Check more friends', ''));
      region.querySelector('button').addEventListener('click', showBatch);
    }
  }
  await showBatch();
}

function entryActions(entry, edit, saved) {
  const mal = `<a class="button" href="https://myanimelist.net/${entry.kind}/${entry.id}" target="_blank" rel="noopener">View on MyAnimeList</a>`;
  if (!state.user || !edit) {
    const cta = state.user ? `<button type="button" class="button primary" data-action="edit-entry">${saved ? 'Edit list entry' : 'Add to my list'}</button>` : state.sessionStatus === 'ready' ? malButton() : '';
    return `<div class="entry-actions"><div class="dialog-actions">${cta}${mal}</div></div>`;
  }
  const statuses = listStatus(entry.kind);
  const selected = saved?.status || statuses.at(-1);
  const rating = `<option value="0">Unscored</option>${Array.from({ length: 10 }, (_, i) => `<option value="${i + 1}" ${saved?.rating === i + 1 ? 'selected' : ''}>${i + 1}</option>`).join('')}`;
  return `<form id="edit-form" class="entry-actions" data-id="${key(entry)}"><div class="edit-fields"><label class="field">Status<select name="status">${statuses.map((status) => `<option value="${status}" ${status === selected ? 'selected' : ''}>${labels[status]}</option>`).join('')}</select></label><label class="field">${entry.kind === 'anime' ? 'Episodes' : 'Chapters'}<input name="progress" type="number" min="0" max="${Math.max(entry.total || 100000, saved?.progress || 0)}" value="${saved?.progress || 0}" required></label><label class="field">Score<select name="rating">${rating}</select></label></div><p class="form-error" hidden role="alert"></p><div class="dialog-actions"><button type="submit" class="button primary">Save to MyAnimeList</button>${saved ? button('Remove', 'remove', 'danger') : ''}${button('Cancel', 'cancel-edit')}${mal}</div></form>`;
}

function setEntryEditing(edit) {
  if (!detailPage?.refreshAccount) return;
  const url = new URL(location.href);
  if (edit) url.searchParams.set('edit', '1');
  else url.searchParams.delete('edit');
  history.replaceState(history.state, '', url);
  detailPage.edit = edit;
  detailPage.refreshAccount();
  const selector = edit ? '#edit-form select' : '[data-action="edit-entry"]';
  view.querySelector(selector)?.focus();
}

async function showEntry(kind, number) {
  const id = `${kind}-${number}`;
  const page = { id, edit: new URLSearchParams(location.search).get('edit') === '1' };
  detailPage = page;
  const label = kind === 'anime' ? 'Anime' : 'Manga';
  const active = () => detailPage === page;
  const known = registry.get(id);
  const path = `/${kind}/${number}`;
  document.title = known ? `${displayTitle(known)} | AniLedger` : `${label} | AniLedger`;
  view.innerHTML = `<div class="page-heading"><h1>${known ? escape(displayTitle(known)) : label}</h1></div><p class="empty" role="status">Loading title details…</p>`;
  try {
    const { data } = await catalog(path);
    if (!data || Array.isArray(data)) throw new Error('Invalid title details.');
    const details = adapt(data, kind);
    if (details.id !== number || !details.title) throw new Error('Invalid title details.');
    remember([details]);
  } catch {
    if (!active()) return;
    if (!known) {
      view.innerHTML = `${heading(label)}<div class="panel empty">Could not load this title. ${button('Retry', 'retry-entry')} ${actionLink(`#${kind}`, `Browse ${kind}`)}</div>`;
      return;
    }
  }
  if (!active()) return;
  const entry = registry.get(id);
  const extra = { characters: [], links: [], streaming: [], detailFailed: true };
  const paint = () => {
    if (!active()) return;
    view.querySelector('[data-sections]').innerHTML = sectionsHtml(entry, extra);
  };
  document.title = `${displayTitle(entry)} | AniLedger`;
  view.innerHTML = `<div class="entry-breadcrumb"><a href="/#${kind}">${label}</a><span aria-hidden="true"> / </span><span>Details</span></div>
    <header class="page-heading entry-heading"><h1 data-entry-heading>${escape(displayTitle(entry))}</h1></header>
    <article class="panel entry-page"><div data-summary>${summaryHtml(entry)}</div><div data-actions></div><div data-sections>${sectionsHtml(entry, extra)}</div>
    <section class="entry-section entry-extra"><h3>Friends’ List Activity</h3><div data-entry-friends></div></section>
    ${kind === 'anime' ? `<div data-entry-themes class="entry-extra">${themeSections()}</div>` : ''}
    <div data-entry-relations class="entry-extra"></div></article>`;
  let friendOwner;
  let actionState;
  page.refreshAccount = () => {
    const owner = state.user?.id ?? state.sessionStatus;
    const saved = state.entries[kind].find((item) => item.id === number);
    const actions = view.querySelector('[data-actions]');
    const waiting = page.edit && state.user && state.listLoading;
    const nextState = JSON.stringify([owner, page.edit, Boolean(waiting), saved?.status, saved?.rating, saved?.progress]);
    if (actionState !== nextState) {
      actions.innerHTML = waiting ? '<p class="row-meta" role="status">Loading your list entry…</p>' : entryActions(entry, page.edit, saved);
      actionState = nextState;
    }
    if (friendOwner !== owner) {
      friendOwner = owner;
      const region = view.querySelector('[data-entry-friends]');
      void loadEntryFriends(entry, region, active);
    }
  };
  page.refreshAccount();
  const loadRelations = async () => {
    const { data } = await catalog(`/${entry.kind}/${entry.id}/relations`);
    if (!active()) return;
    const items = related(data);
    if (!items.length) return;
    remember(items);
    const region = view.querySelector('[data-entry-relations]');
    region.innerHTML = `<section class="entry-section"><h3>Related Entries</h3><div data-related-main class="related-grid"></div>${items.length > 6 ? '<details><summary>More related entries</summary><div data-related-more class="related-grid"></div></details>' : ''}</section>`;
    const fillCovers = async (slot, cards) => {
      slot.innerHTML = relatedCards(cards);
      for (let i = 0; i < cards.length && active(); i += 3) {
        await Promise.allSettled(cards.slice(i, i + 3).map(async (item) => {
          const { data } = await catalog(`/${item.kind}/${item.id}`);
          if (!active() || !data || Array.isArray(data)) return;
          remember([adapt(data, item.kind)]);
          const current = registry.get(key(item)) || item;
          const title = slot.querySelector(`[data-entry="${key(item)}"]`);
          if (!title) return;
          title.textContent = displayTitle(current);
          title.previousElementSibling.textContent = `${item.relation} · ${current.type || (item.kind === 'anime' ? 'Anime' : 'Manga')}`;
          title.closest('.related-card').querySelector('.cover').outerHTML = cover(current, 'thumb');
        }));
      }
    };
    region.querySelector('details')?.addEventListener('toggle', (event) => {
      const more = region.querySelector('[data-related-more]');
      if (event.target.open && !more.hasChildNodes()) void fillCovers(more, items.slice(6));
    });
    await fillCovers(region.querySelector('[data-related-main]'), items.slice(0, 6));
  };
  const loadThemes = async () => {
    if (entry.kind !== 'anime') return;
    const path = `/anime/${entry.id}`;
    const normalize = (data) => {
      const value = data?.themeSongs || data?.theme || data;
      return Array.isArray(value?.openings) || Array.isArray(value?.endings) ? value : null;
    };
    const response = await catalog(`${path}/themes`).catch(() => null);
    let themes = normalize(response?.data);
    if (!themes && active()) {
      const full = await catalog(`${path}/full`).catch(() => null);
      themes = normalize(full?.data);
    }
    if (active()) view.querySelector('[data-entry-themes]').innerHTML = themeSections(themes, !themes);
  };
  const load = async (path, apply) => {
    try {
      const { data } = await catalog(path);
      apply(data);
      paint();
    } catch {
      // A section without data stays hidden; the rest of the page still renders.
    }
  };
  await Promise.allSettled([
    load(`/${entry.kind}/${entry.id}/characters`, (data) => { extra.characters = cast(data); }),
    loadRelations(),
    loadThemes(),
    load(`/${entry.kind}/${entry.id}/external`, (data) => { extra.links = externalLinks(data); }),
    entry.kind === 'anime' ? load(`/anime/${entry.id}/streaming`, (data) => { extra.streaming = externalLinks(data); }) : Promise.resolve(),
  ]);
}

async function saveEntry(form, remove = false) {
  const entry = registry.get(form.dataset.id);
  if (!entry || !state.user) return;
  const inputs = new FormData(form);
  const values = { status: inputs.get('status'), progress: Number(inputs.get('progress')), rating: Number(inputs.get('rating')) };
  const controls = form.querySelectorAll('button');
  for (const control of controls) control.disabled = true;
  const error = form.querySelector('.form-error');
  error.hidden = true;
  try {
    const saved = await siteApi(`lists/${entry.kind}/${entry.id}`, remove ? { method: 'DELETE' } : { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(values) });
    const rest = state.entries[entry.kind].filter((item) => item.id !== entry.id);
    state.entries[entry.kind] = remove ? rest : [{ ...entry, ...values, ...saved, updated: saved.updated || new Date().toISOString() }, ...rest];
    setEntryEditing(false);
    render();
    toast(remove ? 'Removed from MyAnimeList.' : 'Saved to MyAnimeList.');
  } catch (failure) {
    if (failure.status === 401) { confirmSession(failure.message); return; }
    error.textContent = failure.message;
    error.hidden = false;
  } finally {
    for (const control of controls) control.disabled = false;
  }
}

async function moreList(control) {
  const kind = state.listKind;
  const page = state.listPaging[kind];
  if (!page) return;
  control.disabled = true;
  try {
    const next = await siteApi(`lists/${kind}?page=${page}`);
    state.entries[kind] = [...new Map([...state.entries[kind], ...remember(next.entries)].map((item) => [item.id, item])).values()];
    state.listPaging[kind] = next.hasNext ? page + 1 : 0;
    render();
  } catch (error) {
    if (error.status === 401) { confirmSession(error.message); return; }
    toast(error.message);
  } finally {
    control.disabled = false;
  }
}

document.addEventListener('click', async (event) => {
  const control = event.target.closest('[data-action], [data-list-kind]');
  if (!control) return;
  if (control.dataset.listKind) {
    state.listKind = control.dataset.listKind;
    state.status = 'all';
    render();
    view.querySelector(`[data-list-kind="${state.listKind}"]`)?.focus();
    return;
  }
  switch (control.dataset.action) {
    case 'account': showAccount(); break;
    case 'retry-session': checkSession(); break;
    case 'close': dialog.close(); break;
    case 'scroll-anime':
    case 'scroll-manga': {
      const rail = view.querySelector(`[data-suggestion="${control.dataset.action.slice(7)}"]`);
      if (rail) rail.scrollLeft = rail.scrollLeft + rail.clientWidth >= rail.scrollWidth - 2 ? 0 : rail.scrollLeft + rail.clientWidth * .8;
      break;
    }
    case 'retry-mal-suggestions': loadMalSuggestions(); break;
    case 'retry-catalog': browse(); break;
    case 'more-catalog': state.catalogPage++; browse(false); break;
    case 'retry-lists': loadLists(); break;
    case 'more-list': moreList(control); break;
    case 'more-friends': loadFriends(); break;
    case 'refresh-friends': loadFriends(true); break;
    case 'retry-entry': {
      const { kind, id } = route();
      if (kind) void showEntry(kind, id);
      break;
    }
    case 'edit-entry': setEntryEditing(true); break;
    case 'cancel-edit': setEntryEditing(false); break;
    case 'remove': saveEntry(view.querySelector('#edit-form'), true); break;
    case 'logout':
      try {
        await siteApi('logout', { method: 'POST' });
        state.user = null;
        state.suggestions = {};
        state.malSuggestions = null;
        state.entries = { anime: [], manga: [] };
        state.listError = '';
        state.listPaging = {};
        state.friends = emptyFeed();
        dialog.close();
        loadSuggestions();
        renderAccount();
        render();
        toast('Signed out of AniLedger.');
      } catch (error) { toast(error.message); }
      break;
  }
});

document.addEventListener('submit', (event) => {
  const form = event.target;
  if (!['search-form', 'season-form', 'edit-form'].includes(form.id)) return;
  event.preventDefault();
  if (form.id === 'edit-form') { saveEntry(form); return; }
  const data = new FormData(form);
  if (form.id === 'season-form') {
    seasonFilter = { year: Number(data.get('year')), season: data.get('season') };
    browse();
  } else {
    const q = data.get('q').trim();
    if (!q) return;
    const hash = `#search?${new URLSearchParams({ q, kind: data.get('kind') })}`;
    if (route().page === 'detail') location.assign(`/${hash}`);
    else if (location.hash === hash) browse();
    else location.hash = hash;
  }
});

document.addEventListener('change', (event) => {
  if (event.target.id !== 'status-filter') return;
  state.status = event.target.value;
  render();
  view.querySelector('#status-filter')?.focus();
});
document.addEventListener('error', (event) => {
  if (!(event.target instanceof HTMLImageElement)) return;
  const container = event.target.closest('.cover');
  if (!container) return;
  const fallback = event.target.dataset.fallbackSrc;
  if (fallback) {
    event.target.dataset.failedPoster = event.target.getAttribute('src');
    delete event.target.dataset.fallbackSrc;
    event.target.src = fallback;
    return;
  }
  container.setAttribute('data-failed', '');
  event.target.remove();
}, true);
window.addEventListener('hashchange', () => {
  if (route().page === 'detail') return;
  browseTicket++;
  state.browse = null;
  render();
  browse();
  loadVisibleFriends();
  window.scrollTo(0, 0);
});

mountIcons();
render();
browse();

let pendingAuth = new URLSearchParams(location.search).get('auth') || '';
if (pendingAuth) {
  const url = new URL(location.href);
  url.searchParams.delete('auth');
  history.replaceState(history.state, '', url);
}
function authFeedback(authResult) {
  if (authResult === 'setup') return showAccount(true);
  if (authResult === 'connected') {
    return toast(state.sessionStatus === 'ready' && !state.user
      ? 'MyAnimeList sign-in could not be verified. Retry the session check.'
      : 'MyAnimeList connected.');
  }
  return toast({ expired: 'Sign-in expired. Please try again.', cancelled: 'MyAnimeList sign-in was cancelled.', failed: 'MyAnimeList sign-in could not be completed.' }[authResult] || 'Please try signing in again.');
}

async function checkSession(authResult = pendingAuth) {
  state.sessionStatus = 'loading';
  renderAccount();
  if (['panel', 'lists', 'friends', 'detail'].includes(route().page)) render();
  let session;
  try {
    session = await siteApi('session', { signal: AbortSignal.timeout(10000) });
  } catch {
    state.sessionStatus = 'error';
    renderAccount();
    if (['panel', 'lists', 'friends', 'detail'].includes(route().page)) render();
    if (authResult) authFeedback(authResult);
    return;
  }
  if (state.user?.id !== session.user?.id) state.malSuggestions = null;
  state.user = session.user;
  state.configured = session.configured;
  state.sessionStatus = 'ready';
  if (!state.user) {
    state.suggestions = {};
    state.malSuggestions = null;
    state.entries = { anime: [], manga: [] };
    state.listPaging = {};
    state.listError = '';
    state.friends = emptyFeed();
  }
  renderAccount();
  if (state.user) {
    loadLists();
    if (!state.malSuggestions || state.malSuggestions.error) loadMalSuggestions();
  } else loadSuggestions();
  if (!state.user && ['panel', 'lists', 'friends', 'detail'].includes(route().page)) render();
  loadVisibleFriends();
  if (authResult) {
    pendingAuth = '';
    authFeedback(authResult);
  }
}

checkSession();

Promise.allSettled([
  catalog('/seasons/now').then(({ data }) => { state.season = rows(data, 'anime'); }),
  catalog('/top/anime?filter=airing').then(({ data }) => { state.airing = rows(data, 'anime'); }),
  upcomingCatalog().then(({ data }) => { state.upcoming = rows(data, 'anime'); }).catch(() => { state.upcoming = []; }),
]).then(() => { if (route().page === 'panel') render(); });

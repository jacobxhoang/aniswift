import { featured, otherAnime, mangaPicks, seed, previewUpdates } from './catalog.js';

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
  user: null, configured: null, entries: { anime: [], manga: [] }, listPaging: {}, listError: '',
  listKind: 'anime', status: 'all', catalogPage: 1, browse: null, season: [], airing: [], friends: emptyFeed(),
};
const registry = new Map(seed.map((item) => [`${item.kind}-${item.id}`, { ...item, englishTitle: item.title }]));
const memory = new Map();
const titleQueue = new Map();
const checkedTitles = new Set();
let resolvingTitles = false;
let browseTicket = 0;
let detailTicket = 0;
let toastTimer;

const escape = (value) => String(value ?? '').replace(/[&<>"']/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]);
const unit = (kind, n) => kind === 'manga' ? (n === 1 ? 'chapter' : 'chapters') : (n === 1 ? 'episode' : 'episodes');
const score = (value) => Number(value) > 0 ? Number(value).toFixed(2) : '';
const key = (entry) => `${entry.kind}-${entry.id}`;
const displayTitle = (entry) => registry.get(key(entry))?.englishTitle || entry.title;
const safeImage = (url) => typeof url === 'string' && url.startsWith('https://') ? url : '';
const listStatus = (kind) => [kind === 'anime' ? 'watching' : 'reading', 'completed', 'on_hold', 'dropped', kind === 'anime' ? 'plan_to_watch' : 'plan_to_read'];
const ordered = (entries) => [...entries].sort((a, b) => (Date.parse(b.updated) || 0) - (Date.parse(a.updated) || 0));

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

function adapt(item, kind) {
  const id = Number(item.malId ?? item.mal_id ?? item.id);
  const existing = registry.get(`${kind}-${id}`);
  const images = item.images;
  const title = [item.titleEnglish, item.title_english, Array.isArray(item.titles) ? item.titles.find((x) => x.type === 'English')?.title : item.titles?.english]
    .find((value) => typeof value === 'string' && value.trim());
  return {
    id, kind, title: item.title || title || existing?.title, englishTitle: title?.trim(), alt: item.title, image: item.imageUrl || images?.large || images?.jpg?.large_image_url || images?.jpg?.image_url || existing?.image,
    score: item.score || existing?.score, total: item.episodes || item.chapters || existing?.total, type: item.type || existing?.type,
    genres: item.genres?.map((genre) => typeof genre === 'string' ? genre : genre.name).filter(Boolean) || existing?.genres,
    synopsis: item.synopsis || existing?.synopsis, year: item.year || item.aired?.from?.slice(0, 4), season: item.season,
    rank: item.rank, members: item.members,
  };
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
  for (const node of view.querySelectorAll(`[data-catalog-title="${id}"]`)) node.textContent = title;
  for (const node of view.querySelectorAll(`[data-entry="${id}"][data-edit="true"][aria-label]`)) {
    const action = node.dataset.icon === 'edit' ? 'Edit' : 'Add';
    node.setAttribute('aria-label', `${action} ${title}`);
  }
  const active = dialogBody.querySelector(`[data-dialog-title="${id}"]`);
  if (active) active.textContent = title;
}

async function resolveTitles() {
  if (resolvingTitles) return;
  resolvingTitles = true;
  try {
    for (const [id, node] of titleQueue) {
      titleQueue.delete(id);
      if (!node.isConnected || checkedTitles.has(id)) continue;
      const entry = registry.get(id);
      if (!entry || entry.englishTitle) continue;
      checkedTitles.add(id);
      try {
        const { data } = await catalog(`/${entry.kind}/${entry.id}`);
        remember([adapt(data, entry.kind)]);
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
    if (isIntersecting && target.isConnected && !checkedTitles.has(id) && !registry.get(id)?.englishTitle) titleQueue.set(id, target);
  }
  resolveTitles();
}) : null;

async function siteApi(path, init) {
  const response = await fetch(`/api/${path}`, { ...init, headers: { Accept: 'application/json', ...init?.headers } });
  const data = await response.json();
  if (!response.ok) throw new Error(data.error || 'The request could not be completed.');
  return data;
}

function cover(entry, variant = '') {
  const src = safeImage(entry.image);
  return `<span class="cover ${variant}" ${src ? '' : 'data-failed'}>${src ? `<img src="${escape(src)}" alt="" decoding="async">` : ''}</span>`;
}

function entryButton(entry) {
  return `<button type="button" class="title-button" data-entry="${key(entry)}" data-catalog-title="${key(entry)}">${escape(displayTitle(entry))}</button>`;
}

function itemAction(entry, editable = false) {
  const label = editable ? 'Edit' : 'Add';
  return `<button type="button" class="icon-button" data-entry="${key(entry)}" data-edit="true" aria-label="${label} ${escape(displayTitle(entry))}" data-icon="${editable ? 'edit' : 'plus'}"></button>`;
}

function section(title, body, action = '') {
  return `<section class="panel"><div class="panel-heading"><h2>${title}</h2>${action}</div>${body}</section>`;
}

const actionLink = (href, label) => `<a class="text-button" href="${href}">${label}</a>`;
const button = (label, action, style = '') => `<button type="button" class="button ${style}" data-action="${action}">${label}</button>`;
const malButton = (style = '') => `<a href="/auth/mal" class="button primary ${style}">Sign in with MyAnimeList</a>`;

function heading(title, description = '', action = '') {
  const name = `<h1>${title}</h1>`;
  return `<header class="page-heading">${description ? `<div>${name}<p>${description}</p></div>` : name}${action}</header>`;
}

function accountCard() {
  if (state.user) {
    return `<section class="account-card"><h2 class="account-title">MyAnimeList connected</h2><p>List edits sync to MyAnimeList.</p><a class="button wide" href="https://myanimelist.net/profile/${encodeURIComponent(state.user.name)}" target="_blank" rel="noopener">View profile</a></section>`;
  }
  return `<section class="account-card"><h2 class="account-title">Connect MyAnimeList</h2><p>Sync list progress and scores.</p>${malButton('wide')}</section>`;
}

function renderAccount() {
  account.innerHTML = state.user ? button(escape(state.user.name), 'account') : button('Sign in', 'account', 'primary');
}

function activityRows(entries, editable) {
  return `<div class="activity-rows">${entries.map((entry) => {
    const progress = entry.total ? `${entry.progress} / ${entry.total}` : entry.progress;
    const label = entry.progress ? `${progress} ${unit(entry.kind, entry.progress)}` : (entry.kind === 'anime' ? 'Anime' : 'Manga');
    const when = entry.when || (entry.updated ? new Date(entry.updated).toLocaleDateString(undefined, { month: 'short', day: 'numeric' }) : '');
    return `<article class="activity">${cover(entry, 'thumb')}<div>${entryButton(entry)}<p class="row-meta">${escape(label)}${when ? `<span class="separator">·</span>${escape(when)}` : ''}</p></div><span class="status ${escape(entry.status)}">${escape(labels[entry.status] || entry.status)}</span>${itemAction(entry, editable)}</article>`;
  }).join('')}</div>`;
}

function posters(entries, catalog = false) {
  return `<div class="poster-grid ${catalog ? 'catalog-grid' : ''}">${entries.map((entry) => {
    const genre = entry.genres?.slice(0, 2).join(' · ');
    return `<button type="button" class="poster" data-entry="${key(entry)}">${cover(entry)}${score(entry.score) ? `<span class="poster-score">★ ${score(entry.score)}</span>` : ''}<span class="poster-caption"><strong data-catalog-title="${key(entry)}">${escape(displayTitle(entry))}</strong>${genre || entry.type ? `<small>${escape(genre || entry.type)}</small>` : ''}</span></button>`;
  }).join('')}</div>`;
}

function rankings(entries) {
  return `<div class="rank-list">${entries.map((entry, index) => `<article class="rank-row"><span class="rank-number">${index + 1}</span>${cover(entry, 'thumb')}<div>${entryButton(entry)}<p class="row-meta">${score(entry.score) ? `<span class="star">★</span> ${score(entry.score)}` : escape(entry.type || 'Anime')}${entry.total ? ` <span class="separator">·</span> ${entry.total} eps` : ''}</p></div>${itemAction(entry)}</article>`).join('')}</div>`;
}

function friendActivity({ entry, username, status, progress, total, rating, updated }) {
  const details = [
    Number.isFinite(progress) ? `${progress}${total > 0 ? ` / ${total}` : ''} ${unit(entry.kind, progress)}` : '',
    rating > 0 ? `Scored ${rating}` : '',
  ].filter(Boolean).join(' · ');
  const date = updated ? new Date(updated) : null;
  const when = date ? ` <span class="separator">·</span> <time datetime="${date.toISOString()}">${date.toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' })}</time>` : '';
  const person = `<a href="https://myanimelist.net/profile/${encodeURIComponent(username)}" target="_blank" rel="noopener">${escape(username)}</a>`;
  const statusKey = status.toLowerCase().replaceAll(' ', '_');
  const knownStatus = Object.hasOwn(labels, statusKey);
  const label = status ? `<span class="status ${knownStatus ? statusKey : ''}">${escape(knownStatus ? labels[statusKey] : status)}</span>` : '';
  return `<article class="friend-row">${cover(entry, 'thumb')}<div><div class="friend-title">${entryButton(entry)}${label}</div><p class="row-meta">${person}${when}</p>${details ? `<p class="row-meta">${escape(details)}</p>` : ''}</div></article>`;
}

function friendsContent(preview = false) {
  if (!state.user) return `<div class="empty">Sign in to see your friends’ updates.${malButton()}</div>`;
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
  const controls = !feed.loading && (canLoadMore || feed.error || feed.failures)
    ? `<div class="friend-controls">${canLoadMore ? button('Load more friends', 'more-friends') : ''}${feed.error || feed.failures ? button('Retry', 'refresh-friends') : ''}</div>` : '';
  return `<div aria-live="polite" aria-busy="${feed.loading}">${body}${partial}${controls}</div>`;
}

function renderFriends() {
  const refresh = state.user && !state.friends.loading && !state.friends.error && !state.friends.failures ? button('Refresh', 'refresh-friends') : '';
  view.innerHTML = `${heading('Friends feed', 'Public updates from your MyAnimeList friends.', refresh)}<section class="panel friend-page" aria-label="Friend activity">${friendsContent()}</section>`;
}

function refreshFriendsView() {
  if (['panel', 'friends'].includes(route().page)) render();
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
      const { data } = await catalog(`/users/${encodeURIComponent(username)}/friends`, refresh);
      if (!Array.isArray(data)) throw new Error('Invalid friends list.');
      const people = data.filter((person) => /^[a-z0-9_-]{1,32}$/i.test(person?.username) && person.username.toLowerCase() !== username.toLowerCase());
      people.sort((a, b) => (Date.parse(b.lastOnline) || 0) - (Date.parse(a.lastOnline) || 0));
      const names = new Map();
      for (const { username: friend } of people) {
        if (!names.has(friend.toLowerCase())) names.set(friend.toLowerCase(), friend);
      }
      feed.people = [...names.values()];
    }
    if (state.friends !== feed) return;
    const batch = feed.people.slice(feed.checked, feed.checked + friendBatchSize);
    const results = await Promise.allSettled(batch.map(async (friend) => {
      const { data } = await catalog(`/users/${encodeURIComponent(friend)}/userupdates`, refresh);
      if (!Array.isArray(data?.anime) || !Array.isArray(data?.manga)) throw new Error('Invalid friend updates.');
      return kinds.flatMap((kind) => data[kind].filter((item) => item?.entry).map((item) => ({
        entry: adapt(item.entry, kind), username: friend, status: typeof item.status === 'string' ? item.status.trim() : '',
        progress: item.progress, total: item.total, rating: item.score, updated: Number.isFinite(Date.parse(item.date)) ? item.date : null,
      })).filter(({ entry }) => Number.isInteger(entry.id) && entry.id > 0 && entry.title));
    }));
    if (state.friends !== feed) return;
    const updates = results.flatMap((result) => result.status === 'fulfilled' ? result.value : []);
    remember(updates.map(({ entry }) => entry));
    feed.entries = ordered([...feed.entries, ...updates]);
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

function renderPanel() {
  const recent = ordered([...state.entries.anime, ...state.entries.manga]).slice(0, 4);
  const sample = !state.user;
  const display = sample ? previewUpdates : recent;
  const picks = state.season.length ? state.season.slice(0, 4) : featured;
  const airing = state.airing.length ? state.airing.slice(0, 4) : [featured[0], featured[1], otherAnime[0], featured[3]];
  const list = display.length ? activityRows(display, !sample) : `<div class="empty">${escape(state.listError || 'Your list updates will appear here.')}${actionLink('#anime', 'Browse anime')}</div>`;
  const updatesAction = `${sample ? '<span class="preview-label">Sample</span>' : ''}${actionLink('#lists', 'View lists')}`;
  const discover = state.season.length ? 'This season' : 'Featured anime';
  const rankHeading = state.airing.length ? 'Top airing anime' : 'Popular picks';
  view.innerHTML = `${heading('My panel', '', button('Find a title', 'search'))}<div class="dashboard"><div class="stack">
    ${section('Recent list updates', list, updatesAction)}
    ${section(discover, posters(picks), actionLink('#season', 'View season'))}
    ${section('More to explore', posters([...otherAnime, ...mangaPicks]), actionLink('#anime', 'Browse catalog'))}
    </div><aside class="sidebar" aria-label="Dashboard sidebar">${section('My statistics', statistics())}${accountCard()}${section('Friends feed', friendsContent(true), actionLink('#friends', 'View feed'))}${section(rankHeading, rankings(airing), actionLink('#airing', 'See all'))}</aside></div>`;
}

function renderLists() {
  const kind = state.listKind;
  const entries = ordered(state.entries[kind]).filter((entry) => state.status === 'all' || state.status === entry.status);
  const tabs = kinds.map((value) => `<button class="filter" data-list-kind="${value}" aria-pressed="${kind === value}">${value === 'anime' ? 'Anime list' : 'Manga list'}</button>`).join('');
  const options = [['all', 'All statuses'], ...listStatus(kind).map((value) => [value, labels[value]])];
  const select = `<label><span class="sr-only">Status</span><select id="status-filter">${options.map(([value, label]) => `<option value="${value}" ${state.status === value ? 'selected' : ''}>${label}</option>`).join('')}</select></label>`;
  const content = entries.length ? activityRows(entries, true) : `<div class="empty">${state.listLoading ? 'Loading your list…' : 'No entries to show.'}${state.listLoading ? '' : actionLink(`#${kind}`, `Browse ${kind}`)}</div>`;
  view.innerHTML = `${heading('My lists')}${state.user ? `<div class="toolbar"><div class="filters">${tabs}</div>${select}</div><section class="panel">${state.listError ? `<p class="notice">${escape(state.listError)} ${button('Retry', 'retry-lists')}</p>` : ''}${content}${state.listPaging[kind] ? `<div class="empty">${button('Load more', 'more-list')}</div>` : ''}</section>` : `<div class="sidebar account-only">${accountCard()}</div>`}`;
}

const seasonNames = ['Winter', 'Spring', 'Summer', 'Fall'];
const today = new Date();
const defaultSeason = seasonNames[Math.floor(today.getMonth() / 3)].toLowerCase();
let seasonFilter = { year: today.getFullYear(), season: defaultSeason };

function route() {
  const [page, params = ''] = location.hash.slice(1).split('?');
  return { page: ['anime', 'manga', 'season', 'airing', 'lists', 'friends', 'search'].includes(page) ? page : 'panel', params: new URLSearchParams(params) };
}

function fallback(page, q, kind) {
  if (page === 'search') return seed.filter((item) => (kind === 'all' || kind === item.kind) && `${item.title} ${item.alt}`.toLocaleLowerCase().includes(q.toLocaleLowerCase()));
  if (page === 'manga') return mangaPicks;
  if (page === 'season') return featured;
  return [...featured, ...otherAnime];
}

function renderCatalog(page, params) {
  const q = params.get('q') || '';
  const type = params.get('kind') || 'all';
  const names = { anime: 'Top anime', manga: 'Top manga', season: 'Seasonal anime', airing: 'Top airing anime', search: 'Search results' };
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
  const { page, params } = route();
  for (const link of document.querySelectorAll('[data-nav]')) {
    if (link.dataset.nav === page) link.setAttribute('aria-current', 'page');
    else link.removeAttribute('aria-current');
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
  if (['panel', 'lists', 'friends'].includes(page)) return;
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
    if (page === 'search') {
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
  const result = await Promise.allSettled(kinds.map((kind) => siteApi(`lists/${kind}`)));
  for (let i = 0; i < kinds.length; i++) {
    const kind = kinds[i];
    const response = result[i];
    if (response.status === 'fulfilled') {
      state.entries[kind] = remember(response.value.entries);
      state.listPaging[kind] = response.value.hasNext ? 2 : 0;
    } else state.listError = response.reason.message;
  }
  state.listLoading = false;
  render();
}

function toast(message) {
  const node = document.querySelector('#toast');
  node.textContent = message;
  node.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { node.hidden = true; }, 5000);
}

function open(title, body, entryId = '') {
  dialogBody.innerHTML = `<div class="dialog-content"><div class="dialog-heading"><h2 id="dialog-title" data-dialog-title="${entryId}">${escape(title)}</h2><button type="button" class="icon-button" data-action="close" data-icon="close" aria-label="Close"></button></div>${body}</div>`;
  mountIcons(dialog);
  if (!dialog.open) dialog.showModal();
}

function showAccount(setup = false) {
  detailTicket++;
  if (state.user) {
    open('Your account', `<p>Signed in to MyAnimeList as <strong>${escape(state.user.name)}</strong>.</p><div class="dialog-actions"><a class="button" href="https://myanimelist.net/profile/${encodeURIComponent(state.user.name)}" target="_blank" rel="noopener">View profile</a>${button('Sign out', 'logout')}</div>`);
  } else if (setup || state.configured === false) {
    open('MyAnimeList sign-in', `<p>Set up a MyAnimeList OAuth app to enable sign-in.</p><div class="dialog-actions"><a class="button" href="https://myanimelist.net/apiconfig" target="_blank" rel="noopener">MyAnimeList app settings</a></div>`);
  } else {
    open('Sign in', `<p>Authorize AniLedger to sync your MyAnimeList lists.</p><div class="dialog-actions">${malButton()}</div>`);
  }
}

function detailBody(entry, edit, saved) {
  const kind = entry.kind;
  const release = [entry.type, entry.year].filter(Boolean).join(' ');
  const meta = [release, entry.total ? `${entry.total} ${unit(kind, entry.total)}` : '', score(entry.score) ? `★ ${score(entry.score)}` : ''].filter(Boolean).join(', ');
  const details = `<div class="detail">${cover(entry)}<div>${meta ? `<p class="row-meta">${escape(meta)}</p>` : ''}<p data-synopsis>${escape(entry.synopsis || 'Synopsis is unavailable.')}</p></div></div>`;
  const mal = `<a class="button" href="https://myanimelist.net/${kind}/${entry.id}" target="_blank" rel="noopener">View on MyAnimeList</a>`;
  if (!state.user || !edit) {
    const cta = state.user ? `<button type="button" class="button primary" data-entry="${key(entry)}" data-edit="true">${saved ? 'Edit list entry' : 'Add to my list'}</button>` : malButton();
    return `${details}<div class="dialog-actions">${cta}${mal}</div>`;
  }
  const statuses = listStatus(kind);
  const selected = saved?.status || statuses.at(-1);
  const rating = `<option value="0">Unscored</option>${Array.from({ length: 10 }, (_, i) => `<option value="${i + 1}" ${saved?.rating === i + 1 ? 'selected' : ''}>${i + 1}</option>`).join('')}`;
  return `${details}<form id="edit-form" data-id="${key(entry)}"><div class="edit-fields"><label class="field">Status<select name="status">${statuses.map((status) => `<option value="${status}" ${status === selected ? 'selected' : ''}>${labels[status]}</option>`).join('')}</select></label><label class="field">${kind === 'anime' ? 'Episodes' : 'Chapters'}<input name="progress" type="number" min="0" max="${Math.max(entry.total || 100000, saved?.progress || 0)}" value="${saved?.progress || 0}" required></label><label class="field">Score<select name="rating">${rating}</select></label></div><p class="form-error" hidden role="alert"></p><div class="dialog-actions"><button type="submit" class="button primary">Save to MyAnimeList</button>${saved ? button('Remove', 'remove', 'danger') : ''}${mal}</div></form>`;
}

async function showEntry(id, edit) {
  const entry = registry.get(id);
  if (!entry) return;
  const ticket = ++detailTicket;
  const saved = state.entries[entry.kind].find((item) => item.id === entry.id);
  open(displayTitle(entry), detailBody(entry, edit, saved), id);
  try {
    const { data } = await catalog(`/${entry.kind}/${entry.id}`);
    const full = adapt(data, entry.kind);
    remember([full]);
    updateTitle(id);
    if (dialog.open && ticket === detailTicket && full.synopsis) dialogBody.querySelector('[data-synopsis]').textContent = full.synopsis;
  } catch {
    // Keep the available catalog details visible.
  }
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
    dialog.close();
    render();
    toast(remove ? 'Removed from MyAnimeList.' : 'Saved to MyAnimeList.');
  } catch (failure) {
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
    toast(error.message);
  } finally {
    control.disabled = false;
  }
}

document.addEventListener('click', async (event) => {
  const control = event.target.closest('[data-entry], [data-action], [data-list-kind]');
  if (!control) return;
  if (control.dataset.entry) { showEntry(control.dataset.entry, control.dataset.edit === 'true'); return; }
  if (control.dataset.listKind) {
    state.listKind = control.dataset.listKind;
    state.status = 'all';
    render();
    view.querySelector(`[data-list-kind="${state.listKind}"]`)?.focus();
    return;
  }
  switch (control.dataset.action) {
    case 'search': document.querySelector('#query').focus(); break;
    case 'account': showAccount(); break;
    case 'close': dialog.close(); break;
    case 'retry-catalog': browse(); break;
    case 'more-catalog': state.catalogPage++; browse(false); break;
    case 'retry-lists': loadLists(); break;
    case 'more-list': moreList(control); break;
    case 'more-friends': loadFriends(); break;
    case 'refresh-friends': loadFriends(true); break;
    case 'remove': saveEntry(dialog.querySelector('#edit-form'), true); break;
    case 'logout':
      try {
        await siteApi('logout', { method: 'POST' });
        state.user = null;
        state.entries = { anime: [], manga: [] };
        state.listError = '';
        state.listPaging = {};
        state.friends = emptyFeed();
        dialog.close();
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
    if (location.hash === hash) browse();
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
  container.setAttribute('data-failed', '');
  event.target.remove();
}, true);
dialog.addEventListener('close', () => { detailTicket++; });
window.addEventListener('hashchange', () => {
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

const auth = new URLSearchParams(location.search).get('auth');
if (auth) history.replaceState(null, '', `/${location.hash}`);
siteApi('session').then((session) => {
  state.user = session.user;
  state.configured = session.configured;
  renderAccount();
  if (['panel', 'lists', 'friends'].includes(route().page)) render();
  if (state.user) loadLists();
  loadVisibleFriends();
  if (auth === 'setup') showAccount(true);
  else if (auth === 'connected') toast('MyAnimeList connected.');
  else if (auth) toast({ expired: 'Sign-in expired. Please try again.', cancelled: 'MyAnimeList sign-in was cancelled.', failed: 'MyAnimeList sign-in could not be completed.' }[auth] || 'Please try signing in again.');
}).catch(() => { if (auth) toast('Could not check your sign-in. Please try again.'); });

Promise.allSettled([
  catalog('/seasons/now').then(({ data }) => { state.season = rows(data, 'anime'); }),
  catalog('/top/anime?filter=airing').then(({ data }) => { state.airing = rows(data, 'anime'); }),
]).then(() => { if (route().page === 'panel') render(); });

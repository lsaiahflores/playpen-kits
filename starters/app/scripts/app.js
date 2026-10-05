// A tiny router + store + views. Replace the views with the real screens; keep the shell, tokens,
// motion, empty states, light/dark and toasts — that is the polish.
const state = { route: 'overview', items: JSON.parse(localStorage.getItem('items') || 'null') || SAMPLE.items.slice() };
const $ = (s) => document.querySelector(s);
const save = () => { try { localStorage.setItem('items', JSON.stringify(state.items)); } catch { /* private mode */ } };

const ROUTES = [
  { id: 'overview', label: 'Overview', icon: 'home', render: renderOverview },
  { id: 'items', label: 'Items', icon: 'list', render: renderItems },
  { id: 'settings', label: 'Settings', icon: 'settings', render: renderSettings }
];

function spark(points) {
  const w = 160; const h = 44; const max = Math.max(...points); const min = Math.min(...points);
  const d = points.map((p, i) => `${i ? 'L' : 'M'}${(i / (points.length - 1)) * w},${h - 4 - ((p - min) / (max - min || 1)) * (h - 8)}`).join('');
  return `<svg class="spark" viewBox="0 0 ${w} ${h}" preserveAspectRatio="none"><path d="${d}"/></svg>`;
}
const pill = (s) => `<span class="pill ${s === 'Done' ? 'good' : s === 'Review' ? 'warn' : ''}">${s}</span>`;

function renderOverview() {
  return `<div class="grid">${SAMPLE.stats.map((s) => `<div class="card stat"><div class="label">${s.label}</div><div class="value">${s.value}</div><div class="delta ${s.up ? 'up' : 'down'}">${s.delta}</div>${spark(s.trend)}</div>`).join('')}</div>
  <div class="panel-title">Recent activity</div>${list(state.items.slice(0, 4))}`;
}
function list(items) {
  if (!items.length) return `<div class="card empty"><div class="art">${icon('inbox')}</div><h3>Nothing here yet</h3><p>Create your first item and it will show up right here.</p><button class="btn primary" data-act="new">${icon('plus')} New item</button></div>`;
  return `<div class="list">${items.map((i) => `<div class="row" data-id="${i.id}"><div><div class="name">${i.name}</div><div class="sub">${i.owner} · due ${i.due}</div></div>${pill(i.status)}<span class="sub">›</span></div>`).join('')}</div>`;
}
function renderItems() { return list(state.items); }
function renderSettings() {
  return `<div class="card" style="max-width:520px"><div class="field"><label for="name">Display name</label><input id="name" value="Alex"></div><div class="field"><label for="density">Density</label><select id="density"><option>Comfortable</option><option>Compact</option></select></div><button class="btn primary" data-act="save">${icon('check')} Save changes</button></div>`;
}

function nav() {
  $('#nav').innerHTML = `<div class="brand"><span class="logo"></span>My App</div>` + ROUTES.map((r) => `<a data-route="${r.id}" class="${state.route === r.id ? 'active' : ''}">${icon(r.icon)}${r.label}</a>`).join('');
}
function go(id) {
  state.route = id;
  const r = ROUTES.find((x) => x.id === id) || ROUTES[0];
  $('#title').textContent = r.label;
  const v = $('#view');
  v.style.animation = 'none'; void v.offsetWidth; v.style.animation = '';
  v.innerHTML = r.render();
  nav();
}
function toast(msg) { const t = document.createElement('div'); t.className = 'toast'; t.textContent = msg; $('#toasts').appendChild(t); setTimeout(() => t.remove(), 2600); }
function setTheme(t) { document.documentElement.dataset.theme = t; try { localStorage.setItem('theme', t); } catch { /* ignore */ } $('#theme').innerHTML = icon(t === 'dark' ? 'sun' : 'moon'); }

document.addEventListener('click', (e) => {
  const a = e.target.closest('[data-route]'); if (a) return go(a.dataset.route);
  const act = e.target.closest('[data-act]');
  if (act && act.dataset.act === 'new') return newItem();
  if (act && act.dataset.act === 'save') return toast('Saved');
  if (e.target.closest('#new')) return newItem();
  if (e.target.closest('#theme')) return setTheme(document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark');
});
function newItem() { state.items.unshift({ id: Date.now(), name: 'Untitled item', owner: 'You', status: 'Planned', due: 'Soon' }); save(); go('items'); toast('Item created'); }

(function boot() {
  let t = 'light';
  try { t = localStorage.getItem('theme') || (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'); } catch { /* default */ }
  setTheme(t);
  go('overview');
})();

// The live demo in the hero: a small Mac desktop with a Downloads window. Drag a file and tap a wheel's
// key, as in Morph: ⇧ Convert, ⌘ Tools, ⌃ Recipes, ⌥ Actions (Shift, Ctrl, Ctrl+Shift and Alt on
// Windows). The wheel opens under the pointer; tap another key to switch. On a phone, tap a file.
// ⌘-click (Ctrl-click) picks several files to drag together. Nothing leaves the page.

import { Wheel, arrange, outerEdge, OUTSIDE, ON_CENTRE } from './wheel.js';
import { SAMPLE_FILES, SECTIONS, wheelFor, wheelForMany, formatSize } from './content.js';
import { iconSvg } from './icons.js';

const DRAG_START_PX = 5;
const MAX_ADDED = 4;

const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;
const isMac = /Mac|iPhone|iPad/.test(navigator.platform || navigator.userAgent);

// A wheel's key as this visitor's keyboard shows it.
const keyOf = (group) => {
  const s = SECTIONS.find((x) => x.key === group);
  return isMac ? s.mac : s.win;
};

// The wheel a key opens mid-drag, as in the app.
function groupFor(e) {
  if (isMac) return { Shift: 'convert', Meta: 'tools', Control: 'recipes', Alt: 'actions' }[e.key];
  if (e.key === 'Shift') return e.ctrlKey ? 'recipes' : 'convert';
  if (e.key === 'Control') return e.shiftKey ? 'recipes' : 'tools';
  if (e.key === 'Alt') return 'actions';
  return undefined;
}

export function startDemo(stage) {
  const grid = stage.querySelector('[data-files]');
  const overlay = stage.querySelector('[data-overlay]');
  const hint = stage.querySelector('[data-hint]');
  const keys = stage.querySelector('[data-keys]');
  const panel = overlay.querySelector('[data-panel]');
  const card = overlay.querySelector('[data-card]');
  const ghost = overlay.querySelector('[data-ghost]');
  const island = overlay.querySelector('[data-island]');
  const wrap = overlay.querySelector('[data-wheel]');
  const live = stage.querySelector('[data-live]');

  const wheel = new Wheel({ reducedMotion });
  wrap.appendChild(wheel.svg);

  const files = SAMPLE_FILES.map((f) => ({ ...f }));
  const added = [];

  // ---- State ------------------------------------------------------------------------------------

  let file = null;          // the file picked up (the first, when there are several)
  let batch = [];           // every file the wheel works on
  let selected = [];        // names of the selected tiles, in the order picked
  let anchor = null;        // where a Shift-click range starts
  let sections = [];        // its wheel
  let section = 0;
  let mode = 'idle';        // idle | pressed | dragging | wheel | closing
  let byClick = false;      // opened by a click or tap rather than a drag
  let keyHot = false;       // the hot slice was picked with the keyboard
  let pointer = { x: 0, y: 0 };
  let press = null;         // { x, y, id, el, pointerType }
  let centre = { x: 0, y: 0 };
  let scale = 1;
  let islandTimer = 0;
  let isTouch = false;
  let attract = false;      // the opening pose: photo.jpg on Tools, Compress lit, until someone acts
  let attractHot = -1;

  // ---- The Downloads window ---------------------------------------------------------------------

  function tileHtml(f, extra = '') {
    const name = `${f.base}.${f.ext}`;
    return `<button type="button" class="file${extra}" data-name="${name}" aria-label="${name}, ${formatSize(f.mb)}">
      <span class="file-page">${iconSvg(f.icon, 'icon file-icon')}</span>
      <span class="file-name">${name}</span>
    </button>`;
  }

  function renderFiles() {
    grid.innerHTML = files.map((f) => tileHtml(f)).join('') +
      added.map((a) => tileHtml(a, ' file-new')).join('');
    renderSelection();
  }

  function renderSelection() {
    selected = selected.filter((name) => grid.querySelector(`[data-name="${name}"]`));
    grid.querySelectorAll('.file').forEach((el) => el.classList.toggle('is-selected', selected.includes(el.dataset.name)));
  }

  const tileNames = () => [...grid.querySelectorAll('.file')].map((el) => el.dataset.name);
  const totalMb = () => batch.reduce((sum, f) => sum + f.mb, 0);

  const findFile = (name) => files.find((f) => `${f.base}.${f.ext}` === name);

  renderFiles();

  // ---- Hints ------------------------------------------------------------------------------------

  function say(text) {
    hint.textContent = text;
  }
  function announce(text) {
    live.textContent = text;
  }
  const idleHint = () => say(isTouch ? 'Tap a file to open its wheel.' : `Drag a file and tap ${keyOf('convert')}.`);
  const pickMore = isMac ? '⌘-click' : 'Ctrl-click';

  // The wheels' keys, to tap on a phone; they light with the real keys.
  keys.innerHTML = SECTIONS.map((s) =>
    `<button type="button" class="keycap" data-group="${s.key}"><kbd>${keyOf(s.key)}</kbd><span>${s.title}</span></button>`
  ).join('');
  const keyFor = (group) => keys.querySelector(`[data-group="${group}"]`);

  // ---- Geometry ---------------------------------------------------------------------------------

  function overlayRect() {
    return overlay.getBoundingClientRect();
  }

  // Fit the wheel, its top panel above and the result card below, inside the desktop. Sized for the
  // file's biggest section, so the wheel, the panel and the card stay put while sections switch.
  function place(atX, atY) {
    const r = overlayRect();
    const layoutEdge = wheel.extent - 26;
    const panelH = panel.offsetHeight || 36;
    const cardH = 56;
    const need = (extra) => 2 * layoutEdge * extra + panelH + cardH + 40;
    scale = Math.min(1, (r.height - 16) / need(1), (r.width - 16) / (2 * layoutEdge + 8));
    const half = layoutEdge * scale;
    // The wheel bar sits under the ring, as in the app; the result card and progress go above.
    const top = half + cardH + 28, bottom = half + panelH + 28;
    const x = Math.max(half + 8, Math.min(r.width - half - 8, atX));
    const y = Math.max(top + 4, Math.min(r.height - bottom - 4, atY));
    centre = { x, y };
    const size = wheel.extent * 2 * scale;
    wrap.style.width = wrap.style.height = `${size}px`;
    wrap.style.transform = `translate(${x - size / 2}px, ${y - size / 2}px)`;
    // The top panel and the card stay over the wheel, but never past the desktop's edges.
    const along = (w) => Math.max(w / 2 + 8, Math.min(r.width - w / 2 - 8, x));
    panel.style.transform = `translate(-50%, 0) translate(${along(panel.offsetWidth)}px, ${y + half + 22}px)`;
    card.style.transform = `translate(-50%, 0) translate(${along(Math.max(card.offsetWidth, 320))}px, ${y - half - 22 - cardH}px)`;
    island.style.transform = `translate(-50%, 0) translate(${x}px, ${y - half - 22 - 40}px)`;
  }

  function hitTest(clientX, clientY) {
    const r = overlayRect();
    const dx = (clientX - r.left - centre.x) / scale, dy = (clientY - r.top - centre.y) / scale;
    return wheel.slotAt(dx, dy);
  }

  // ---- Wheel bar and result card -------------------------------------------------------------------

  // The wheels these files have, each with its key, as in the bar under the app's wheel.
  function renderPanel() {
    panel.innerHTML = sections.length > 1 ? sections.map((s, i) =>
      `<button type="button" class="panel-tab${i === section ? ' is-on' : ''}" data-section="${i}" tabindex="-1"><kbd>${keyOf(s.key)}</kbd><span>${s.title}</span></button>`
    ).join('') : '';
    panel.classList.toggle('is-empty', sections.length < 2);
  }

  function renderCard() {
    const slice = wheel.hot >= 0 ? wheel.slices[wheel.hot] : null;
    if (!slice || !slice.card) {
      card.classList.remove('is-on');
      return;
    }
    const c = slice.card;
    const more = batch.length > 1 && !slice.single ? ` +${batch.length - 1}` : '';
    card.innerHTML = `<span class="card-icon">${iconSvg(file.icon, 'icon')}</span>
      <span class="card-text"><strong>${c.title}</strong><span class="mono">${c.file}${more}</span></span>
      <span class="card-size">${formatSize(c.size)} · was ${formatSize(totalMb())}</span>`;
    card.classList.add('is-on');
  }

  function showSection(i, dir = 1, animate = true) {
    section = (i + sections.length) % sections.length;
    const s = sections[section];
    const centreText = batch.length > 1 ? `${batch.length} files` : `${file.base}.${file.ext}`;
    const title = byClick ? (isTouch ? 'Tap an action' : 'Click an action') : 'Drop on an action';
    const hint = byClick ? (isTouch ? 'Tap to run' : 'Click to run') : 'Release to run';
    wheel.set({ slices: s.slices, centre: centreText, title, hint, sections: sections.length, section }, { animate, dir });
    renderPanel();
    place(centre.x, centre.y);
    keyHot = false;
    updateHot();
    announce(`${s.title}: ${s.slices.map((x) => x.label).join(', ')}`);
  }

  function updateHot() {
    if (mode !== 'wheel') return;
    if (!keyHot || attract) {
      const slot = hitTest(pointer.x, pointer.y);
      wheel.setHot(slot >= 0 ? slot : attract ? attractHot : -1);
    }
    renderCard();
  }

  // ---- Open, run, cancel --------------------------------------------------------------------------

  // Opens the wheel for `group`, or, when the files have none, Convert or else Tools, as the app does.
  function openWheel(atClientX, atClientY, clicked, group = 'convert') {
    if (!batch.includes(file)) batch = [file];
    sections = batch.length > 1 ? wheelForMany(batch) : wheelFor(file);
    section = Math.max(0, sections.findIndex((s) => s.key === group));
    wheel.frameRings = Math.max(...sections.map((s) => arrange(s.slices.length).rings));
    byClick = clicked;
    mode = 'wheel';
    overlay.classList.add('is-open');
    island.classList.remove('is-on');
    const r = overlayRect();
    centre = { x: atClientX - r.left, y: atClientY - r.top };
    showSection(section, 1, false);
    wheel.open();
    say(clicked
      ? (isTouch ? 'Tap an action to run it, or another wheel below. Tap the middle to cancel.' : 'Click an action. Tap another wheel\'s key to switch. Esc cancels.')
      : 'Drop on an action. Tap another wheel\'s key to switch.');
    stage.focus({ preventScroll: true });
  }

  function closeWheel(dropped) {
    mode = 'closing';
    attract = false;
    overlay.classList.remove('is-attract');
    card.classList.remove('is-on');
    overlay.classList.remove('is-open');
    wheel.onClosed = () => {
      if (mode === 'closing') mode = 'idle';
    };
    wheel.close(dropped);
    endDrag();
  }

  function cancel() {
    closeWheel(false);
    announce('Cancelled. Nothing changed.');
    idleHint();
  }

  function run(slot) {
    const slice = wheel.slices[slot];
    if (!slice) return cancel();
    const source = file;
    const sources = batch.slice();
    const key = sections[section].key;
    closeWheel(true);
    // The top panel shows the progress, then what happened.
    clearTimeout(islandTimer);
    const working = !slice.card ? `${slice.label}…` : sources.length > 1 ? `Working on ${sources.length} files…` : `Working on ${source.base}.${source.ext}…`;
    island.innerHTML = `<span class="island-mark">${iconSvg(source.icon, 'icon')}</span><span class="island-text">${working}</span><span class="island-bar"><span></span></span>`;
    island.classList.add('is-on', 'is-busy');
    say(`${slice.label}: working on it…`);
    islandTimer = setTimeout(() => {
      island.classList.remove('is-busy');
      island.innerHTML = `<span class="island-mark is-done">${iconSvg('check', 'icon')}</span><span class="island-text">${slice.done}</span>`;
      announce(slice.done);
      if (slice.card && (slice.single || sources.length === 1)) addResult(source, slice.card);
      else if (slice.card) {
        // One result per file, each from that file's own wheel.
        for (const f of sources) {
          const own = wheelFor(f).find((x) => x.key === key)?.slices.find((x) => x.label === slice.label);
          if (own?.card) addResult(f, own.card);
        }
      }
      say(slice.card ? 'Saved next to the original, which is untouched. Try another file.' : 'Done. Try another file, or another wheel.');
      islandTimer = setTimeout(() => island.classList.remove('is-on'), 3200);
    }, reducedMotion ? 300 : 900);
  }

  function addResult(source, c) {
    const dot = c.file.lastIndexOf('.');
    const isFolder = c.title === 'Folder';
    const base = isFolder || dot < 0 ? c.file : c.file.slice(0, dot);
    const ext = isFolder || dot < 0 ? '' : c.file.slice(dot + 1);
    const kind = { svg: 'image', webp: 'image', png: 'image', jpg: 'image', avif: 'image', heic: 'image', tiff: 'image', bmp: 'image', gif: 'image',
      pdf: 'pdf', mp4: 'video', mkv: 'video', webm: 'video', avi: 'video', wmv: 'video', mov: 'video',
      mp3: 'audio', m4a: 'audio', flac: 'audio', ogg: 'audio', opus: 'audio', aiff: 'audio', wma: 'audio', wav: 'audio',
      zip: 'archive', '7z': 'archive', 'tar.gz': 'archive', gz: 'archive' }[ext.toLowerCase()] ?? (isFolder ? 'files' : 'document');
    const name = ext ? `${base}.${ext}` : base;
    const prev = added.findIndex((a) => `${a.base}${a.ext ? '.' + a.ext : ''}` === name);
    if (prev >= 0) added.splice(prev, 1);
    added.push({ base, ext, mb: c.size, icon: kind, kind: kindOf(kind), result: true });
    while (added.length > MAX_ADDED) added.shift();
    renderFiles();
    const tile = [...grid.querySelectorAll('.file-new')].pop();
    if (tile && !reducedMotion) tile.animate([{ opacity: 0, transform: 'scale(0.94)' }, { opacity: 1, transform: 'scale(1)' }], { duration: 260, easing: 'cubic-bezier(0.23, 1, 0.32, 1)' });
  }

  const kindOf = (icon) => ({ image: 'photo', pdf: 'pdf', video: 'video', audio: 'audio', archive: 'archive', document: 'document' }[icon] ?? 'archive');

  // Results dropped back on the desk can be picked up again, as the files they are.
  function fileFor(name) {
    const f = findFile(name);
    if (f) return f;
    const a = added.find((x) => (x.ext ? `${x.base}.${x.ext}` : x.base) === name);
    if (!a) return null;
    if (a.icon === 'files') return null; // an extracted folder: not part of the demo
    return { ...a, ext: a.ext || 'zip' };
  }

  // ---- Dragging ---------------------------------------------------------------------------------

  function beginDrag() {
    mode = 'dragging';
    // A selected tile carries the whole selection with it, as in Finder.
    const name = press.el.dataset.name;
    batch = selected.length > 1 && selected.includes(name)
      ? [file, ...selected.filter((x) => x !== name).map(fileFor).filter(Boolean)]
      : [file];
    selected = [];
    renderSelection();
    for (const f of batch) grid.querySelector(`[data-name="${f.base}.${f.ext}"]`)?.classList.add('is-dragging');
    press.el.classList.add('is-dragging');
    ghost.innerHTML = `${iconSvg(file.icon, 'icon')}<span class="mono">${batch.length > 1 ? `${batch.length} files` : `${file.base}.${file.ext}`}</span>`;
    ghost.classList.add('is-on');
    moveGhost();
    say(`Now tap a key: ${SECTIONS.map((s) => `${keyOf(s.key)} ${s.title}`).join(', ')}.`);
    keys.classList.add('is-ready');
  }

  function moveGhost() {
    const r = overlayRect();
    ghost.style.transform = `translate(${pointer.x - r.left + 16}px, ${pointer.y - r.top + 14}px)`;
  }

  function endDrag() {
    ghost.classList.remove('is-on');
    keys.classList.remove('is-ready');
    grid.querySelectorAll('.is-dragging').forEach((e) => e.classList.remove('is-dragging'));
    if (press?.el?.hasPointerCapture?.(press.id)) press.el.releasePointerCapture(press.id);
    press = null;
  }

  grid.addEventListener('pointerdown', (e) => {
    const el = e.target.closest('.file');
    if (!el || e.button !== 0) return;
    isTouch = e.pointerType === 'touch';
    if (mode === 'wheel' && attract) {
      closeWheel(false);
      idleHint();
    } else if (mode === 'wheel') return;
    const f = fileFor(el.dataset.name);
    if (!f) return;
    file = f;
    batch = [f];
    press = { x: e.clientX, y: e.clientY, id: e.pointerId, el, pointerType: e.pointerType, ctrl: e.ctrlKey || e.metaKey, shift: e.shiftKey };
    pointer = { x: e.clientX, y: e.clientY };
    mode = 'pressed';
    if (e.pointerType !== 'touch') {
      el.setPointerCapture(e.pointerId);
      // No preventDefault: the press must move keyboard focus into the page (from the address bar,
      // say), or the keys never reach it. The stage's user-select: none stops text selection.
      el.focus({ preventScroll: true });
    }
  });

  window.addEventListener('pointermove', (e) => {
    pointer = { x: e.clientX, y: e.clientY };
    if (mode === 'pressed' && press && press.pointerType !== 'touch' &&
        Math.hypot(e.clientX - press.x, e.clientY - press.y) > DRAG_START_PX) {
      beginDrag();
      // Shift already held when the drag started: Convert opens straight away.
      if (e.shiftKey) {
        openWheel(pointer.x, pointer.y, false, 'convert');
        updateHot();
      }
    }
    if (mode === 'dragging' || (mode === 'wheel' && !byClick)) moveGhost();
    if (mode === 'wheel') {
      if (keyHot && !attract && Math.hypot(e.movementX, e.movementY) > 2) keyHot = false;
      updateHot();
    }
  });

  window.addEventListener('pointerup', (e) => {
    pointer = { x: e.clientX, y: e.clientY };
    if (mode === 'pressed' && press.pointerType !== 'touch') {
      // A click only selects, as in Finder: ⌘-click (Ctrl-click) adds or removes a file, Shift-click
      // takes a range. The wheel needs a key tapped during a drag.
      const { el, ctrl, shift } = press;
      const name = el.dataset.name;
      endDrag();
      mode = 'idle';
      if (ctrl) {
        selected = selected.includes(name) ? selected.filter((x) => x !== name) : [...selected, name];
        anchor = name;
      } else if (shift && anchor) {
        const names = tileNames();
        const [a, b] = [names.indexOf(anchor), names.indexOf(name)].sort((x, y) => x - y);
        selected = a < 0 ? [name] : names.slice(a, b + 1);
      } else {
        selected = [name];
        anchor = name;
      }
      renderSelection();
      say(selected.length > 1
        ? `${selected.length} files selected. Drag them and tap ${keyOf('convert')}.`
        : selected.length ? `Now drag it and tap ${keyOf('convert')}. ${pickMore} picks more files.` : `Drag a file and tap ${keyOf('convert')}.`);
      return;
    }
    if (mode === 'pressed') {
      // A tap (no keys on a phone): the wheel opens over the file.
      const el = press.el;
      endDrag();
      const r = el.getBoundingClientRect();
      openWheel(r.left + r.width / 2, r.top + r.height / 2, true);
      pointer = { x: -1e4, y: -1e4 };
      updateHot();
      return;
    }
    if (mode === 'dragging') {
      endDrag();
      mode = 'idle';
      say(`No key, no wheel: the drop goes wherever you let go, as usual. Try again and tap ${keyOf('convert')}.`);
      return;
    }
    if (mode === 'wheel' && !byClick) {
      const slot = keyHot ? wheel.hot : hitTest(e.clientX, e.clientY);
      if (slot >= 0) run(slot);
      else cancel();
    }
  });

  // A touch that turned into a page scroll is not a tap.
  window.addEventListener('pointercancel', () => {
    if (mode === 'pressed' || mode === 'dragging') {
      endDrag();
      mode = 'idle';
    }
  });

  // Clicks and taps while the wheel is open (click mode).
  overlay.addEventListener('pointerup', (e) => {
    if (mode !== 'wheel' || !byClick) return;
    const tab = e.target.closest('[data-section]');
    if (tab) {
      const i = Number(tab.dataset.section);
      if (i !== section) showSection(i, i > section ? 1 : -1);
      return;
    }
    const slot = hitTest(e.clientX, e.clientY);
    if (slot >= 0) run(slot);
    else if (slot === ON_CENTRE || slot === OUTSIDE) cancel();
  });

  // The bar's wheels also answer a click during a drag (pointer capture sends it elsewhere).
  panel.addEventListener('pointerdown', (e) => {
    const tab = e.target.closest('[data-section]');
    if (!tab || mode !== 'wheel' || !byClick) return;
    e.stopPropagation();
  });

  // ---- Keyboard ---------------------------------------------------------------------------------

  // Moves the highlight one action round the ring: arrows and the scroll wheel, as in the app.
  function step(dir) {
    const n = wheel.slices.length;
    const next = wheel.hot < 0 ? (dir > 0 ? 0 : n - 1) : (wheel.hot + dir + n) % n;
    keyHot = true;
    if (attract) attractHot = next;
    wheel.setHot(next);
    renderCard();
    announce(`${wheel.slices[next].label}: ${wheel.slices[next].title ?? ''}`);
  }

  // Tapping another wheel's key while one is open switches to it, if these files have it.
  function switchTo(group) {
    const i = sections.findIndex((s) => s.key === group);
    if (i >= 0 && i !== section) showSection(i, i > section ? 1 : -1);
  }

  window.addEventListener('keydown', (e) => {
    const group = groupFor(e);
    if (group) {
      if (e.repeat) return;
      keyFor(group)?.classList.add('is-down');
      if (mode === 'pressed' && press && press.pointerType !== 'touch') beginDrag();
      if (mode === 'dragging') {
        openWheel(pointer.x, pointer.y, false, group);
        updateHot();
      } else if (mode === 'wheel' && !attract) switchTo(group);
      // Alt alone would move focus to the browser's menu on Windows.
      if (mode !== 'idle' && e.key === 'Alt') e.preventDefault();
      return;
    }
    if (mode !== 'wheel') return;
    if (e.key === 'Escape') {
      cancel();
      e.preventDefault();
    } else if (e.key === 'ArrowRight' || e.key === 'ArrowDown' || e.key === 'ArrowLeft' || e.key === 'ArrowUp') {
      step(e.key === 'ArrowRight' || e.key === 'ArrowDown' ? 1 : -1);
      e.preventDefault();
    } else if (e.key === 'Enter' || e.key === ' ') {
      if (wheel.hot >= 0) run(wheel.hot);
      e.preventDefault();
    } else if (e.key === 'Tab') {
      const dir = e.shiftKey ? -1 : 1;
      showSection(section + dir, dir);
      e.preventDefault();
    }
  });

  window.addEventListener('keyup', () => {
    keys.querySelectorAll('.is-down').forEach((k) => k.classList.remove('is-down'));
  });

  // Enter or Space on a focused file opens the wheel over it.
  grid.addEventListener('keydown', (e) => {
    const el = e.target.closest('.file');
    if (!el || (e.key !== 'Enter' && e.key !== ' ') || mode === 'wheel' || e.ctrlKey || e.metaKey) return;
    const f = fileFor(el.dataset.name);
    if (!f) return;
    e.preventDefault();
    file = f;
    batch = [f];
    const r = el.getBoundingClientRect();
    openWheel(r.left + r.width / 2, r.top + r.height / 2, true);
    keyHot = true;
    wheel.setHot(0);
    renderCard();
  });

  // ---- Scrolling moves the highlight -------------------------------------------------------------

  let wheelAcc = 0, wheelAt = 0;
  // Listened for on the whole window, before anything else sees it: while a drag holds the mouse,
  // some browsers send the scroll to the dragged tile or elsewhere rather than to the wheel.
  window.addEventListener('wheel', (e) => {
    if (mode !== 'wheel') return;
    // The opening pose only takes the scroll over the wheel itself, so the page still scrolls.
    if (attract && !e.target.closest?.('[data-wheel], [data-panel]')) return;
    e.preventDefault();
    const now = performance.now();
    if (now - wheelAt > 300) wheelAcc = 0;
    wheelAt = now;
    // Holding Shift turns a mouse wheel's scroll sideways (deltaX) in most browsers; it counts the same.
    const delta = Math.abs(e.deltaY) >= Math.abs(e.deltaX) ? e.deltaY : e.deltaX;
    wheelAcc += e.deltaMode === 1 ? delta * 40 : e.deltaMode === 2 ? delta * 400 : delta; // lines, pages
    if (Math.abs(wheelAcc) >= 40) {
      const dir = Math.sign(wheelAcc);
      wheelAcc = 0;
      step(dir);
    }
  }, { passive: false, capture: true });

  // The on-screen keys: tap one to open its wheel for the last file picked, or to switch to it.
  keys.addEventListener('click', (e) => {
    const group = e.target.closest('[data-group]')?.dataset.group;
    if (!group) return;
    if (mode === 'wheel' && !attract) return switchTo(group);
    if (mode === 'wheel') closeWheel(false);
    if (!file) file = findFile('photo.jpg');
    batch = [file];
    const el = grid.querySelector(`[data-name="${file.base}.${file.ext}"]`) ?? grid.querySelector('.file');
    const r = el.getBoundingClientRect();
    openWheel(r.left + r.width / 2, r.top + r.height / 2, true, group);
  });

  document.addEventListener('pointerdown', (e) => {
    if (mode === 'wheel' && byClick && !attract && !stage.contains(e.target)) cancel();
  });

  window.addEventListener('resize', () => {
    if (mode === 'wheel') place(centre.x, centre.y);
  });

  // ---- Clock --------------------------------------------------------------------------------------

  const clock = stage.querySelector('[data-clock]');
  const tick = () => {
    const now = new Date();
    clock.textContent = `${now.toLocaleDateString([], { weekday: 'short' })} ${now.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}`;
  };
  tick();
  setInterval(tick, 15000);

  isTouch = matchMedia('(hover: none)').matches;
  idleHint();

  // The opening pose: photo.jpg picked up, the Tools wheel open beside the window with Compress lit and
  // its result card showing. Only where there is room beside it.
  function startAttract() {
    const r = overlayRect();
    const explorer = stage.querySelector('.explorer').getBoundingClientRect();
    const room = r.right - explorer.right;
    if (room < 360 || mode !== 'idle') return;
    file = findFile('photo.jpg');
    batch = [file];
    openWheel(explorer.right + room / 2, r.top + r.height * 0.5, true, 'tools');
    attract = true;
    overlay.classList.add('is-attract');
    attractHot = Math.max(0, wheel.slices.findIndex((s) => s.label === 'Compress'));
    keyHot = true;
    wheel.setHot(attractHot);
    renderCard();
    const edge = (outerEdge(wheel.layout) + 8) * scale;
    ghost.innerHTML = `${iconSvg(file.icon, 'icon')}<span class="mono">${file.base}.${file.ext}</span>`;
    ghost.style.transform = `translate(${centre.x + edge * 0.62}px, ${centre.y - edge * 0.9}px)`;
    ghost.classList.add('is-on');
    idleHint();
  }
  startAttract();
}

import { startDemo } from './demo.js';
import { Wheel } from './wheel.js';
import { SAMPLE_FILES, wheelFor } from './content.js';
import { iconSvg } from './icons.js';

// Icons named in the HTML (data-icon="download").
for (const el of document.querySelectorAll('[data-icon]')) {
  el.insertAdjacentHTML('afterbegin', iconSvg(el.dataset.icon, el.dataset.iconClass || 'icon'));
}

// The sun/moon button in the header.
for (const b of document.querySelectorAll('[data-theme-toggle]')) {
  const label = () => b.setAttribute('aria-label', document.documentElement.dataset.theme === 'dark' ? 'Switch to light mode' : 'Switch to dark mode');
  label();
  b.addEventListener('click', () => { window.toggleTheme?.(); label(); });
}

// Labels are measured to fit their tiles, so the wheels wait for the fonts.
await Promise.all([document.fonts.load('600 13px "IBM Plex Sans"'), document.fonts.load('400 12px "IBM Plex Sans"')]).catch(() => {});
await document.fonts.ready;

// Still wheels drawn by the same engine (How it works, Private by design, the 404 page). They show a
// photo on Convert with WebP hovered, as the app does.
for (const host of document.querySelectorAll('[data-still-wheel]')) {
  const photo = SAMPLE_FILES.find((f) => f.base === 'photo');
  const [convert] = wheelFor(photo);
  const wheel = new Wheel({ reducedMotion: true });
  wheel.set({ slices: convert.slices, centre: '1 file', title: convert.title, sections: 4, section: 0 });
  const hot = host.dataset.stillWheel;
  if (hot !== '') wheel.setHot(Number(hot));
  host.appendChild(wheel.svg);
}

const stage = document.querySelector('[data-stage]');
// Phones and tablets get a still wheel instead (no mouse to drag with, no Shift key).
if (stage && getComputedStyle(stage).display !== 'none') startDemo(stage);
else {
  // They get a short silent loop of the app instead, loaded only here. Reduced motion: the still
  // frame, with controls to play it.
  const loop = document.querySelector('[data-loop]');
  if (loop) {
    loop.poster = loop.dataset.poster;
    for (const s of loop.querySelectorAll('source[data-src]')) s.src = s.dataset.src;
    if (matchMedia('(prefers-reduced-motion: reduce)').matches) loop.controls = true;
    else {
      loop.preload = 'auto';
      loop.load();
      loop.play().catch(() => { loop.controls = true; });
    }
  }
}

// The header gains a line once the page scrolls under it.
const header = document.querySelector('.site-header');
if (header) {
  const onScroll = () => header.classList.toggle('is-scrolled', window.scrollY > 8);
  onScroll();
  window.addEventListener('scroll', onScroll, { passive: true });
}


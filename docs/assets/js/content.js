// What Morph's wheels offer each sample file: the same wheels, actions, order and output names as the
// app (Library.swift, Runner.swift's recipes, the Mac app's Actions). Sizes are examples for the demo;
// nothing is converted in the browser.

// The four wheels and the keys that open them mid-drag, on a Mac and on Windows.
export const SECTIONS = [
  { key: 'convert', title: 'Convert', icon: 'convert', mac: '⇧', win: 'Shift' },
  { key: 'tools', title: 'Tools', icon: 'tools', mac: '⌘', win: 'Ctrl' },
  { key: 'recipes', title: 'Recipes', icon: 'recipe', mac: '⌃', win: 'Ctrl+Shift' },
  { key: 'actions', title: 'Actions', icon: 'files', mac: '⌥', win: 'Alt' },
];

export function formatSize(mb) {
  if (mb >= 100) return `${Math.round(mb)} MB`;
  if (mb >= 1) return `${mb.toFixed(1)} MB`;
  return `${Math.max(1, Math.round(mb * 1024))} KB`;
}

const name = (file) => `${file.base}.${file.ext}`;
const pct = (was, now) => Math.round((1 - now / was) * 100);

// ---- Builders ----------------------------------------------------------------------------------------

// A new file beside the original: Morph names it after the original, plus a word for what changed.
function result(file, label, icon, title, out, mb, { folder = false, smaller = false } = {}) {
  return {
    label, icon, title,
    card: { title: folder ? 'Folder' : label, file: out, size: mb },
    done: smaller ? `${formatSize(file.mb)} → ${formatSize(mb)}, ${pct(file.mb, mb)}% smaller` : `Saved ${out}`,
  };
}

const convert = (file, label, ext, mb, icon) => result(file, label, icon, `Convert to ${label}`, `${file.base}.${ext}`, mb);

function zip(file) {
  const packed = file.kind === 'photo' || file.kind === 'video' || file.kind === 'audio' ? 0.97 : 0.4;
  return result(file, 'Zip', 'zip', 'Zip', `${file.base}.zip`, file.mb * packed);
}

// The Mac app's Actions wheel: things done with the file itself, nothing new is made.
function actions(file) {
  const n = name(file);
  return [
    { label: 'AirDrop', icon: 'airdrop', title: 'AirDrop', done: `AirDrop opened with ${n}` },
    { label: 'Messages', icon: 'message', title: 'Send in Messages', done: `Messages opened with ${n}` },
    { label: 'Mail', icon: 'mail', title: 'Send in Mail', done: `New mail with ${n} attached` },
    { label: 'Copy', icon: 'copy', title: 'Copy', done: `${n} copied` },
    { label: 'Copy Path', icon: 'link', title: 'Copy Path', done: `Copied ~/Downloads/${n}` },
    { label: 'Move To…', icon: 'move', title: 'Move To…', done: 'Pick a folder to move it to' },
    { label: 'Copy To…', icon: 'duplicate', title: 'Copy To…', done: 'Pick a folder to copy it to' },
    { label: 'Terminal', icon: 'terminal', title: 'Open Terminal Here', done: 'Terminal opened in Downloads' },
  ];
}

// The formats a photo can become, in the wheel's order: the common ones, then SVG and PDF on the first page.
const IMAGE_FORMATS = [
  ['PNG', 'png', 2.9, 'image'], ['JPG', 'jpg', 1, 'image'], ['HEIC', 'heic', 0.5, 'image'], ['SVG', 'svg', 0.2, 'vector'],
  ['PDF', 'pdf', 1.03, 'pdf'], ['AVIF', 'avif', 0.3, 'image'], ['TIFF', 'tiff', 9, 'image'], ['GIF', 'gif', 0.9, 'image'], ['BMP', 'bmp', 9, 'image'],
];

function photo(file) {
  const jpgMb = file.ext === 'png' ? file.mb / 2.9 : file.mb;
  const b = file.base;
  return {
    convert: IMAGE_FORMATS.filter(([, ext]) => ext !== file.ext).map(([label, ext, k, icon]) => convert(file, label, ext, jpgMb * k, icon)),
    tools: [
      result(file, 'Compress', 'shrink', 'Compress', `${b} compressed.jpg`, jpgMb * 0.42, { smaller: true }),
      result(file, 'Resize', 'fit', 'Resize to 2048 px', `${b} 2048px.${file.ext}`, file.mb * 0.4),
      result(file, 'Remove Metadata', 'tag', 'Remove Location and Camera Info', `${b} clean.${file.ext}`, file.mb * 0.99),
      result(file, 'Blur Faces', 'face', 'Blur Faces', `${b} redacted.${file.ext}`, file.mb),
      result(file, 'Hide Personal Info', 'redact', 'Hide Emails, Numbers and IDs', `${b} redacted.${file.ext}`, file.mb),
      result(file, 'Extract Text', 'text', 'Extract Text', `${b} text.txt`, 0.002),
      { label: 'Read QR', icon: 'qr', title: 'Read QR Codes', done: 'No QR codes or barcodes found' },
      zip(file),
    ],
    recipes: [
      result(file, 'Share-Safe Photo', 'private', 'No Location, 2048 px', `${b} clean 2048px.${file.ext}`, file.mb * 0.4),
      result(file, 'Web Image', 'globe', '1600 px WebP', `${b} 1600px.webp`, jpgMb * 0.12, { smaller: true }),
      result(file, 'Under 1 MB', 'mail', 'Under 1 MB, for Email and Forms', `${b} compressed.jpg`, 0.96, { smaller: true }),
    ],
    actions: actions(file),
  };
}

function video(file) {
  const fmts = [['MP4', 'mp4', 0.95, 'video'], ['WEBM', 'webm', 0.39, 'video'], ['MKV', 'mkv', 1, 'video'], ['GIF', 'gif', 1.4, 'image'],
    ['M4A', 'm4a', 0.016, 'audio'], ['WAV', 'wav', 0.17, 'audio'], ['AIFF', 'aiff', 0.17, 'audio'], ['MP3', 'mp3', 0.018, 'audio']];
  const b = file.base;
  return {
    convert: fmts.map(([label, ext, k, icon]) => convert(file, label, ext, file.mb * k, icon)),
    tools: [
      result(file, 'Compress', 'shrink', 'Compress', `${b} compressed.mp4`, file.mb * 0.18, { smaller: true }),
      result(file, 'Remove Metadata', 'tag', 'Remove Location and Camera Info', `${b} clean.${file.ext}`, file.mb),
      result(file, 'Mute', 'mute', 'Remove the Sound', `${b} muted.${file.ext}`, file.mb * 0.97),
      result(file, 'Snapshots', 'frames', 'Snapshots', `${b} frames`, 4.2, { folder: true }),
      result(file, 'Normalize Loudness', 'normalize', 'Normalize Loudness', `${b} normalized.${file.ext}`, file.mb),
      zip(file),
    ],
    recipes: [result(file, 'Under 1 MB', 'mail', 'Under 1 MB, for Email and Forms', `${b} compressed.mp4`, 0.97, { smaller: true })],
    actions: actions(file),
  };
}

function pdf(file) {
  const b = file.base;
  return {
    convert: [
      result(file, 'Images', 'image', 'Every Page as an Image', `${b} images`, file.mb * 2.4, { folder: true }),
      convert(file, 'Text', 'txt', 0.01, 'text'),
      convert(file, 'DOCX', 'docx', file.mb * 0.4, 'document'),
    ],
    tools: [
      result(file, 'Compress', 'shrink', 'Compress', `${b} compressed.pdf`, file.mb * 0.45, { smaller: true }),
      result(file, 'Extract Text', 'text', 'Extract Text', `${b} text.txt`, 0.01),
      { label: 'Read QR', icon: 'qr', title: 'Read QR Codes', done: '1 QR code read and copied' },
      result(file, 'Split PDF', 'split', 'A PDF per Page', `${b} pages`, file.mb, { folder: true }),
      zip(file),
    ],
    recipes: [result(file, 'Under 1 MB', 'mail', 'Under 1 MB, for Email and Forms', `${b} compressed.pdf`, Math.min(0.96, file.mb * 0.6), { smaller: true })],
    actions: actions(file),
  };
}

function audio(file) {
  const fmts = [['M4A', 'm4a', 0.09], ['AIFF', 'aiff', 1], ['MP3', 'mp3', 0.09], ['FLAC', 'flac', 0.55], ['OGG', 'ogg', 0.07], ['OPUS', 'opus', 0.05]];
  const b = file.base;
  return {
    convert: fmts.map(([label, ext, k]) => convert(file, label, ext, file.mb * k, 'audio')),
    tools: [
      result(file, 'Remove Metadata', 'tag', 'Remove Tags and Info', `${b} clean.${file.ext}`, file.mb),
      result(file, 'Normalize Loudness', 'normalize', 'Normalize Loudness', `${b} normalized.${file.ext}`, file.mb),
      result(file, 'Trim Silence', 'trim', 'Trim Silence', `${b} trimmed.${file.ext}`, file.mb * 0.94),
      result(file, 'Waveform Video', 'visuals', 'Waveform Video', `${b} waveform.mp4`, file.mb * 0.3),
      zip(file),
    ],
    actions: actions(file),
  };
}

function document_(file) {
  const fmts = [['PDF', 'pdf', 1.6, 'pdf'], ['ODT', 'odt', 0.9, 'document'], ['RTF', 'rtf', 1.4, 'document'], ['HTML', 'html', 0.4, 'html'],
    ['MD', 'md', 0.1, 'markdown'], ['TXT', 'txt', 0.05, 'text']];
  return {
    convert: fmts.map(([label, ext, k, icon]) => convert(file, label, ext, file.mb * k, icon)),
    tools: [zip(file)],
    actions: actions(file),
  };
}

function archive(file) {
  return {
    tools: [result(file, 'Extract', 'extract', 'Extract', file.base, file.mb * 2.6, { folder: true }), zip(file)],
    actions: actions(file),
  };
}

const BUILD = { photo, video, pdf, audio, document: document_, archive };

const wheels = (sets) => SECTIONS.filter((s) => sets[s.key]?.length).map((s) => ({ ...s, slices: sets[s.key] }));

// The wheels Morph shows for a file, in order, each only if it has actions.
export function wheelFor(file) {
  return wheels(BUILD[file.kind](file));
}

// Several files at once. Files of one kind get that kind's wheels, each action run on every file; several
// images also make one PDF, and several PDFs merge. A mix of kinds gets what fits them all: Zip and Actions.
// Cards show the first file's result; `single` actions make one file for all.
export function wheelForMany(list) {
  if (list.length === 1) return wheelFor(list[0]);
  const n = list.length;
  const total = list.reduce((sum, f) => sum + f.mb, 0);
  const first = list[0];
  const many = { ...first, mb: total };
  const zipAll = { ...result(many, 'Zip', 'zip', 'Zip', 'Archive.zip', total * 0.7), single: true, done: `${n} files saved in Archive.zip` };
  const acts = actions(first).map((a) => ({ ...a, done: a.done.replace(name(first), `${n} files`).replace(/\bit\b/, 'them') }));
  if (!list.every((f) => f.kind === first.kind)) return wheels({ tools: [zipAll], actions: acts });
  const sets = BUILD[first.kind](first);
  const each = (s) => (s.card ? { ...s, done: `${n} files done` } : s);
  for (const key of ['convert', 'tools', 'recipes']) if (sets[key]) sets[key] = sets[key].map(each);
  sets.tools = sets.tools.map((s) => (s.label === 'Zip' ? zipAll : s));
  if (first.kind === 'photo') {
    sets.convert = sets.convert.map((s) => (s.label === 'PDF'
      ? { ...s, single: true, title: 'One PDF, a Page per Image', card: { ...s.card, file: `${first.base}.pdf`, size: total * 1.03 }, done: `${n} images in one PDF` }
      : s));
  }
  if (first.kind === 'pdf') {
    sets.tools.splice(3, 0, { ...result(many, 'Merge PDFs', 'merge', 'Merge into One PDF', 'Merged.pdf', total * 0.97), single: true, done: `${n} PDFs merged into Merged.pdf` });
  }
  sets.actions = acts;
  return wheels(sets);
}

export const SAMPLE_FILES = [
  { base: 'screenshot', ext: 'png', kind: 'photo', mb: 1.2, icon: 'image' },
  { base: 'photo', ext: 'jpg', kind: 'photo', mb: 3.4, icon: 'image' },
  { base: 'contract-v3', ext: 'pdf', kind: 'pdf', mb: 1.6, icon: 'pdf' },
  { base: 'podcast-ep12', ext: 'wav', kind: 'audio', mb: 58, icon: 'audio' },
  { base: 'demo-cut', ext: 'mov', kind: 'video', mb: 248, icon: 'video' },
  { base: 'notes', ext: 'docx', kind: 'document', mb: 0.24, icon: 'document' },
  { base: 'assets', ext: 'zip', kind: 'archive', mb: 12, icon: 'archive' },
  { base: 'invoice-0918', ext: 'pdf', kind: 'pdf', mb: 0.9, icon: 'pdf' },
];

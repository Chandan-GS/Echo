// Draws every Echo icon from echo_icons.html in headless Chrome and writes
// them into the app (Android, iOS, macOS, Windows) and, given its folder, the
// website:
//   node tool/brand/render.mjs [path/to/echo-landing-page]
// Then draw the splash: see test/render/splash_render_test.dart.
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, '../..');
const website = process.argv[2] && path.resolve(process.argv[2]);
const chromePath = process.env.CHROME ?? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const port = 9341;

const profile = fs.mkdtempSync(path.join(fs.realpathSync('/tmp'), 'echo-icons-'));
const chrome = spawn(chromePath, ['--headless=new', '--disable-gpu', `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`, 'about:blank'], { stdio: 'ignore' });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

try {
  let ws;
  for (let i = 0; i < 50 && !ws; i++) {
    try {
      const pages = await (await fetch(`http://127.0.0.1:${port}/json`)).json();
      const page = pages.find((p) => p.type === 'page');
      if (page) ws = new WebSocket(page.webSocketDebuggerUrl);
    } catch {}
    if (!ws) await sleep(200);
  }
  await new Promise((r) => ws.addEventListener('open', r));
  let id = 0;
  const waiting = new Map();
  ws.addEventListener('message', (e) => {
    const m = JSON.parse(e.data);
    if (m.id && waiting.has(m.id)) { waiting.get(m.id)(m); waiting.delete(m.id); }
  });
  const send = (method, params = {}) => new Promise((r) => { const i = ++id; waiting.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });

  await send('Page.navigate', { url: `file://${path.join(here, 'echo_icons.html')}#quiet` });
  await sleep(1500);
  const reply = await send('Runtime.evaluate', { expression: 'render()', returnByValue: true });
  const files = reply.result?.result?.value;
  if (!files) throw new Error(`render() failed: ${JSON.stringify(reply.result?.exceptionDetails ?? reply)}`);

  const ico = [];
  for (const [rel, url] of Object.entries(files)) {
    const png = Buffer.from(url.split(',')[1], 'base64');
    if (rel.startsWith('windows-ico/')) { ico.push([parseInt(path.basename(rel)), png]); continue; }
    if (rel.startsWith('web/')) {
      if (!website) continue;
      write(path.join(website, 'public', rel.slice(4)), png);
      continue;
    }
    write(path.join(repo, rel), png);
  }
  write(path.join(repo, 'windows/runner/resources/app_icon.ico'), icoFile(ico.sort((a, b) => a[0] - b[0])));
  console.log(`Wrote ${Object.keys(files).length - ico.length + 1} files${website ? '' : ' (no website folder given; skipped its icons)'}.`);
} finally {
  // Chrome is still writing its profile as it quits: let it go first.
  const exited = new Promise((r) => chrome.once('exit', r));
  chrome.kill();
  await exited;
  fs.rmSync(profile, { recursive: true, force: true, maxRetries: 5, retryDelay: 200 });
}

function write(file, data) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, data);
}

/** A Windows .ico holding each size as a PNG. */
function icoFile(images) {
  const head = Buffer.alloc(6 + 16 * images.length);
  head.writeUInt16LE(0, 0); head.writeUInt16LE(1, 2); head.writeUInt16LE(images.length, 4);
  let offset = head.length;
  images.forEach(([n, png], i) => {
    const e = 6 + 16 * i;
    head.writeUInt8(n >= 256 ? 0 : n, e); head.writeUInt8(n >= 256 ? 0 : n, e + 1);
    head.writeUInt8(0, e + 2); head.writeUInt8(0, e + 3);
    head.writeUInt16LE(1, e + 4); head.writeUInt16LE(32, e + 6);
    head.writeUInt32LE(png.length, e + 8); head.writeUInt32LE(offset, e + 12);
    offset += png.length;
  });
  return Buffer.concat([head, ...images.map(([, png]) => png)]);
}

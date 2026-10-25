// Takes the raw store screenshots from the web build with a demo family.
//
// Needs: the Firebase emulators (auth + firestore), the web app built with
// --dart-define=USE_EMULATOR=true and served on http://localhost:8765, the
// demo data (OUT=... flutter test tool/demo_family_test.dart) and Playwright.
// Build with --dart-define=CLASSROOM=false when the store version hides Classroom.
// Usage: node store/screenshots.js <demo.json> <play|ios> <out dir>
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const [demoFile, target, outDir] = process.argv.slice(2);
const SIZES = { play: { width: 360, height: 640 }, ios: { width: 430, height: 932 } };
const FS = 'http://127.0.0.1:8080/v1/projects/demo-supermom/databases/(default)/documents';
const AUTH = 'http://127.0.0.1:9099';
const owner = { Authorization: 'Bearer owner', 'Content-Type': 'application/json' };
// Wednesday 28 Oct 2026, 4:35 pm in Dubai.
const DEMO_TIME = new Date('2026-10-28T16:35:00+04:00');

const toValue = (v) => {
  if (v === null || v === undefined) return { nullValue: null };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (typeof v === 'number') return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  if (typeof v === 'string') return { stringValue: v };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(toValue) } };
  return { mapValue: { fields: Object.fromEntries(Object.entries(v).map(([k, x]) => [k, toValue(x)])) } };
};
const put = async (docPath, data) => {
  const res = await fetch(`${FS}/${docPath}`, { method: 'PATCH', headers: owner, body: JSON.stringify({ fields: toValue(data).mapValue.fields }) });
  if (!res.ok) throw new Error(`${docPath}: ${res.status} ${await res.text()}`);
};

async function seed() {
  await fetch(`${AUTH}/emulator/v1/projects/demo-supermom/accounts`, { method: 'DELETE' });
  await fetch(FS.replace('/v1/', '/emulator/v1/'), { method: 'DELETE' });
  const signUp = await (await fetch(`${AUTH}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo-api-key`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: 'mom@example.com', password: 'bismillah123', returnSecureToken: true }),
  })).json();
  const demo = JSON.parse(fs.readFileSync(demoFile, 'utf8'));
  demo.family.parents = [signUp.localId];
  await put('families/demo', demo.family);
  for (const [id, kid] of Object.entries(demo.kids)) await put(`families/demo/kids/${id}`, kid);
  for (const [id, week] of Object.entries(demo.weeks)) await put(`families/demo/weeks/${id}`, week);
}

(async () => {
  await seed();
  fs.mkdirSync(outDir, { recursive: true });
  const b = await chromium.launch();
  const ctx = await b.newContext({ viewport: SIZES[target], deviceScaleFactor: 3, timezoneId: 'Asia/Dubai' });
  if (process.env.FIREBASE_JS_DIR) {
    await ctx.route(/gstatic\.com\/firebasejs\/[^/]+\/(.+)$/, (route) => {
      const f = route.request().url().match(/firebasejs\/[^/]+\/(.+)$/)[1];
      route.fulfill({ path: `${process.env.FIREBASE_JS_DIR}/${f}`, contentType: 'application/javascript' });
    });
  }
  // Hide the emulator's "Running in emulator mode" banner.
  await ctx.addInitScript(() => {
    new MutationObserver(() => {
      for (const el of document.querySelectorAll('body > div, body > p')) {
        if (/emulator mode/i.test(el.textContent || '')) el.remove();
      }
    }).observe(document, { childList: true, subtree: true });
  });
  const p = await ctx.newPage();
  await p.clock.install({ time: DEMO_TIME });
  p.on('pageerror', (e) => console.log('ERR', e.message.slice(0, 200)));

  const tap = async (name, opts = {}) => {
    await p.getByRole('button', { name, ...opts }).first().click({ timeout: 8000, force: true });
    await p.waitForTimeout(900);
  };
  const tab = async (name) => { await p.getByRole('tab', { name }).first().click({ force: true }); await p.waitForTimeout(900); };
  const type = async (label, text) => {
    await p.locator(`input[aria-label="${label}"]`).or(p.getByRole('textbox', { name: label })).first().click({ force: true });
    await p.waitForTimeout(400);
    await p.keyboard.type(text, { delay: 30 });
    await p.waitForTimeout(300);
  };
  const scroll = async (dy) => { await p.mouse.move(SIZES[target].width / 2, SIZES[target].height / 2); await p.mouse.wheel(0, dy); await p.waitForTimeout(700); };
  const shot = async (name) => { await p.waitForTimeout(600); await p.screenshot({ path: path.join(outDir, `${name}.png`) }); console.log('saved', name); };

  await p.goto('http://localhost:8765/');
  await p.waitForTimeout(3500);
  await p.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  await p.waitForTimeout(500);
  await tap("I'm a parent");
  await type('Email', 'mom@example.com');
  await type('Password', 'bismillah123');
  await tap('Sign in', { exact: true });
  await p.waitForTimeout(2500);
  await type('PIN (4 to 6 digits)', '1234');
  await tap('Save PIN');
  await p.waitForTimeout(2500);

  await shot('4-mom-today');
  await tab('School');
  await p.mouse.move(5, 5);
  await p.waitForTimeout(1500); // let the tab's tooltip fade
  await shot('5-mom-school');
  await tap('Settings');
  await tap(/linked/);
  await tap('Link a device');
  await p.getByRole('checkbox', { name: /Aisha/ }).first().click({ force: true });
  await p.waitForTimeout(500);
  // Link codes are checked against the server's real clock, so use it here.
  await p.clock.setSystemTime(new Date());
  await tap('Show the code');
  await p.mouse.move(5, 5);
  await shot('6-link-device');
  await p.clock.setSystemTime(DEMO_TIME);
  await tap('Back');
  await tap('Back');
  await tap('Back');
  await tap('Kids mode');
  await tap('Aisha');
  await p.waitForTimeout(1500);
  await shot('1-kid-home');
  await scroll(target === 'ios' ? 640 : 560);
  await shot('2-kid-jobs');
  for (let i = 0; i < 12; i++) await scroll(800); // to the school and rewards cards
  await shot('3-kid-rewards');
  await b.close();
})().catch((e) => { console.error('FAILED', e.message); process.exit(1); });

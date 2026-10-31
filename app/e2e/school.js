// Stage 3 test against the Firebase emulator. See README, "Run and test".
// Mom adds a competition in the School tab; homework (as Google Classroom
// would create it) appears on Aisha's tablet; Aisha ticks it; Mom sees it.
const { chromium } = require('playwright');

const TZ = 'Pacific/Kiritimati';
const FS = 'http://127.0.0.1:8080/v1/projects/demo-supermom/databases/(default)/documents';
const owner = { Authorization: 'Bearer owner', 'Content-Type': 'application/json' };
const step = (m) => console.log('STEP', m);

async function newPhone(b, name) {
  const ctx = await b.newContext({ viewport: { width: 420, height: 900 }, timezoneId: TZ });
  if (process.env.FIREBASE_JS_DIR) {
    await ctx.route(/gstatic\.com\/firebasejs\/[^/]+\/(.+)$/, (route) => {
      const f = route.request().url().match(/firebasejs\/[^/]+\/(.+)$/)[1];
      route.fulfill({ path: `${process.env.FIREBASE_JS_DIR}/${f}`, contentType: 'application/javascript' });
    });
  }
  // Hide the emulator's "Running in emulator mode" banner; it covers the bottom of the screen.
  await ctx.addInitScript(() => {
    new MutationObserver(() => {
      for (const el of document.querySelectorAll('body > div, body > p')) {
        if (/emulator mode/i.test(el.textContent || '')) el.remove();
      }
    }).observe(document, { childList: true, subtree: true });
  });
  const p = await ctx.newPage();
  await p.clock.install();
  p.on('pageerror', (e) => console.log(name, 'ERR', e.message.slice(0, 300)));
  await p.goto('http://localhost:8765/');
  await p.waitForTimeout(3500);
  await p.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  await p.waitForTimeout(600);
  return p;
}
// Scrolls the Flutter page until the element is on screen (the picture on
// the first screens pushes some buttons below the fold).
async function reveal(p, loc) {
  const vh = p.viewportSize().height;
  for (let i = 0; i < 25; i++) {
    const box = await loc.boundingBox().catch(() => null);
    if (box && box.y >= 0 && box.y + box.height <= vh) return;
    await p.mouse.move(p.viewportSize().width / 2, vh / 2);
    await p.mouse.wheel(0, !box || box.y > vh / 2 ? 300 : -300);
    await p.waitForTimeout(150);
  }
}
const tap = async (p, name, opts = {}) => {
  console.log('  tap', String(name));
  const b = p.getByRole('button', { name, ...opts }).first(); await b.waitFor({ state: 'attached', timeout: 8000 }); await reveal(p, b); await b.click({ timeout: 8000, force: true });
  await p.waitForTimeout(900);
};
const type = async (p, label, text) => {
  const f = p.locator(`input[aria-label="${label}"], textarea[aria-label="${label}"]`).or(p.getByRole('textbox', { name: label })).first();
  await f.waitFor({ state: 'attached', timeout: 8000 }); await reveal(p, f); await f.click({ force: true, timeout: 5000 }); await p.waitForTimeout(400); await p.keyboard.type(text, { delay: 30 }); await p.waitForTimeout(300);
};
const tab = async (p, name) => {
  console.log('  tab', name);
  await p.getByRole('tab', { name }).first().click({ timeout: 8000, force: true });
  await p.waitForTimeout(900);
};
const screenText = (p) => p.evaluate(() =>
  [...document.querySelectorAll('flt-semantics')].map((e) => e.getAttribute('aria-label') || e.textContent).join(' | '));
// Lists build lazily, so scroll through the page and collect what appears.
const fullText = async (p) => {
  await p.mouse.move(210, 450);
  let text = await screenText(p);
  for (let i = 0; i < 8; i++) {
    await p.mouse.wheel(0, 600);
    await p.waitForTimeout(250);
    text += ' | ' + (await screenText(p));
  }
  for (let i = 0; i < 8; i++) await p.mouse.wheel(0, -600);
  await p.waitForTimeout(400);
  return text;
};
const shot = (p, f) => p.screenshot({ path: `${__dirname}/screenshots/${f}` });

// On a weekend the test moves both phones (and the family's time zone, which
// the security rules use) forward to Monday, because school tasks only open
// on school days. Set after the devices are linked: link codes are checked
// against the server's real clock.
let SHIFT_MS = 0;
const realWeekday = () => new Intl.DateTimeFormat('en-GB', { timeZone: TZ, weekday: 'short' }).format(new Date());
const SHIFT_DAYS = { Sat: 2, Sun: 1 }[realWeekday()] ?? 0;
const TZ_OFFSET_MIN = 14 * 60; // Pacific/Kiritimati

// Local time on the test phones.
function localNow() {
  const parts = Object.fromEntries(new Intl.DateTimeFormat('en-GB', {
    timeZone: TZ, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', weekday: 'short', hourCycle: 'h23',
  }).formatToParts(new Date(Date.now() + SHIFT_MS)).map((x) => [x.type, x.value]));
  return { ymd: `${parts.year}${parts.month}${parts.day}`, minute: +parts.hour * 60 + +parts.minute, weekday: parts.weekday };
}
const fsValue = (v) => typeof v === 'number' ? { integerValue: String(v) } : typeof v === 'boolean' ? { booleanValue: v } : v === null ? { nullValue: null } : { stringValue: v };

(async () => {
  await fetch('http://127.0.0.1:9099/emulator/v1/projects/demo-supermom/accounts', { method: 'DELETE' });
  await fetch(`${FS}`.replace('/v1/', '/emulator/v1/'), { method: 'DELETE' });
  const b = await chromium.launch();
  try {
    const mom = await newPhone(b, 'MOM');
    step('mom signs up and creates the family');
    await tap(mom, "I'm a parent");
    await tap(mom, 'New account');
    await type(mom, 'Email', 'mom@example.com');
    await type(mom, 'Password', 'bismillah123');
    await tap(mom, 'Create account', { exact: true });
    await mom.waitForTimeout(2500);
    step('mom confirms her email with the link');
    const codes = await (await fetch('http://127.0.0.1:9099/emulator/v1/projects/demo-supermom/oobCodes')).json();
    const verify = codes.oobCodes.filter((c) => c.requestType === 'VERIFY_EMAIL' && c.email === 'mom@example.com').pop();
    if (!verify) throw new Error('no confirmation email was sent');
    await fetch(verify.oobLink);
    await tap(mom, "I've confirmed my email");
    await mom.waitForTimeout(2500);
    await type(mom, 'Your name', 'Nousheen');
    await type(mom, 'Phone number', '+974 5512 3456');
    await mom.getByRole('checkbox', { name: /18 years or older/ }).first().click({ force: true });
    await mom.waitForTimeout(300);
    await type(mom, 'PIN (4 to 6 digits)', '1234');
    await type(mom, 'Type the PIN again', '1234');
    await type(mom, 'First name', 'Aisha');
    await tap(mom, 'Start', { exact: true });
    await mom.waitForTimeout(3000);

    step('mom links the tablet');
    await tap(mom, 'Settings');
    await tap(mom, /linked/);
    await tap(mom, 'Link a device');
    await mom.getByRole('checkbox', { name: /Aisha/ }).first().click({ force: true });
    await mom.waitForTimeout(600);
    await tap(mom, 'Show the code');
    await mom.waitForTimeout(1500);
    const pairings = await (await fetch(`${FS}/pairings`, { headers: owner })).json();
    const code = pairings.documents[0].name.split('/').pop();
    const kid = await newPhone(b, 'KID');
    await tap(kid, "This is my child's device");
    await type(kid, 'Code', code);
    await type(kid, 'Name for this device', "Aisha's tablet");
    await tap(kid, 'Link this device');
    await kid.waitForTimeout(3000);
    await tap(mom, 'Done');
    await tap(mom, 'Back');
    await tap(mom, 'Back');

    if (SHIFT_DAYS) {
      step(`moving the test clock ${SHIFT_DAYS} day(s) forward to Monday`);
      SHIFT_MS = SHIFT_DAYS * 86400000;
      for (const pg of [mom, kid]) await pg.clock.setSystemTime(new Date(Date.now() + SHIFT_MS));
      await mom.waitForTimeout(40000); // Mom's phone does its daily upkeep for the new day
      const fams = await (await fetch(`${FS}/families`, { headers: owner })).json();
      const fp = fams.documents[0].name;
      const r = await fetch(`http://127.0.0.1:8080/v1/${fp}?updateMask.fieldPaths=tzOffsetMin`, {
        method: 'PATCH', headers: owner,
        body: JSON.stringify({ fields: { tzOffsetMin: { integerValue: String(TZ_OFFSET_MIN + SHIFT_DAYS * 1440) } } }),
      });
      if (!r.ok) throw new Error('could not shift the family time zone');
      await mom.waitForTimeout(1500);
    }
    const local = localNow();

    step('mom adds a competition in the School tab');
    await tab(mom, 'School');
    await tap(mom, 'Add competition');
    await type(mom, 'Competition', "Qur'an recitation");
    await tap(mom, 'Save', { exact: true });
    await mom.waitForTimeout(1500);
    await shot(mom, 's1-mom-school.png');
    const momSchool = await screenText(mom);
    console.log('COMPETITION LISTED:', /Qur'an recitation/.test(momSchool) && /practice 0 of 10/.test(momSchool));

    step('homework for today arrives (as a Classroom sync would write it)');
    const families = await (await fetch(`${FS}/families`, { headers: owner })).json();
    const famPath = families.documents[0].name;
    const kidId = (await (await fetch(`${FS}/${famPath.split('/documents/')[1]}/kids`, { headers: owner })).json()).documents[0].name.split('/').pop();
    const hw = {
      id: 's_cw_e2e', kidId, kind: 'homework', title: 'Worksheet p.42', subject: 'Maths', dueYmd: local.ymd,
      fromYmd: local.ymd, toYmd: local.ymd, startMin: Math.max(0, local.minute - 30), endMin: Math.min(1439, local.minute + 60),
      source: 'classroom', link: null, practiceTarget: 0, practiceDone: 0,
    };
    const fields = Object.fromEntries(Object.entries(hw).map(([k, v]) => [k, fsValue(v)]));
    const res = await fetch(`http://127.0.0.1:8080/v1/${famPath}?updateMask.fieldPaths=schoolItems.s_cw_e2e`, {
      method: 'PATCH', headers: owner,
      body: JSON.stringify({ fields: { schoolItems: { mapValue: { fields: { s_cw_e2e: { mapValue: { fields } } } } } } }),
    });
    if (!res.ok) throw new Error(`seeding homework failed: ${res.status} ${await res.text()}`);
    // A teacher's announcement, as the Classroom sync stores it.
    const notice = {
      id: 's_an_e2e', kidId, kind: 'notice', title: 'Bring your science notebook tomorrow.', subject: 'Grade 3',
      dueYmd: local.ymd, fromYmd: null, toYmd: null, startMin: 0, endMin: 0, source: 'classroom', link: null,
      practiceTarget: 0, practiceDone: 0, handedIn: false, details: 'Bring your science notebook tomorrow. We start the plants project.',
    };
    const noticeFields = Object.fromEntries(Object.entries(notice).map(([k, v]) => [k, fsValue(v)]));
    const res2 = await fetch(`http://127.0.0.1:8080/v1/${famPath}?updateMask.fieldPaths=schoolItems.s_an_e2e`, {
      method: 'PATCH', headers: owner,
      body: JSON.stringify({ fields: { schoolItems: { mapValue: { fields: { s_an_e2e: { mapValue: { fields: noticeFields } } } } } } }),
    });
    if (!res2.ok) throw new Error(`seeding announcement failed: ${res2.status}`);
    await kid.waitForTimeout(2500);
    await shot(kid, 's2-kid-school.png');
    const kidText = await fullText(kid);
    console.log('KID SEES HOMEWORK:', /Homework \(Maths\): Worksheet p\.42/.test(kidText));
    console.log('KID SEES COMPETITION:', /Qur'an recitation/.test(kidText));
    console.log('KID SEES ENCOURAGEMENT:', /Come on, Aisha!/.test(kidText));
    if (process.env.DEBUG) { const i = kidText.indexOf('Come on'); console.log('DEBUG', kidText.slice(i, i + 700)); }
    console.log('KID SEES TEACHER ANNOUNCEMENT:', /From your teacher/.test(kidText) && /science notebook/.test(kidText));

    step('aisha ticks the homework');
    await tap(kid, /^Mark done: Homework/);
    await kid.waitForTimeout(2500);
    await shot(kid, 's3-kid-ticked.png');

    step('mom sees it');
    await tab(mom, 'Today');
    await mom.waitForTimeout(1500);
    await shot(mom, 's4-mom-today.png');
    const momText = await fullText(mom);
    const seen = /Worksheet p\.42[^|]*\|?[^|]*ticked by Aisha/.test(momText) || (/Worksheet p\.42/.test(momText) && /ticked by Aisha/.test(momText));
    console.log('MOM SEES HOMEWORK TICK:', seen);
    if (!seen || !/Homework \(Maths\)/.test(kidText) || !/Come on, Aisha!/.test(kidText) || !/From your teacher/.test(kidText)) process.exitCode = 1;
  } catch (e) {
    console.log('FAILED', e.message.split('\n')[0]);
    process.exitCode = 1;
  } finally {
    await b.close();
  }
})();

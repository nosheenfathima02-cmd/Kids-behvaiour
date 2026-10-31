// Two-device test against the Firebase emulator. See README, "Testing".
// Uses the Pacific/Kiritimati time zone so the test runs on a school day
// most of the time; the open task it ticks depends on the hour.
// Mom creates a family, links Aisha's tablet, Aisha ticks a task, Mom sees it, Mom unlinks the tablet.
const { chromium } = require('playwright');
const step = (m) => console.log('STEP', m);
async function newPhone(b, name) {
  const ctx = await b.newContext({ viewport: { width: 420, height: 900 }, timezoneId: 'Pacific/Kiritimati' });
  // Optional: serve the Firebase JS SDK from a local `npm i firebase` when gstatic.com is unreachable.
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
  p.on('pageerror', e => console.log(name, 'ERR', e.message.slice(0, 300)));
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
const tap = async (p, name, opts = {}) => { console.log('  tap', String(name)); const b = p.getByRole('button', { name, ...opts }).first(); await b.waitFor({ state: 'attached', timeout: 8000 }); await reveal(p, b); await b.click({ timeout: 8000, force: true }); await p.waitForTimeout(900); };
const type = async (p, label, text) => { const f = p.locator(`input[aria-label="${label}"], textarea[aria-label="${label}"]`).or(p.getByRole('textbox', { name: label })).first(); await f.waitFor({ state: 'attached', timeout: 8000 }); await reveal(p, f); await f.click({ force: true, timeout: 5000 }); await p.waitForTimeout(400); await p.keyboard.type(text, { delay: 30 }); await p.waitForTimeout(300); };
const shot = (p, f) => p.screenshot({ path: `${__dirname}/screenshots/${f}` });

(async () => {
  await fetch('http://127.0.0.1:9099/emulator/v1/projects/demo-supermom/accounts', { method: 'DELETE' });
  await fetch('http://127.0.0.1:8080/emulator/v1/projects/demo-supermom/databases/(default)/documents', { method: 'DELETE' });
  const b = await chromium.launch();
  try {
    const mom = await newPhone(b, 'MOM');
    step('mom signs up');
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
    await shot(mom, 'e2-setup.png');
    step('mom creates family');
    await type(mom, 'Your name', 'Nousheen');
    await type(mom, 'Phone number', '+974 5512 3456');
    await type(mom, 'PIN (4 to 6 digits)', '1234');
    await type(mom, 'Type the PIN again', '1234');
    await type(mom, 'First name', 'Aisha');
    await tap(mom, 'Start', { exact: true });
    await mom.waitForTimeout(3000);
    await shot(mom, 'e3-mom.png');
    step('mom makes a link code');
    await tap(mom, 'Settings');
    await tap(mom, /linked/);
    await tap(mom, 'Link a device');
    await mom.getByRole('checkbox', { name: /Aisha/ }).first().click({ force: true }); await mom.waitForTimeout(700);
    await tap(mom, 'Show the code');
    await mom.waitForTimeout(1500);
    await shot(mom, 'e4-code.png');
    // The code is drawn on screen; the test reads it from the emulator instead.
    const res = await (await fetch('http://127.0.0.1:8080/v1/projects/demo-supermom/databases/(default)/documents/pairings', { headers: { Authorization: 'Bearer owner' } })).json();
    const code = res.documents[0].name.split('/').pop();
    console.log('CODE', code);

    step('tablet links with the code');
    const kid = await newPhone(b, 'KID');
    await tap(kid, "This is my child's device");
    await type(kid, 'Code', code);
    await type(kid, 'Name for this device', "Aisha's tablet");
    await tap(kid, 'Link this device');
    await kid.waitForTimeout(3500);
    await shot(kid, 'e5-kid.png');
    await shot(mom, 'e6-mom-linked.png');

    // On a weekend no task is open (correct), so move both phones and the
    // family's time zone forward to Monday. Done after linking: link codes
    // are checked against the server's real clock.
    const weekday = new Intl.DateTimeFormat('en-GB', { timeZone: 'Pacific/Kiritimati', weekday: 'short' }).format(new Date());
    const shiftDays = { Sat: 2, Sun: 1 }[weekday] ?? 0;
    if (shiftDays) {
      step(`moving the test clock ${shiftDays} day(s) forward to Monday`);
      for (const pg of [mom, kid]) await pg.clock.setSystemTime(new Date(Date.now() + shiftDays * 86400000));
      await mom.waitForTimeout(40000); // Mom's phone does its daily upkeep for the new day
      const FS = 'http://127.0.0.1:8080/v1/projects/demo-supermom/databases/(default)/documents';
      const fams = await (await fetch(`${FS}/families`, { headers: { Authorization: 'Bearer owner' } })).json();
      const r = await fetch(`http://127.0.0.1:8080/v1/${fams.documents[0].name}?updateMask.fieldPaths=tzOffsetMin`, {
        method: 'PATCH', headers: { Authorization: 'Bearer owner', 'Content-Type': 'application/json' },
        body: JSON.stringify({ fields: { tzOffsetMin: { integerValue: String(14 * 60 + shiftDays * 1440) } } }),
      });
      if (!r.ok) throw new Error('could not shift the family time zone');
      await kid.waitForTimeout(2000);
    }

    step('aisha ticks an open task');
    await tap(kid, /^Mark done/);
    await kid.waitForTimeout(2500);
    await shot(kid, 'e7-kid-ticked.png');

    step('mom sees it');
    await tap(mom, 'Done');
    await mom.goBack().catch(() => {});
    await mom.keyboard.press('Escape');
    await tap(mom, 'Back').catch(() => {});
    await mom.waitForTimeout(1000);
    await shot(mom, 'e8-mom-sees.png');
    const momText = await mom.evaluate(() => document.body.innerText + [...document.querySelectorAll('[aria-label]')].map(e => e.getAttribute('aria-label')).join(' '));
    console.log('MOM SEES TICK:', /ticked by Aisha/.test(momText));

    step('mom removes the tablet');
    await tap(mom, 'Settings');
    await tap(mom, /linked/);
    await tap(mom, 'Remove…');
    await tap(mom, 'Remove', { exact: true });
    await kid.waitForTimeout(3000);
    await shot(kid, 'e9-kid-unlinked.png');
    const kidText = await kid.evaluate(() => [...document.querySelectorAll('flt-semantics')].map(e => e.textContent).join(' '));
    console.log('KID UNLINKED:', /no longer linked/.test(kidText));

    step('mom deletes her account and all family data');
    await tap(mom, 'Back'); // from the devices list to Settings
    await mom.mouse.move(210, 450);
    for (let i = 0; i < 12; i++) { await mom.mouse.wheel(0, 800); await mom.waitForTimeout(200); }
    // Firebase only deletes a sign-in used in the last few minutes; older
    // sign-ins get asked to sign in again. Back to the real clock first.
    await mom.clock.setSystemTime(new Date());
    const accountGone = async () => {
      const users = await (await fetch('http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/projects/demo-supermom/accounts:query', {
        method: 'POST', headers: { Authorization: 'Bearer owner', 'Content-Type': 'application/json' }, body: '{}',
      })).json();
      return !(users.userInfo || []).some((u) => u.email === 'mom@example.com');
    };
    const deleteFromSettings = async () => {
      await tap(mom, 'Delete account and family data');
      await tap(mom, 'Tap again to delete everything');
      for (let i = 0; i < 20 && !(await accountGone()); i++) await mom.waitForTimeout(1000);
    };
    await deleteFromSettings();
    if (!(await accountGone())) {
      step('app asked to sign in again before deleting (safety rule); signing in');
      await tap(mom, "I'm a parent");
      await type(mom, 'Email', 'mom@example.com');
      await type(mom, 'Password', 'bismillah123');
      await tap(mom, 'Sign in', { exact: true });
      await mom.waitForTimeout(3000);
      await tap(mom, 'Settings');
      await mom.mouse.move(210, 450);
      for (let i = 0; i < 12; i++) { await mom.mouse.wheel(0, 800); await mom.waitForTimeout(200); }
      await deleteFromSettings();
    }
    await shot(mom, 'e10-deleted.png');
    const fs = await (await fetch('http://127.0.0.1:8080/v1/projects/demo-supermom/databases/(default)/documents/families', { headers: { Authorization: 'Bearer owner' } })).json();
    const users = await (await fetch('http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/projects/demo-supermom/accounts:query', {
      method: 'POST', headers: { Authorization: 'Bearer owner', 'Content-Type': 'application/json' }, body: '{}',
    })).json();
    const momLeft = (users.userInfo || []).some((u) => u.email === 'mom@example.com');
    const deleted = !(fs.documents && fs.documents.length) && !momLeft;
    console.log('FAMILY AND ACCOUNT DELETED:', deleted);

    if (!/ticked by Aisha/.test(momText) || !/no longer linked/.test(kidText) || !deleted) process.exitCode = 1;
  } catch (e) {
    console.log('FAILED', e.message.split('\n')[0]);
    for (const [i, pg] of b.contexts().flatMap((c) => c.pages()).entries()) await pg.screenshot({ path: `${__dirname}/screenshots/failed-${i}.png` });
    process.exitCode = 1;
  } finally {
    await b.close();
  }
})();

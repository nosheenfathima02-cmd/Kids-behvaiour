// Tries to break the Firestore rules. Run with: npm test (starts the emulator).
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  query,
  where,
  Timestamp,
  deleteDoc,
  deleteField,
  doc,
  getDoc,
  getDocs,
  collection,
  setDoc,
  updateDoc,
  writeBatch,
} from 'firebase/firestore';

const FID = 'fam1';
let env;

// Time windows are built around "now". On a weekend the test family gets a
// time zone 1-2 days ahead, so its local "now" is a Monday (school tasks
// only open on school days).
const utcNow = new Date();
const utcDow = ((utcNow.getUTCDay() + 6) % 7) + 1;
const TZ = utcDow > 5 ? (8 - utcDow) * 1440 : 0;
const now = new Date(utcNow.getTime() + TZ * 60000);
const nowMin = now.getUTCHours() * 60 + now.getUTCMinutes();
const dow = ((now.getUTCDay() + 6) % 7) + 1; // 1 = Monday
const ymd = (d) => String(d.getUTCFullYear() * 10000 + (d.getUTCMonth() + 1) * 100 + d.getUTCDate());
const weekId = ymd(new Date(now.getTime() - (dow - 1) * 86400000));
const lastWeekId = ymd(new Date(now.getTime() - (dow - 1 + 7) * 86400000));
const otherDay = dow === 1 ? 2 : 1;
const allDays = [1, 2, 3, 4, 5, 6, 7];
const closedWindow = nowMin + 100 < 1440 ? [nowMin + 90, nowMin + 100] : [0, nowMin - 120];

const routine = {
  open: { title: 'Homework', startMin: Math.max(0, nowMin - 30), endMin: Math.min(1439, nowMin + 30), weekdays: allDays },
  closed: { title: 'Tidy room', startMin: closedWindow[0], endMin: closedWindow[1], weekdays: allDays },
  notToday: { title: 'Bag', startMin: 0, endMin: 1439, weekdays: [otherDay] },
  yusufOnly: { title: 'Spelling', startMin: 0, endMin: 1439, weekdays: allDays, kidIds: ['yusuf'] },
  asr: { title: 'Pray Asr', prayer: 'asr', weekdays: allDays },
  fajr: { title: 'Pray Fajr', prayer: 'fajr', weekdays: allDays },
};

const tomorrow = ymd(new Date(now.getTime() + 86400000));
const school = (kidId, from, to, start, end) => ({ kidId, kind: 'homework', title: 'Maths p.42', dueYmd: to ?? ymd(now), fromYmd: from, toYmd: to, startMin: start, endMin: end });
const schoolItems = {
  s_today: school('aisha', ymd(now), ymd(now), Math.max(0, nowMin - 30), Math.min(1439, nowMin + 30)),
  s_tomorrow: school('aisha', tomorrow, tomorrow, 0, 1439),
  s_yusuf: school('yusuf', ymd(now), ymd(now), 0, 1439),
  s_closed: school('aisha', ymd(now), ymd(now), closedWindow[0], closedWindow[1]),
  s_reminderOnly: school('aisha', null, null, 0, 1439),
};

const mom = () => env.authenticatedContext('mom', { firebase: { sign_in_provider: 'google.com' } }).firestore();
const stranger = () => env.authenticatedContext('eve', { firebase: { sign_in_provider: 'google.com' } }).firestore();
const device = (uid) => env.authenticatedContext(uid, { firebase: { sign_in_provider: 'anonymous' } }).firestore();
const aishaTablet = () => device('dev-aisha');

const week = (db, kid, w = weekId) => doc(db, `families/${FID}/weeks/${w}_${kid}`);
const tick = (db, taskId, kid = 'aisha', day = dow) =>
  setDoc(week(db, kid), { kidId: kid, weekId, checks: { [`${day}:${taskId}`]: 'kid' }, lastChange: `${day}:${taskId}` }, { merge: true });

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-supermom',
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'), host: '127.0.0.1', port: 8080 },
  });
});

after(async () => env.cleanup());

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const pw = Array(10).fill(0);
    pw[4] = Math.max(0, nowMin - 10); pw[5] = nowMin + 10; // Asr open now
    pw[0] = closedWindow[0]; pw[1] = closedWindow[1]; // Fajr not open
    await setDoc(doc(db, `families/${FID}`), {
      parents: ['mom'], tzOffsetMin: TZ, routine, schoolItems, prayerWindows: { [ymd(now)]: pw }, prayer: { city: 'Dubai' },
    });
    await setDoc(doc(db, `families/${FID}/kids/aisha`), { name: 'Aisha', rewards: [{ name: 'Park', stars: 10 }, { name: 'Dinner', stars: 8 }] });
    await setDoc(doc(db, `families/${FID}/kids/yusuf`), { name: 'Yusuf', rewards: [] });
    await setDoc(doc(db, `families/${FID}/devices/dev-aisha`), { kidIds: ['aisha'], name: "Aisha's tablet", pairCode: 'OLDCODE1', pairedAt: Timestamp.now() });
  });
});

describe('parents', () => {
  test('mom can read and change everything in her family', async () => {
    const db = mom();
    await assertSucceeds(getDoc(doc(db, `families/${FID}`)));
    await assertSucceeds(updateDoc(doc(db, `families/${FID}`), { 'prayer.city': 'Doha' }));
    await assertSucceeds(setDoc(doc(db, `families/${FID}/kids/sara`), { name: 'Sara', rewards: [] }));
    await assertSucceeds(setDoc(week(db, 'aisha'), { kidId: 'aisha', weekId, checks: { [`${otherDay}:closed`]: 'mom' }, timeouts: [{ reason: 'Shouting' }] }));
    await assertSucceeds(getDocs(collection(db, `families/${FID}/devices`)));
  });

  test('another signed-in parent cannot see this family', async () => {
    await assertFails(getDoc(doc(stranger(), `families/${FID}`)));
    await assertFails(getDoc(doc(stranger(), `families/${FID}/kids/aisha`)));
    await assertFails(setDoc(doc(stranger(), `families/${FID}/kids/x`), { name: 'X' }));
  });

  test('a parent cannot remove themselves by accident', async () => {
    await assertFails(updateDoc(doc(mom(), `families/${FID}`), { parents: [] }));
  });

  test('a child device cannot create a family', async () => {
    await assertFails(setDoc(doc(device('anon1'), 'families/new'), { parents: ['anon1'] }));
    await assertSucceeds(setDoc(doc(stranger(), 'families/new'), { parents: ['eve'] }));
  });
});

describe('linking a device', () => {
  const makeCode = async (code, kidIds = ['aisha'], minutes = 10) =>
    assertSucceeds(setDoc(doc(mom(), `pairings/${code}`), {
      familyId: FID, kidIds, createdBy: 'mom', expiresAt: Timestamp.fromMillis(Date.now() + minutes * 60000),
    }));
  const link = (db, uid, code, kidIds = ['aisha'], deleteCode = true) => {
    const b = writeBatch(db);
    b.set(doc(db, `families/${FID}/devices/${uid}`), { kidIds, name: 'Tablet', pairCode: code, pairedAt: Timestamp.now() });
    if (deleteCode) b.delete(doc(db, `pairings/${code}`));
    return b.commit();
  };

  test('a new device links with a valid code, and the code works only once', async () => {
    await makeCode('ABCD2345');
    await assertSucceeds(link(device('new1'), 'new1', 'ABCD2345'));
    await assertSucceeds(getDoc(doc(device('new1'), `families/${FID}`)));
    await assertFails(link(device('new2'), 'new2', 'ABCD2345'));
  });

  test('the code must be deleted in the same write', async () => {
    await makeCode('ABCD2345');
    await assertFails(link(device('new1'), 'new1', 'ABCD2345', ['aisha'], false));
  });

  test('a device cannot ask for more kids than the code allows', async () => {
    await makeCode('ABCD2345');
    await assertFails(link(device('new1'), 'new1', 'ABCD2345', ['aisha', 'yusuf']));
  });

  test('expired or made-up codes do not work', async () => {
    await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'pairings/OLD12345'), {
      familyId: FID, kidIds: ['aisha'], createdBy: 'mom', expiresAt: Timestamp.fromMillis(Date.now() - 1000),
    }));
    await assertFails(link(device('new1'), 'new1', 'OLD12345'));
    await assertFails(link(device('new1'), 'new1', 'MADEUP99'));
  });

  test('codes cannot be listed, and only parents can make them', async () => {
    await makeCode('ABCD2345');
    await assertFails(getDocs(collection(device('x'), 'pairings')));
    await assertFails(setDoc(doc(stranger(), 'pairings/EVIL1234'), {
      familyId: FID, kidIds: ['aisha'], createdBy: 'eve', expiresAt: Timestamp.fromMillis(Date.now() + 60000),
    }));
    await assertFails(setDoc(doc(mom(), 'pairings/LONG1234'), {
      familyId: FID, kidIds: ['aisha'], createdBy: 'mom', expiresAt: Timestamp.fromMillis(Date.now() + 3600000),
    }));
  });

  test('an unlinked device sees nothing', async () => {
    await assertFails(getDoc(doc(device('random'), `families/${FID}`)));
  });

  test('when Mom unlinks a device it loses access', async () => {
    await assertSucceeds(getDoc(doc(aishaTablet(), `families/${FID}`)));
    await assertSucceeds(deleteDoc(doc(mom(), `families/${FID}/devices/dev-aisha`)));
    await assertFails(getDoc(doc(aishaTablet(), `families/${FID}`)));
  });

  test('a device cannot give itself more kids', async () => {
    await assertFails(updateDoc(doc(aishaTablet(), `families/${FID}/devices/dev-aisha`), { kidIds: ['aisha', 'yusuf'] }));
  });
});

describe("a child's device", () => {
  test('sees only its own child', async () => {
    const db = aishaTablet();
    await assertSucceeds(getDoc(doc(db, `families/${FID}/kids/aisha`)));
    await assertFails(getDoc(doc(db, `families/${FID}/kids/yusuf`)));
    await assertFails(getDoc(week(db, 'yusuf')));
    await assertFails(getDocs(collection(db, `families/${FID}/kids`)));
  });

  test('can tick an open task and untick it again', async () => {
    const db = aishaTablet();
    await assertSucceeds(tick(db, 'open'));
    await assertSucceeds(updateDoc(week(db, 'aisha'), { [`checks.${dow}:open`]: deleteField(), lastChange: `${dow}:open` }));
  });

  test('can tick salah only while that prayer is open', async () => {
    await assertSucceeds(tick(aishaTablet(), 'asr'));
    await assertFails(tick(aishaTablet(), 'fajr'));
  });

  test('cannot tick a task whose time is not open', async () => {
    await assertFails(tick(aishaTablet(), 'closed'));
  });

  test('cannot tick another day, or a task not set for that day', async () => {
    await assertFails(tick(aishaTablet(), 'open', 'aisha', otherDay));
    await assertFails(tick(aishaTablet(), 'notToday'));
  });

  test("cannot tick a brother's task or week", async () => {
    await assertFails(tick(aishaTablet(), 'yusufOnly'));
    await assertFails(tick(aishaTablet(), 'open', 'yusuf'));
  });

  test('cannot write "mom" as the one who ticked', async () => {
    await assertFails(setDoc(week(aishaTablet(), 'aisha'), { kidId: 'aisha', weekId, checks: { [`${dow}:open`]: 'mom' }, lastChange: `${dow}:open` }));
  });

  test('cannot tick two tasks at once or sneak in extra fields', async () => {
    await assertFails(setDoc(week(aishaTablet(), 'aisha'), {
      kidId: 'aisha', weekId, checks: { [`${dow}:open`]: 'kid', [`${dow}:asr`]: 'kid' }, lastChange: `${dow}:open`,
    }));
    await assertFails(setDoc(week(aishaTablet(), 'aisha'), {
      kidId: 'aisha', weekId, checks: { [`${dow}:open`]: 'kid' }, lastChange: `${dow}:open`, timeouts: [],
    }));
  });

  test("cannot undo Mom's tick or remove a time-out", async () => {
    await env.withSecurityRulesDisabled((ctx) => setDoc(week(ctx.firestore(), 'aisha'), {
      kidId: 'aisha', weekId, checks: { [`${dow}:open`]: 'mom' }, timeouts: [{ reason: 'Shouting' }],
    }));
    const db = aishaTablet();
    await assertFails(updateDoc(week(db, 'aisha'), { [`checks.${dow}:open`]: deleteField(), lastChange: `${dow}:open` }));
    await assertFails(updateDoc(week(db, 'aisha'), { timeouts: [] }));
  });

  test("cannot change last week's ticks", async () => {
    await env.withSecurityRulesDisabled((ctx) => setDoc(week(ctx.firestore(), 'aisha', lastWeekId), { kidId: 'aisha', weekId: lastWeekId, checks: {} }));
    await assertFails(updateDoc(week(aishaTablet(), 'aisha', lastWeekId), { [`checks.${dow}:open`]: 'kid', lastChange: `${dow}:open` }));
  });

  test('can pick a reward from the list, but not invent one', async () => {
    const db = aishaTablet();
    await assertSucceeds(tick(db, 'open'));
    await assertSucceeds(updateDoc(week(db, 'aisha'), { wishIndex: 1 }));
    await assertFails(updateDoc(week(db, 'aisha'), { wishIndex: 5 }));
  });

  test('cannot change the routine, rewards or settings', async () => {
    const db = aishaTablet();
    await assertFails(updateDoc(doc(db, `families/${FID}`), { 'routine.closed.endMin': 1439 }));
    await assertFails(updateDoc(doc(db, `families/${FID}/kids/aisha`), { rewards: [] }));
  });
});

describe('school items (homework, tests, competitions)', () => {
  test("a child can tick today's homework while it is open", async () => {
    await assertSucceeds(tick(aishaTablet(), 's_today'));
  });

  test("but not tomorrow's, a closed one, a brother's, or a reminder", async () => {
    await assertFails(tick(aishaTablet(), 's_tomorrow'));
    await assertFails(tick(aishaTablet(), 's_closed'));
    await assertFails(tick(aishaTablet(), 's_yusuf'));
    await assertFails(tick(aishaTablet(), 's_reminderOnly'));
    await assertFails(tick(aishaTablet(), 's_madeUp'));
  });

  test('only parents can add or move homework', async () => {
    await assertFails(updateDoc(doc(aishaTablet(), `families/${FID}`), { 'schoolItems.s_tomorrow.fromYmd': ymd(now) }));
    await assertSucceeds(updateDoc(doc(mom(), `families/${FID}`), { 'schoolItems.s_new': school('aisha', tomorrow, tomorrow, 0, 600) }));
  });
});

describe('deleting the account', () => {
  test('mom can delete all family data; a child device and strangers cannot', async () => {
    await assertFails(deleteDoc(doc(aishaTablet(), `families/${FID}`)));
    await assertFails(deleteDoc(doc(stranger(), `families/${FID}/kids/aisha`)));
    const db = mom();
    await assertSucceeds(deleteDoc(doc(db, `families/${FID}/kids/aisha`)));
    await assertSucceeds(deleteDoc(doc(db, `families/${FID}/devices/dev-aisha`)));
    await assertSucceeds(deleteDoc(doc(db, `families/${FID}`)));
  });

  test('mom can find and delete her own link codes, but not list anyone else\'s', async () => {
    await assertSucceeds(setDoc(doc(mom(), 'pairings/MINE2345'), {
      familyId: FID, kidIds: ['aisha'], createdBy: 'mom', expiresAt: Timestamp.fromMillis(Date.now() + 60000),
    }));
    await assertSucceeds(getDocs(query(collection(mom(), 'pairings'), where('createdBy', '==', 'mom'))));
    await assertFails(getDocs(query(collection(stranger(), 'pairings'), where('createdBy', '==', 'mom'))));
    await assertSucceeds(deleteDoc(doc(mom(), 'pairings/MINE2345')));
  });
});

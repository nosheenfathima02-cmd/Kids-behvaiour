// Optional: tells the parents' phones when a child ticks a task.
// Cloud Functions need the Firebase "Blaze" (pay as you go) plan. A family
// app stays far inside the free allowance, but Google asks for a card.
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { onDocumentUpdated, onDocumentCreated } from 'firebase-functions/v2/firestore';

initializeApp();
const db = getFirestore();

async function notifyTick(fid, after, before) {
  const key = after?.lastChange;
  if (!key || after.checks?.[key] !== 'kid' || before?.checks?.[key] === 'kid') return;

  const [family, kid, tokens] = await Promise.all([
    db.doc(`families/${fid}`).get(),
    db.doc(`families/${fid}/kids/${after.kidId}`).get(),
    db.collection(`families/${fid}/parentTokens`).get(),
  ]);
  if (tokens.empty) return;
  const task = family.get(`routine`)?.[key.split(':')[1]];
  const kidName = kid.get('name') ?? 'Your child';

  const res = await getMessaging().sendEachForMulticast({
    tokens: tokens.docs.map((d) => d.id),
    notification: { title: `${kidName} ticked a task`, body: task?.title ?? 'A task was marked done' },
    data: { familyId: fid, kidId: after.kidId },
  });
  // Forget phones that uninstalled the app.
  await Promise.all(res.responses.map((r, i) =>
    !r.success && r.error?.code === 'messaging/registration-token-not-registered'
      ? tokens.docs[i].ref.delete()
      : null));
}

export const tickCreated = onDocumentCreated('families/{fid}/weeks/{wid}', (event) =>
  notifyTick(event.params.fid, event.data?.data(), null));

export const tickUpdated = onDocumentUpdated('families/{fid}/weeks/{wid}', (event) =>
  notifyTick(event.params.fid, event.data?.after.data(), event.data?.before.data()));

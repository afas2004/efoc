// Security rules on the Firebase emulator (spec "Testing layers": player A
// can't read B's hand or hostState, can't write the log, can't forge
// another uid's intent). Run with `npm test` here (starts the emulators).

import { assertFails, assertSucceeds, initializeTestEnvironment, type RulesTestEnvironment } from '@firebase/rules-unit-testing';
import { readFileSync } from 'node:fs';
import { afterAll, beforeAll, beforeEach, describe, it } from 'vitest';
import { get, ref, serverTimestamp, set, update } from 'firebase/database';
import { addDoc, collection, doc, getDoc, setDoc } from 'firebase/firestore';

let env: RulesTestEnvironment;
const R = 'rooms/r1';

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-efoc-games',
    database: { rules: readFileSync(new URL('./database.rules.json', import.meta.url), 'utf8'), host: '127.0.0.1', port: 9000 },
    firestore: { rules: readFileSync(new URL('./firestore.rules', import.meta.url), 'utf8'), host: '127.0.0.1', port: 8080 },
  });
});

afterAll(async () => {
  await env.cleanup();
});

const db = (uid: string | null) => (uid ? env.authenticatedContext(uid) : env.unauthenticatedContext()).database();
const fs = (uid: string) => env.authenticatedContext(uid).firestore();

/** host h opened r1 for group {h, a, b}; a and b joined; o is outside the group. */
async function seedRoom(extra: Record<string, unknown> = {}): Promise<void> {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await set(ref(ctx.database(), R), {
      allowed: { h: true, a: true, b: true },
      meta: { hostUid: 'h', status: 'playing', gameId: 'bigtwo', groupId: 'g1' },
      members: {
        h: { name: 'Host', avatar: '😎', ready: true, joinedAt: 1 },
        a: { name: 'Ann', avatar: '🐇', ready: true, joinedAt: 2 },
        b: { name: 'Ben', avatar: '🦊', ready: true, joinedAt: 3 },
      },
      log: { '000000': { seat: 0, deadline: 1 } },
      hands: { a: { n: 0, cards: ['3d', '4d'] }, b: { n: 0, cards: ['5d'] } },
      hostState: { n: 0, seedBase: 1 },
      snapshot: { n: 0 },
      ...extra,
    });
  });
}

beforeEach(async () => {
  await env.clearDatabase();
});

describe('creating a room', () => {
  it('the host writes meta and the allowed list together', async () => {
    await assertSucceeds(
      update(ref(db('h'), R), { meta: { hostUid: 'h', status: 'waiting' }, allowed: { h: true, a: true } }),
    );
  });
  it('nobody can create a room in someone else\'s name', async () => {
    await assertFails(update(ref(db('a'), R), { meta: { hostUid: 'h', status: 'waiting' }, allowed: { a: true } }));
  });
  it("the allowed list can't be rewritten later, even by the host", async () => {
    await seedRoom();
    await assertFails(set(ref(db('h'), `${R}/allowed`), { h: true, o: true }));
    await assertFails(set(ref(db('o'), `${R}/allowed/o`), true));
  });
  it('signed-out users get nothing', async () => {
    await seedRoom();
    await assertFails(get(ref(db(null), `${R}/meta`)));
  });
});

describe('joining and reading', () => {
  it('group members can read the room to join it; outsiders cannot', async () => {
    await seedRoom();
    await assertSucceeds(get(ref(db('a'), `${R}/meta`)));
    await assertSucceeds(get(ref(db('a'), `${R}/log`)));
    await assertFails(get(ref(db('o'), `${R}/meta`)));
    await assertFails(get(ref(db('o'), `${R}/log`)));
  });
  it('a group member joins as themself only', async () => {
    await seedRoom({ members: {} });
    await assertSucceeds(set(ref(db('a'), `${R}/members/a`), { name: 'Ann', avatar: '🐇', ready: false, joinedAt: 5 }));
    await assertFails(set(ref(db('a'), `${R}/members/b`), { name: 'Fake', avatar: '🦊', ready: false, joinedAt: 5 }));
    await assertFails(set(ref(db('o'), `${R}/members/o`), { name: 'Out', avatar: '👻', ready: false, joinedAt: 5 }));
  });
  it('member records are short and well formed', async () => {
    await seedRoom();
    await assertFails(set(ref(db('a'), `${R}/members/a/name`), 'x'.repeat(41)));
    await assertFails(set(ref(db('a'), `${R}/members/a/ready`), 'yes'));
    await assertSucceeds(set(ref(db('a'), `${R}/members/a/ready`), false));
  });
  it('a spectator takes one of 8 slots, in the same write as their record', async () => {
    await seedRoom({ allowed: { h: true, s0: true, s9: true } });
    await assertSucceeds(update(ref(db('s0'), R), { 'spectatorSlots/0': 's0', 'spectators/s0': { name: 'S0', slot: 0 } }));
    // No slot, someone else's slot, or a slot past 7: refused.
    await assertFails(set(ref(db('s9'), `${R}/spectators/s9`), { name: 'S9', slot: 1 }));
    await assertFails(update(ref(db('s9'), R), { 'spectatorSlots/0': 's9', 'spectators/s9': { name: 'S9', slot: 0 } }));
    await assertFails(update(ref(db('s9'), R), { 'spectatorSlots/8': 's9', 'spectators/s9': { name: 'S9', slot: 8 } }));
  });
  it('spectators: group members only, at most 8', async () => {
    const allowed: Record<string, boolean> = { h: true };
    const slots: Record<string, string> = {};
    for (let i = 0; i < 9; i++) allowed[`s${i}`] = true;
    for (let i = 0; i < 8; i++) slots[i] = `s${i}`;
    await seedRoom({ allowed, spectatorSlots: slots });
    for (let i = 0; i < 9; i++) {
      await assertFails(update(ref(db('s8'), R), { [`spectatorSlots/${i}`]: 's8', 'spectators/s8': { name: 'S8', slot: i } }));
    }
    await assertFails(update(ref(db('o'), R), { 'spectatorSlots/0': 'o', 'spectators/o': { name: 'O', slot: 0 } }));
  });
});

describe('hidden cards', () => {
  it("a player reads their own hand, never another's", async () => {
    await seedRoom();
    await assertSucceeds(get(ref(db('a'), `${R}/hands/a`)));
    await assertFails(get(ref(db('a'), `${R}/hands/b`)));
    await assertFails(get(ref(db('a'), `${R}/hands`)));
  });
  it('only the host reads or writes hostState', async () => {
    await seedRoom();
    await assertFails(get(ref(db('a'), `${R}/hostState`)));
    await assertFails(set(ref(db('a'), `${R}/hostState`), { n: 9 }));
    await assertSucceeds(get(ref(db('h'), `${R}/hostState`)));
  });
  it('only the host deals hands', async () => {
    await seedRoom();
    await assertFails(set(ref(db('a'), `${R}/hands/a/cards`), ['2s', '2h']));
    await assertSucceeds(set(ref(db('h'), `${R}/hands/a/cards`), ['2s']));
  });
});

describe('moves', () => {
  it('a member sends an intent as themself', async () => {
    await seedRoom();
    await assertSucceeds(set(ref(db('a'), `${R}/intents/i1`), { uid: 'a', n: 0, move: { type: 'pass' } }));
  });
  it("nobody can forge another player's intent", async () => {
    await seedRoom();
    await assertFails(set(ref(db('a'), `${R}/intents/i1`), { uid: 'b', n: 0, move: { type: 'pass' } }));
  });
  it("intents can't be edited or read by players, only consumed by the host", async () => {
    await seedRoom({ intents: { i1: { uid: 'a', n: 0, move: { type: 'pass' } } } });
    await assertFails(set(ref(db('a'), `${R}/intents/i1`), { uid: 'a', n: 0, move: { type: 'play' } }));
    await assertFails(get(ref(db('a'), `${R}/intents`)));
    await assertSucceeds(set(ref(db('h'), `${R}/intents/i1`), null));
  });
  it('outsiders and spectators cannot send moves', async () => {
    await seedRoom({ allowed: { h: true, a: true, s: true }, spectators: { s: { name: 'S' } } });
    await assertFails(set(ref(db('s'), `${R}/intents/i2`), { uid: 's', n: 0, move: { type: 'pass' } }));
    await assertFails(set(ref(db('o'), `${R}/intents/i3`), { uid: 'o', n: 0, move: { type: 'pass' } }));
  });
  it('only the host appends to the log, and never rewrites it', async () => {
    await seedRoom();
    await assertFails(set(ref(db('a'), `${R}/log/000001`), { seat: 1 }));
    await assertSucceeds(set(ref(db('h'), `${R}/log/000001`), { seat: 1 }));
    await assertFails(set(ref(db('h'), `${R}/log/000000`), { seat: 2 }));
  });
  it('the host writes a whole turn as one multi-path update', async () => {
    await seedRoom({ intents: { i1: { uid: 'a', n: 0, move: { type: 'pass' } } } });
    await assertSucceeds(
      update(ref(db('h'), R), {
        'log/000001': { seat: 1 },
        hostState: { n: 2 },
        snapshot: { n: 1 },
        'hands/a/n': 1,
        'intents/i1': null,
      }),
    );
  });
});

describe('host migration', () => {
  const presence = (online: boolean, ageMs: number) => ({ h: { online, lastSeen: Date.now() - ageMs } });

  it("can't take over while the host is online", async () => {
    await seedRoom();
    await env.withSecurityRulesDisabled((ctx) => set(ref(ctx.database(), 'presence/r1'), presence(true, 120_000)));
    await assertFails(set(ref(db('a'), `${R}/meta/hostUid`), 'a'));
  });
  it("can't take over until the host has been silent for 60 s", async () => {
    await seedRoom();
    await env.withSecurityRulesDisabled((ctx) => set(ref(ctx.database(), 'presence/r1'), presence(false, 10_000)));
    await assertFails(set(ref(db('a'), `${R}/meta/hostUid`), 'a'));
  });
  it('a seated member takes over an offline, silent host', async () => {
    await seedRoom();
    await env.withSecurityRulesDisabled((ctx) => set(ref(ctx.database(), 'presence/r1'), presence(false, 120_000)));
    await assertSucceeds(set(ref(db('a'), `${R}/meta/hostUid`), 'a'));
  });
  it('taking over changes only hostUid, and only to yourself', async () => {
    await seedRoom();
    await env.withSecurityRulesDisabled((ctx) => set(ref(ctx.database(), 'presence/r1'), presence(false, 120_000)));
    await assertFails(set(ref(db('a'), `${R}/meta/hostUid`), 'b'));
    await assertFails(set(ref(db('a'), `${R}/meta`), { hostUid: 'a', status: 'waiting' }));
    await assertFails(set(ref(db('o'), `${R}/meta/hostUid`), 'o'));
  });
});

describe("a group's open tables", () => {
  const T = 'tables/g1/r1';
  const entry = (hostUid: string) => ({ gameId: 'bigtwo', hostUid, hostName: 'Host', createdAt: serverTimestamp() });
  it('the host lists their own room under its group', async () => {
    await seedRoom();
    await assertSucceeds(set(ref(db('h'), T), entry('h')));
    await assertSucceeds(get(ref(db('a'), 'tables/g1')));
  });
  it("nobody lists a room they don't host, or under another group", async () => {
    await seedRoom();
    await assertFails(set(ref(db('a'), T), entry('a')));
    await assertFails(set(ref(db('a'), T), entry('h')));
    await assertFails(set(ref(db('h'), 'tables/g2/r1'), entry('h')));
    await assertFails(set(ref(db('h'), 'tables/g1/nope'), entry('h')));
  });
  it("a listing can't be edited; players in the room can take it down", async () => {
    await seedRoom();
    await assertSucceeds(set(ref(db('h'), T), entry('h')));
    await assertFails(set(ref(db('h'), `${T}/hostName`), 'Someone else'));
    await assertFails(set(ref(db('o'), T), null));
    await assertSucceeds(set(ref(db('a'), T), null));
  });
  it('signed-out users see no tables', async () => {
    await assertFails(get(ref(db(null), 'tables/g1')));
  });
});

describe('presence', () => {
  it('group members write their own presence only', async () => {
    await seedRoom();
    await assertSucceeds(set(ref(db('a'), 'presence/r1/a'), { online: true, lastSeen: serverTimestamp() }));
    await assertFails(set(ref(db('a'), 'presence/r1/b'), { online: false, lastSeen: 0 }));
    await assertFails(set(ref(db('o'), 'presence/r1/o'), { online: true, lastSeen: 0 }));
  });
});

describe('chat (Phase 4 rules, already in place)', () => {
  it('one message per second, 1–200 characters, as yourself', async () => {
    await seedRoom();
    const msg = (id: string, text: string, uid = 'a') => ({
      [`chat/r1/${id}`]: { uid, text, ts: serverTimestamp() },
      [`chatRate/r1/a`]: serverTimestamp(),
    });
    const rootA = ref(db('a'));
    await assertSucceeds(update(rootA, msg('m1', 'hello')));
    await assertFails(update(rootA, msg('m2', 'too fast')));
    await new Promise((r) => setTimeout(r, 1100));
    await assertFails(update(rootA, msg('m3', 'x'.repeat(201))));
    await assertFails(update(rootA, msg('m4', 'as Ben', 'b')));
    await assertSucceeds(update(rootA, msg('m5', 'later')));
  });
});

describe('Firestore: stats, achievements, reports', () => {
  it('players write only their own stats; any signed-in player reads them', async () => {
    await assertSucceeds(setDoc(doc(fs('a'), 'users/a/stats/bigtwo'), { played: 1 }));
    await assertFails(setDoc(doc(fs('a'), 'users/b/stats/bigtwo'), { played: 99 }));
    await assertSucceeds(getDoc(doc(fs('b'), 'users/a/stats/bigtwo')));
  });
  it('anyone signed in can file a report as themself; nobody reads reports', async () => {
    await assertSucceeds(addDoc(collection(fs('a'), 'reports'), { reporterUid: 'a', text: 'rude' }));
    await assertFails(addDoc(collection(fs('a'), 'reports'), { reporterUid: 'b', text: 'framed' }));
    await assertFails(getDoc(doc(fs('a'), 'reports/x')));
  });
});

// Component-only fixture; the VM and Node permissions are not OS sandboxes.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';
import vm from 'node:vm';

assert.equal(process.argv.length, 3);
const source = await readFile(process.argv[2], 'utf8');
const clock = {
  now: 0,
  timers: new Map(),
  set(fn, delay) {
    assert.equal(typeof fn, 'function');
    assert.ok(Number.isFinite(delay) && delay >= 0);
    const timer = { unref() { return this; } };
    this.timers.set(timer, { at: this.now + delay, fn });
    return timer;
  },
  clear(timer) { this.timers.delete(timer); },
  advance(ms) {
    this.now += ms;
    while (true) {
      const next = [...this.timers].sort((a, b) => a[1].at - b[1].at)[0];
      if (!next || next[1].at > this.now) return;
      this.timers.delete(next[0]);
      next[1].fn();
    }
  },
};
const context = vm.createContext({
  setTimeout: (fn, delay) => clock.set(fn, delay),
  clearTimeout: (timer) => clock.clear(timer),
}, { codeGeneration: { strings: false, wasm: false } });
const mod = new vm.SourceTextModule(stripTypeScriptTypes(source, { mode: 'transform' }), {
  context,
  importModuleDynamically: () => { throw new Error('dynamic imports denied'); },
});
await mod.link((specifier) => { throw new Error(`imports denied: ${specifier}`); });
await mod.evaluate();
const { NotificationGate, deliverNativeNotification } = mod.namespace;
const base = { slug: 'workspace', itemId: 'item-1', issueKey: 'MUL-1', title: 'title', body: 'body' };

class FakeNotification {
  callbacks = new Map();
  showCalls = 0;
  on() {}
  once(event, callback) {
    assert.ok(!this.callbacks.has(event));
    this.callbacks.set(event, callback);
  }
  show() { this.showCalls += 1; }
  emit(event) {
    assert.equal(this.showCalls, 1, 'show must be called exactly once before any event');
    const callback = this.callbacks.get(event);
    assert.equal(typeof callback, 'function', `missing ${event} listener`);
    this.callbacks.delete(event);
    callback();
  }
}
function fixture() {
  const gate = new NotificationGate();
  const created = [];
  const start = (workspaceId, createNotification = () => {
    const notification = new FakeNotification();
    created.push(notification);
    return notification;
  }) => deliverNativeNotification({
    value: { ...base, workspaceId }, gate, confirmed: true, supported: true,
    anyWindowFocused: false, confirmationTimeoutMs: 15, createNotification, onClick() {},
  });
  return { gate, created, start };
}
const result = (value) => ({ shown: value.shown, reason: value.reason });
const clean = () => assert.equal(clock.timers.size, 0, 'fixture must leave no active timers');
test.afterEach(() => {
  const remaining = clock.timers.size;
  clock.timers.clear();
  assert.equal(remaining, 0, 'test left active timers');
});

test('controlled clock fires on deadline and cancels cleared timers', () => {
  const fired = [];
  clock.set(() => fired.push('due'), 5).unref();
  const cancelled = clock.set(() => fired.push('cancelled'), 5);
  clock.clear(cancelled);
  clock.advance(4);
  assert.deepEqual(fired, []);
  clock.advance(1);
  assert.deepEqual(fired, ['due']);
  clean();
});

test('failure releases only its workspace and permits a confirmed retry', async () => {
  const f = fixture();
  const a = f.start('ws-a');
  const b = f.start('ws-b');
  assert.equal(typeof a.then, 'function');
  assert.equal(typeof b.then, 'function');
  const [aHandle, bHandle] = f.created;
  const bToken = f.gate.currentAttempt(base.itemId, 'ws-b');
  assert.notEqual(bToken, undefined);
  aHandle.emit('failed');
  assert.deepEqual(result(await a), { shown: false, reason: 'error' });
  assert.equal(f.gate.currentAttempt(base.itemId, 'ws-a'), undefined);
  assert.equal(f.gate.currentAttempt(base.itemId, 'ws-b'), bToken);
  const duplicate = f.start('ws-b');
  assert.equal(typeof duplicate.then, 'undefined');
  assert.deepEqual(result(duplicate), { shown: false, reason: 'duplicate' });
  const retry = f.start('ws-a');
  assert.equal(f.created.length, 3);
  assert.equal(f.created[2].showCalls, 1);
  f.created[2].emit('show');
  bHandle.emit('show');
  assert.deepEqual(result(await retry), { shown: true, reason: undefined });
  assert.deepEqual(result(await b), { shown: true, reason: undefined });
  clean();
});

test('timeout is pending before deadline and late events cannot release a newer attempt', async () => {
  const f = fixture();
  const a = f.start('ws-a');
  const firstToken = f.gate.currentAttempt(base.itemId, 'ws-a');
  const aHandle = f.created[0];
  let completed = false;
  a.then(() => { completed = true; }, () => { completed = true; });
  clock.advance(14);
  await Promise.resolve();
  assert.equal(completed, false);
  assert.notEqual(firstToken, undefined);
  clock.advance(1);
  assert.deepEqual(result(await a), { shown: false, reason: 'unconfirmed' });
  assert.equal(f.gate.currentAttempt(base.itemId, 'ws-a'), undefined);
  const b = f.start('ws-a');
  const nextToken = f.gate.currentAttempt(base.itemId, 'ws-a');
  assert.notEqual(nextToken, undefined);
  assert.notEqual(firstToken, nextToken);
  aHandle.emit('failed');
  aHandle.emit('show');
  assert.equal(f.gate.currentAttempt(base.itemId, 'ws-a'), nextToken);
  assert.deepEqual(result(await f.start('ws-a')), { shown: false, reason: 'duplicate' });
  assert.equal(f.created.length, 2);
  f.created[1].emit('show');
  assert.deepEqual(result(await b), { shown: true, reason: undefined });
  clean();
});

test('unsettled old attempt cannot release a newer claim on failure', async () => {
  const f = fixture();
  const a = f.start('ws-a');
  const firstToken = f.gate.currentAttempt(base.itemId, 'ws-a');
  assert.notEqual(firstToken, undefined);
  f.gate.release(base.itemId, 'ws-a', firstToken);
  const b = f.start('ws-a');
  const nextToken = f.gate.currentAttempt(base.itemId, 'ws-a');
  assert.notEqual(nextToken, undefined);
  assert.notEqual(firstToken, nextToken);
  f.created[0].emit('failed');
  assert.deepEqual(result(await a), { shown: false, reason: 'error' });
  assert.equal(f.gate.currentAttempt(base.itemId, 'ws-a'), nextToken);
  assert.deepEqual(result(await f.start('ws-a')), { shown: false, reason: 'duplicate' });
  f.created[1].emit('show');
  assert.deepEqual(result(await b), { shown: true, reason: undefined });
  clean();
});

test('synchronous factory and show failures release the claim for retry', async () => {
  for (const failAt of ['factory', 'show']) {
    const f = fixture();
    let injected = 0;
    const failed = f.start('ws-a', () => {
      if (failAt === 'factory') { injected += 1; throw new Error('injected factory failure'); }
      const notification = new FakeNotification();
      notification.show = () => { injected += 1; throw new Error('injected show failure'); };
      return notification;
    });
    assert.equal(typeof failed.then, failAt === 'factory' ? 'undefined' : 'function');
    assert.deepEqual(result(await failed), { shown: false, reason: 'error' });
    assert.equal(injected, 1);
    assert.equal(f.gate.currentAttempt(base.itemId, 'ws-a'), undefined);
    const retry = f.start('ws-a');
    assert.equal(f.created.length, 1);
    f.created[0].emit('show');
    assert.deepEqual(result(await retry), { shown: true, reason: undefined });
    clean();
  }
});

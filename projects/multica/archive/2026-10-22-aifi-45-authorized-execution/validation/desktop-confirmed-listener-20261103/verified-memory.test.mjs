// Component-only fixture; the VM and Node permissions are not OS sandboxes.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';
import vm from 'node:vm';

assert.equal(process.argv.length, 4);
const [, , sourcePath, mode] = process.argv;
assert.ok(mode === 'old' || mode === 'current');
const hash = (value) => createHash('sha256').update(value).digest('hex');
let source = await readFile(sourcePath, 'utf8');
assert.equal(hash(source), '7a33a3f876c29b643afa8a99e981f7fa3016122bf72502542a63ebe6eb596a23');
const current = `    timer.unref?.();
    try {
      notification.once("show", () => finish({ shown: true }));
      notification.once("failed", () => {
        if (settled) return;
        releaseAttempt();
        finish({ shown: false, reason: "error" });
      });
      notification.show();`;
const old = `    timer.unref?.();
    notification.once("show", () => finish({ shown: true }));
    notification.once("failed", () => {
      if (settled) return;
      releaseAttempt();
      finish({ shown: false, reason: "error" });
    });
    try {
      notification.show();`;
const eol = source.includes('\r\n') ? '\r\n' : '\n';
const currentBytes = current.replaceAll('\n', eol);
const oldBytes = old.replaceAll('\n', eol);
assert.equal(source.split(currentBytes).length, 2, 'expected exactly one current block');
if (mode === 'old') {
  source = source.replace(currentBytes, oldBytes);
  assert.equal(hash(source), '0d9db959c83fb63a7be41f7cda39049fdd51201e7198ee1f354877b712372965');
}
const clock = {
  timers: new Set(),
  created: 0,
  cancelled: 0,
  set() {
    const timer = { unref() {} };
    this.created += 1;
    this.timers.add(timer);
    return timer;
  },
  clear(timer) {
    if (this.timers.delete(timer)) this.cancelled += 1;
  },
};
const context = vm.createContext({
  setTimeout: () => clock.set(),
  clearTimeout: (timer) => clock.clear(timer),
}, { codeGeneration: { strings: false, wasm: false } });
const mod = new vm.SourceTextModule(stripTypeScriptTypes(source, { mode: 'transform' }), {
  context,
  importModuleDynamically: () => { throw new Error('dynamic imports denied'); },
});
await mod.link(() => { throw new Error('imports denied'); });
await mod.evaluate();
const { NotificationGate, deliverNativeNotification } = mod.namespace;
const value = { slug: 'workspace', workspaceId: 'ws-a', itemId: 'item-1', issueKey: 'MUL-1', title: 'title', body: 'body' };

test.afterEach(() => {
  const remaining = clock.timers.size;
  clock.timers.clear();
  assert.equal(remaining, 0, 'test left active timers');
});

for (const failingEvent of ['show', 'failed']) {
  test(`confirmed ${failingEvent} registration failure releases only its attempt`, async () => {
    const gate = new NotificationGate();
    const beforeCreated = clock.created;
    const beforeCancelled = clock.cancelled;
    let registrations = 0;
    let showCalls = 0;
    let oldShow;
    const common = { value, gate, confirmed: true, supported: true, anyWindowFocused: false, onClick() {} };
    const failed = deliverNativeNotification({
      ...common,
      createNotification: () => ({
        on() {},
        once(event, callback) {
          registrations += 1;
          if (event === failingEvent) throw new Error('injected registration failure');
          if (event === 'show') oldShow = callback;
        },
        show() { showCalls += 1; },
      }),
    });
    assert.equal(typeof failed.then, 'function');
    let outcome;
    try {
      const result = await failed;
      outcome = { shown: result.shown, reason: result.reason };
    } catch (error) {
      outcome = { rejected: error.message };
    }
    const tokenAfterFailure = gate.currentAttempt(value.itemId, value.workspaceId);
    const created = clock.created - beforeCreated;
    const cancelled = clock.cancelled - beforeCancelled;
    const pending = clock.timers.size;
    clock.timers.clear();
    assert.equal(registrations, failingEvent === 'show' ? 1 : 2);
    assert.equal(showCalls, 0);
    assert.deepEqual(outcome, { shown: false, reason: 'error' });
    assert.equal(tokenAfterFailure, undefined);
    assert.equal(created, 1);
    assert.equal(cancelled, 1);
    assert.equal(pending, 0);

    let retryShow;
    const retry = deliverNativeNotification({
      ...common,
      createNotification: () => ({
        on() {},
        once(event, callback) { if (event === 'show') retryShow = callback; },
        show() { showCalls += 1; },
      }),
    });
    assert.equal(typeof retry.then, 'function');
    const retryToken = gate.currentAttempt(value.itemId, value.workspaceId);
    assert.notEqual(retryToken, undefined);
    assert.equal(showCalls, 1);
    if (failingEvent === 'failed') {
      assert.equal(typeof oldShow, 'function');
      oldShow();
      assert.equal(gate.currentAttempt(value.itemId, value.workspaceId), retryToken);
      const duplicate = deliverNativeNotification({ ...common, createNotification() { throw new Error('must not create'); } });
      assert.deepEqual({ shown: duplicate.shown, reason: duplicate.reason }, { shown: false, reason: 'duplicate' });
    }
    retryShow();
    const result = await retry;
    assert.equal(result.shown, true);
    assert.equal(clock.timers.size, 0);
  });
}

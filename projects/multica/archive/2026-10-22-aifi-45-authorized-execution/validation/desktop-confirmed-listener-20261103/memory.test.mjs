// Component-only fixture; the VM and Node permissions are not OS sandboxes.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';
import vm from 'node:vm';

assert.equal(process.argv.length, 3);
const source = await readFile(process.argv[2], 'utf8');
const timers = new Set();
const context = vm.createContext({
  setTimeout: () => {
    const timer = { unref() {} };
    timers.add(timer);
    return timer;
  },
  clearTimeout: (timer) => timers.delete(timer),
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
  const remaining = timers.size;
  timers.clear();
  assert.equal(remaining, 0, 'test left active timers');
});

for (const failingEvent of ['show', 'failed']) {
  test(`confirmed ${failingEvent} listener registration failure releases the claim`, async () => {
    const gate = new NotificationGate();
    let registrations = 0;
    let showCalls = 0;
    const common = { value, gate, confirmed: true, supported: true, anyWindowFocused: false, onClick() {} };
    const failing = deliverNativeNotification({
      ...common,
      createNotification: () => ({
        on() {},
        once(event) {
          registrations += 1;
          if (event === failingEvent) throw new Error('injected registration failure');
        },
        show() { showCalls += 1; },
      }),
    });
    assert.equal(typeof failing.then, 'function');
    let observed;
    try {
      const result = await failing;
      observed = { shown: result.shown, reason: result.reason };
    } catch {
      observed = 'promise-rejected';
    }
    const tokenAfterFailure = gate.currentAttempt(value.itemId, value.workspaceId);
    const outstandingTimers = timers.size;
    timers.clear();
    assert.equal(registrations, failingEvent === 'show' ? 1 : 2);
    assert.equal(showCalls, 0);
    assert.deepEqual(observed, { shown: false, reason: 'error' });
    assert.equal(tokenAfterFailure, undefined);
    assert.equal(outstandingTimers, 0);

    let onShow;
    const retry = deliverNativeNotification({
      ...common,
      createNotification: () => ({
        on() {},
        once(event, callback) { if (event === 'show') onShow = callback; },
        show() { showCalls += 1; onShow(); },
      }),
    });
    assert.equal(typeof retry.then, 'function');
    const result = await retry;
    assert.equal(result.shown, true);
    assert.equal(showCalls, 1);
    assert.equal(timers.size, 0);
  });
}

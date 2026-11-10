// Component-only preflight: the Node permission model and VM are not OS sandboxes.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';
import vm from 'node:vm';

assert.equal(process.argv.length, 3, 'supply exactly one authorized source path');
const source = await readFile(process.argv[2], 'utf8');
const context = vm.createContext({ setTimeout, clearTimeout }, { codeGeneration: { strings: false, wasm: false } });
const mod = new vm.SourceTextModule(stripTypeScriptTypes(source, { mode: 'transform' }), {
  context,
  importModuleDynamically: () => { throw new Error('dynamic imports denied'); },
});
await mod.link((specifier) => { throw new Error(`imports denied: ${specifier}`); });
await mod.evaluate();
const { NotificationGate, deliverNativeNotification } = mod.namespace;
const payload = { slug: 'workspace', itemId: 'item-1', issueKey: 'MUL-1', title: 'title', body: 'body' };

function fixture(value, confirmed = true) {
  const gate = new NotificationGate();
  let created = 0;
  let shown = 0;
  const options = {
    value, confirmed, gate, supported: true, anyWindowFocused: false,
    createNotification() {
      created += 1;
      let onShow;
      return {
        on() {},
        once(event, callback) { if (event === 'show') onShow = callback; },
        show() { shown += 1; onShow?.(); },
      };
    },
    onClick() {},
  };
  return { options, gate, counts: () => ({ created, shown }) };
}

function result(value) { return { shown: value.shown, reason: value.reason }; }

test('confirmed missing workspace is invalid and has no gate or native side effects', async () => {
  const f = fixture(payload);
  let gateCalls = 0;
  const shouldShow = f.gate.shouldShow.bind(f.gate);
  f.gate.shouldShow = (...args) => { gateCalls += 1; return shouldShow(...args); };
  const r = await deliverNativeNotification(f.options);
  assert.deepEqual({ result: result(r), counts: f.counts(), gateCalls, attempt: f.gate.currentAttempt(payload.itemId) },
    { result: { shown: false, reason: 'invalid-payload' }, counts: { created: 0, shown: 0 }, gateCalls: 0, attempt: undefined });
  const valid = await deliverNativeNotification({ ...f.options, value: { ...payload, workspaceId: 'ws-a' } });
  assert.deepEqual({ result: result(valid), counts: f.counts() },
    { result: { shown: true, reason: undefined }, counts: { created: 1, shown: 1 } });
});

test('legacy notification still accepts an unscoped payload synchronously', () => {
  const f = fixture(payload, false);
  const r = deliverNativeNotification(f.options);
  assert.equal(typeof r.then, 'undefined');
  assert.deepEqual({ result: result(r), counts: f.counts(), claimed: f.gate.currentAttempt(payload.itemId) !== undefined },
    { result: { shown: true, reason: undefined }, counts: { created: 1, shown: 1 }, claimed: true });
});

test('missing confirmed scope is invalid even when unsupported or focused', async () => {
  for (const overrides of [{ supported: false }, { anyWindowFocused: true }]) {
    const f = fixture(payload);
    const r = await deliverNativeNotification({ ...f.options, ...overrides });
    assert.deepEqual({ result: result(r), counts: f.counts(), attempt: f.gate.currentAttempt(payload.itemId) },
      { result: { shown: false, reason: 'invalid-payload' }, counts: { created: 0, shown: 0 }, attempt: undefined });
  }
});

test('invalid workspace values remain rejected for both delivery modes', async () => {
  for (const workspaceId of [null, 123, '', '   ', 'x'.repeat(257)]) {
    for (const confirmed of [true, false]) {
      const f = fixture({ ...payload, workspaceId }, confirmed);
      const r = await deliverNativeNotification(f.options);
      assert.deepEqual({ result: result(r), counts: f.counts() },
        { result: { shown: false, reason: 'invalid-payload' }, counts: { created: 0, shown: 0 } });
    }
  }
});

test('focused confirmed does not claim while focused legacy does', async () => {
  const confirmed = fixture({ ...payload, workspaceId: 'ws-a' });
  const cr = await deliverNativeNotification({ ...confirmed.options, anyWindowFocused: true });
  const legacy = fixture(payload, false);
  const lr = deliverNativeNotification({ ...legacy.options, anyWindowFocused: true });
  assert.deepEqual({ confirmed: result(cr), confirmedClaim: confirmed.gate.currentAttempt(payload.itemId, 'ws-a'),
    legacy: result(lr), legacyClaim: legacy.gate.currentAttempt(payload.itemId) !== undefined },
  { confirmed: { shown: false, reason: 'focused' }, confirmedClaim: undefined,
    legacy: { shown: false, reason: 'focused' }, legacyClaim: true });
});

test('confirmed workspace identities remain separate and retry dedupe stays scoped', async () => {
  const f = fixture({ ...payload, workspaceId: 'ws-a' });
  const first = await deliverNativeNotification(f.options);
  const second = await deliverNativeNotification({ ...f.options, value: { ...payload, workspaceId: 'ws-b' } });
  const duplicate = await deliverNativeNotification(f.options);
  assert.deepEqual({ first: result(first), second: result(second), duplicate: result(duplicate), counts: f.counts() },
    { first: { shown: true, reason: undefined }, second: { shown: true, reason: undefined },
      duplicate: { shown: false, reason: 'duplicate' }, counts: { created: 2, shown: 2 } });
});

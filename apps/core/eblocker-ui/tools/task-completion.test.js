'use strict';
const assert = require('assert');
const { completeTasks, karmaError } = require('./task-completion');
let calls = [];
let complete = completeTasks(2, error => calls.push(error));
complete(); assert.strictEqual(calls.length, 0);
complete(); complete(); assert.deepStrictEqual(calls, [undefined]);
calls = [];
const failure = new Error('template generation failed');
complete = completeTasks(3, error => calls.push(error));
complete(failure); complete(); complete(new Error('later'));
assert.deepStrictEqual(calls, [failure]);
assert.throws(() => completeTasks(-1, () => {}), RangeError);
assert.throws(() => completeTasks(1.5, () => {}), RangeError);
assert.strictEqual(karmaError(0), undefined);
for (const code of [1, 2, null, undefined]) {
    assert(karmaError(code) instanceof Error);
}
let emptyCalls = 0;
completeTasks(0, error => { assert.strictEqual(error, undefined); emptyCalls++; });
setImmediate(() => {
    assert.strictEqual(emptyCalls, 1);
    console.log('Build completion regressions passed');
});

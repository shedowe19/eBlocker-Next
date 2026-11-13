'use strict';

// Complete a parallel build task exactly once; never convert a child error into success.
function completeTasks(total, done) {
    if (!Number.isInteger(total) || total < 0) {
        throw new RangeError('Task count must be a non-negative integer');
    }
    let remaining = total;
    let settled = false;
    const complete = function(error) {
        if (settled) {
            return;
        }
        if (error || --remaining <= 0) {
            settled = true;
            done(error);
        }
    };
    if (total === 0) {
        process.nextTick(complete);
    }
    return complete;
}

function karmaError(exitCode) {
    return exitCode === 0 ? undefined : new Error('Karma exited with code ' + exitCode);
}

module.exports = { completeTasks, karmaError };

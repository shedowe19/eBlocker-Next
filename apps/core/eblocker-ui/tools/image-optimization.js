'use strict';

const { execFile } = require('child_process');
const fs = require('fs').promises;
const os = require('os');
const path = require('path');
const { promisify } = require('util');

const execute = promisify(execFile);
const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
const endChunk = Buffer.from([0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130]);

function dimensions(buffer) {
    if (buffer.length < 45 || !buffer.subarray(0, 8).equals(signature) ||
        buffer.readUInt32BE(8) !== 13 || buffer.toString('ascii', 12, 16) !== 'IHDR' ||
        !buffer.subarray(-12).equals(endChunk)) {
        throw new Error('OptiPNG requires a complete PNG image');
    }
    return [buffer.readUInt32BE(16), buffer.readUInt32BE(20)];
}

function systemOptipng({ optimizationLevel = 3, binary = 'optipng', tempRoot = os.tmpdir() } = {}) {
    return async buffer => {
        if (!Buffer.isBuffer(buffer)) {
            throw new TypeError('Expected a PNG buffer');
        }
        if (!buffer.subarray(0, 8).equals(signature)) {
            return buffer;
        }
        const originalDimensions = dimensions(buffer);
        const directory = await fs.mkdtemp(path.join(tempRoot, 'eblocker-optipng-'));
        try {
            const input = path.join(directory, 'input.png');
            const output = path.join(directory, 'output.png');
            await fs.writeFile(input, buffer);
            await execute(binary, [
                '-strip', 'all', '-clobber', '-o', String(optimizationLevel),
                '-out', output, '-fix', input
            ], { timeout: 120000, maxBuffer: 4 * 1024 * 1024 });
            const optimized = await fs.readFile(output);
            const optimizedDimensions = dimensions(optimized);
            if (originalDimensions.some((value, index) => value !== optimizedDimensions[index])) {
                throw new Error('OptiPNG changed PNG dimensions');
            }
            // A completed, validated optimization must never increase the asset size.
            return optimized.length < buffer.length ? optimized : buffer;
        } finally {
            await fs.rm(directory, { recursive: true, force: true });
        }
    };
}

function pngOptimizer(factory, options) {
    const plugin = typeof factory === 'function' ? factory(options) : undefined;
    // gulp-imagemin silently returns undefined when its optional npm plugin is absent.
    return typeof plugin === 'function' ? plugin : systemOptipng(options);
}

module.exports = { pngOptimizer, systemOptipng };

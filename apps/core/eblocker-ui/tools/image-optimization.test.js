'use strict';

const assert = require('assert');
const fs = require('fs').promises;
const os = require('os');
const path = require('path');
const zlib = require('zlib');
const { pngOptimizer, systemOptipng } = require('./image-optimization');

function crc32(bytes) {
    let crc = 0xFFFFFFFF;
    for (const byte of bytes) {
        crc ^= byte;
        for (let bit = 0; bit < 8; bit++) {
            crc = (crc >>> 1) ^ ((crc & 1) ? 0xEDB88320 : 0);
        }
    }
    return (crc ^ 0xFFFFFFFF) >>> 0;
}

function chunk(type, data) {
    const body = Buffer.concat([Buffer.from(type), data]);
    const length = Buffer.alloc(4);
    const checksum = Buffer.alloc(4);
    length.writeUInt32BE(data.length);
    checksum.writeUInt32BE(crc32(body));
    return Buffer.concat([length, body, checksum]);
}

function fixture() {
    // More than 256 distinct, non-gray, non-opaque colors prevent palette, depth
    // and color-type reduction. PNG row filters may still change and are decoded below.
    const width = 257;
    const pixels = Buffer.alloc(width * 4);
    for (let x = 0; x < width; x++) {
        pixels[x * 4] = x & 255;
        pixels[x * 4 + 1] = (x * 73 + 31 + Math.floor(x / 256)) & 255;
        pixels[x * 4 + 2] = (x * 29 + 127) & 255;
        pixels[x * 4 + 3] = 1 + (x * 17) % 254;
    }
    const header = Buffer.alloc(13);
    header.writeUInt32BE(width, 0);
    header.writeUInt32BE(1, 4);
    header[8] = 8;
    header[9] = 6;
    return { width, pixels, png: Buffer.concat([
        Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
        chunk('IHDR', header),
        chunk('tEXt', Buffer.from('Comment\0' + 'removable metadata '.repeat(256))),
        chunk('IDAT', zlib.deflateSync(Buffer.concat([Buffer.from([0]), pixels]), { level: 0 })),
        chunk('IEND', Buffer.alloc(0))
    ]) };
}

function rgbaPixels(png, width) {
    assert(png.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])));
    const data = [];
    let ended = false;
    for (let offset = 8; offset < png.length;) {
        const length = png.readUInt32BE(offset);
        const type = png.toString('ascii', offset + 4, offset + 8);
        const body = png.subarray(offset + 4, offset + 8 + length);
        assert.strictEqual(crc32(body), png.readUInt32BE(offset + 8 + length));
        if (type === 'IHDR') {
            assert.strictEqual(png.readUInt32BE(offset + 8), width);
            assert.strictEqual(png.readUInt32BE(offset + 12), 1);
            assert.strictEqual(png[offset + 16], 8);
            assert.strictEqual(png[offset + 17], 6);
        }
        if (type === 'IDAT') { data.push(png.subarray(offset + 8, offset + 8 + length)); }
        offset += length + 12;
        if (type === 'IEND') { assert.strictEqual(offset, png.length); ended = true; }
    }
    assert(ended);
    const row = zlib.inflateSync(Buffer.concat(data));
    assert.strictEqual(row.length, width * 4 + 1);
    const pixels = Buffer.alloc(width * 4);
    // There is one row, so Up and upper-left are zero for all filter types.
    for (let x = 0; x < pixels.length; x++) {
        const left = x >= 4 ? pixels[x - 4] : 0;
        const predictors = [0, left, 0, Math.floor(left / 2), left];
        assert(row[0] <= 4);
        pixels[x] = (row[x + 1] + predictors[row[0]]) & 255;
    }
    return pixels;
}

async function main() {
    const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'eblocker-images-test-'));
    const tools = await fs.mkdtemp(path.join(os.tmpdir(), 'eblocker-image-tools-test-'));
    try {
        const original = fixture();
        assert.deepStrictEqual(rgbaPixels(original.png, original.width), original.pixels);
        const existing = buffer => Promise.resolve(buffer);
        assert.strictEqual(pngOptimizer(() => existing, {}), existing);
        const optimize = pngOptimizer(() => undefined, { optimizationLevel: 5, tempRoot: directory });
        const optimized = await optimize(original.png);
        assert(optimized.length < original.png.length, 'Native OptiPNG must actually optimize the PNG');
        assert.deepStrictEqual(rgbaPixels(optimized, original.width), original.pixels);
        assert.strictEqual(await optimize(optimized), optimized, 'An already optimal PNG must retain its original buffer');
        const larger = Buffer.concat([
            optimized.subarray(0, -12),
            chunk('tEXt', Buffer.from('Comment\0' + 'larger valid output '.repeat(256))),
            optimized.subarray(-12)
        ]);
        assert.deepStrictEqual(rgbaPixels(larger, original.width), original.pixels);
        const largerFile = path.join(tools, 'larger.png');
        await fs.writeFile(largerFile, larger);
        const largerTool = path.join(tools, 'larger-output');
        const invalidTool = path.join(tools, 'invalid-output');
        const outputArgument = "process.argv[process.argv.indexOf('-out') + 1]";
        await fs.writeFile(largerTool, '#!' + process.execPath + '\n' +
            "require('fs').copyFileSync(" + JSON.stringify(largerFile) + ', ' + outputArgument + ');\n', { mode: 0o755 });
        await fs.writeFile(invalidTool, '#!' + process.execPath + '\n' +
            "require('fs').writeFileSync(" + outputArgument + ", 'invalid PNG');\n", { mode: 0o755 });
        assert.strictEqual(await systemOptipng({ binary: largerTool, tempRoot: directory })(optimized), optimized,
            'A larger but valid tool result must retain the original PNG');
        await assert.rejects(systemOptipng({ binary: invalidTool, tempRoot: directory })(original.png), /complete PNG/);
        const svg = Buffer.from('<svg/>');
        assert.strictEqual(await optimize(svg), svg);
        await assert.rejects(optimize('not a buffer'), TypeError);
        await assert.rejects(systemOptipng({ binary: path.join(directory, 'missing-optipng'), tempRoot: directory })(original.png),
            error => error.code === 'ENOENT');
        await assert.rejects(systemOptipng({ binary: process.execPath, tempRoot: directory })(original.png),
            error => typeof error.code === 'number' && error.code !== 0);
        assert.deepStrictEqual(await fs.readdir(directory), [], 'Temporary image files must be removed after success and failure');
        console.log('Image optimization regressions passed: native PNG compression, pixels, fallback and failures');
    } finally {
        await fs.rm(directory, { recursive: true, force: true });
        await fs.rm(tools, { recursive: true, force: true });
    }
}

main().catch(error => { console.error(error); process.exitCode = 1; });

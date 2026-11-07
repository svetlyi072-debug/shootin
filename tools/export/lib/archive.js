'use strict';
// Мини-библиотека архивов без внешних зависимостей. Нужна, чтобы собирать пакеты для Linux и macOS
// на Windows с правильными Unix-правами (755 у скриптов и программы): обычные средства Windows их не умеют.
//   zipWrite(entries) / zipRead(buf)  — zip (readers копируют готовые записи как есть, без перепаковки)
//   tarGz(entries)                     — .tar.gz (права сохраняются при распаковке любым архиватором)
// entries: { name, data?:Buffer, raw?:{...из zipRead}, mode:0o755, dir?:true }
const zlib = require('zlib');

const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();

function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function dosTime(date) {
  const time = (date.getHours() << 11) | (date.getMinutes() << 5) | (date.getSeconds() >> 1);
  const day = ((date.getFullYear() - 1980) << 9) | ((date.getMonth() + 1) << 5) | date.getDate();
  return { time, day };
}

// --- ZIP ------------------------------------------------------------------------------------

function zipWrite(entries, { level = 9, date = new Date() } = {}) {
  const parts = [];
  const central = [];
  let offset = 0;
  const stamp = dosTime(date);
  for (const entry of entries) {
    const isDir = !!entry.dir || entry.name.endsWith('/');
    const name = isDir && !entry.name.endsWith('/') ? entry.name + '/' : entry.name;
    const nameBuf = Buffer.from(name, 'utf8');
    const ascii = /^[\x20-\x7e]*$/.test(name);
    let method, crc, comp, size, time = stamp.time, day = stamp.day;
    if (entry.raw) {
      ({ method, crc, comp, size } = entry.raw);
      comp = entry.raw.data;
      time = entry.raw.time;
      day = entry.raw.day;
    } else {
      const data = isDir ? Buffer.alloc(0) : entry.data;
      crc = crc32(data);
      size = data.length;
      if (data.length > 0) {
        const deflated = zlib.deflateRawSync(data, { level });
        if (deflated.length < data.length) { method = 8; comp = deflated; } else { method = 0; comp = data; }
      } else { method = 0; comp = data; }
    }
    const flags = ascii ? 0 : 0x0800;
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(20, 4);
    local.writeUInt16LE(flags, 6);
    local.writeUInt16LE(method, 8);
    local.writeUInt16LE(time, 10);
    local.writeUInt16LE(day, 12);
    local.writeUInt32LE(crc, 14);
    local.writeUInt32LE(comp.length, 18);
    local.writeUInt32LE(size, 22);
    local.writeUInt16LE(nameBuf.length, 26);
    local.writeUInt16LE(0, 28);
    parts.push(local, nameBuf, comp);
    const mode = entry.mode !== undefined ? entry.mode : (isDir ? 0o755 : 0o644);
    const attrs = (((isDir ? 0o040000 : 0o100000) | mode) << 16) >>> 0 | (isDir ? 0x10 : 0);
    const cen = Buffer.alloc(46);
    cen.writeUInt32LE(0x02014b50, 0);
    cen.writeUInt16LE((3 << 8) | 20, 4);  // создано в Unix
    cen.writeUInt16LE(20, 6);
    cen.writeUInt16LE(flags, 8);
    cen.writeUInt16LE(method, 10);
    cen.writeUInt16LE(time, 12);
    cen.writeUInt16LE(day, 14);
    cen.writeUInt32LE(crc, 16);
    cen.writeUInt32LE(comp.length, 20);
    cen.writeUInt32LE(size, 24);
    cen.writeUInt16LE(nameBuf.length, 28);
    cen.writeUInt16LE(0, 30);
    cen.writeUInt16LE(0, 32);
    cen.writeUInt16LE(0, 34);
    cen.writeUInt16LE(0, 36);
    cen.writeUInt32LE(attrs >>> 0, 38);
    cen.writeUInt32LE(offset, 42);
    central.push(cen, nameBuf);
    offset += local.length + nameBuf.length + comp.length;
  }
  const centralBuf = Buffer.concat(central);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(entries.length, 8);
  end.writeUInt16LE(entries.length, 10);
  end.writeUInt32LE(centralBuf.length, 12);
  end.writeUInt32LE(offset, 16);
  return Buffer.concat([...parts, centralBuf, end]);
}

function zipRead(buf) {
  let eocd = -1;
  for (let i = buf.length - 22; i >= Math.max(0, buf.length - 65557); i--) {
    if (buf.readUInt32LE(i) === 0x06054b50) { eocd = i; break; }
  }
  if (eocd < 0) throw new Error('не zip: нет конца каталога');
  const count = buf.readUInt16LE(eocd + 10);
  let pos = buf.readUInt32LE(eocd + 16);
  const entries = [];
  for (let n = 0; n < count; n++) {
    if (buf.readUInt32LE(pos) !== 0x02014b50) throw new Error('повреждён каталог zip');
    const madeBy = buf.readUInt16LE(pos + 4);
    const method = buf.readUInt16LE(pos + 10);
    const time = buf.readUInt16LE(pos + 12);
    const day = buf.readUInt16LE(pos + 14);
    const crc = buf.readUInt32LE(pos + 16);
    const comp = buf.readUInt32LE(pos + 20);
    const size = buf.readUInt32LE(pos + 24);
    const nameLen = buf.readUInt16LE(pos + 28);
    const extraLen = buf.readUInt16LE(pos + 30);
    const commentLen = buf.readUInt16LE(pos + 32);
    const attrs = buf.readUInt32LE(pos + 38);
    const localOffset = buf.readUInt32LE(pos + 42);
    const name = buf.toString('utf8', pos + 46, pos + 46 + nameLen);
    const localNameLen = buf.readUInt16LE(localOffset + 26);
    const localExtraLen = buf.readUInt16LE(localOffset + 28);
    const dataStart = localOffset + 30 + localNameLen + localExtraLen;
    const isDir = name.endsWith('/');
    const unixMode = (madeBy >> 8) === 3 ? (attrs >>> 16) & 0o7777 : (isDir ? 0o755 : 0o644);
    entries.push({
      name, dir: isDir, mode: unixMode, madeBy,
      raw: { method, crc, comp, size, time, day, data: buf.subarray(dataStart, dataStart + comp) },
    });
    pos += 46 + nameLen + extraLen + commentLen;
  }
  return entries;
}

function zipExtract(entry) {
  if (entry.raw.method === 0) return Buffer.from(entry.raw.data);
  if (entry.raw.method === 8) return zlib.inflateRawSync(entry.raw.data);
  throw new Error('неизвестный метод сжатия ' + entry.raw.method);
}

// --- TAR.GZ ---------------------------------------------------------------------------------

function octal(value, length) {
  return value.toString(8).padStart(length - 1, '0') + '\0';
}

function tarHeader(name, size, mode, type, mtime) {
  const header = Buffer.alloc(512);
  let prefix = '';
  let base = name;
  if (Buffer.byteLength(name) > 100) {
    const cut = name.lastIndexOf('/', 155);
    if (cut <= 0) throw new Error('слишком длинное имя в tar: ' + name);
    prefix = name.slice(0, cut);
    base = name.slice(cut + 1);
  }
  header.write(base, 0, 100, 'utf8');
  header.write(octal(mode, 8), 100, 'ascii');
  header.write(octal(0, 8), 108, 'ascii');
  header.write(octal(0, 8), 116, 'ascii');
  header.write(octal(size, 12), 124, 'ascii');
  header.write(octal(mtime, 12), 136, 'ascii');
  header.write('        ', 148, 'ascii');  // место под контрольную сумму
  header.write(type, 156, 'ascii');
  header.write('ustar\0', 257, 'ascii');
  header.write('00', 263, 'ascii');
  header.write('root', 265, 'ascii');
  header.write('root', 297, 'ascii');
  header.write(prefix, 345, 155, 'utf8');
  let sum = 0;
  for (let i = 0; i < 512; i++) sum += header[i];
  header.write(sum.toString(8).padStart(6, '0') + '\0 ', 148, 'ascii');
  return header;
}

function tarGz(entries, { date = new Date() } = {}) {
  const mtime = Math.floor(date.getTime() / 1000);
  const blocks = [];
  for (const entry of entries) {
    const isDir = !!entry.dir || entry.name.endsWith('/');
    if (isDir) {
      blocks.push(tarHeader(entry.name.replace(/\/?$/, '/'), 0, entry.mode !== undefined ? entry.mode : 0o755, '5', mtime));
      continue;
    }
    const data = entry.data;
    blocks.push(tarHeader(entry.name, data.length, entry.mode !== undefined ? entry.mode : 0o644, '0', mtime));
    blocks.push(data);
    const pad = (512 - (data.length % 512)) % 512;
    if (pad) blocks.push(Buffer.alloc(pad));
  }
  blocks.push(Buffer.alloc(1024));
  return zlib.gzipSync(Buffer.concat(blocks), { level: 9 });
}

module.exports = { crc32, zipWrite, zipRead, zipExtract, tarGz };

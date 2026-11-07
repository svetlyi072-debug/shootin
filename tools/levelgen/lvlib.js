// Небольшая библиотека для сборки карт уровней ShootIn (ASCII).
'use strict';
const fs = require('fs');

class Grid {
  constructor(w, h) {
    this.w = w; this.h = h;
    this.g = Array.from({ length: h }, () => Array(w).fill('.'));
  }
  inside(x, y) { return x >= 0 && x < this.w && y >= 0 && y < this.h; }
  get(x, y) { return this.inside(x, y) ? this.g[y][x] : '#'; }
  set(x, y, c) { if (!this.inside(x, y)) throw new Error(`вне карты (${x},${y}) '${c}'`); this.g[y][x] = c; }
  rect(x0, y0, x1, y1, c) { for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) this.set(x, y, c); }
  clear(x0, y0, x1, y1) { this.rect(x0, y0, x1, y1, '.'); }
  hline(y, x0, x1, c) { for (let x = x0; x <= x1; x++) this.set(x, y, c); }
  // сквозная платформа в ряду y
  plat(y, x0, x1) { this.hline(y, x0, x1, '-'); }
  // пол толщиной 2 ряда: верхняя поверхность — ряд top
  floor(top, x0, x1, thick = 2) { this.rect(x0, top, x1, Math.min(top + thick - 1, this.h - 1), '#'); }
  // персонаж/предмет в клетке (x,y): стоит на блоке в (x,y+1)
  put(x, y, c) { this.set(x, y, c); }
  solidAt(x, y) { const c = this.get(x, y); return c === '#' || c === 'f'; }
  floorAt(x, y) { return this.solidAt(x, y) || this.get(x, y) === '-'; }
  // ставит на самую низкую опору в колонке не выше ряда fromY
  stand(x, c, fromY) {
    for (let y = fromY; y >= 1; y--) {
      if (this.get(x, y) === '.' && this.floorAt(x, y + 1)) { this.set(x, y, c); return y; }
    }
    throw new Error(`негде поставить '${c}' в колонке ${x}`);
  }
  rows() { return this.g.map((r) => r.join('')); }
}

function levelFile({ num, title, theme, desc, requireClear = false, extra = '', rows }) {
  return `extends RefCounted
## Уровень ${num}. ${desc}
## Легенда символов — в scripts/level/level.gd.

const TITLE := "${title}"
## Выход откроется только после победы над всеми врагами.
const REQUIRE_CLEAR := ${requireClear ? 'true' : 'false'}
## Оформление: grass, meadow, clay, candy, stone, crypt, wood, jade, brick (THEMES в level.gd).
const THEME := "${theme}"
${extra}
const MAP := [
${rows.map((r) => `\t"${r}",`).join('\n')}
]
`;
}

function writeLevel(file, spec) { fs.writeFileSync(file, levelFile(spec)); }

module.exports = { Grid, writeLevel, levelFile };

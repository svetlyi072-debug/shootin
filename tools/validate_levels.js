#!/usr/bin/env node
// Проверка проходимости уровней ShootIn (без запуска Godot).
//
// Запуск из папки проекта:
//   node tools/validate_levels.js           — все уровни из levels/level_list.gd
//   node tools/validate_levels.js 3 7       — только уровни 3 и 7
//   node tools/validate_levels.js 3 --show  — ещё и нарисовать, куда игрок может попасть
//   node tools/validate_levels.js path/to/level.gd — проверить отдельный файл
// Служебные флаги: --exact (прыжок ровно как в игре, без запаса),
//   --paths FILE (записать найденные маршруты до выхода в JSON — для повтора в Godot).
//
// Что проверяется:
//  * на карте ровно один игрок P и есть выход E (или босс B — тогда цель дойти до арены);
//  * враги и предметы стоят в пустых клетках, наземные враги и выход — на опоре;
//  * от старта можно дойти до выхода. Физика игрока моделируется: бег, прыжки с разной
//    длительностью нажатия, падения, сквозные платформы. Касание шипов и падение
//    в пропасть считаются проигрышем;
//  * ловушки: пила o, шипастый шар * и огонь f двигаются или горят по времени, поэтому
//    они не закрывают маршрут (проходят в момент, когда ловушка отошла, или перепрыгивают);
//    проверяется только геометрия: пила — на ровном полу с запасом высоты для прыжка,
//    шар — под блоком и над полом, огонь — над пламенем свободно. Батут T предсказуем:
//    в основном маршруте он препятствие (его не касаются), а отдельным проходом
//    проверяется, до каких аптечек на высоких уступах он помогает добраться;
//  * тупики: места, куда попасть можно, а выбраться к выходу уже нельзя;
//  * до каких аптечек можно добраться.
// Модель упрощённая и чуть осторожнее настоящей физики (прыжок на 0,1 клетки ниже),
// врагов она не учитывает.

'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const T = 32;                                   // Game.TILE
const GRAVITY = 980;                            // physics/2d/default_gravity
const RUN = 5 * T;                              // Player.run_speed_tiles
// Player.jump_height_tiles = 2.5; по умолчанию берём с запасом 0,1 клетки.
const JUMP_TILES = process.argv.includes('--exact') ? 2.5 : 2.4;
const JUMP_V = Math.sqrt(2 * GRAVITY * JUMP_TILES * T);
const HALF_W = 12;                              // половина ширины тела игрока
const HEIGHT = 48;                              // рост игрока
const DT = 1 / 60;
const EPS = 0.01;
// В Godot касание шипов засчитывается чуть раньше (касание краями, отставание на кадр),
// а с самого края платформы игрок соскальзывает. Поэтому модель осторожнее:
const SPIKE_PAD = 3;    // шипы «шире» на столько пикселей с каждой стороны
const MIN_SUPPORT = 12; // приземление — только если под ногами хотя бы полтела опоры
const MAX_STATES = 60000;
// Места для стояния различаются с точностью до полклетки; позиция выравнивается по центру
// половинки (если там можно стоять), чтобы разбег у края ямы не зависел от того,
// откуда игрок пришёл.
const SUB = T / 2;
// Враги: s слизняк, b мышь, k скелет, g гоблин, m грибник, r крыса, c мимик, p панцирник,
// z зомби, y могильный зомби, x зомби-рыцарь.
// Боссы: M король-гриб, N костяной рыцарь, O око бездны, W огненный червь, V тёмный колдун, Z король зомби,
// B древний слизень, K царь-панцирь (он крупнее остальных: нужны 5 клеток в ширину и 3 в высоту).
const BASE_ENEMIES = 'sbkgmrcpzyx';  // z зомби, y могильный зомби, x зомби-рыцарь
const BASE_BOSSES = 'MNOWVBKZ';           // Z король зомби
let ENEMIES = BASE_ENEMIES;
let BOSSES = BASE_BOSSES;
const FLYING = 'bO';
// Ловушки. Размеры согласованы со scripts/traps/*.gd.
const BALL_CHAIN = 3 * T, BALL_R = 15, BALL_SWING = 65;        // шар: цепь 3 клетки, размах ±65°
const TRAMP_TILES = 5.3;                                       // батут бросает на 5,4 клетки — берём с запасом
const TRAMP_V = Math.sqrt(2 * GRAVITY * TRAMP_TILES * T);
const TRAPS = 'o*fT';
let KNOWN = new Set(['.', '#', '-', '^', '+', 'E', 'P', ' ', ...TRAPS, ...ENEMIES, ...BOSSES]);
// Символы врагов и боссов мода (читаются из enemies/*.json и bosses/*.json рядом с уровнем).
function useSymbols(extraEnemies, extraBosses) {
  ENEMIES = BASE_ENEMIES + extraEnemies;
  BOSSES = BASE_BOSSES + extraBosses;
  KNOWN = new Set(['.', '#', '-', '^', '+', 'E', 'P', ' ', ...TRAPS, ...ENEMIES, ...BOSSES]);
}

// Набор «приёмов»: куда жать и сколько держать.
const PRIMITIVES = [];
for (const dir of [-1, 1]) {
  for (const hold of [0.1, 0.2]) PRIMITIVES.push({ dir, jump: false, delay: 0, hold });
  for (const hold of [0.1, 0.2, 0.3, 0.45, 0.6, 0.8, Infinity]) PRIMITIVES.push({ dir, jump: true, delay: 0, hold });
  for (const delay of [0.15, 0.3]) PRIMITIVES.push({ dir, jump: true, delay, hold: Infinity });
}
PRIMITIVES.push({ dir: 0, jump: true, delay: 0, hold: 0 });

function loadLevelList() {
  const list = fs.readFileSync(path.join(ROOT, 'levels', 'level_list.gd'), 'utf8');
  const files = [];
  const re = /preload\("res:\/\/([^"]+)"\)/g;
  let m;
  while ((m = re.exec(list))) files.push(m[1]);
  return files;
}

function modSymbols(dir) {
  let out = '';
  if (!fs.existsSync(dir)) return out;
  for (const f of fs.readdirSync(dir)) {
    if (!f.endsWith('.json')) continue;
    try {
      const sym = JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8')).symbol;
      if (typeof sym === 'string' && sym.length === 1) out += sym;
    } catch (e) { /* битый файл — это заметит игра */ }
  }
  return out;
}

// Уровень мода: levels/*.txt (заголовок «ключ: значение», пустая строка, карта) или *.json.
function parseModLevel(abs) {
  const src = fs.readFileSync(abs, 'utf8').replace(/^\ufeff/, '');
  let header = {};
  let rows = [];
  if (abs.endsWith('.json')) {
    const j = JSON.parse(src);
    header = j;
    rows = (j.map || []).map(String);
  } else {
    const lines = src.replace(/\r\n?/g, '\n').split('\n');
    let i = 0;
    if (lines.length && /^[A-Za-z_]+\s*:/.test(lines[0])) {
      while (i < lines.length && lines[i].trim() !== '') {
        const colon = lines[i].indexOf(':');
        header[lines[i].slice(0, colon).trim().toLowerCase()] = lines[i].slice(colon + 1).trim();
        i++;
      }
      i++;
    }
    rows = lines.slice(i);
    while (rows.length && rows[rows.length - 1].trim() === '') rows.pop();
  }
  const root = path.dirname(path.dirname(abs));
  return {
    title: String(header.title || path.basename(abs)),
    requireClear: ['yes', 'true', 'да', '1', 'on'].includes(String(header.require_clear || '').toLowerCase()),
    rows,
    winBoss: String(header.win_boss || ''),
    extraEnemies: modSymbols(path.join(root, 'enemies')),
    extraBosses: modSymbols(path.join(root, 'bosses')),
  };
}

function parseLevel(relPath) {
  const abs = path.resolve(ROOT, relPath);
  if (/\.(txt|json)$/.test(abs)) return parseModLevel(abs);
  const src = fs.readFileSync(abs, 'utf8');
  const title = (src.match(/const\s+TITLE\s*:?=\s*"([^"]*)"/) || [])[1] || '';
  const requireClear = /const\s+REQUIRE_CLEAR\s*:?=\s*true/.test(src);
  const block = src.match(/const\s+MAP\s*:?=\s*\[([\s\S]*?)\n\]/);
  if (!block) throw new Error('не найден const MAP');
  const rows = [];
  const re = /"([^"]*)"/g;
  let m;
  while ((m = re.exec(block[1]))) rows.push(m[1]);
  const winBoss = (src.match(/const\s+WIN_BOSS\s*:?=\s*"([^"]*)"/) || [])[1] || '';
  return { title, requireClear, rows, winBoss, extraEnemies: '', extraBosses: '' };
}

class Level {
  constructor(rows) {
    this.rows = rows;
    this.h = rows.length;
    this.w = Math.max(...rows.map((r) => r.length));
    this.deathY = (this.h + 2) * T;
    this.spikes = [];
    this.pads = [];          // батуты: зоны, которые подбрасывают
    this.useTramps = false;  // true — батуты работают (проход для аптечек), false — это препятствие
    this.traps = [];         // для статических проверок: {c, x, y}
    this.exits = [];
    this.pickups = [];
    this.enemies = [];
    this.players = [];
    this.bosses = [];
    for (let y = 0; y < this.h; y++) {
      for (let x = 0; x < rows[y].length; x++) {
        const c = rows[y][x];
        const bx = (x + 0.5) * T, by = (y + 1) * T;
        if (c === '^') {
          this.spikes.push({ l: x * T + 4 - SPIKE_PAD, r: (x + 1) * T - 4 + SPIKE_PAD, t: (y + 0.5) * T - SPIKE_PAD, b: (y + 1) * T });
        }
        if (TRAPS.includes(c)) this.traps.push({ c, x, y });
        if (c === 'T') this.pads.push({ l: bx - 17, r: bx + 17, t: by - 22, b: by });
        if (c === 'E') this.exits.push({ x, y, l: bx - 12, r: bx + 12, t: by - 56, b: by });
        if (c === '+') this.pickups.push({ x, y, l: bx - 10, r: bx + 10, t: by - 22, b: by - 2 });
        if (c === 'P') this.players.push({ x, y });
        if (ENEMIES.includes(c)) this.enemies.push({ c, x, y });
        if (BOSSES.includes(c)) this.bosses.push({ c, x, y });
      }
    }
  }

  cell(x, y) {
    if (x < 0 || x >= this.w) return '#'; // невидимые стены по краям
    if (y < 0 || y >= this.h) return '.';
    return this.rows[y][x] || '.';
  }

  solid(x, y) { const c = this.cell(x, y); return c === '#' || c === 'f'; }  // f — основание огня
  platform(x, y) { return this.cell(x, y) === '-'; }

  columns(s) {
    return [Math.floor((s.x - HALF_W + EPS) / T), Math.floor((s.x + HALF_W - EPS) / T)];
  }

  colBlocked(cx, top, bottom) {
    for (let ry = Math.floor((top + EPS) / T); ry <= Math.floor((bottom - EPS) / T); ry++) {
      if (this.solid(cx, ry)) return true;
    }
    return false;
  }

  step(s) {
    // По горизонтали.
    s.x += s.vx * DT;
    if (s.vx > 0) {
      const cx = Math.floor((s.x + HALF_W - EPS) / T);
      if (this.colBlocked(cx, s.y - HEIGHT, s.y)) s.x = cx * T - HALF_W;
    } else if (s.vx < 0) {
      const cx = Math.floor((s.x - HALF_W + EPS) / T);
      if (this.colBlocked(cx, s.y - HEIGHT, s.y)) s.x = (cx + 1) * T + HALF_W;
    }
    // По вертикали.
    s.vy += GRAVITY * DT;
    const oldBottom = s.y;
    const oldTop = s.y - HEIGHT;
    s.y += s.vy * DT;
    s.onFloor = false;
    const [c0, c1] = this.columns(s);
    if (s.vy > 0) {
      for (let ry = Math.ceil((oldBottom - EPS) / T); ry * T <= s.y; ry++) {
        let support = 0;
        for (let cx = c0; cx <= c1; cx++) {
          if (this.solid(cx, ry) || this.platform(cx, ry)) {
            support += Math.min(s.x + HALF_W, (cx + 1) * T) - Math.max(s.x - HALF_W, cx * T);
          }
        }
        if (support >= MIN_SUPPORT) {
          s.y = ry * T;
          s.vy = 0;
          s.onFloor = true;
          break;
        }
      }
    } else {
      const newTop = s.y - HEIGHT;
      for (let ry = Math.floor((oldTop - EPS) / T); (ry + 1) * T >= newTop; ry--) {
        let bonk = false;
        for (let cx = c0; cx <= c1; cx++) if (this.solid(cx, ry)) bonk = true;
        if (bonk) {
          s.y = (ry + 1) * T + HEIGHT;
          s.vy = 0;
          break;
        }
      }
    }
  }

  // Можно ли спокойно стоять в точке (x, y — ноги на границе клетки).
  standable(x, y) {
    const s = { x, y };
    const [c0, c1] = this.columns(s);
    const ry = Math.round(y / T);
    let support = 0;
    for (let cx = c0; cx <= c1; cx++) {
      if (this.solid(cx, ry) || this.platform(cx, ry)) {
        support += Math.min(x + HALF_W, (cx + 1) * T) - Math.max(x - HALF_W, cx * T);
      }
      if (this.colBlocked(cx, y - HEIGHT, y)) return false;
    }
    return support >= MIN_SUPPORT && !this.spikes.some((sp) => Level.overlaps(s, sp)) && !this.hitsPad(s);
  }

  // Касание батута: пока он «препятствие», зона чуть шире, как у шипов.
  hitsPad(s) {
    return this.pads.some((p) => Level.overlaps(s, p)) && !this.useTramps
      ? this.pads.some((p) => Level.overlaps(s, { l: p.l - SPIKE_PAD, r: p.r + SPIKE_PAD, t: p.t - SPIKE_PAD, b: p.b }))
      : false;
  }

  static overlaps(s, r) {
    return s.x + HALF_W >= r.l && s.x - HALF_W <= r.r && s.y >= r.t && s.y - HEIGHT <= r.b;
  }

  simulate(start, p, goals) {
    const s = { x: start.x, y: start.y, vx: 0, vy: 0, onFloor: true };
    if (p.jump) s.vy = -JUMP_V;
    const result = { end: null, goal: false, hits: new Set(), pickups: [] };
    let airborne = false;
    let padCooldown = 0;
    for (let i = 0; i < 300; i++) {
      const t = i * DT;
      s.vx = (t >= p.delay && t < p.delay + p.hold) ? p.dir * RUN : 0;
      this.step(s);
      if (this.useTramps && padCooldown-- <= 0 && this.pads.some((pd) => Level.overlaps(s, pd))) {
        s.vy = -TRAMP_V;      // батут подбросил
        s.onFloor = false;
        airborne = true;
        padCooldown = 24;
      }
      goals.forEach((g, gi) => { if (Level.overlaps(s, g)) { result.goal = true; result.hits.add(gi); } });
      this.pickups.forEach((pk, idx) => { if (Level.overlaps(s, pk)) result.pickups.push(idx); });
      if (s.y > this.deathY || this.spikes.some((sp) => Level.overlaps(s, sp)) || this.hitsPad(s)) return result;
      if (!s.onFloor) airborne = true;
      const inputDone = t + DT >= p.delay + (Number.isFinite(p.hold) ? p.hold : 0);
      if (s.onFloor && inputDone && (airborne || !p.jump)) {
        result.end = { x: s.x, y: s.y };
        return result;
      }
    }
    return result;
  }
}

function key(s) { return `${Math.floor(s.x / SUB)},${Math.round(s.y / T)}`; }
function keyToCell(k) { const [sx, y] = k.split(',').map(Number); return [Math.floor((sx * SUB) / T), y]; }

function checkLevel(index, file, show) {
  const errors = [];
  const warnings = [];
  let data;
  try {
    data = parseLevel(file);
    useSymbols(data.extraEnemies || '', data.extraBosses || '');
  } catch (e) {
    return { errors: [`${file}: ${e.message}`], warnings, info: '' };
  }
  const lv = new Level(data.rows);
  const name = `${String(index + 1).padStart(2, '0')} «${data.title}»`;

  // --- Статические проверки ---
  data.rows.forEach((row, y) => {
    [...row].forEach((c, x) => { if (!KNOWN.has(c)) errors.push(`неизвестный символ '${c}' в (${x},${y})`); });
  });
  if (lv.players.length !== 1) errors.push(`игроков P на карте: ${lv.players.length} (нужен ровно 1)`);
  if (lv.exits.length === 0 && lv.bosses.length === 0) errors.push('нет ни выхода E, ни босса');
  if (lv.w < 27 || lv.h < 16) warnings.push(`карта ${lv.w}x${lv.h} меньше экрана (27x16) — камера покажет пустоту`);
  const supported = (x, y) => lv.solid(x, y + 1) || lv.platform(x, y + 1);
  for (const e of lv.enemies) {
    if (!FLYING.includes(e.c) && !supported(e.x, e.y)) warnings.push(`враг '${e.c}' в (${e.x},${e.y}) висит в воздухе`);
  }
  for (const b of lv.bosses) {
    if (!FLYING.includes(b.c) && !supported(b.x, b.y)) warnings.push(`босс '${b.c}' в (${b.x},${b.y}) висит в воздухе`);
    const halfW = b.c === 'K' || b.c === 'H' || b.c === 'D' ? 2 : 1;
    const height = b.c === 'K' || b.c === 'H' || b.c === 'Z' || b.c === 'D' || !BASE_BOSSES.includes(b.c) ? 3 : 2;
    for (let dx = -halfW; dx <= halfW; dx++) for (let dy = -height; dy <= 0; dy++) {
      if (lv.solid(b.x + dx, b.y + dy)) errors.push(`боссу в (${b.x},${b.y}) не хватает места (блок в (${b.x + dx},${b.y + dy}))`);
    }
  }
  for (const t of lv.traps) {
    const where = `'${t.c}' в (${t.x},${t.y})`;
    if (lv.solid(t.x, t.y) && t.c !== 'f') errors.push(`ловушка ${where} внутри блока`);
    if (t.c === 'o') {
      for (let dx = -3; dx <= 3; dx++) {
        if (Math.abs(dx) <= 2 && lv.solid(t.x + dx, t.y)) errors.push(`пила ${where}: на пути блок в (${t.x + dx},${t.y})`);
        else if (Math.abs(dx) <= 2 && !supported(t.x + dx, t.y)) warnings.push(`пила ${where}: на пути нет пола в (${t.x + dx},${t.y})`);
        for (let dy = 1; dy <= 3; dy++) {
          if (lv.solid(t.x + dx, t.y - dy)) { warnings.push(`пила ${where}: низкий потолок над путём в (${t.x + dx},${t.y - dy}) — не перепрыгнуть`); dx = 9; break; }
        }
      }
    }
    if (t.c === 'T' && !supported(t.x, t.y)) warnings.push(`батут ${where} висит в воздухе`);
    if (t.c === 'f' && (lv.solid(t.x, t.y - 1) || lv.solid(t.x, t.y - 2))) errors.push(`над огнём ${where} блок — пламени и прыжку некуда`);
    if (t.c === '*') {
      if (t.y > 0 && !lv.solid(t.x, t.y - 1)) warnings.push(`шару ${where} не к чему крепиться (над ним нет блока)`);
      if (!lv.solid(t.x, t.y + 4) && !lv.platform(t.x, t.y + 4) && !lv.solid(t.x, t.y + 5) && !lv.platform(t.x, t.y + 5)) warnings.push(`под шаром ${where} нет пола на 4–5 клеток ниже`);
      for (let a = -BALL_SWING; a <= BALL_SWING; a += 6) {
        const cx = Math.floor(((t.x + 0.5) * T + BALL_CHAIN * Math.sin(a * Math.PI / 180)) / T);
        const cy = Math.floor((t.y * T + BALL_CHAIN * Math.cos(a * Math.PI / 180)) / T);
        if (lv.solid(cx, cy)) { warnings.push(`шар ${where} проходит сквозь блок в (${cx},${cy})`); break; }
      }
    }
  }
  for (const e of lv.exits) {
    if (!supported(e.x, e.y)) warnings.push(`выход в (${e.x},${e.y}) висит в воздухе`);
    if (lv.solid(e.x, e.y - 1)) errors.push(`над выходом в (${e.x},${e.y}) блок — дверь 2 клетки высотой`);
  }
  if (errors.length || lv.players.length !== 1) return { errors, warnings, info: name };

  // --- Цели: выход или арена босса ---
  // Арена босса: игрок дошёл до него по горизонтали ближе 6 клеток (на любой высоте —
  // летающий босс может висеть под потолком).
  // Если боссов несколько (огромный финальный уровень), у каждого свой участок арены по высоте
  // (кроме летающих), достижим должен быть каждый, а маршрут строится к главному боссу
  // (WIN_BOSS из файла уровня, иначе последний по карте).
  const many = lv.bosses.length > 1;
  const goals = lv.exits.length ? lv.exits : lv.bosses.map((b) => ({
    l: (b.x - 6) * T, r: (b.x + 7) * T,
    t: many && !FLYING.includes(b.c) ? (b.y - 2) * T : -1e9,
    b: many && !FLYING.includes(b.c) ? (b.y + 1) * T : 1e9,
  }));
  const finalGoals = new Set();
  if (lv.exits.length || !many) {
    goals.forEach((_, i) => finalGoals.add(i));
  } else {
    let fi = data.winBoss ? lv.bosses.findIndex((b) => b.c === data.winBoss) : -1;
    if (fi < 0) fi = lv.bosses.reduce((best, b, i) => (b.x > lv.bosses[best].x ? i : best), 0);
    finalGoals.add(fi);
  }
  const goalsReached = new Set();

  // --- Поиск в ширину по местам, где игрок может стоять ---
  const p0 = lv.players[0];
  const settle = lv.simulate({ x: (p0.x + 0.5) * T, y: (p0.y + 1) * T }, { dir: 0, jump: false, delay: 0, hold: 0 }, goals);
  if (!settle.end) return { errors: ['игрок в начале уровня падает в пропасть или на шипы'], warnings, info: name };

  let states = new Map();
  let queue = [];
  const add = (landed, parent, via) => {
    const k = key(landed);
    const centered = { x: (Math.floor(landed.x / SUB) + 0.5) * SUB, y: Math.round(landed.y / T) * T };
    const pos = lv.standable(centered.x, centered.y) ? centered : landed;
    if (!states.has(k)) {
      states.set(k, { pos, next: new Set(), goal: false, goalVia: null, parent, via });
      queue.push(k);
    }
    return k;
  };
  const startKey = add(settle.end, null, null);
  const pickupsReached = new Set();
  const explore = () => {
    while (queue.length && states.size < MAX_STATES) {
      const k = queue.shift();
      const st = states.get(k);
      for (const p of PRIMITIVES) {
        const res = lv.simulate(st.pos, p, goals);
        res.pickups.forEach((i) => pickupsReached.add(i));
        res.hits.forEach((i) => goalsReached.add(i));
        if ([...res.hits].some((i) => finalGoals.has(i)) && !st.goal) { st.goal = true; st.goalVia = p; }
        if (res.end) st.next.add(add(res.end, k, p));
      }
    }
  };
  explore();
  const mainStates = states;
  const mainStartKey = startKey;

  // Второй проход: батуты работают. Нужен только чтобы понять, до каких аптечек
  // можно добраться с их помощью; маршрут и тупики считаются по первому проходу.
  let extraStates = 0;
  if (lv.pads.length) {
    lv.useTramps = true;
    states = new Map();
    queue = [];
    add(settle.end, null, null);
    explore();
    extraStates = states.size;
    lv.useTramps = false;
    states = mainStates;
  }

  // Кратчайший найденный маршрут до цели (для повтора настоящей физикой в Godot).
  let route = null;
  const goalKey = [...states.keys()].find((k) => states.get(k).goal);
  if (goalKey) {
    const chain = [];
    for (let k = goalKey; states.get(k).parent !== null; k = states.get(k).parent) chain.unshift(k);
    const enc = (p) => ({ dir: p.dir, jump: p.jump, delay: p.delay, hold: Number.isFinite(p.hold) ? p.hold : -1 });
    route = chain.map((k) => {
      const st = states.get(k);
      const from = states.get(st.parent).pos;
      return { x: from.x, y: from.y, prim: enc(st.via), expect: st.pos, final: false };
    });
    const last = states.get(goalKey);
    route.push({ x: last.pos.x, y: last.pos.y, prim: enc(last.goalVia), expect: null, final: true });
  }

  // --- Откуда можно добраться до цели (обратный обход) ---
  const prev = new Map([...states.keys()].map((k) => [k, []]));
  for (const [k, st] of states) for (const n of st.next) prev.get(n).push(k);
  const canFinish = new Set();
  const stack = [...states].filter(([, st]) => st.goal).map(([k]) => k);
  stack.forEach((k) => canFinish.add(k));
  while (stack.length) {
    for (const p of prev.get(stack.pop())) if (!canFinish.has(p)) { canFinish.add(p); stack.push(p); }
  }

  if (!canFinish.has(startKey)) {
    errors.push(lv.exits.length ? 'до выхода не добраться' : 'до арены босса не добраться');
  }
  if (many && !lv.exits.length) {
    lv.bosses.forEach((b, i) => {
      if (!goalsReached.has(i)) errors.push(`до арены босса '${b.c}' в (${b.x},${b.y}) не добраться`);
    });
  }
  const deadEnds = [...states.keys()].filter((k) => !canFinish.has(k));
  if (canFinish.has(startKey) && deadEnds.length) {
    warnings.push(`тупики (оттуда не выбраться к цели, только R): ${deadEnds.length} мест, например ${[...new Set(deadEnds.map((k) => keyToCell(k).join(',')))].slice(0, 6).map((c) => `(${c})`).join(' ')}`);
  }
  lv.pickups.forEach((pk, i) => {
    if (!pickupsReached.has(i)) warnings.push(`до аптечки в (${pk.x},${pk.y}) не добраться`);
  });

  if (show) {
    const grid = data.rows.map((r) => [...r.padEnd(lv.w, '.')]);
    for (const k of states.keys()) {
      const [x, y] = keyToCell(k);
      const ry = y - 1;
      if (grid[ry] && grid[ry][x] === '.') grid[ry][x] = canFinish.has(k) ? 'o' : 'x';
    }
    console.log(grid.map((r) => '    ' + r.join('')).join('\n'));
    console.log('    o — можно стоять и дойти до цели, x — тупик');
  }

  return { errors, warnings, route, goals, info: `${name}: ${lv.w}x${lv.h}, мест для стояния ${states.size}` };
}

function main() {
  const args = process.argv.slice(2);
  const show = args.includes('--show');
  const pathsIdx = args.indexOf('--paths');
  const pathsFile = pathsIdx >= 0 ? args[pathsIdx + 1] : null;
  const only = args.filter((a) => /^\d+$/.test(a)).map(Number);
  const direct = args.filter((a) => /\.(gd|txt|json)$/.test(a) && a !== pathsFile);
  const files = direct.length ? direct : loadLevelList();
  const routes = [];
  let failed = 0;
  files.forEach((file, i) => {
    if (only.length && !only.includes(i + 1)) return;
    const { errors, warnings, info, route, goals } = checkLevel(i, file, show);
    if (route) routes.push({ index: i, file, steps: route, goals });
    const status = errors.length ? 'ОШИБКА' : (warnings.length ? 'ок, но' : 'ок');
    console.log(`[${status}] ${info || file}`);
    errors.forEach((e) => console.log(`    ✗ ${e}`));
    warnings.forEach((w) => console.log(`    ! ${w}`));
    if (errors.length) failed++;
  });
  if (pathsFile) fs.writeFileSync(pathsFile, JSON.stringify({ routes }, null, 1));
  console.log(failed ? `\nНе проходятся: ${failed}` : '\nВсе уровни проходимы.');
  process.exit(failed ? 1 : 0);
}

main();

'use strict';
// Сборка релизных версий ShootIn: Windows, Linux, macOS и Web — в папку D:/shootin/export.
//
//   node tools/export/build.js                 — собрать всё
//   node tools/export/build.js windows web     — только указанные платформы (windows | linux | macos | web)
//   node tools/export/build.js --skip-tests    — не гонять проверку игры на собранном exe
//
// Нужны: Godot 4.3 с установленными шаблонами экспорта (переменная GODOT, по умолчанию Godot на рабочем столе),
// Node.js и встроенный в Windows компилятор C# (csc.exe) для установщика.
// Версия берётся из project.godot (application/config/version).
const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');
const cp = require('child_process');
const archive = require('./lib/archive.js');

const ROOT = path.resolve(__dirname, '..', '..');
const OUT = path.join(ROOT, 'export');
const BUILD = path.join(__dirname, 'build');
const ASSETS = path.join(__dirname, 'assets');
const GODOT = process.env.GODOT || path.join(os.homedir(), 'Desktop', 'Godot_v4.3-stable_win64.exe');
const TEMPLATES = path.join(process.env.APPDATA || '', 'Godot', 'export_templates', '4.3.stable');
const CSC = 'C:/Windows/Microsoft.NET/Framework64/v4.0.30319/csc.exe';
const NAME = 'ShootIn';

const projectText = fs.readFileSync(path.join(ROOT, 'project.godot'), 'utf8');
const VERSION = (projectText.match(/config\/version="([^"]+)"/) || [])[1] || '1.0.0';

const argv = process.argv.slice(2);
const SKIP_TESTS = argv.includes('--skip-tests');
const wanted = argv.filter((a) => !a.startsWith('--'));
const ALL = ['windows', 'linux', 'macos', 'web'];
const targets = wanted.length ? wanted : ALL;
for (const t of targets) if (!ALL.includes(t)) { console.error('Неизвестная платформа: ' + t); process.exit(2); }

const results = [];
const warnings = [];

function log(text) { console.log(text); }
function step(text) { console.log('\n=== ' + text); }
function mkdir(dir) { fs.mkdirSync(dir, { recursive: true }); }
function rmrf(target) { fs.rmSync(target, { recursive: true, force: true }); }
function size(file) { return (fs.statSync(file).size / 1048576).toFixed(1) + ' МБ'; }
function fail(text) { console.error('\nОШИБКА: ' + text); process.exit(1); }

function run(command, args, { cwd = ROOT, allowFail = false, quiet = false } = {}) {
  const r = cp.spawnSync(command, args, { cwd, encoding: 'utf8', maxBuffer: 1 << 28, windowsHide: true });
  const text = (r.stdout || '') + (r.stderr || '');
  if (!quiet && text.trim()) log(text.trim().split('\n').slice(-12).join('\n'));
  if (r.status !== 0 && !allowFail) fail(path.basename(command) + ' завершился с кодом ' + r.status + '\n' + text.slice(-2000));
  return { status: r.status, text };
}

function godot(args, options) { return run(GODOT, ['--headless', '--path', ROOT, ...args], options); }

function writePresets(windowsTemplate) {
  const template = fs.readFileSync(path.join(__dirname, 'export_presets.template.cfg'), 'utf8');
  const text = template.replace('@WINDOWS_TEMPLATE@', windowsTemplate || '').replace(/@VERSION@/g, VERSION);
  fs.writeFileSync(path.join(ROOT, 'export_presets.cfg'), text);
}

function exportPreset(preset, file) {
  mkdir(path.dirname(file));
  rmrf(file);
  const r = godot(['--export-release', preset, file], { quiet: true, allowFail: true });
  const errors = r.text.split('\n').filter((l) => /^(ERROR|SCRIPT ERROR):/.test(l) || /Не удалось|Failed|failed/.test(l));
  if (r.status !== 0 || !fs.existsSync(file)) fail('экспорт «' + preset + '» не удался:\n' + r.text.slice(-3000));
  if (errors.length) { warnings.push('экспорт «' + preset + '»: ' + errors.slice(0, 3).join(' | ')); log(errors.slice(0, 5).join('\n')); }
  log('экспорт «' + preset + '» → ' + path.relative(ROOT, file) + ' (' + size(file) + ')');
}

function addResult(label, file) { results.push({ label, file }); }

// --- проверки готовых файлов -----------------------------------------------------------------

function peHasSection(buf, wanted) {
  const pe = buf.readUInt32LE(0x3c);
  if (buf.toString('ascii', pe, pe + 4) !== 'PE\0\0') return false;
  const count = buf.readUInt16LE(pe + 6);
  const optSize = buf.readUInt16LE(pe + 20);
  let pos = pe + 24 + optSize;
  for (let i = 0; i < count; i++, pos += 40) {
    if (buf.toString('ascii', pos, pos + 8).replace(/\0+$/, '') === wanted) return true;
  }
  return false;
}

function checkSmoke(exe) {
  if (SKIP_TESTS) return;
  const r = run(exe, ['--headless', '--script', path.join(__dirname, 'smoke_test.gd')], { quiet: true, allowFail: true });
  if (!/ИТОГ: ВСЁ ХОРОШО/.test(r.text)) fail('проверка игры на собранном exe не пройдена:\n' + r.text.slice(-2500));
  log('проверка на собранном exe: все 34 уровня загружаются из упакованных ресурсов');
}

// --- Windows ---------------------------------------------------------------------------------

function patchedWindowsTemplate() {
  mkdir(BUILD);
  const patcher = path.join(BUILD, 'IconPatcher.exe');
  const source = path.join(__dirname, 'installer', 'IconPatcher.cs');
  if (!fs.existsSync(patcher) || fs.statSync(patcher).mtimeMs < fs.statSync(source).mtimeMs) {
    run(CSC, ['/nologo', '/codepage:65001', '/target:exe', '/out:' + patcher, source]);
  }
  const patched = path.join(BUILD, 'windows_release_x86_64_patched.exe');
  fs.copyFileSync(path.join(TEMPLATES, 'windows_release_x86_64.exe'), patched);
  run(patcher, [patched, path.join(ASSETS, 'icon.ico'), VERSION, NAME, NAME + ' — 2D экшен-платформер', NAME], { quiet: true });
  return patched.replace(/\\/g, '/');
}

function buildInstaller(gameExe, outFile) {
  const dir = path.join(BUILD, 'installer');
  rmrf(dir);
  mkdir(dir);
  const version4 = (VERSION + '.0.0.0').split('.').slice(0, 4).join('.');
  const infoFor = (title) => `using System.Reflection;
[assembly: AssemblyTitle("${title}")]
[assembly: AssemblyProduct("${NAME}")]
[assembly: AssemblyCompany("${NAME}")]
[assembly: AssemblyDescription("${title}")]
[assembly: AssemblyVersion("${version4}")]
[assembly: AssemblyFileVersion("${version4}")]
static class BuildInfo { public const string Version = "${VERSION}"; }
`;
  const common = ['/nologo', '/codepage:65001', '/target:winexe', '/optimize+', '/win32icon:' + path.join(ASSETS, 'icon.ico'),
    '/win32manifest:' + path.join(__dirname, 'installer', 'Setup.manifest'),
    '/r:System.dll', '/r:System.Windows.Forms.dll', '/r:System.Drawing.dll', '/r:System.IO.Compression.dll', '/r:System.IO.Compression.FileSystem.dll'];
  const setupSource = path.join(__dirname, 'installer', 'Setup.cs');

  const uninstallInfo = path.join(dir, 'InfoUninstall.cs');
  fs.writeFileSync(uninstallInfo, '\ufeff' + infoFor('Удаление ShootIn'));
  const uninstallExe = path.join(dir, 'Uninstall.exe');
  run(CSC, [...common, '/define:UNINSTALLER', '/out:' + uninstallExe, setupSource, uninstallInfo]);

  const payload = path.join(dir, 'payload.zip');
  fs.writeFileSync(payload, archive.zipWrite([{ name: 'ShootIn.exe', data: fs.readFileSync(gameExe), mode: 0o755 }]));
  log('данные установщика: ' + size(payload));

  const setupInfo = path.join(dir, 'InfoSetup.cs');
  fs.writeFileSync(setupInfo, '\ufeff' + infoFor('Установка ShootIn'));
  run(CSC, [...common, '/resource:' + payload + ',payload.zip', '/resource:' + uninstallExe + ',uninstall.exe', '/out:' + outFile, setupSource, setupInfo]);
  log('установщик → ' + path.relative(ROOT, outFile) + ' (' + size(outFile) + ')');
}

function buildWindows() {
  step('Windows (exe со встроенным PCK + установщик)');
  const template = patchedWindowsTemplate();
  writePresets(template);
  const exe = path.join(OUT, 'windows', 'portable', 'ShootIn.exe');
  exportPreset('Windows', exe);
  const data = fs.readFileSync(exe);
  if (!peHasSection(data, 'pck')) fail('в ShootIn.exe нет встроенного PCK (секция pck)');
  log('PCK встроен в exe (секция pck найдена)');
  checkSmoke(exe);
  const setup = path.join(OUT, 'windows', `ShootIn-${VERSION}-Setup.exe`);
  buildInstaller(exe, setup);
  fs.writeFileSync(path.join(OUT, 'windows', 'portable', 'README.txt'),
    `ShootIn ${VERSION} — переносная версия для Windows.\r\n\r\n` +
    'ShootIn.exe — вся игра в одном файле (ресурсы встроены). Положите его куда угодно и запустите.\r\n' +
    'Моды: создайте рядом с ShootIn.exe папку mods и кладите туда .zip-архивы модов или установите их из самой игры (Моды → Установить из файла…).\r\n' +
    'Сохранения лежат в %APPDATA%\\Godot\\app_userdata\\ShootIn.\r\n', 'utf8');
  addResult('Windows: установщик', setup);
  addResult('Windows: игра одним файлом (встроенный PCK)', exe);
}

// --- Linux -----------------------------------------------------------------------------------

function buildLinux() {
  step('Linux x86_64 (бинарник со встроенным PCK + установщик)');
  writePresets('');
  const bin = path.join(OUT, 'linux', 'portable', 'ShootIn.x86_64');
  exportPreset('Linux', bin);
  const data = fs.readFileSync(bin);
  if (data.readUInt32BE(0) !== 0x7f454c46 || data[4] !== 2 || data.readUInt16LE(18) !== 0x3e) fail('ShootIn.x86_64 — не ELF x86-64');
  if (data.toString('latin1', data.length - 4) !== 'GDPC') fail('в ShootIn.x86_64 нет встроенного PCK (в конце файла нет метки GDPC)');
  log('ELF x86-64, PCK встроен (метка GDPC в конце файла)');

  const folder = `ShootIn-${VERSION}-linux-x86_64`;
  const sub = (file) => fs.readFileSync(path.join(__dirname, 'linux', file), 'utf8').replace(/@VERSION@/g, VERSION).replace(/\r\n/g, '\n');
  const readme = `ShootIn ${VERSION} для Linux (x86_64)

Установка (одна команда или двойной клик):
  ./install.sh            — для себя, в ~/.local/share/ShootIn (root не нужен)
  ./install.sh --system   — для всех пользователей, в /opt/ShootIn (попросит пароль)
Если install.sh не запускается («нет прав»), выполните:  sh install.sh
Установщик сам ставит право на запуск (chmod +x) на игру, создаёт папки (игра, mods, сохранения),
ярлык в меню приложений и на рабочем столе и команду «shootin».

Без установки: игру можно запустить прямо из этой папки — ./ShootIn.x86_64
(если файл не запускается, один раз выполните: chmod +x ShootIn.x86_64).

Моды: кладите .zip-архивы или папки модов в папку mods рядом с игрой либо ставьте из самой игры
(главное меню → Моды → Установить из файла…).
Удаление: uninstall.sh в папке игры (--purge удалит и сохранения).
Сохранения: ~/.local/share/godot/app_userdata/ShootIn
`;
  const entries = [
    { name: folder + '/', dir: true, mode: 0o755 },
    { name: folder + '/install.sh', data: Buffer.from(sub('install.sh')), mode: 0o755 },
    { name: folder + '/uninstall.sh', data: Buffer.from(sub('uninstall.sh')), mode: 0o755 },
    { name: folder + '/ShootIn.x86_64', data, mode: 0o755 },
    { name: folder + '/ShootIn.png', data: fs.readFileSync(path.join(ASSETS, 'icon-256.png')), mode: 0o644 },
    { name: folder + '/README.txt', data: Buffer.from(readme), mode: 0o644 },
  ];
  const tgz = path.join(OUT, 'linux', folder + '.tar.gz');
  fs.writeFileSync(tgz, archive.tarGz(entries));
  log('пакет → ' + path.relative(ROOT, tgz) + ' (' + size(tgz) + '), права 755 у install.sh и игры записаны в архив');
  fs.writeFileSync(path.join(OUT, 'linux', 'portable', 'README.txt'), readme, 'utf8');
  addResult('Linux: пакет с установщиком (.tar.gz)', tgz);
  addResult('Linux: игра одним файлом (встроенный PCK)', bin);
}

// --- macOS -----------------------------------------------------------------------------------

function buildMac() {
  step('macOS (universal .app + установщик)');
  writePresets('');
  const godotZip = path.join(BUILD, 'macos', 'ShootIn-macos.zip');
  exportPreset('macOS', godotZip);
  const entries = archive.zipRead(fs.readFileSync(godotZip));
  const find = (suffix) => entries.find((e) => e.name === suffix);
  const main = find('ShootIn.app/Contents/MacOS/ShootIn');
  if (!main) fail('в macOS-экспорте нет ShootIn.app/Contents/MacOS/ShootIn: ' + entries.slice(0, 8).map((e) => e.name).join(', '));
  if ((main.mode & 0o111) === 0) fail('у ShootIn.app/Contents/MacOS/ShootIn нет права на запуск (mode ' + main.mode.toString(8) + ')');
  const bin = archive.zipExtract(main);
  const magic = bin.readUInt32BE(0);
  const universal = magic === 0xcafebabe;
  const pck = entries.find((e) => /Contents\/Resources\/.*\.pck$/.test(e.name));
  const plist = find('ShootIn.app/Contents/Info.plist');
  const plistText = plist ? archive.zipExtract(plist).toString('utf8') : '';
  if (!pck) fail('в ShootIn.app нет .pck с ресурсами игры');
  if (!/com\.shootin\.game/.test(plistText)) fail('в Info.plist нет идентификатора com.shootin.game');
  const signed = entries.some((e) => /_CodeSignature/.test(e.name)) || bin.indexOf(Buffer.from([0xfa, 0xde, 0x0c, 0xc0])) > 0;
  log(`ShootIn.app: ${universal ? 'universal (x86_64 + arm64)' : 'не universal, magic ' + magic.toString(16)}, ресурсы игры: ${pck.name.split('/').pop()}, подпись: ${signed ? 'есть' : 'не найдена'}`);
  if (!universal) warnings.push('macOS: бинарник не universal');
  if (!signed) warnings.push('macOS: в бинарнике не найдена подпись (ad-hoc); установщик подпишет приложение на Mac сам');

  const readme = `ShootIn ${VERSION} для macOS (Intel и Apple Silicon)

Установка:
  1. Распакуйте архив (двойной клик по .zip).
  2. Дважды щёлкните «Install ShootIn.command». Если macOS пишет, что файл нельзя открыть, потому что
     он загружен из интернета: нажмите на него правой кнопкой → «Открыть» → «Открыть» (один раз).
  Установщик скопирует ShootIn.app в «Программы», сам поставит право на запуск, снимет блокировку
  Gatekeeper, подпишет приложение локально, создаст папки для модов и запустит игру.

Без установщика: перетащите ShootIn.app в «Программы» и откройте правой кнопкой → «Открыть».
Игра не подписана сертификатом Apple Developer (он платный), поэтому первый запуск без установщика
требует этого подтверждения.

Моды: главное меню → Моды → Установить из файла… (или положите .zip в
~/Library/Application Support/Godot/app_userdata/ShootIn/mods).
Удаление: «Uninstall ShootIn.command» (сохранения остаются; ключ --purge удалит и их) либо просто
перетащите ShootIn.app в корзину.
`;
  const extra = [
    { name: 'Install ShootIn.command', data: Buffer.from(fs.readFileSync(path.join(__dirname, 'macos', 'Install ShootIn.command'), 'utf8').replace(/\r\n/g, '\n')), mode: 0o755 },
    { name: 'Uninstall ShootIn.command', data: Buffer.from(fs.readFileSync(path.join(__dirname, 'macos', 'Uninstall ShootIn.command'), 'utf8').replace(/\r\n/g, '\n')), mode: 0o755 },
    { name: 'README.txt', data: Buffer.from(readme), mode: 0o644 },
  ];
  const outZip = path.join(OUT, 'macos', `ShootIn-${VERSION}-macos.zip`);
  mkdir(path.dirname(outZip));
  fs.writeFileSync(outZip, archive.zipWrite([...entries, ...extra]));
  log('пакет → ' + path.relative(ROOT, outZip) + ' (' + size(outZip) + '), право 755 у установщика и игры сохранено');
  addResult('macOS: пакет с установщиком (.zip с ShootIn.app)', outZip);
}

// --- Web -------------------------------------------------------------------------------------

function buildWeb() {
  step('Web (WebAssembly, без потоков)');
  writePresets('');
  const site = path.join(OUT, 'web', 'site');
  // Папку не удаляем, а очищаем: если в ней сейчас открыт локальный сервер, Windows не даёт удалить саму папку.
  if (fs.existsSync(site)) for (const entry of fs.readdirSync(site)) rmrf(path.join(site, entry));
  exportPreset('Web', path.join(site, 'index.html'));
  const files = fs.readdirSync(site).sort();
  for (const need of ['index.html', 'index.js', 'index.wasm', 'index.pck']) if (!files.includes(need)) fail('в web-экспорте нет ' + need);
  log('файлы сайта: ' + files.join(', '));
  const entries = files.map((f) => ({ name: f, data: fs.readFileSync(path.join(site, f)), mode: 0o644 }));
  const zip = path.join(OUT, 'web', `ShootIn-${VERSION}-web.zip`);
  fs.writeFileSync(zip, archive.zipWrite(entries));
  fs.writeFileSync(path.join(OUT, 'web', 'run-local.bat'),
    '@echo off\r\nrem Запускает игру в браузере на этом компьютере: http://localhost:8060/\r\ncd /d "%~dp0site"\r\nstart "" http://localhost:8060/\r\n' +
    'python -m http.server 8060 2>nul || py -m http.server 8060 || (echo Нужен Python 3: https://www.python.org/ & pause)\r\n', 'utf8');
  fs.writeFileSync(path.join(OUT, 'web', 'run-local.sh'),
    '#!/bin/sh\n# Запускает игру в браузере на этом компьютере: http://localhost:8060/\ncd "$(dirname "$0")/site" || exit 1\n' +
    '(command -v xdg-open >/dev/null && xdg-open http://localhost:8060/ || command -v open >/dev/null && open http://localhost:8060/) >/dev/null 2>&1 &\n' +
    'exec python3 -m http.server 8060\n', 'utf8');
  addResult('Web: сайт (zip для itch.io и хостинга)', zip);
  addResult('Web: папка сайта (открывать через run-local)', path.join(site, 'index.html'));
}

// --- итоги -----------------------------------------------------------------------------------

function writeReadme() {
  const exists = (rel) => fs.existsSync(path.join(OUT, rel));
  const mb = (rel) => (exists(rel) ? ' (' + size(path.join(OUT, rel)) + ')' : ' (не собрано)');
  const text = `# ShootIn ${VERSION} — готовые сборки

Эту папку создаёт \`node tools/export/build.js\`. Игрокам отдают файлы из столбца «Что отдать игроку».

| Платформа | Что отдать игроку | Что внутри |
|---|---|---|
| **Windows** (10/11, x64) | \`windows/ShootIn-${VERSION}-Setup.exe\`${mb(`windows/ShootIn-${VERSION}-Setup.exe`)} | графический установщик: сам создаёт папки, ярлыки, запись в «Установке и удалении программ» и деинсталлятор |
| | \`windows/portable/ShootIn.exe\`${mb('windows/portable/ShootIn.exe')} | вся игра одним файлом, PCK встроен — без установки |
| **Linux** (x86_64) | \`linux/ShootIn-${VERSION}-linux-x86_64.tar.gz\`${mb(`linux/ShootIn-${VERSION}-linux-x86_64.tar.gz`)} | \`install.sh\` + игра: установщик сам ставит право на запуск, создаёт папки и ярлыки |
| | \`linux/portable/ShootIn.x86_64\`${mb('linux/portable/ShootIn.x86_64')} | игра одним файлом, PCK встроен (после копирования нужен \`chmod +x\`) |
| **macOS** (Intel и Apple Silicon, 10.12+) | \`macos/ShootIn-${VERSION}-macos.zip\`${mb(`macos/ShootIn-${VERSION}-macos.zip`)} | \`ShootIn.app\` (universal) + \`Install ShootIn.command\` |
| **Web** | \`web/ShootIn-${VERSION}-web.zip\`${mb(`web/ShootIn-${VERSION}-web.zip`)} | сайт: \`index.html\` + wasm; загружается на itch.io или любой хостинг как есть |

\`SHA256SUMS.txt\` — контрольные суммы всех файлов.

## Windows

Двойной клик по \`ShootIn-${VERSION}-Setup.exe\`. Установка в профиль пользователя (\`%LOCALAPPDATA%\\Programs\\ShootIn\`), права администратора не нужны.
Установщик создаёт: папку игры, папку \`mods\` рядом с игрой (сюда кладут моды), папку сохранений и модов (\`%APPDATA%\\Godot\\app_userdata\\ShootIn\`),
ярлыки на рабочем столе и в меню «Пуск», деинсталлятор. Ключи для тихой установки: \`/S /D=папка /NODESKTOP /NOSTARTMENU /LOG=файл\`; удаление — \`Uninstall.exe /S\`.
Файл не подписан сертификатом, поэтому SmartScreen при первом запуске может показать «Windows защитила ваш компьютер» → «Подробнее» → «Выполнить в любом случае».

## Linux

\`\`\`
tar -xzf ShootIn-${VERSION}-linux-x86_64.tar.gz
cd ShootIn-${VERSION}-linux-x86_64
./install.sh            # для себя;  ./install.sh --system — для всех (sudo)
\`\`\`
Права на запуск сохранены внутри архива, поэтому архиватор файловой менеджера (двойной клик → «Распаковать») тоже даёт исполняемые файлы;
если \`install.sh\` не запускается — \`sh install.sh\`. Установщик сам ставит \`chmod +x\` на игру, создаёт папки (игра, \`mods\`, сохранения),
ярлык в меню приложений и на рабочем столе, команду \`shootin\` и \`uninstall.sh\`.

## macOS

Распаковать zip, дважды щёлкнуть **Install ShootIn.command** (при первом запуске: правая кнопка → «Открыть»).
Скрипт копирует игру в «Программы», ставит право на запуск, снимает «карантин» Gatekeeper, подписывает приложение локально и создаёт папку модов.
Приложение не подписано сертификатом Apple Developer и не нотаризовано (это платная программа Apple), поэтому без установщика первый запуск —
правая кнопка → «Открыть».

## Web

Сайт собран без потоков (\`thread_support=false\`), поэтому ему не нужны специальные заголовки сервера — подойдёт любой статический хостинг.
Локально: \`web/run-local.bat\` (Windows) или \`web/run-local.sh\` — запускают сервер на http://localhost:8060/ (нужен Python 3).
Открывать \`index.html\` двойным кликом нельзя: браузеры не дают загружать wasm с \`file://\`.
В браузере моды ставятся кнопкой «Установить из файла…» (окно выбора файла браузера) или по https-ссылке (если сервер мода разрешает CORS);
хранятся они в браузере (IndexedDB) и пропадают при очистке данных сайта. Кнопки «Выход» и «Открыть папку модов» в веб-версии скрыты.

## Как пересобрать

\`\`\`
node tools/export/build.js                  # всё
node tools/export/build.js windows web      # только выбранные платформы
node tools/export/build.js --skip-tests     # без проверки игры на собранном exe
\`\`\`
Нужны Godot 4.3 с шаблонами экспорта (переменная \`GODOT\`), Node.js и \`csc.exe\` из Windows (установщик). Версия — \`config/version\` в \`project.godot\`.
Сборка сама проверяет: PCK встроен (Windows — секция \`pck\`, Linux — метка \`GDPC\`), бинарник Linux — ELF x86-64, macOS-приложение universal и подписано (ad-hoc),
а собранный \`ShootIn.exe\` прогоняется через \`tools/export/smoke_test.gd\`: меню, экран модов, все 34 уровня и установка мода из zip.
Установщик Windows проверяет \`tools/export/test_installer.ps1\` (установка, ярлыки, реестр, запуск, обновление, удаление).

## Что не проверено

Linux- и macOS-сборки собраны и проверены статически (формат файлов, права, скрипты установки на тестовом профиле), но не запускались на настоящих Linux и Mac.
В релизных сборках работают клавиши PageUp/PageDown (переход между уровнями): отключаются константой \`DEBUG_LEVEL_KEYS\` в \`scripts/autoload/game.gd\`.
`;
  fs.writeFileSync(path.join(OUT, 'README.md'), text);
}

function sha256(file) { return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex'); }

function writeSums() {
  const files = [];
  const walk = (dir) => {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      const p = path.join(dir, e.name);
      if (e.isDirectory()) { if (e.name !== 'site') walk(p); } else if (/\.(exe|zip|gz|x86_64)$/.test(e.name)) files.push(p);
    }
  };
  walk(OUT);
  const lines = files.sort().map((f) => sha256(f) + '  ' + path.relative(OUT, f).replace(/\\/g, '/'));
  fs.writeFileSync(path.join(OUT, 'SHA256SUMS.txt'), lines.join('\n') + '\n');
}

function main() {
  if (!fs.existsSync(GODOT)) fail('не найден Godot: ' + GODOT + ' (задайте переменную GODOT)');
  if (!fs.existsSync(path.join(TEMPLATES, 'version.txt'))) fail('не установлены шаблоны экспорта Godot 4.3: ' + TEMPLATES);
  mkdir(OUT);
  mkdir(BUILD);
  fs.writeFileSync(path.join(OUT, '.gdignore'), '');
  fs.writeFileSync(path.join(BUILD, '.gdignore'), '');
  log(`ShootIn ${VERSION}: сборка для ${targets.join(', ')}`);
  step('Импорт ресурсов');
  writePresets('');
  godot(['--import'], { quiet: true, allowFail: true });
  try {
    if (targets.includes('windows')) buildWindows();
    if (targets.includes('linux')) buildLinux();
    if (targets.includes('macos')) buildMac();
    if (targets.includes('web')) buildWeb();
  } finally {
    writePresets('');  // в проекте остаются чистые пресеты без путей к временным файлам
  }
  writeReadme();
  writeSums();
  step('Готово');
  for (const r of results) log(`  ${r.label}\n    ${path.relative(ROOT, r.file)}  (${size(r.file)})`);
  if (warnings.length) { log('\nПредупреждения:'); for (const w of warnings) log('  - ' + w); }
}

main();

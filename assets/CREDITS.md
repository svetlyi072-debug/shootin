# Графика: авторы и лицензии

Вся графика в этой папке — бесплатная. Почти везде это лицензия **CC0 1.0** (общественное достояние):
её можно использовать, менять и распространять, в том числе в коммерческих проектах.
Указывать авторов не обязательно, но приятно — поэтому они перечислены здесь.

| Папка | Набор | Автор | Источник | Лицензия |
|---|---|---|---|---|
| `pixel_adventure/` | Pixel Adventure 1 | Pixel Frog | https://pixelfrog-assets.itch.io/pixel-adventure-1 | CC0 |
| `monsters_creatures_fantasy/` | Monsters Creatures Fantasy (вкл. версии 1.2 и 1.3) | LuizMelo | https://luizmelo.itch.io/monsters-creatures-fantasy | CC0 |
| `monsters_creatures_fantasy_2/` | Monsters Creatures Fantasy 2 | LuizMelo | https://luizmelo.itch.io/monsters-creatures-fantasy-2 | CC0 |
| `fire_worm/` | Fire Worm | LuizMelo | https://luizmelo.itch.io/fire-worm | CC0 |
| `zombie/` | Medieval King Pack 2 и Hero Knight, **перекрашены** (`tools/make_zombies.gd`; оригиналы лежат в `design/source/luizmelo/`) | LuizMelo | https://luizmelo.itch.io/medieval-king-pack-2, https://luizmelo.itch.io/hero-knight | CC0 |
| `evil_wizard_2/` | Evil Wizard 2 | LuizMelo | https://luizmelo.itch.io/evil-wizard-2 | CC0 |
| `slime/` | Animated Pixel Slime | rvros | https://rvros.itch.io/pixel-art-animated-slime | CC0 |

Что откуда взято:
- **Шуткин** — персонаж «Virtual Guy» из Pixel Adventure (в `heroes/` лежат и три других героя
  набора: Ninja Frog, Mask Dude, Pink Man — их можно подставить).
- Блоки (`terrain.png`), сквозные платформы, шипы, флаг-выход, яблоко-аптечка, фоны
  и пыль ударной волны босса (`dust.png`) — Pixel Adventure.
- **Пила, шипастый шар, огненная ловушка и батут** — из того же Pixel Adventure (папка Traps),
  лежат в `pixel_adventure/traps/`.
- **Скелет**, **гоблин** (и его бомба), **грибник** (и его споры) — Monsters Creatures Fantasy.
  Из этого же набора: **Костяной рыцарь** (скелет, увеличенный и перекрашенный, его брошенный меч),
  **Король-гриб** (грибник, увеличенный и перекрашенный), **Око бездны** (летающий глаз и его заряды —
  те же заряды использует Тёмный колдун).
- **Летучая мышь**, **крыса** и **мимик** — Monsters Creatures Fantasy 2.
- **Огненный червь** и огненный шар — Fire Worm. **Тёмный колдун** — Evil Wizard 2.
- **Слизняк** и **Древний слизень** (тот же слизень, увеличенный и перекрашенный) — Animated Pixel Slime.

- **Зомби, могильные зомби и Король зомби** — Medieval King Pack 2, **Зомби-рыцарь** — Hero Knight
  (оба LuizMelo, CC0; того же автора, что скелет, гоблин, грибник и колдун в игре). Спрайты
  перекрашены скриптом `tools/make_zombies.gd` (зелёная кожа, лохмотья, ржавая броня), лежат в `zombie/`.
  Могильные зомби «встают из земли» — это кадры смерти, проигранные наоборот.
- **Панцирник**, **Царь-Панцирь**, падающий камень и облако пыли — картинки, **сгенерированные нейросетью**
  по промптам из `design/shellback_prompts.md` (исходные полосы — `design/source/`, готовые кадры —
  `shellback/`). Автор запросов — владелец проекта; условия использования определяются сервисом,
  которым картинки сгенерированы, — при публикации игры проверьте их.

Имена файлов (кроме папки `shellback/`) переименованы в латиницу без пробелов, сами изображения не изменены.
SpriteFrames-ресурсы в `frames/` собраны из этих картинок скриптом `tools/build_sprite_frames.gd`.

Примеры модов (`mods/frost_crypt/sprites/`, `mods/vampire_rage/sprites/`, `mods/_template/sprites/`) — перекрашенные
спрайты зомби из LuizMelo (Medieval King Pack 2 и Hero Knight, CC0), см. выше.

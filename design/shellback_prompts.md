# Панцирник и Царь-Панцирь: концепт и промпты для генерации картинок

Папка `design/` Godot не сканирует (там лежит пустой `.gdignore`). Это заметки для художника.

## 1. Кто это

**Панцирник** (Shellback) — пещерная мокрица-броненосец размером с крупную собаку. Спина — каменный
панцирь из 7 пластин с короткими шипами-«заклёпками», брюхо и лапки мягкие, рыжие. Ходит враскачку,
а заметив игрока, сворачивается в шар и катится на него. Свёрнутого его не пробить пулей, но на
стене он разбивается о камень, разворачивается и сидит оглушённый.

**Царь-Панцирь** (Shellback King) — тот самый Панцирник, только гигантский и древний: панцирь из
9 тёмных плит, вдоль хребта растёт корона из пяти бирюзовых кристаллов, между плитами светятся
бирюзовые трещины, голова в каменной маске с рогами-жвалами. Катится через всю арену, в стену
врезается кристаллами и падает на спину: на брюхе светится слабое место.

Цвета подобраны так, чтобы не путаться с остальными боссами: у Огненного червя тёплая охра,
у Царя-Панциря холодный серо-синий камень и бирюзовые кристаллы.

### Как это ляжет в игру (для справки, не нужно для генерации)

| | Панцирник | Царь-Панцирь |
|---|---|---|
| Кадр | 64×64 px, в игре масштаб ≈ 1,2 | 128×128 px, в игре масштаб ≈ 1,6 |
| HP / награда | 30 HP, +12 силы | 320 HP (на умной сложности больше) |
| Состояния | IDLE, WALK, CURL, ROLL, DIZZY, HURT, DEAD | IDLE, WALK, WINDUP, ROLL, STOMP, DIZZY, HURT, DEAD |
| Ход боя | ходит 2 кл/с; заметил игрока в 6 клетках, дрожит 0,5 с (CURL) и катится 9 кл/с (контакт 12 урона) до стены; ударился — DIZZY 1,5 с, тогда он уязвим вдвое сильнее; свёрнутый получает почти ноль урона | катится через арену (25 урона), в стену врезается — падает на спину (DIZZY 2,5 с, бей в светящийся кристалл на брюхе, урон ×2); топает (STOMP) — сверху сыплются камни; зовёт трёх Панцирников; на половине здоровья катится туда и обратно без паузы |

Когда картинки будут готовы, положите их в `assets/shellback/` (названия в разделе 6) и скажите мне:
я соберу SpriteFrames, сделаю сцены, ИИ врага и боя с боссом и новый уровень-арену.

---

## 2. Как пользоваться промптами

1. Каждый промпт — это **[СТИЛЬ] + [ПАЛИТРА] + [ГЕОМЕТРИЯ] + текст самого промпта** (блоки из раздела 3).
   Вставляйте их друг за другом. Блок [НЕГАТИВ] кладите в поле Negative prompt, если оно есть.
2. Нейросети не умеют считать пиксели. Просите картинку **в 8 раз больше**: 64 px → 512 px,
   128 px → 1024 px, с «жирными» пикселями. Потом уменьшайте до нужного размера
   **методом ближайшего соседа** (Nearest Neighbor, в Aseprite или Photoshop; без сглаживания).
3. Сначала сделайте листы-образцы (промпты 1 и 5): они фиксируют внешний вид. Дальше подавайте
   этот лист в генератор как **референс** (image reference / image-to-image, сила 0,6–0,8) вместе
   с промптом полосы анимации, иначе персонаж будет «плыть» от кадра к кадру.
4. Если нейросеть не умеет прозрачность, просите фон ровного цвета `#FF00FF` (маджента) и вырежьте
   его (волшебная палочка с допуском 0).
5. Полоса из 8 кадров за один раз обычно выходит хуже, чем кадры по отдельности. Если вышло криво,
   генерируйте по 1–2 кадра с тем же референсом и собирайте полосу руками.
6. Проверка результата: после уменьшения должно остаться не больше 22 цветов палитры, обводка везде
   ровно в 1 пиксель, ноги стоят на нужной строке. Лишние цвета можно заменить на ближайшие из палитры.

---

## 3. Общие блоки (вставлять в каждый промпт)

### [СТИЛЬ]

```
Pixel art game sprite, strict side view (pure profile), the creature faces RIGHT. Retro 16-bit
platformer style in the spirit of Pixel Adventure and Monsters Creatures Fantasy: chunky, readable
shapes, a ONE-pixel dark outline (#1B1426) around the whole silhouette, flat cel shading with exactly
three tones per material plus one highlight tone, light coming from the TOP-LEFT. No anti-aliasing,
no gradients, no dithering, no blur, no glow halos, no soft shadows, no cast shadow, no ground line,
no scenery. Every pixel is a hard-edged square of exactly one palette color. Transparent background
(if transparency is impossible: flat #FF00FF magenta). Strict pixel grid: the final art has exactly
the frame size stated below and the creature's feet rest on the stated ground row. The art is drawn
at 8x scale (each art pixel is an 8x8 block of identical color) so that downscaling by 8 with
nearest-neighbor gives the exact pixel art.
```

### [ПАЛИТРА] (использовать только эти цвета)

```
PALETTE, use ONLY these colors:
OUTLINE   #1B1426  (1 px outline, deepest shadows, pupils)
STONE_D   #34405F  (shell shadow side)
STONE_M   #55648F  (shell base)
STONE_L   #8796C2  (shell lit side)
STONE_HL  #C9D4F0  (shell glints, 1-2 px)
SEAM      #262E4A  (gaps between shell plates, cracks)
SKIN_D    #7A3F26  (legs, belly shadow)
SKIN_M    #BF7539  (head, legs, belly base)
SKIN_L    #E8A95A  (head and belly highlight)
EYE       #FFD23F  (eyes)
EYE_BOSS  #FF4A3A  (boss eyes, ring around the amber core)
WHITE     #FFFFFF  (eye glints, hit flash)
FLASH     #F4F6FF  (whole-body hit flash)
MOSS_D    #3F6B2C  (moss shadow)
MOSS_L    #8CC152  (moss light)
CRYSTAL_D #1F7A8C  (crystal shadow facet)
CRYSTAL_M #3DC9D9  (crystal base facet)
CRYSTAL_L #B8F5F2  (crystal lit facet and sparkle)
DUST_L    #D9D2C3  (dust and rock debris light)
DUST_M    #A9A190  (dust mid)
DUST_D    #7A7466  (dust dark)
SPARK     #FFE066  (dizzy stars)
```

### [НЕГАТИВ] (Negative prompt)

```
photo, photorealistic, 3D render, vector art, smooth shading, anti-aliased edges, blurry, gradient,
painterly, watercolor, isometric, top-down view, front view, three-quarter view, outlines of varying
thickness, colored outline, text, letters, watermark, signature, UI, grid lines, floor, ground shadow,
background scenery, extra legs, extra eyes, human face, cute chibi face with big sparkly eyes, fur,
feathers, wings, tail with spikes, additional colors outside the palette, JPEG artifacts
```

### [ГЕОМЕТРИЯ ПАНЦИРНИКА] (для промптов 1–4)

Все координаты считаются в пикселях кадра 64×64: x вправо от 0, y вниз от 0. Существо смотрит
вправо. Нижняя строка стоящих ног — **y = 59** (строки 60–63 пустые).

```
SHELLBACK GEOMETRY (frame 64x64, x to the right 0..63, y downwards 0..63, creature faces right,
the feet baseline is row y=59, rows 60-63 are empty).

Standing pose, the whole body is a low armoured dome (like a pill bug / woodlouse).
SHELL silhouette including its 1 px outline, x-range per row:
y30: 24-33   y31: 20-37   y32: 17-40   y33: 15-42   y34: 13-44   y35: 12-45   y36: 11-46
y37-39: 10-47   y40-43: 9-48   y44-50: 8-49   y51: 9-48   y52: 11-46 (flat bottom edge of the shell).
So the shell is 42 px long and 23 px tall.
SHELL surface: base STONE_M. A 2 px thick STONE_L band follows the upper-left curve of the dome.
Four isolated STONE_HL glints (2x1 px) on that lit band. A 3 px thick STONE_D band follows the lower-right
curve. Seven armour plates: six 1 px SEAM lines run from the ridge down the side of the shell, each
curving 2 px backwards (to the left) towards the bottom, at x = 14, 19, 25, 31, 37, 43 measured on the
ridge line. Four stone studs (small triangles, 3 px wide and 3 px tall, STONE_L left half and STONE_D
right half, 1 px outline) sit on the ridge at x = 20, 27, 35, 42, each one on the dome outline and
pointing straight up, so they add 3 px above the dome line. Two moss patches: 4x4 px at
(22,35) and 3x5 px at (11,44), mostly MOSS_D with a few MOSS_L pixels.
HEAD (soft, not armoured): a rounded 11x11 px block at x47-57, y42-52 with the corners cut by one pixel,
partly in front of the shell's front edge. Base SKIN_M, SKIN_L highlight 2 px on the forehead
(x49-50, y43), SKIN_D shade on the bottom row y51 and on the jaw. EYE: a 3x3 px square at x52-54,
y45-47 colored EYE, pupil = one OUTLINE pixel at (54,46), one WHITE glint pixel at (52,45). Mouth: 3 px SEAM line at
x54-56, y50, with two 1 px mandible ticks at (57,49) and (57,51). Antennae: the near one is a 1 px line
from (53,41) up-right to (56,37) with a 2x2 px SKIN_L bulb at (56-57,36-37); the far one is a 1 px SKIN_D
line from (50,41) to (52,37) with a 2x2 px SKIN_D bulb at (52-53,36-37).
LEGS: seven pairs, side view shows four near legs and three far legs. Near legs at x = 14, 22, 30, 38
(each 3 px wide): upper segment 3x3 px at y53-55 in SKIN_M, lower segment 2x4 px at y56-59 in SKIN_D with
a 1 px foot pointing forwards at y59 (so the foot is 3 px wide). Far legs at x = 18, 26, 34 (2 px wide,
y53-58), all SKIN_D, partly hidden behind the near legs. Two small SKIN_M tail nubs, 2x2 px each, at the
rear: x6-7 y47-48 and x6-7 y50-51.
Everything not listed is transparent.

BALL pose (rolled up): a perfect circle, center (32,42), radius 17 (x15-49, y25-59), 1 px outline,
shaded like the shell (STONE_L upper-left band, STONE_D lower-right band, glints). Eight meridian SEAM
arcs divide it into eight bands (a segmented ball, like an orange), eight studs of 3 px height stand
around the circle every 45 degrees (the bottom one is flattened to 1 px because it touches the ground).
No head, no legs, no antennae visible. A 2 px dark OUTLINE slit at the lower right (x45-47, y52-53)
where the head is tucked in.
```

### [ГЕОМЕТРИЯ ЦАРЯ-ПАНЦИРЯ] (для промптов 5–8)

Кадр 128×128, ноги стоят на строке **y = 124**.

```
SHELLBACK KING GEOMETRY (frame 128x128, x to the right 0..127, y downwards 0..127, the creature faces
right, the feet baseline is row y=124, rows 125-127 are empty). It is the same species as the small
Shellback but gigantic, ancient and heavier: darker stone, nine plates, a crown of crystals.

Standing pose. SHELL silhouette including outline, x-range per row:
y44: 48-70   y46: 40-78   y48: 34-84   y50: 30-88   y52: 26-92   y56: 22-96   y60: 19-99   y64: 17-101
y70: 15-103   y76: 13-105   y84-100: 11-107   y104: 12-106   y108: 16-102 (flat bottom edge of the shell).
So the shell is 97 px long and 65 px tall.
SHELL surface: base STONE_D (it is darker than the small one), STONE_M as the main lit tone,
STONE_L as a 4 px thick band along the upper-left curve, STONE_HL glints (3x1 px, eight of them),
and a 5 px thick OUTLINE-colored shadow band along the lower-right curve. Nine armour plates:
eight 2 px SEAM lines run from the ridge down the side, each curving 5 px backwards (left) towards the
bottom, at x = 24, 33, 42, 51, 60, 69, 78, 87 measured on the ridge line. In every seam glows a
1 px CRYSTAL_M crack (a 1 px line of light inside the 2 px SEAM line, with CRYSTAL_L dots every 8 px).
Old battle scars: three diagonal 1 px STONE_L scratches 6-9 px long, one deep chip (4x4 px notch
with STONE_M interior) at the rear upper left (x24-27, y66-69). Moss on the rear plates only:
two patches of about 5x3 px, MOSS_D with MOSS_L pixels.
CRYSTAL CROWN: five crystals rise from the ridge at x = 36, 48, 60, 72, 84, with heights above the
dome line 14, 20, 26, 20, 14 px. Each crystal is a tall hexagonal prism 6-8 px wide with a pointed top,
leaning 1 px outward from the centre one: left facet CRYSTAL_L, right facet CRYSTAL_M, a CRYSTAL_D
base row and a 1 px WHITE sparkle near the top of the left facet. Every crystal stands in a stone
socket (a STONE_M ring 10 px wide, 4 px tall, outlined) sunk into the shell.
HEAD (armoured mask): a block 26 px wide and 28 px tall at x100-125, y80-107, partly in front of the
shell's front edge. A STONE_M helmet-mask covers the top and the sides (with STONE_L highlight on the
forehead and a SEAM line running from brow to cheek), a SKIN_M soft muzzle under it. Two curved stone
horn-mandibles, each 5 px wide and 12 px long, curve forward and down from the jaw at x118-127,
y96-108 (STONE_M with STONE_L tips). EYE: 6x6 px at x108-113, y88-93, ring EYE_BOSS, a 2x2 EYE core in the
middle, one WHITE glint pixel, and a heavy OUTLINE brow 2 px thick slanting down towards the front above
it (angry). Two antennae: 2 px thick, 14 px long, SKIN_D, ending in 3x3 px SKIN_L bulbs, rising from the
top of the head at x108 and x114.
LEGS: seven pairs; the side view shows four near legs and three far legs. Near legs at x = 26, 44, 62, 80
(each 7 px wide): upper segment 7x8 px at y109-116 SKIN_M with a 7x3 px STONE_M knee guard on top,
lower segment 5x8 px at y117-124 SKIN_D with a foot that is 9 px wide at y123-124. Far legs at x = 35, 53,
71 (5 px wide, y109-122), all SKIN_D, partly hidden. Two heavy tail nubs 5x4 px at the rear, x6-10, y92-95
and y99-102, SKIN_M.

BALL pose: a circle, center (64,78), radius 46 (x18-110, y32-124), 1 px outline, shaded like the
shell, STONE_D base. Eight meridian SEAM arcs with glowing CRYSTAL_M cracks, and eight crystal spikes
radiating from the circle every 45 degrees, each 12 px long (the bottom one hidden). No head, no legs.

DIZZY pose (knocked onto its back): the shell dome rests on the ground, rocking, the pale BELLY
faces the sky. Belly = seven curved horizontal plates in SKIN_M/SKIN_L separated by SKIN_D lines,
fourteen legs (SKIN_M with SKIN_D) sticking up and waving, the head turned up at the right.
In the centre of the belly sits the WEAK POINT: a diamond crystal 12x12 px, CRYSTAL_M with CRYSTAL_L
top-left facet and CRYSTAL_D bottom-right facet and a 1 px WHITE sparkle, in a SKIN_D socket.
```

---

## 4. Промпты Панцирника (маленький враг), кадр 64×64

### Промпт 1. Лист-образец Панцирника (три позы)

Холст 192×64 (в 8× это 1536×512): три кадра по 64×64 рядом: ходьба, полусвёрнутый, шар.

```
[СТИЛЬ] + [ПАЛИТРА] + [ГЕОМЕТРИЯ ПАНЦИРНИКА]

TASK: a character design reference sheet of the small enemy "Shellback", a cave pill-bug armoured with
a stone shell. Canvas 192x64 pixels (drawn at 8x: 1536x512), three frames of 64x64 side by side with no
gaps, the frame borders are invisible. Same creature in all three frames, same palette, same lighting.

Frame 1 (x0-63): STANDING pose exactly as described in the geometry block: dome shell 42x23 px, head with
one amber eye and two antennae at the front, seven pairs of short rusty legs, four stone studs along the
ridge, moss patches. Neutral calm face. The four near legs are planted: feet on row y=59.

Frame 2 (x64-127): HALF-CURLED pose, the creature is mid-transformation. The shell bends into a C shape:
the rear of the shell has lifted and rolled forward, the body is 36 px long and 32 px tall, tilted 15
degrees so the front goes down. The head is pulled under the front plate, only the top of the head with
the angry brow line (a 3 px diagonal OUTLINE stroke over the eye) and one amber eye is visible; the legs
are folded into 2 px stubs. The studs follow the curve and stand perpendicular to the shell. Lowest
point of the body touches y=59.

Frame 3 (x128-191): fully rolled BALL as in the geometry block, a segmented sphere of radius 17 with eight
studs and the tiny dark slit where the head is tucked in. The sphere touches the ground at y=59.

Every frame: 1 px OUTLINE around the silhouette, three-tone stone shading with the lit band at the
upper left, STONE_HL glints, SKIN_M soft parts. Crisp hard pixels, no anti-aliasing.
```

### Промпт 2. Панцирник: ходьба (6 кадров) и удар (2 кадра)

Холст 512×64 (8× → 4096×512): 8 кадров 64×64. Кадры 1–6 это цикл ходьбы, 7–8 это реакция на удар.

```
[СТИЛЬ] + [ПАЛИТРА] + [ГЕОМЕТРИЯ ПАНЦИРНИКА]
Use the attached reference sheet for the exact look of the creature.

TASK: sprite strip of the small Shellback, canvas 512x64 px (drawn at 8x: 4096x512), eight frames of
64x64 px side by side without gaps; frame k occupies x = 64(k-1) .. 64k-1. Every frame: the creature faces
right, the shell's rear is at x≈8 and the head's front at x≈57 of its frame, the feet baseline is row
y=59. The shell, studs, moss and plate seams are identical in every frame (only the body height
offset changes, the shell never changes shape).

FRAMES 1-6, WALK CYCLE (leg groups: A = near legs 1 and 3 plus far leg 2; B = near legs 2 and 4 plus far legs 1
and 3). The body moves as a whole by "dy" pixels (negative = up) and the head follows it:
Frame 1, contact: dy 0. Group A planted, feet 2 px forward of their rest position. Group B planted, feet 2 px
 behind rest. Antennae straight, tips at rest.
Frame 2, push: dy -1. Group A planted at rest position, pushing. Group B lifting: feet raised 2 px (y57),
 1 px back of rest. Near antenna tip 1 px higher.
Frame 3, swing: dy 0. Group A planted 2 px behind rest. Group B swinging forward, feet raised 3 px (y56) and
 1 px ahead of rest. Antennae tips back to rest.
Frame 4, contact (mirror of 1): dy 0. Group B planted 2 px forward, group A planted 2 px behind rest.
Frame 5, push: dy -1. Group B planted at rest, group A lifting 2 px and swinging forward.
Frame 6, swing: dy 0. Group B planted behind, group A swinging forward, feet raised 3 px. This frame leads
 back into frame 1 without a visible jump. The near antenna tip is 1 px lower than rest in frames 4 and 5.

FRAMES 7-8, HURT:
Frame 7: the whole creature is pushed 2 px to the left and flashes: every non-outline pixel becomes FLASH
 (#F4F6FF) except the eye (2x2 px OUTLINE squeezed shut, shaped like a ">" mark) and the OUTLINE itself.
 The legs are straightened, feet 1 px off the ground.
Frame 8: recoil, normal colors. The head is retracted by 5 px so only 6 px of the head show in front of
 the shell, the rear of the shell is lowered by 2 px so the shell tilts 5 degrees backwards (rear
 lower), antennae flat (lying back, 1 px lines), eye squeezed shut (">" shape). Feet planted on y=59.

No motion blur, no speed lines, no shadows. Everything unchanged between frames must be pixel-identical.
```

### Промпт 3. Панцирник: сворачивание (4 кадра) и качение (4 кадра)

```
[СТИЛЬ] + [ПАЛИТРА] + [ГЕОМЕТРИЯ ПАНЦИРНИКА]
Use the attached reference sheet for the exact look of the creature.

TASK: sprite strip, canvas 512x64 px (drawn at 8x: 4096x512), eight frames of 64x64 px side by side without
gaps. Frame k occupies x = 64(k-1) .. 64k-1. The creature faces right. The lowest pixel of the body
touches row y=59 in every frame.

FRAMES 1-4, CURLING UP (anticipation, then closing):
Frame 1, shiver: the creature squats: dome apex lowered to y=32 (the shell is 2 px flatter), legs bent
 outwards (knees 2 px wider), eye narrowed with an angry brow (3 px diagonal OUTLINE stroke above the
 eye), mouth open 3 px (SEAM). The whole sprite is shifted 1 px to the right (the shiver; drawn as a
 plain 1 px offset, not a blur).
Frame 2, tuck: the sprite is shifted 1 px to the LEFT (shiver). Head pulled back 6 px under the front plate (only
 the top of the head and the eye are visible), antennae folded flat, legs reduced to 2 px stubs, body
 shortened to 40 px, tilted 8 degrees forward (front lower).
Frame 3, half-curl: C-shape, 36 px long and 32 px tall, tilted 15 degrees so the front goes down; head fully
 hidden, only the dark slit at the front; studs perpendicular to the shell; legs gone.
Frame 4, closed: perfect ball, circle center (32,42), radius 17, eight studs, tiny dark slit at the lower
 right, meridian SEAM arcs as in the geometry block (stud at the top exactly at 12 o'clock).

FRAMES 5-8, ROLLING LOOP (the ball spins CLOCKWISE; the pattern repeats every 45 degrees, so four frames
 rotated by 11.25 degrees each close the loop seamlessly):
Frame 5: pattern rotated 0 degrees (stud at 12 o'clock). Behind the ball (to the left, on the ground, x8-14,
 y56-59) a small dust puff of 6 DUST_M pixels with 2 DUST_L pixels.
Frame 6: rotated 11.25 degrees clockwise (studs and seams shifted along the circle by about 3.3 px). The dust puff
 is 1 px further left and a bit higher (y54-58), 5 pixels.
Frame 7: rotated 22.5 degrees. A new smaller puff appears at x10-15, y56-59 (4 pixels), the old one has
 dissolved into three DUST_D pixels at x4-6, y52-55.
Frame 8: rotated 33.75 degrees. The puff at x8-13, y55-59 (6 pixels, DUST_M and DUST_L).
In frames 5-8 the ball is drawn exactly 1 px lower on the ground in every frame with the studs as the
only changing silhouette parts; the highlight band stays at the upper left (light does not rotate with the
ball). The ball sprite is the same size in all four frames.

No motion blur, no speed lines.
```

### Промпт 4. Панцирник: оглушение (2 кадра) и смерть (6 кадров)

```
[СТИЛЬ] + [ПАЛИТРА] + [ГЕОМЕТРИЯ ПАНЦИРНИКА]
Use the attached reference sheet for the exact look of the creature.

TASK: sprite strip, canvas 512x64 px (drawn at 8x: 4096x512), eight frames of 64x64 px side by side without
gaps. Frame k occupies x = 64(k-1) .. 64k-1. The creature faces right; the feet / lowest pixels rest on row
y=59.

FRAMES 1-2, DIZZY (it has just crashed into a wall, uncurled and is stunned):
Standing pose from the geometry block, but: the head hangs down 3 px (head block at y45-55, drooping),
antennae limp (lying back along the head, 1 px lines); the eye is a 3x3 px spiral drawn as an
OUTLINE ring with a EYE center pixel; the legs are splayed apart, the feet 3 px wider; the shell is
tilted back 4 degrees. Three SPARK (#FFE066) stars, each a 3x3 px plus sign with a WHITE center pixel,
orbit above the head around the point (46,26) with a radius of 9 px.
Frame 1: stars at angles 90, 210 and 330 degrees. Frame 2: the same stars rotated 60 degrees, the eye
spiral flipped (center pixel in the opposite quadrant), body 1 px lower.

FRAMES 3-8, DEATH:
Frame 3: hit flash: the whole creature in FLASH (#F4F6FF) with the OUTLINE kept, mouth open, the eye is a
 ">" squeeze, pushed back 2 px.
Frame 4: the shell cracks: normal colors, a jagged 1 px WHITE crack runs from the top of the dome at
 x=28 down to x=34 at the shell's lower edge, two small STONE_L chips (3x3 px) fly off to the upper right
 (x40, y22 and x46, y26). The head and legs drop 1 px.
Frame 5: the shell splits along the crack: the left half tilts 12 degrees to the left and sits 3 px lower,
 the right half tilts 12 degrees to the right, a 4 px gap between them shows the SKIN_M soft body inside
 (SKIN_L top highlight). Studs hang on the halves. Four chips in the air above.
Frame 6: the halves tip out to 25 degrees and drop another 4 px; the soft body slumps: the legs are
 curling inwards, the eye is an "x" (two 1 px diagonal OUTLINE strokes), the antennae are limp.
Frame 7: the halves lie on their sides next to each other (each a half-dome 20 px wide, 11 px tall lying
 flat, cut side up toward the sky), the soft body lies on its back between them, belly SKIN_L, seven
 curled legs (SKIN_D) pointing upward, "x" eye. Everything is lower than 24 px tall.
Frame 8: the final resting pile, identical to frame 7 but with the legs curled further in (2 px shorter)
 and four resting stone chips (2-3 px, STONE_M and STONE_D) scattered on the ground at both sides, the
 antennae flat. This frame is the one that stays on screen as the corpse. All of the pile stays inside rows
 y38-59.
No motion blur, no extra effects other than the described chips and stars.
```

---

## 5. Промпты Царя-Панциря (босс), кадр 128×128

### Промпт 5. Лист-образец Царя-Панциря (три позы)

Холст 384×128 (в 8× это 3072×1024).

```
[СТИЛЬ] + [ПАЛИТРА] + [ГЕОМЕТРИЯ ЦАРЯ-ПАНЦИРЯ]
Frame size for this prompt is 128x128 px (1024x1024 px at 8x scale).

TASK: a character design reference sheet of the boss "Shellback King", a gigantic ancient cave pill-bug
in dark stone armour with a crown of five cyan crystals. Canvas 384x128 pixels (drawn at 8x: 3072x1024),
three frames of 128x128 side by side without gaps, invisible frame borders. Same creature, palette and
lighting in all frames.

Frame 1 (x0-127): STANDING pose exactly as in the geometry block: dome shell 97 px long and 65 px tall in dark
STONE_D/STONE_M, nine plates with thin glowing cyan cracks in the seams, the crown of five crystals (the
middle one tallest at 26 px), scarred and mossy at the rear, the armoured head-mask with horn-mandibles
and an angry red-ringed amber eye at the front, thick SKIN_M legs with stone knee guards, two long
antennae. Menacing, heavy, calm.

Frame 2 (x128-255): BALL pose: circle center (64,78) radius 46, nine glowing cyan cracks wrapping around the
sphere like meridians, eight crystal spikes 12 px long radiating from the circle. The ball touches the
ground at y=124. The lit band on the upper left, a tiny dark slit where the head is tucked in.

Frame 3 (x256-383): DIZZY pose, knocked onto its back as described in the geometry block: dome shell rocking on
the ground, the pale belly with seven plates facing the sky, fourteen legs sticking up, the head turned
to the right with a swirl eye, and the glowing diamond WEAK POINT crystal (12x12 px) in the middle of the
belly. The crown crystals are squashed against the ground below the shell (just 6 px of them show at the
bottom edge).

1 px OUTLINE everywhere, hard pixels, no anti-aliasing, no gradients.
```

### Промпт 6. Царь-Панцирь: покой (4 кадра) и ходьба (4 кадра)

Холст 1024×128 (в 8× → 8192×1024): 8 кадров по 128×128.

```
[СТИЛЬ] + [ПАЛИТРА] + [ГЕОМЕТРИЯ ЦАРЯ-ПАНЦИРЯ]
Frame size is 128x128 (1024x1024 at 8x). Use the attached reference sheet for the exact look.

TASK: sprite strip, canvas 1024x128 px (drawn at 8x: 8192x1024), eight frames of 128x128 side by side without
gaps; frame k occupies x = 128(k-1) .. 128k-1. The King faces right. In every frame the feet baseline is
row y=124. The shell, plates, scratches and crystal crown are pixel-identical in all frames except for the
changes listed (the shell never changes shape, the body moves as a whole by dy).

FRAMES 1-4, IDLE (breathing, 4 frames):
Frame 1: standing pose, dy 0. A WHITE sparkle pixel (1 px) on the left facet of the first crystal (x=36).
Frame 2: dy -1 (inhale, the whole shell and head rise 1 px; the legs stay planted). Sparkle moves to the
 second crystal (x=48). Antennae tips 1 px higher.
Frame 3: dy -2 (top of the breath). Sparkle on the third crystal (x=60), a second tiny sparkle on the fifth.
 Cracks between plates are brighter: add CRYSTAL_L dots every 4 px instead of 8.
Frame 4: dy -1 (exhale), the eye is closed (a 6 px OUTLINE line instead of the eye, a blink). Sparkle on
 the fourth crystal (x=72). Antennae tips back to rest.

FRAMES 5-8, WALK (slow, heavy, 4 frames; leg groups A = near legs 1 and 3 plus far leg 2, B = near legs 2
and 4 plus far legs 1 and 3). The legs of the King are large (7 px wide), a step is about 6 px:
Frame 5, contact: dy 0. Group A planted 5 px forward of rest, group B planted 5 px behind rest.
Frame 6, passing: dy -3 (the heavy body rises while the legs pass). Group A pushes (at rest position),
 group B lifted 5 px and moving forward (1 px ahead of rest). The crown sways: all crystals lean 1 px to
 the right (the tops shift by 1 px, the sockets stay).
Frame 7, contact (mirror): dy 0. Group B planted 5 px forward, group A planted 5 px behind rest. The
 crystals lean back to vertical.
Frame 8, passing: dy -3. Group B pushes, group A lifted 5 px and swinging forward. Crystals lean 1 px to the
 right again. This frame loops into frame 5.
During the walk the red eye ring stays steady and the head bobs together with the body.
No motion blur, no dust, no shadow.
```

### Промпт 7. Царь-Панцирь: замах (2 кадра), качение (4 кадра), топот (2 кадра)

```
[СТИЛЬ] + [ПАЛИТРА] + [ГЕОМЕТРИЯ ЦАРЯ-ПАНЦИРЯ]
Frame size is 128x128 (1024x1024 at 8x). Use the attached reference sheet for the exact look.

TASK: sprite strip, canvas 1024x128 px (drawn at 8x: 8192x1024), eight frames of 128x128 px side by side without
gaps. Frame k occupies x = 128(k-1) .. 128k-1. The King faces right.

FRAMES 1-2, WINDUP (it is about to roll; this must be a clear warning for the player):
Frame 1: the body squats 6 px (dy +6, the shell is 6 px flatter at the top: apex y=50), the legs are bent
 and splayed 6 px wider, the head is pushed forward and down 4 px, the eye ring is brighter (EYE_BOSS ring
 2 px thick), all five crystals glow: every crystal's facets are one tone lighter and 3 CRYSTAL_L
 sparkle pixels float above each crystal (x±4, y-4..-8). The seam cracks glow brighter: CRYSTAL_L dots every
 3 px. The whole sprite is shifted 2 px to the left (shiver).
Frame 2: dy +8, shifted 2 px to the RIGHT (shiver), the head is tucking under the front plate (only the helmet
 top and the angry eye remain visible), the legs are drawn in, the crystals flash CRYSTAL_L almost white,
 six sparkles above them, a few DUST_M pixels (6) kicked up around the feet at y118-123.
 
FRAMES 3-6, ROLL LOOP (ball spinning CLOCKWISE; the pattern repeats every 45 degrees, so four frames at
 11.25 degrees close the loop; this is the same ball as in the reference sheet, radius 46, center (64,78),
 bottom touching y=124):
Frame 3: rotation 0 (a crystal spike at 12 o'clock). Dust trailing behind the ball at x6-20, y112-124:
 about 20 pixels of DUST_M with 6 DUST_L and 4 DUST_D.
Frame 4: rotation 11.25 degrees; dust at x4-18, y108-124 (the cloud grows and rises).
Frame 5: rotation 22.5 degrees; dust at x2-16, y110-124 with a bigger gap.
Frame 6: rotation 33.75 degrees; dust at x4-18, y112-124 (new puff). Loops into frame 3.
The lit band stays at the upper left of the ball (light does not rotate), the glowing cracks rotate with the
ball. A faint CRYSTAL_L glint on the tip of each spike.

FRAMES 7-8, STOMP (the King rears up and slams the front half down; rocks fall from the ceiling):
Frame 7, rear up: the front of the body rises, the shell is tilted 14 degrees backwards (rear lower), the head is up
 and the mandibles are open, the two front pairs of legs are lifted 12 px off the ground, the rear
 legs bear all the weight (feet at y124), the crown tilts with the shell.
Frame 8, slam: the front slams down: body dy +4, the shell is level again, the front legs planted wide,
 mandibles closed. On the ground in front of the King (x95-127, y121-127) three jagged SEAM-colored 1 px
 crack lines run away from the feet, plus a ring of 8 DUST_L and DUST_M pixels (dust cloud, 3-4 px puffs) at the
 impact and 6 small STONE_M rubble pixels flying up to y100. The crystals are shaken: each sprays one
 CRYSTAL_L sparkle pixel.
No motion blur other than the described dust.
```

### Промпт 8. Царь-Панцирь: оглушение (3 кадра), удар (1 кадр), смерть (4 кадра)

```
[СТИЛЬ] + [ПАЛИТРА] + [ГЕОМЕТРИЯ ЦАРЯ-ПАНЦИРЯ]
Frame size is 128x128 (1024x1024 at 8x). Use the attached reference sheet for the exact look.

TASK: sprite strip, canvas 1024x128 px (drawn at 8x: 8192x1024), eight frames of 128x128 px side by side without
gaps. Frame k occupies x = 128(k-1) .. 128k-1. The King faces right.

FRAMES 1-3, DIZZY ON THE BACK (it hit the wall at full speed and fell; this is the moment the player
must attack the weak point):
Frame 1: the pose from the geometry block, dome shell on the ground (its lowest pixel at y=124) rocking:
 tilted 6 degrees to the right, the pale belly with seven plates faces up, fourteen legs up and waving
 (legs near the head are bent forward, the rear legs are bent backward), the head turned up at the right
 with a swirl eye (6x6 px OUTLINE spiral with EYE core), antennae limp. The weak point diamond 12x12 px
 glows: CRYSTAL_L facets, a WHITE sparkle pixel, a 2 px CRYSTAL_M halo made of four single pixels around it
 (no soft glow). Three SPARK stars (3x3 px plus signs) circle above the head around (112,50) with a radius of
 14 px.
Frame 2: the shell rocks the other way, tilted 6 degrees to the left. The legs are mirrored in their
 waving (every leg shifted 3 px to the other side and 2 px lower or higher). The diamond is now at its
 dim state (CRYSTAL_M and CRYSTAL_D only, no sparkle) so it pulses. Stars rotated 120 degrees.
Frame 3: the shell tilts back 15 degrees as if starting to rise: the front legs touch the ground and
 push, head lifting, eye regaining focus (EYE_BOSS ring and a plain EYE core, an angry brow starting),
 the diamond bright again. Stars gone.

FRAME 4, HURT (single frame): the standing pose, shifted 3 px to the left and flashing: every non-outline pixel
 FLASH (#F4F6FF); the eye an OUTLINE ">" squeeze; the legs straight, feet raised by 2 px; one WHITE
 4-px starburst on the shell at (60,66). The crystals stay CRYSTAL_L.

FRAMES 5-8, DEATH:
Frame 5: the crystals crack: standing pose, the five crystals each split by a 1 px WHITE crack, six
 CRYSTAL_M shards (3 px triangles) fly outwards from the crown to a height of y12; the seam cracks flare
 to CRYSTAL_L; the eye is wide (the amber core 4x4 px), mouth open; the body trembles (shifted 2 px left).
Frame 6: the crystals burst: only the stone sockets remain on the ridge, twelve cyan shards (3 px triangles
 and 2 px dots in CRYSTAL_L, CRYSTAL_M and CRYSTAL_D) are in the air all around the crown up to y4 and
 to x20 and x120. The shell has a large jagged WHITE crack from the ridge at x=60 down to the lower edge at
 x=66; the King sags 6 px (the legs bent).
Frame 7: the shell splits along the crack: the left half leans 14 degrees to the left and the right half 14
 degrees to the right with a 10 px gap, the soft SKIN_M body slumping inside (SKIN_L top highlight), the
 head drooping with an "x" eye (two 3 px diagonal OUTLINE strokes), legs buckling. Dust and falling
 shards below.
Frame 8: the corpse (stays on screen): two half-domes (each 44 px wide, 24 px tall) lying side by side cut side
 up, a pale belly-up soft body between them with fourteen curled legs, "x" eye, seven scattered
 CRYSTAL_M shards on the ground and one tiny dim CRYSTAL_L sparkle left on a shard, five STONE_M rubble
 chips. Everything lies inside rows y88-124.
```

### Промпт 9. Эффекты босса: пыль и камни (кадр 64×64)

Холст 512×64 (в 8× → 4096×512): 8 кадров по 64×64.

```
[СТИЛЬ] + [ПАЛИТРА]
Effects, not a creature: ignore "the creature faces right".

TASK: an effects strip, canvas 512x64 px (drawn at 8x: 4096x512), eight frames of 64x64 px side by side without
gaps. Frame k occupies x = 64(k-1) .. 64k-1. Transparent background. No outline on the dust (dust has no outline:
only the rock has the 1 px OUTLINE).

FRAMES 1-4, GROUND DUST PUFF (a dust cloud kicked up at the impact point at the bottom center; the ground
is row y=59, the cloud sits on it, centered at x=32):
Frame 1: a small cluster, 14 px wide and 6 px tall: DUST_M main, DUST_L 3 px highlights on the top left,
 DUST_D 2 px shade on the lower right.
Frame 2: 26 px wide and 14 px tall, three round lobes: DUST_M/DUST_L, a DUST_D underside.
Frame 3: 36 px wide and 20 px tall, lobes separating, holes appear (transparent 2x2 gaps), the top lobes are
 mostly DUST_L, pixels dropping out at the edges.
Frame 4: 40 px wide and 22 px tall, the cloud is breaking up into about twenty separate 2x2 and 3x3 blocks,
 mostly DUST_D and DUST_M, the lowest row almost empty. (The fade is done by removing pixels, not by
 transparency.)

FRAMES 5-8, FALLING ROCK CHUNK (a 14x14 px rock chunk rotating as it falls; it sits at the center of the frame, it
 does not move between frames, only rotates by 90 degrees per frame): angular rock with five visible facets:
 STONE_M main facet, STONE_L upper-left facet, STONE_D lower-right facet, one STONE_HL 2 px glint, 1 px
 OUTLINE around it. A tiny CRYSTAL_M speck (2 px) sits on one facet.
Frame 5: rotation 0 (the pointed end up). Frame 6: rotated 90 degrees clockwise. Frame 7: 180 degrees.
 Frame 8: 270 degrees. In every frame the light stays at the upper left (re-shade the facets, don't just
 rotate the image), and the crystal speck moves with the rock.
```

---

## 6. Куда класть готовые картинки

Если вы получите картинки разрезанными по полосам, положите их так (размеры кадров важны, я нарезаю по ним):

| Файл | Что в нём | Кадров × размер |
|---|---|---|
| `assets/shellback/shellback_walk_hurt.png` | промпт 2: ходьба 1–6, удар 7–8 | 8 × 64×64 |
| `assets/shellback/shellback_curl_roll.png` | промпт 3: сворачивание 1–4, качение 5–8 | 8 × 64×64 |
| `assets/shellback/shellback_dizzy_death.png` | промпт 4: оглушение 1–2, смерть 3–8 | 8 × 64×64 |
| `assets/shellback/king_idle_walk.png` | промпт 6: покой 1–4, ходьба 5–8 | 8 × 128×128 |
| `assets/shellback/king_windup_roll_stomp.png` | промпт 7: замах 1–2, качение 3–6, топот 7–8 | 8 × 128×128 |
| `assets/shellback/king_dizzy_hurt_death.png` | промпт 8: оглушение 1–3, удар 4, смерть 5–8 | 8 × 128×128 |
| `assets/shellback/fx_dust_rock.png` | промпт 9: пыль 1–4, камень 5–8 | 8 × 64×64 |

Листы-образцы (промпты 1 и 5) в игру не идут, они нужны только как референс.
Прозрачный фон, PNG, без сглаживания. Автор (или генератор) картинок и условия использования
впишите в `assets/CREDITS.md`.

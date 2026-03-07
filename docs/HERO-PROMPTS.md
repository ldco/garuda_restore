# Hero Prompt Kit (v1)

Ниже шаблоны для стабильной генерации персонажей в одном стиле.
Используйте один и тот же `STYLE_BLOCK` для всех героев и томов.

## 1) STYLE_BLOCK (общий для всего проекта)

```text
[STYLE_BLOCK]
graphic novel, clean line art, controlled ink thickness, cinematic framing,
consistent face proportions, stable eye shape, stable nose/lips geometry,
limited color palette, soft shadow mapping, no random accessories,
no extra fingers, no deformed hands, no anatomy distortion
```

## 2) HERO_ID_BLOCK (на каждого героя)

```text
[HERO_ID_BLOCK]
name: <HERO_NAME>
age_stage: <TEEN|YOUNG_ADULT|ADULT>
height: <...>
body_type: <...>
face_markers: <scar/freckles/jawline/eyebrows>
hair: <shape + color + length>
eyes: <shape + color>
signature_items: <ring/necklace/watch/etc>
personality_in_pose: <calm/aggressive/shy/confident>
```

## 3) Базовый мастер-промпт (full body)

```text
<STYLE_BLOCK>
<HERO_ID_BLOCK>
full body character sheet, neutral standing pose, front view,
plain background, high detail character consistency, production reference sheet
```

## 4) Анатомический референс (без сексуализации)

Если нужен вариант "без одежды", для production безопаснее использовать нейтральный референс:

```text
<STYLE_BLOCK>
<HERO_ID_BLOCK>
full body anatomy reference, neutral expression, neutral pose,
skin-tight neutral bodysuit, no sexualization, plain studio background,
for proportion and silhouette consistency only
```

## 5) Одежда: базовые шаблоны

### Casual
```text
<STYLE_BLOCK>
<HERO_ID_BLOCK>
full body, casual outfit: <describe>,
front view, plain background, character turn-around reference
```

### Battle / Action
```text
<STYLE_BLOCK>
<HERO_ID_BLOCK>
full body, action outfit: <describe>,
dynamic but readable pose, clear silhouette, no motion blur, production reference
```

### Formal
```text
<STYLE_BLOCK>
<HERO_ID_BLOCK>
full body, formal outfit: <describe>,
elegant posture, clean folds, plain background, style consistency
```

## 6) Turnaround / ракурсы (обязательно для каждого героя)

Генерируйте один и тот же набор:

1. Front
2. 3/4 Left
3. Left Profile
4. Back
5. Right Profile
6. 3/4 Right
7. Top-down mild
8. Low-angle mild

Шаблон:
```text
<STYLE_BLOCK>
<HERO_ID_BLOCK>
<OUTFIT_BLOCK>
character turnaround view: <VIEW_NAME>,
same facial geometry and body proportions as master sheet,
plain background, reference sheet quality
```

## 7) Портреты лица (для стабильности)

```text
<STYLE_BLOCK>
<HERO_ID_BLOCK>
headshot sheet, views: front, 3/4 left, profile left, 3/4 right,
expressions: neutral, smile, anger, sadness, surprise,
same face geometry, same eye distance, same nose length
```

## 8) Руки (частая проблема)

```text
<STYLE_BLOCK>
<HERO_ID_BLOCK>
hand reference sheet, open palm, fist, pointing, holding object,
clean anatomy, exactly five fingers, no distortions, plain background
```

## 9) Negative block (добавляйте в конец)

```text
bad anatomy, extra fingers, fused fingers, broken wrists, asymmetrical eyes,
identity drift, different character, random hairstyle changes,
low detail face, inconsistent line weight, cluttered background
```

## 10) Именование файлов (чтобы не потеряться)

```text
hero_<name>__age_<stage>__outfit_<casual|battle|formal>__view_<front|3qL|left|back|right|3qR|top|low>__v001
```

## 11) Минимальный порядок работы

1. Сделать `master sheet` (front).
2. Сделать полный `turnaround`.
3. Сделать `headshot sheet`.
4. Сделать `hand sheet`.
5. Только потом переходить к сценам комикса.

## 12) Быстрый старт (копируй и запускай)

```text
graphic novel, clean line art, controlled ink thickness, cinematic framing,
consistent face proportions, limited color palette, soft shadow mapping,
name: AIRA, age_stage: YOUNG_ADULT, height: 170cm, body_type: athletic slim,
face_markers: light freckles, defined eyebrows, hair: short black bob,
eyes: gray almond, signature_items: silver ring, personality_in_pose: confident,
full body character sheet, neutral standing pose, front view, plain background,
high detail character consistency, production reference sheet,
bad anatomy, extra fingers, fused fingers, asymmetrical eyes, identity drift
```


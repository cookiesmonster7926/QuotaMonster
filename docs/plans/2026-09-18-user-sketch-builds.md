# 使用者手繪雙環圖示 — 五種實作

> 互動頁：https://claude.ai/artifact/Pv8rWxc2LgduKt18u4MQtF
> mockup：`sketch-mockups/*.html` · 渲染證據：`docs/evidence/*.png`

## 設計（使用者手繪，不可更改的部分）

- 外圈 / 內圈兩條**底部開口**的弧，都表示**剩餘**用量（5h 與 7d）
- 頂端兩個刻度 = 各自那圈的 **50% 標記**（弧從底部開口起算繞過頂端，正上方即中點）
- 底部開口內的點 = **幾隻 agent 在跑**，顏色區分狀態
- 中間那隻**只在有 agent 跑的時候會動**
- 有人需要輸入 → 整個變紅、內部變三個 chevron
- 額度用完 → 中間那隻**睡著**

## 半徑預算（評審實測）

圓心往外只有 9.00pt，要分給「外弧筆畫 + 空隙 + 內弧筆畫 + 空隙 + 中間那隻」：

```
faithful   1.50 + 2.00 + 1.50 + 2.20 + 1.80 = 9.00   兩個空隙都達 1x 下限
inarc      1.50 + 1.80 + 1.20 + 1.21 + 2.29 = 8.00   真正的 16pt 環
precision  1.00 + 2.00 + 1.00 + 2.00 + 3.00 = 9.00   空隙達標，筆畫只剩 1.0pt
creature   1.50 + 1.50 + 1.50 + 1.50 + 3.00 = 9.00
wide       1.50 + 1.50 + 1.50 + 1.50 + 2.80 = 8.80
```

付帳方式只有四種：犧牲墨水高度、空隙、筆畫粗細、或中間那隻。
實測墨水高度 inarc 17 / creature 17.5 / wide 18 / precision 18 / faithful 18.5 —— **沒有一個做得到理想的 16pt**。

## 評分（滿分 80）

| 排名 | 做法 | 總分 | 忠於草圖 | 1x 存活率 |
|---|---|---|---|---|
| 1 | 缺口就是碼頭（Inarc, 24pt） | 63.5 | 第 2 | 第 1 |
| 2 | 儀表精度（Sleeping Gauge, 22pt） | 61.5 | 第 1 | 第 3 |
| 3 | 完全忠實（Undiluted, 22pt） | 59 | 第 3 | 第 2 |
| 4 | 生物優先（Sleeping Creature, 22pt） | 55 | 第 4 | 第 4 |
| 5 | 加寬畫布（SK-WIDE, 28pt） | 46 | 第 5 | 第 5 |

## 已知缺陷

- **Undiluted**：警示環用 `.al{opacity:0}` + 動畫顯示，但 reduce-motion 把動畫關掉 → **開了「減少動態效果」時，有人在等你的狀態完全不顯示**。
- **SK-WIDE**：最自豪的光柵化宣稱經實際渲染證明為假；常態下沒畫軌道環，讀起來是 wifi 波紋。
- **Inarc / Undiluted 共同**：頂端 50% 刻度畫到環外，1x 下像天線，破壞圓形剪影。

### 缺口就是碼頭 — Inarc（63.5/80）

**22pt 怎麼塞：** The sketch stacks five bands — outer arc, gap, inner arc, gap, creature — and then puts a row of dots underneath. Stacked, that is impossible: 16pt of ink is about four parallel elements and the dot row would need another 3pt it does not have. The way out is the one the sketch already contains: THE MOUTH IS THE DOCK. The beads are not below the ring, they are ON the ring, riding the track at R 6.90 inside the opening the arcs leave at the bottom, so they cost ZERO extra height. Total ink stays 17.00pt in the 22pt box (2.00 top margin at the 50% pip, 3.00 bottom under the beads); the ring itself is exactly 16.00 x 16.00pt with 3pt margins, matching the measured Tailscale and SF Symbol references. The radial budget then reads outward-in: 1.50 outer stroke, 1.80 counter, 1.20 inner stroke, 1.20–1.61 counter, and the animal gets what is left — a 3.80 x 4.80pt body. Second move: the mouth BREATHES with the agent count, 96° idle to 138° at five agents, because the dock needs the angle and an empty dock does not. That is safe — and this is the load-bearing argument — because each track is symmetric about 12 o'clock and each arc fills from one end, so the halfway point of the track is top dead centre at EVERY mouth width. The single calibrated reading the user asked for, "the middle tick is half", is invariant under the breathing. What was sacrificed: countable agents past four (five beads touch, six or more collapse to a bar), exact blocked counts (one vs more-than-one only), and the 50% pips had to move to the outside of their arcs because the inside of each arc is where the next element already lives.

**幾何：** All in points, 1pt = 1px, viewBox 24 x 22, ring centre (12, 11), angles from 12 o'clock, clockwise.
RING: ink radius 8.00 (16.00pt ring, 3.00 margins top and bottom); item 24pt wide (4.00 side margins).
OUTER ARC (5-hour): centreline R 7.25, stroke 1.50 (9.4% of ink), round caps, edges 6.50 / 8.00.
COUNTER 1: 1.80 (6.50 → 4.70).
INNER ARC (7-day): centreline R 4.10, stroke 1.20 (7.5%), round caps, edges 3.50 / 4.70.
COUNTER 2: 1.20 minimum (at the arc ends) to 1.61 (top and sides).
CREATURE ENVELOPE: R 2.00 wherever an arc runs; body may drop below that only inside the mouth wedge.
MOUTH (gap, centred on 6 o'clock): 96° at 0 agents, 104° at 1, 112° at 2, 124° at 3, 132° at 4, 138° at 5 or more, 126° asleep. Arc ends therefore at ±132° / ±128° / ±124° / ±118° / ±114° / ±111° / ±117°. Round caps add 0.75 (outer) and 0.60 (inner), so the visible mouth is about 12° narrower than the nominal gap.
SWEEP: track sweep = 360 − gap (264° idle, 236° at 3 agents, 222° at 5). Each arc is drawn from the lower-LEFT end clockwise; remaining fraction f covers f × sweep. At the real data, 72% remaining on a 236° track puts the 5-hour head at +51.9°, past the tick; 82% on the inner track puts its head at +75.5°.
50% PIPS: both at exactly 0°, radial, 1.20 wide. Outer pip R 8.00 → 9.00 (1.00 long, in free space beyond the silhouette). Inner pip R 4.70 → 5.50 (0.80 long, sitting in counter 1 with 1.00 clearance to the outer arc).
DOCK: track R 6.90 — beads straddle 5.80 → 8.00, flush with the ring, breaking no new height. Bead ⌀ 2.20 for n ≤ 3, 2.00 for n ≥ 4. Angular pitch 30.0° (n ≤ 3) → chord 3.57, edge gap 1.37; 27.0° (n = 4) → chord 3.22, edge gap 1.22; 22.5° (n = 5) → chord 2.69, edge gap 0.69. A bead centre keeps 23.1° off an arc end cap, which gives a usable window of ±24.9° (idle) to ±45.9° (five agents) — 10.36pt of arc in total.
OVERFLOW BAR (n ≥ 6): single 2.00pt stroke on the same R 6.90 from −45.9° to +45.9° (11.06pt of arc); for n = 6–8 it is cut into n butt-capped segments of 1.15pt with 0.50pt notches, plus 1.00pt round end caps; for n ≥ 9 it is solid.
CREATURE (awake): ellipse rx 1.90, ry 2.40 at (12, 11.50), plus two ear wedges to R 2.29 — 3.80 x 4.80pt overall.
CREATURE (asleep): ellipse rx 1.85, ry 1.25 at (12.15, 12.85) + head bump r 1.00 at (10.60, 12.75) + one ear — 3.90 x 2.60pt lying low in the bowl.
NEEDS INPUT: closed ring R 7.25 stroke 1.50 (one blocked) or R 6.85 stroke 2.30 (two or more, same 8.00 O.D.). Chevrons: stroke 1.10, depth 1.70, half-height 2.30, pitch 2.86 (perpendicular counter 1.20), cluster 7.42pt wide, scaled ×0.88 in the heavy-ring variant. Clearance to the ring I.D. 1.37 / 1.19.
STALE: same paths at 1.00pt, dash 0.60/1.50, everything at 30–38% alpha. GHOST TRACK (exhausted): 1.00pt at 26%.

**中間那隻：** A filled mass, never an outlined drawing — Apple's own "ant" is 7% fully-opaque at 1x and the interior detail in the sketch's blob would die the same way. It is an egg: ellipse rx 1.90, ry 2.40 at (12, 11.50), with two small ear wedges rising off the crown to R 2.29, so 3.80 x 4.80pt overall — taller than wide, sitting upright in the bowl of the two arcs, never crossing R 2.00 where an arc runs (minimum counter 1.20 at the mouth corners, 1.61 across the top). NO EYES, at any size, in any state. Two eyes read as a face at every tested spacing, and one eye on a 3.80pt head would be a 0.45pt line cutting a fake counter into a template alpha — so the animal is carried entirely by silhouette and motion, like the Invertocat or the monochrome whale.
MOVEMENT: it only moves while agents are running. The bob is translateY ±0.70pt with a 3% squash on a 1.35s ease-in-out loop — 0.70pt is deliberately above the 0.50pt "invisible at 1x" line, so it reads as one device pixel of travel at 1x and two at 2x. When the first agent starts it WAKES: a 12.8s→16s stretch, scale(1.10, 0.93) then scale(0.97, 1.05) then rest, about 600ms. With nothing running it is perfectly still, which is the whole point — motion in the menu bar means work in flight and nothing else.
SLEEP: no z's, no closed eye, no face. The pose flips. It lies down and flattens into 3.90 x 2.60pt — wider than tall, low in the bowl — with the head bump to the left and one folded ear, and breathes on a 4.4s scale(1) → scale(1.055) loop. Because the 5-hour track is a 26% ghost by then, the whole mark is quiet, and the only thing with any weight left in it is the animal. The pose flip is the one part of the sleep state that survives 1x, and it is enough.

**agent 點：** One bead per agent, riding the dock track at R 6.90 — dead centre of the mouth the arcs leave open, straddling 5.80 → 8.00 so they sit flush inside the ring silhouette and add no height. Beads are 2.20pt for one to three agents and 2.00pt for four or five. Pitch is angular, not linear: 30.0° up to three (chord 3.57, edge gap 1.37 — countable at 1x), 27.0° at four (gap 1.22), 22.5° at five (gap 0.69 — they visibly kiss). The mouth itself opens to make room: 96° → 104° → 112° → 124° → 132° → 138°, which is also expressive, the ring literally opening up as the swarm grows. A bead centre always keeps 23.1° off an arc's end cap, so it never collides with the round cap.
COLOUR CODING: blue running, amber queued, grey exiting, red blocked. All four are colour-only, by necessity — a hollow or ringed bead needs a stroke plus a counter inside 2.00pt, which is impossible, so status can never be carried by bead SHAPE at this size. That is not a hole in the design, because the one status with a deadline (blocked) is carried by the whole-mark chevron morph, exactly as the sketch specified.
PAST THE POINT THEY FIT: the dock is 10.36pt of arc, and a legible bead plus a legible gap costs 3.4pt of it, so four fit comfortably and five touch. At six the beads stop being beads and become a BAR on the same track — a 2.00pt stroke across the whole window, cut into n butt-capped segments of 1.15pt with 0.50pt notches for six to eight agents, and solid from nine up. The chain degrades gracefully: countable beads → a beaded chain → a notched bar → a full bar meaning "a lot". The honest cost is that past five you can no longer count, and past eight the notches stop meaning anything at all.

**變形：** When a session blocks, the mark stops being a gauge. The two arcs sweep closed into ONE ring in alert red at R 7.25 / stroke 1.50, the beads retract into the track, the pips and the creature fade out, and three right-pointing chevrons scale in from 0.86 over about 400ms. Nothing else in the bar looks like it, which is the point: the only state with a deadline gets the only total transformation and the strongest colour.
At 22pt the chevrons are stroke 1.10, depth 1.70, half-height 2.30, pitch 2.86 — which puts 1.20pt of counter perpendicular to the arms, the tightest they can be and still be three things. The cluster is 7.42pt wide inside a 13.00pt interior, keeping 1.37pt off the ring. HOW IT ACTUALLY READS AT 22pt: at Retina it is unmistakably three nested carets, a fast-forward, a prompt. At 1x it is a grey rightward wedge — the DIRECTION survives, the three-ness does not. That is why the chevrons march: a 1.25s opacity wave, 130ms apart, left to right. Motion has no pixel floor, so the rhythm carries the meaning through the blur at any scale, and it also reads as "waiting on you" rather than "working".
TWO OR MORE BLOCKED: the ring thickens from 1.50 to 2.30pt (holding the same 8.00 O.D., so the silhouette does not grow) and the chevrons scale to 0.88 to keep their clearance, and the pulse becomes a double beat. One ring weight versus another is a coarse signal, but it is the only quantitative channel left inside a 13pt circle that already holds three chevrons — so the mark says "one" or "more than one", and nothing finer. When it clears, the alert fades, the mouth reopens at the current agent count, and the pet comes back.

**1x 誠實報告：** Measured floors used throughout: stroke 1.00pt, counter 2.00pt at 1x and 1.00pt at 2x, element 2.00pt. I verified the final geometry by rendering the real page at device-scale-factor 1 and 2 and magnifying the actual pixels, so this is observation, not assertion.
SURVIVES 1x: the 5-hour stroke (1.50, 9.4% of ink, fully opaque core row); the 7-day stroke (1.20 — above the render floor, deliberately below the 8–11% weight band because the ambient window should not shout); bead diameters (2.20 / 2.00, solid); the bead gap at three agents (1.37, about 70% open, countable); the sleep silhouette (3.90 x 2.60, the pose flip reads); and the whole-mark morph, which is a colour and shape change at ring scale.
MARGINAL AT 1x, CLEAN AT 2x: the counter between the two arcs is 1.80 against a 2.00 floor — about 85% open, a faint grey in the trough. I spent the missing 0.20 on the creature and would again. The creature-to-inner-arc counter is 1.20 at the two mouth corners (about 55% open) and 1.61 elsewhere. The bead gap at four agents is 1.22.
FAILS 1x — RETINA-ONLY, NAMED: (1) The inner 50% pip keeps only 1.00pt of clearance to the outer arc, so at 12 o'clock, and only there, the ring pair looks bridged at 1x. Accepted deliberately: an index mark that touches its own scale still reads as an index mark. (2) Five beads have a 0.69pt gap and fuse into a single bar at 1x — the count is Retina-only, and this is the true ceiling of the dock. (3) The overflow bar's 1.15pt segments and 0.50pt notches are Retina-only and even there only a hint; at 1x it is a solid bar meaning "a lot". (4) The chevrons, at 1.10pt stroke with 1.20pt counters, are a grey wedge at 1x — direction survives, three-ness does not; the marching pulse is what carries it. (5) The creature's 0.90pt ears with their 0.90pt notch are gone at 1x — the crown flattens and the animal is a pebble, which is still correct. (6) The stale state's 0.60/1.50 dashing collapses to a dim broken line at 1x, which is the intended reading.
PARITY: the ring is centred at (12, 11) with an 8.00 outer radius, so the silhouette's cardinal edges land on whole device pixels at 1x — y = 3.00 and y = 19.00. The consequence is that the outer stroke's inner edge falls on a half pixel (4.50 / 17.50), making the ring's inner boundary a 50% row at those four points. I chose the outline over the counter, because the outline is the silhouette. The 1.20pt pips are centred on x = 12, a whole point, so at 1x each lands about 60/60 across two columns — a soft 2px pip rather than a crisp 1px one; widening to 2.00 would have made it a bead, so I took the softness. A circle is off-grid everywhere except its four cardinal points, which is the honest reason this design leans on arc length and angular position rather than on crisp edges.

**評審必修：**
- (忠於草圖, 31.5/40) The outer 50% pip pokes OUT to R9.00, past the ring, and at 1x it reads as an antenna on the silhouette — it is the one element that breaks the 16pt ring you worked so hard to keep. Move it inward and eat the 1.00pt, or widen the 1.80 counter to 2.00 and put it there. Second: your counter-2 claim is optimistic against your own render. In the silhouette variant at ±40° the creature and the inner arc measure 0.58 fill between them, i.e. about 42% open, not the 55% you state — in monochrome they visibly merge on the flanks. Third: the mouth breathing from 96° to 138° moves both arc heads when no quota changed. Your TDC-invariance proof is sound, but nothing on the mark teaches it, and you are asking the user to read position-relative-to-a-1.2pt-pip.
- (1x 存活率, 32/40) Get both 50% pips back inside their arcs. Widen counter 1 from 1.80 to 2.00 and take it out of the creature, or root each pip as a 1.00pt inward spur off its own arc the way Undiluted does — the current outward pip breaks the circular silhouette and the inner one bridges the ring at 1x. Then cap the bead ladder at 4 so beads never kiss (0.69pt at n=5 is below every floor you cite).

**自陳缺點：**
- Past five agents the beads stop being countable and become a bar, and past eight even the notches are meaningless — the dock holds 10.36pt of arc and a legible bead with a legible gap costs 3.4pt of it. A user with twelve agents sees the same mark as a user with twenty.
- The needs-input state encodes only 'one' versus 'more than one' blocked, as a ring weight change from 1.50 to 2.30pt plus a double-beat pulse. A weight change is a coarse signal and a user may not notice it at all without a side-by-side.
- I moved the two 50% pips to the OUTSIDE of their arcs, against the sketch, which says just inside. It was forced — the counters are 1.80 and 1.20 and cannot host a 1.00pt mark with clearance on both sides — but it changes the silhouette: the outer pip breaks the circle at 12 o'clock and can read as a stem or an antenna rather than an index mark until you know what it is.
- The inner pip still keeps only 1.00pt off the outer arc, so at 1x the ring pair looks bridged at 12 o'clock. On a non-Retina display that is a visible defect at the single most-looked-at point of the mark.
- The mouth breathing from 96° to 138° means the arc heads move when agents start or stop even though no quota changed. The 50% tick stays true, but anyone reading the head's absolute angle rather than its position relative to the tick will be misled.
- Bead status colour is colour-only and cannot survive template monochrome. In a pure alpha rendering, a queued agent, an exiting agent and a running agent are identical dots.
- The creature is 3.80 x 4.80pt and has no face by design. It is a blue egg with ears; whether it reads as 'a pet' to someone who has not been told is unproven, and at 1x the ears are gone and it is simply a blob.
- The live scenario cross-fades between three fixed mouth widths over ~400ms rather than tweening, because CSS cannot animate path data, and its beads hold one radius instead of stepping 1.10 to 1.00 at four agents. The real implementation would redraw the path each frame; the demo dissolves.
- At 8% remaining the 5-hour arc is a short amber stub at the lower left and the ring visually disappears. I argue that is the alarm, but it also means the mark loses its identity at exactly the moment it matters most, and it can be mistaken for a rendering failure.
- The whole thing depends on the user learning one convention — that top dead centre is half. Nothing on the mark teaches it, and a 1.20 x 1.00pt pip is a very small place to hang the only calibrated reading in the design.

### 儀表精度 — Sleeping Gauge（61.5/80）

**22pt 怎麼塞：** The dot row never stacks below the ring — it sits INSIDE the 110° bottom opening, in the lane the arcs themselves vacate. The outer arc terminates at y16.8; the lane runs y18–20. So the dots cost zero height, which is the user's own drawing read literally, and the whole mark fits 18pt of ink in the 22pt box with 2.0pt of margin top and bottom.

The radial budget is the hard part. Five concentric bands — arc, counter, arc, counter, creature — at the measured floors (1.0 stroke, 2.0 counter) need exactly 9pt of radius: outer arc r8–9, counter 2.0, inner arc r5–6, counter 2.0, creature ø6. There is no slack anywhere.

That forces 18pt of ink rather than the 16pt target, and parity is what makes the choice binary: for the arc edges to land on whole pixels at top dead centre the ring diameter must be EVEN, so the only candidates are 16 and 18. At 16 the creature collapses to 4.0pt and stops being a creature — it becomes a dot, and the sleep pose and eye die with it. So 18.

What was sacrificed for that: (1) stroke weight — 1.0pt is 5.6% of the mark, under the measured 8–11% band, because a 1.5pt stroke closes a 2.0pt counter and a closed counter destroys the composition while a light stroke merely looks light; (2) neighbourly optical weight — the mark is 18pt tall against the wifi fan's 11 and the battery's 10, so it is visibly the biggest thing on the bar. The document says so plainly beside a drawn battery and wifi glyph rather than claiming parity.

**幾何：** All in points, 1pt = 1px at 1×. Item box 22 × 22, ink 18 × 18, centre (11, 11).

ARCS — bottom gap 110°, from bearing 125° to 235°, so each arc sweeps 250° and top dead centre is the exact midpoint of the sweep. Outer (5-hour): edges r8.0/9.0, centreline 8.5, stroke 1.00, path M4.0372 15.8754 A8.5 8.5 0 1 1 17.9628 15.8754, length 37.088. Inner (7-day): edges r5.0/6.0, centreline 5.5, stroke 1.00, path M6.4947 14.1547 A5.5 5.5 0 1 1 15.5053 14.1547, length 23.998. Both are drawn full-length with a 22%-alpha track behind and depleted by stroke-dashoffset from the lower-LEFT anchor, so the head retreats counter-clockwise and 50% remaining ends exactly at TDC. Resolution: 1pt of arc = 2.70% on the 5h window, 4.17% on the 7d.

COUNTERS — A (between arcs) r6.0–8.0 = 2.00. B (inner arc to creature) r3.0–5.0 = 2.00.

TICKS — 2.0 × 1.0 rects at x10–12, the 5h at y3–4 (hugging the outer arc's inner edge), the 7d at y6–7. Placed contiguous with their own arc so each reads as that arc doubling to 2px at TDC. 2.0pt wide rather than 1.0 because cx = 11 and a 1pt-wide mark centred there would land on half-points.

CREATURE — ø6.00 filled, bounding box x8–14, y8–14.

DOTS — 2.0 × 2.0 rounded squares, corner r0.5, lane y18–20, pitch 3.00, max row 14.0 (left edges 4, 7, 10, 13, 16). Odd counts centre on x11; even counts sit 0.5pt left of centre so every edge stays on a whole point.

ALERT — sealed ring, centreline r8.0 stroke 2.00 (edges 7/9) for one blocked, centreline r7.5 stroke 3.00 (edges 6/9) for two or more. Chevrons 1.25pt, apexes at x7/11/15 on a 4.0 pitch, arms from (apex−1.5, 8) to (apex, 11) to (apex−1.5, 14); perpendicular counter 2.33.

TIGHTEST PAIR — 1.87 diagonal, between the outer arc's end cap at (18.372, 16.162) and the fifth dot's corner at (18, 18).

**中間那隻：** A ø6pt filled mass with zero interior detail, sitting on the floor of the ring: rounded crown, flanks that flare outward to a 6pt base with 0.6pt bottom corners. Not a circle — the flare is what makes it read as something sitting rather than a dot. It is a MASS, per the measured warning that organic outline dies at this size; measured 0.83 alpha at the crown and 1.00 through the body at 1×.

While agents run it breathes: scale(1.045, 0.935) on a 0.85s ease-in-out cycle with the transform origin at its feet (11, 14), so it squashes down and spreads rather than floating. Nothing else about the mark moves. When nothing is running the same path is drawn with no animation at all — idle and working are the same silhouette, distinguished purely by whether it is moving, which is exactly the user's "the movement in the middle means agents are running" and costs zero pixels.

Asleep: it lies down — the body squashes to 6 × 4pt, y10–14, and gains one closed eye, a 2.0 × 1.0 rounded slot CUT OUT of the mass at x10–12, y11–12 with fill-rule evenodd. Exactly one eye, never two, and it is subtractive rather than an added hairline, which is why it survives: measured 0.19 / 0.15 alpha in the slot at 1×, about 83% open, a real hole. It breathes on a 4.2s cycle instead of 0.85s. Awake-to-asleep is a 0.5s cross-fade between the two paths under a squash, not a path morph, so it works in every browser.

**agent 點：** One 2.0 × 2.0pt mark per running agent, corner radius 0.5, in the lane at y18–20, on a 3.0pt pitch — 2.0 of mark and 1.0 of gap. They are rounded SQUARES, not circles, and that is a rasterisation decision: a 2pt circle at 1× peaks at 0.785 alpha because π/4 of the pixel is all it can cover, while the rounded square measured 0.87 / 0.97 with the 1.0pt gaps at a true 0.00 — empty pixel columns, exactly.

Row widths: 1 dot = 2.0, 3 = 8.0, 5 = 14.0, which is the full lane. Odd counts centre on x11; even counts take a 0.5pt leftward bias so no edge ever falls on a half point. When the count changes the whole lane translates by a WHOLE number of points to re-centre — 5→4 is +1.0, 4→3 is +2.0 — so it lands back on the grid every time. During the 0.18s slide it is off-grid and soft; that is stated.

Status: solid at full alpha = running; 45% alpha = queued or waiting on a tool; alert colour = blocked, though blocked is really carried by the whole-mark morph rather than by one dot. Alpha survives template tinting, so the queued state works in monochrome where colour does not.

Past 5 they no longer fit. The ladder: 6–7 agents drop to 1.0 × 2.0pt marks on a 2.0 pitch (measured 0.63 / 0.84 with clean gaps — resolved, but a lighter texture rather than countable units at 1×). 8 or more saturates: a 2.0pt overflow lozenge at x4–6 followed by six 1pt marks, 14.0 of lane, meaning "six shown, more running". Above that the mark stops counting, and it says so — subitising gives out at four or five anyway, and a lane claiming to encode eleven at 22pt would be lying about its resolution. The exact number lives in the dropdown.

**變形：** When a session blocks, the whole mark changes silhouette, not just colour — which is the point, because as a template image colour is thrown away. Both quota arcs fade over 0.29s while two half-arcs draw inward from the two arc terminals and meet at the bottom, sealing the 110° opening into a closed ring at double weight (2.0pt, centreline r8, edges on y2 and y4 at TDC). The gap closing from both ends at once is the animation that carries the meaning: the thing that was open is now shut.

Inside, three right-pointing chevrons wipe in from the left over 0.3s and then march — a staggered alpha pulse, 1.05s per pass, offset a third of a cycle each, so exactly one is at full while the others sit at 0.55 and the eye reads a rightward travel. Chevron geometry: 1.25pt stroke, apexes at x7/11/15, arms from (apex−1.5, 8) to (apex, 11) to (apex−1.5, 14), steeper than 45° at about 63° from horizontal.

That angle is chosen for the rasteriser, not for looks. A diagonal stroke gets its coverage for free: a 1.25pt arm at 63° lays 1.40px of ink down any pixel column, and the 2.33pt perpendicular counter opens to 2.6px. Measured at 1× the arms came back 0.86 + 0.43 across two columns with two columns at a true 0.00 between each pair — three chevrons stay three at 22pt. Diagonal edges can never be grid-locked, so they stair-step; they do not go grey.

One blocked versus two or more is a step in ring weight, 2.0 to 3.0pt (centreline r7.5, edges 6/9 — odd width on a half-point centreline, correct parity), with the chevrons scaled in to clear the heavier ring and marching at double rate. Beyond "more than one" the number is not in the mark, and that is stated as a limit rather than hidden.

**1x 誠實報告：** Every number below was measured, not estimated: the page was rendered headless at device-scale-factor=1 and the mark sampled pixel by pixel off the alpha channel.

SURVIVES 1× — Tick 1.00, the only element in the mark that hits full alpha, because it is a rect on whole points; it doubles its arc to two solid pixels at TDC, so the 50% landmark is the crispest thing in the design. Arc at the cardinal tangents 0.93 (5h) and 0.89 (7d). Creature 0.83 at the crown, 1.00 through the body. 2pt dots 0.87 / 0.97 and their 1.0pt gaps a true 0.00 — genuinely empty pixel columns. Chevron arms 0.86 + 0.43 with 0.00 counters. Alert ring 1.00 at the tangents. Closed eye slot 0.19 / 0.15, about 83% open — a real hole at 1×. Counter B at the 7d tick: 0.00, fully open, because both its neighbours are straight edges.

THE SURPRISE, AND IT CONTRADICTS WHAT I EXPECTED — a 1.0pt CURVED stroke is not binary even with both edges on whole points. Skia lands it at ~0.90 in its own pixel and pushes 0.10–0.16 into one neighbour. So the 1.0pt counter at the 5h tick came back 0.16, i.e. 84% open, not the clean zero I designed for; the 2.0pt counters still keep one pixel at a true 0.00 and are safe. Straight edges came back perfectly binary every time. That asymmetry is the whole argument for 2.0pt counters and for putting the only fine detail — the tick, the eye slot, the dot gaps — on straight edges.

SOFT AT EVERY SCALE — on the 45° reaches an arc measures 0.80 + 0.45 split across two pixels. Only four points on a circle can be grid-locked. No geometry fixes this; it is the price of drawing a gauge.

RETINA-ONLY — (1) counting past five: the 1pt tier resolves with clean gaps but lands at 0.63–0.84 against the 2pt tier's 0.97, so it reads as texture, not units; (2) the creature's squash — the 4.5% breath moves its edge 0.13pt, which at 1× is alpha flicker on the boundary pixels, a shimmer rather than a squash, so the DOTS are the hard signal that agents are running and the creature is the emotional one; (3) the closed eye reads as a notch at 1× and as an eye at 2×; (4) the 22% empty track on a light bar.

ONE FRAGILE DEPENDENCY — the 1.0pt counters at the ticks are clean only while the image origin lands on a whole point. The mark is 22 × 22, even, centred in a 22pt bar, so AppKit places it on an integer and it holds. Ship it at an odd width and those two counters close to 25% fill. Worth a unit test on the drawn rect.

**評審必修：**
- (忠於草圖, 32.5/40) The 1.0pt arcs are the weakest ink here and the gauge is the primary reading. Measured off the diagonals they split 0.62/0.49 and 0.54/0.93 across two rows — they never reach black over most of their length, exactly as the brief's SF-Symbol-Light data predicts. Buy weight back: go to 1.25pt strokes and 1.75pt counters (still above the 1.0pt 2x floor, and the tick/dot/eye detail that carries this design is all straight-edged and unaffected), or accept the arcs are grey at 1x and say so in the headline rather than in weakness #2. Also: give the creature a crown. A flared ø6 dome is the least pet-like body in the set and the user asked for a pet, not a bell. And document the chevron-to-ring clearance — measured it is a single pixel at 0.13 fill at the arm ends, which is tighter than anything else in your own tables.
- (1x 存活率, 29/40) Redraw the creature with the eared silhouette the user drew — the dome has no character awake and the sleeping version is a mound with a slot, not a pet. Then take the arcs from 1.0 to at least 1.25pt; you are at 5.6% weight against the 8-11% band you cite, and the mark currently reads thinner than wifi while being taller than everything on the bar.

**自陳缺點：**
- The mark is the biggest thing on the menu bar: 18pt of height against the wifi fan's 11 and the battery's 10. Parity forces the ring diameter to be even, so the only options were 16 and 18, and 16 kills the creature — but it does mean the item sits louder than its neighbours, and the strip in section 3 shows that rather than hiding it.
- The 1.0pt stroke is 5.6% of the mark, well under the measured 8–11% band. It is the weakest ink in the design and it measured 0.80 on the 45° reaches. I traded stroke weight for open counters; if a reviewer's eye says the arcs look thin, they are right and there is no fix inside this composition.
- The 1.0pt counters flanking the ticks came back 0.16 filled at 1×, not the clean zero the pixel-snapping was supposed to buy. Curve antialiasing bleeds where straight edges do not. 84% open reads as open, but the claim I set out to prove is only true for the straight elements.
- Agent counting dies above five. Six and seven resolve as a lighter dotted row; eight and eleven look identical. The mark reports 'more than six', not a number.
- Quota resolution is 2.70% per pixel on the 5-hour window and 4.17% on the 7-day. Anything finer than a 3% change is invisible, so this is a gauge and never a readout.
- The alert seals the ring and hides both quota arcs for as long as it is up. That is deliberate — a sealed silhouette is the only thing that survives template monochrome — but it means you cannot see your burn rate at the moment you are most likely to be looking.
- The creature's aliveness is carried almost entirely by motion, and at 1× that motion is a 0.13pt edge shimmer rather than a visible squash. On a non-Retina display the creature reads as a static blob and the dots do all the work.
- Two or more blocked sessions is a ring-weight step from 2.0 to 3.0pt. It distinguishes one from many and nothing else; the count is not in the mark.
- The whole design assumes the mark is placed on an integer origin. Centre it on a half point — an odd item width, an odd-height bar — and the tick counters close to 25% fill and the top of the mark goes soft.
- Section 5 compresses the quota axis about 200× so an 18s loop can show a window emptying. Every other timing in it is real, but the drain itself is not something you would ever watch happen.

### 完全忠實 — Undiluted（59/80）

**22pt 怎麼塞：** The sketch is built exactly as drawn, and the trick that makes it fit is that the ring is NOT a circle's worth of ink. Because both arcs stop at 220° and −40°, the outer arc's ink box is 18.00pt wide but only 15.05pt tall (y 1.75 → 16.80). That leaves the bottom of the box genuinely empty, and the dot row drops into it at y 19.00 with 1.75pt of margin below — exactly where the drawing puts it, tucked into the opening rather than hanging off the bottom. Total ink 18.50 × 18.50 in a 22 × 22 box, 1.75pt margin on every side, ring centre (11.00, 10.75).

The radial budget from the centre, 9.00pt to spend: outer stroke 1.50 (R 8.25, edges 7.50/9.00) → outer 50% spur 1.00 long → counter 1.00 → inner stroke 1.50 (R 4.75, edges 4.00/5.50) → inner spur 1.00 long → counter 1.00 → creature crown. That is five bands plus two ticks in nine points. Every edge sits on a 0.50pt boundary, so every edge is a whole device pixel at 2×.

Three things were sacrificed, all named out loud. (1) Ink height: 18.50pt, not the 16.00pt that Tailscale and SF Symbols at pointSize 16 both measure. A bottom-open ring with a dot row inside its opening cannot be 16pt and still hold five bands; the mark sits visibly taller and busier than its neighbours in the bar. (2) The counters: 1.00pt between the arcs and 1.00–1.20pt between the inner arc and the creature, against a measured 2.00pt 1× floor. Widening either to 2.00 would have left the creature about 2.0pt tall, which is not a creature. (3) The ticks touch their arcs. A free-floating tick needs gap 1.00 + tick 1.00 + gap 1.00 = 3.00pt of clear band and there is no 3.00pt band anywhere in this design, so each tick became a 1.00 × 1.00pt spur growing inward off its own arc at top dead centre. That is the single largest deviation from the sketch and it is the only one.

What was NOT sacrificed: both arcs, both ticks at TDC, a 5.60 × 4.70 creature with real mass, a full-width dot row in the gap, the chevron morph and the sleep pose. The whole point of this entry is to show what the drawing looks like when nothing is negotiated away.

**幾何：** All values in points. Box 22.00 × 22.00, origin top-left, 1pt = 1px. Ring centre (11.00, 10.75). Ink box 18.50 × 18.50 at (1.75, 1.75).

ARCS — both bottom-open, start 220°, end −40°, 260° of sweep, 100° gap. Midpoint of the sweep is 90° = top dead centre = the 50% mark.
  Outer (5-hour): centreline R 8.25, stroke 1.50, round caps, edges at R 7.50 / 9.00. Path M4.68 16.053 A8.25 8.25 0 1 1 17.32 16.053. End caps at (4.68, 16.05) and (17.32, 16.05); cap ink reaches y 16.80.
  Inner (7-day): centreline R 4.75, stroke 1.50, round caps, edges at R 4.00 / 5.50. Path M7.361 13.803 A4.75 4.75 0 1 1 14.639 13.803. End caps at (7.36, 13.80) and (14.64, 13.80).
  Counter between arcs: 7.50 − 5.50 = 1.00.
  Both carry pathLength="100" and stroke-dasharray:100, so remaining quota f is drawn by stroke-dashoffset = 100(1−f). Depletion eats from the lower-right end backwards toward the lower-left start. An empty track of the same path sits behind at alpha 0.20.
  Real data: 5-hour 72% remaining → dashoffset 28, arc ends at 32.8° (about 1 o'clock). 7-day 82% → dashoffset 18, ends at 6.8° (just above 3 o'clock). Both run past the top spur, so both read "more than half left".

TICKS — 1.00pt wide, 1.00pt long, butt caps, at x 11.00, alpha 0.82.
  Outer spur: y 3.25 → 4.25 (R 7.50 → 6.50), rooted on the outer arc's inner edge.
  Inner spur: y 6.75 → 7.75 (R 4.00 → 3.00), rooted on the inner arc's inner edge.
  Clear band below the outer spur to the inner arc: 1.00. Below the inner spur to the creature crown: 1.20.

CREATURE — filled, no stroke. bbox 5.60 × 4.70, x 8.20 → 13.80, y 8.95 → 13.65, centre (11.00, 11.30). Two ear humps peaking at x 9.75 and 12.25 with a 1.40pt valley at (11.00, 10.35). Minimum radial clearance to the inner arc's inner edge (R 4.00) is 1.02. Zero eyes.

AGENT DOTS — row centreline y 19.00, ink bottom y 20.25, row half-width hard-capped at 9.25.
  n ≤ 5: ⌀2.50, pitch 4.00, counter 1.50. n=5 sits at x 3, 7, 11, 15, 19 — a full 18.50pt row.
  n = 6: ⌀2.25, pitch 3.25, counter 1.00.
  n = 7: ⌀1.75, pitch 2.75, counter 1.00. Last count that is a number.
  n ≥ 8: five ⌀2.00 dots at pitch 2.75 (x 2.75 … 13.75), gap 1.00, then a 4.50 × 2.00 fully rounded overflow tail at x 15.75 → 20.25.
  Blocked agent: the dot becomes a standing capsule, 2.20 wide × 3.10 tall, in the alert colour.
  Clearance from the outermost dot to the nearest arc end cap: 1.39 (n=5), 1.77 (n=7/overflow).

NEEDS-INPUT — closed ring, centre (11.00, 10.75), R 8.25, stroke 1.50 (2.00 when two or more are blocked). Three chevrons, apexes at x 8.19, 12.09, 15.99, each M(a−2.40) 8.35 L a 10.75 L (a−2.40) 13.15, stroke 1.50, round cap and join. Horizontal pitch 3.90 gives a perpendicular counter of 1.25 (the 45° arms divide the pitch by √2). Group extent x 5.26 → 16.74, y 7.82 → 13.68; nearest approach to the ring's inner edge 1.06.

SLEEP — creature scaled (1.00, 0.62) about origin (11.00, 13.65): 5.60 × 2.91, resting on y 13.65, crown at 10.74. Two bubbles, ⌀1.30 at (11.80, 19.60) and ⌀1.90 at (14.20, 18.40), gap 1.08, taking the empty dot row.

STROKE WEIGHTS — arcs 1.50 (8.1% of the 18.50pt ink), ticks 1.00, alert ring 1.50/2.00, chevrons 1.50. Everything else is fill.

**中間那隻：** A filled mass, never an outlined drawing — at 5.60 × 4.70pt an outline would need a 1pt stroke and a sub-1pt counter, which measured out at 5–7% fully-opaque pixels on Apple's own "ant" and "pawprint". So the creature is one closed path: a wide rounded body with a flat-ish base and two shallow ear humps on the crown separated by a 1.40pt valley. The silhouette carries all the character; the interior carries none. It has zero eyes, awake and asleep. Two eyes read as a face at every spacing from 3% to 15% of mark width, and the 2012 Twitter bird, the GitHub Invertocat and the Docker monochrome whale all get by with none.

Motion is the whole semantic. Idle means *completely still* — that is the user's rule and it is the strongest signal in the design, because a menu bar is a field of motionless glyphs and any movement at all is loud. While agents run the creature breathes: scaleY 1.000 → 1.072, scaleX 0.978, about a transform-origin pinned at its feet (11.00, 13.65), so the crown lifts about 0.33pt and the base never moves. The rate tracks load — 1.05s at one agent, 0.78s at three, 0.58s at five, 0.45s at seven or more. It is a squash-and-stretch, not a translation, so at 1× it reads as the top boundary row's alpha pulsing rather than as a shape moving; at 2× it is a clear breath.

Asleep, it scales to (1.00, 0.62) about the same foot origin: 5.60 × 2.91, a low mound with its two humps flattened into a curled back, and breathes at 3.6s. Two bubbles rise to the right in the dot row, which is empty anyway because no agents can run. There is no closed eye and no "z" — an eye would need a 1pt curve with sub-1pt counters inside a 2.91pt mass and a z needs three strokes with 0.5pt counters; both are below every floor. Honestly: at real size the pose reads as "it has lain down", and the *meaning* asleep is carried by the emptied arc beside it. At 4× it reads exactly as intended.

**agent 點：** One dot per running agent, sitting in the bottom gap at y 19.00 exactly as drawn — inside the ring's opening, not hanging below it, which is what keeps the mark inside 22pt at all.

Size and pitch, a ladder rather than a formula, so each rung lands on the pixel grid: n ≤ 5 is ⌀2.50 at pitch 4.00 (counter 1.50), and five dots fill the full 18.50pt row, which is the natural cap. n = 6 drops to ⌀2.25 at pitch 3.25 (counter 1.00). n = 7 drops to ⌀1.75 at pitch 2.75 (counter 1.00) — 1.75pt is the ink floor for a disc, so seven is the last honest count. The row re-centres at every count; it never grows off one end.

Past seven the design stops lying about precision. n ≥ 8 draws five ⌀2.00 dots at pitch 2.75 plus a 4.50 × 2.00 rounded overflow tail after a 1.00pt gap. It reads "five and more", the total width stays 18.50, and the exact number moves to the dropdown where it belongs. Eight discrete dots would need a 0.36pt counter, which fails even at 2×.

Colour: running is the accent blue, blocked is the alert red. But colour is the channel a template image throws away, so blocked also changes *shape* — the dot becomes a standing capsule 2.20 wide × 3.10 tall, taller than its neighbours, which survives monochrome and survives 1×. Everything else (queued, finishing) shares the running treatment; there is no room for a third shape.

The honest limit: in template monochrome the dots encode count and blocked-vs-running, nothing more. Session identity, model, elapsed time — none of it fits in a 2.50pt disc and none of it is attempted.

**變形：** Drawing 2 built as drawn: the ring closes into a full red circle at R 8.25 and the interior becomes three right-pointing chevrons. Apexes at x 8.19, 12.09, 15.99, arms ±2.40 in both axes, stroke 1.50 with round caps and joins. The horizontal pitch is 3.90 rather than 2.75 because 45° arms divide the pitch by √2 — at 2.75 the perpendicular counter would have been 0.44pt and the three would have welded into a triangle even at 2×. At 3.90 the perpendicular counter is 1.25pt, which clears the 2× floor. The group spans 11.48 × 5.86 and its nearest approach to the ring's inner edge is 1.06. The chevrons nudge 0.70pt right on a 1.15s cycle — a caret being pushed, not a blink.

At 22pt this reads as a red ring with a solid forward arrowhead inside it. At 4× the three chevrons are unmistakable. At 1× they merge into one arrowhead mass: the direction survives, the count of three does not, and that is fine because three was never data.

The problem the drawing creates and how it is solved: a closed ring has no bottom gap, so the agent dots have nowhere to live, and the mark would surrender the count exactly when you most want it. So the morph is a *cycle*, not a replacement — 1.6s as the closed red ring with chevrons, 2.4s back to the normal mark. Quota and agent count stay readable, and the blocked agent shows in the row as a red standing capsule during the normal phase. That is how one blocked is told from two or more: you count the capsules. Two or more also speeds the cycle to 2.6s total, speeds the chevrons to 0.58s and thickens the ring from 1.50 to 2.00pt. In a frozen screenshot of the chevron phase, one and two-plus are genuinely indistinguishable; that information lives in the other half of the cycle.

Red is reserved for this state alone. Near-exhaustion gets amber, which is a deadline you can see coming; needs-input is the only state with a deadline someone else set.

**1x 誠實報告：** Every edge in this mark sits on a 0.50pt grid, so at 2× (1pt = 2 device px) every stroke edge, dot edge and counter boundary lands on a whole device pixel. At 1× a 1.50pt stroke is mathematically incapable of landing both edges on whole pixels — each arc is one fully-covered row plus one half-covered row, peak alpha 1.0. That is unavoidable and it is not what breaks. The counters break.

PASSES AT 1×: outer arc stroke 1.50; creature mass 5.60 × 4.70 (it is a filled mass precisely so that it survives); overflow tail 4.50 × 2.00; blocked capsule 2.20 × 3.10; alert ring 1.50/2.00. The 1.75pt discs at n=7 are exactly at the ink floor and render as weak discs.

RETINA-ONLY, stated plainly:
• The 1.00pt counter between the two arcs. This is the headline failure. Against a measured 2.00pt 1× floor, a 1.00pt gap comes back about 50% filled, so at 1× the outer and inner arcs fuse into a single ~4pt band over the top. You see one gauge, not two. 5-hour and 7-day become one number.
• Both 50% tick spurs, 1.00 × 1.00pt. Being attached to their arcs means they need no counter on the arc side, but a 1px bump on a 1.5px stroke is invisible at 1×. The 50% reference disappears entirely on a non-Retina display.
• The empty track at alpha 0.20 — below any perceptual threshold at 1×, which also means a nearly-empty arc at 1× looks like a broken stub with nothing to measure it against.
• The counter between the inner arc and the creature, 1.20pt nominal / 1.02pt minimum radial. At 1× the crown touches the arc and they merge into one blob.
• The creature's 1.40pt ear notch. At 1× it is a plain dome; the ears are a Retina luxury.
• The agent-dot counters. 1.50pt at n ≤ 5 is below the 2.00pt floor, so the row reads as a dashed bar whose *length* tracks the count while the count itself is unreadable. At n = 6 and 7 the 1.00pt counter gives one continuous grey bar. Discrete agent counting is Retina-only, full stop.
• The 1.25pt perpendicular counter between chevrons — at 1× the three merge into one solid arrowhead.
• The ⌀1.30 sleep bubble, under the ink floor at 1×.

WHAT A NON-RETINA MAC ACTUALLY SEES: one thick gauge band over the top whose swept length is the remaining quota; a dark rounded mass in the middle that grows and shrinks while work runs; a dashed bar under it that gets longer with more agents; a red circle with a solid arrowhead when something is waiting; a low mound with the gauge empty when the quota is gone. That is still a working icon. It is just not this icon — it is a one-window, approximate-count version of it.

One addition to the sketch that I will own: the arcs carry an empty track behind them at alpha 0.20. Without it, an 8%-remaining arc reads as a rendering bug and the 50% spur floats against nothing. It costs zero spatial budget because it occupies the band the arc already owns, and at 1× it is invisible anyway.

**評審必修：**
- (忠於草圖, 29/40) Two things, one fatal. FATAL: `.al{opacity:0}` plus `@media (prefers-reduced-motion:reduce){.sk-faithful *{animation:none!important}}` means that with Reduce Motion on, the chevron ring never renders. The single state with a deadline silently does not exist. Make needs-input a state and put the alternation behind the media query, not the visibility. SECOND: your geometry says 'Counter between arcs: 7.50 - 5.50 = 1.00'. That is 2.00. The real counter is 2.00 everywhere except the 1pt column at TDC where the spur eats half of it — I measured a fully empty row (0.00 / 0.01) between your arcs at 1x, and the arcs do not fuse. Your headline rasterisation failure and weakness #2 are both false, built on one subtraction. Fix the arithmetic and you can stop apologising for the best 1x gauge in the set — or spend the discovered slack buying the ink height back down from 18.50.
- (1x 存活率, 30/40) Kill the alternation. A menu-bar glyph that changes every two seconds is punishment, and it costs you the agent count half the time anyway — hold the chevron ring and put the blocked count in the row as red capsules when the ring is not up. Then buy the inter-arc counter up to at least 1.50 (drop the outer stroke to 1.25) so the two windows are still two windows in template monochrome at 1x.

**自陳缺點：**
- Ink height is 18.50pt against the 16.00pt convention measured on Tailscale's shipped StatusBarIcon and on SF Symbol "circle" at pointSize 16. In the simulated bar the mark is visibly taller and busier than the battery and wifi beside it. A bottom-open ring with a dot row inside its opening cannot be 16pt and still hold five bands, so this is the drawing's first and largest cost.
- At 1× the 1.00pt counter between the two arcs fails the measured 2.00pt floor and the arcs fuse into a single band. The whole premise — two windows, two arcs — collapses to one on every non-Retina display. This is the single most expensive consequence of refusing to drop a band.
- Both 50% ticks are spurs rooted on their arcs rather than free-floating marks as drawn, because a floating tick needs 3.00pt of clear band and no 3.00pt band exists anywhere in the design. They are also invisible at 1×. The most explicitly-drawn feature in the sketch is the one that survives worst.
- Discrete agent counting is Retina-only. At 1× the dot row is a dashed or solid bar; you read approximate load from its length, not a number. Past seven agents even at 2× the count is surrendered to an overflow tail.
- In needs-input, one blocked and two-or-more blocked are indistinguishable in a still frame of the chevron phase. They differ only by cycle speed, chevron speed, a 0.50pt ring weight change, and the number of red capsules visible during the other half of the alternation. Anyone screenshotting the icon gets an ambiguous answer.
- The needs-input state blinks. Alternating between the closed red ring and the normal mark every 1.6s/2.4s is the only way to keep quota and agent count readable while honouring the closed-ring drawing, but a periodically-changing glyph in a menu bar is genuinely irritating and some users will hate it.
- The sleeping pose reads as "lain down", not unambiguously as "asleep". With zero eyes, no closed-eye curve (a 2.91pt-tall mass cannot hold one) and no "z" (three strokes with 0.5pt counters), the semantic leans on the emptied arc beside it and on two small bubbles, one of which dies at 1×.
- In template monochrome the two arcs are told apart only by radius and by 0.86 vs 1.00 alpha. Which one is the 5-hour window and which is the 7-day is not derivable from the mark — it has to be learned once from the dropdown.
- The empty track at alpha 0.20 is an addition the sketch does not have. It is justified (a near-empty arc otherwise looks broken and the 50% spur otherwise floats against nothing) but it is still one more element in a glyph that was already over budget.
- The mark's own ink box is 18.50 × 18.50 while the ring alone is 18.00 × 15.05 — the optical centre of the ring sits 0.25pt above the centre of the ink. It is correct by construction but it means the glyph does not optically centre on the same line as a plain circular neighbour.

### 生物優先 — Sleeping Creature（55/80）

**22pt 怎麼塞：** The dot row does not go below the ring — it goes *in* the ring's mouth. Stacked under a 16pt ring inside 22pt leaves ~3pt, under every floor at once. So the bottom gap opens to 96° and the dock drops to centre y 18.25, which puts the dots in the same vertical band as the arc terminals (the terminals reach y 16.02–17.02; the dots span 17.00–19.50) instead of claiming a band of their own. Total ink is 17.50pt in the 22pt box, margins 2.00 top / 2.50 bottom. What that costs: 1.75pt more ink than the 16.00pt Tailscale/SF-Symbols reference, so the mark is optically a shade heavier than its neighbours; and the mouth only holds three dots for free — agents 4+ push the mark rightward (28pt at five, 44pt at the ceiling, 47–49pt in the alert state), so the menu bar reflows and icons to the left of it shift. Second sacrifice: the two drawn 50% ticks became a single 1.00pt notch *cut through* both arcs at top dead centre. There was no room to add a stroke plus two counters inside an 8.25pt radius. It costs zero ink, sits exactly where the sketch puts it, and gains a read the drawn tick could not — once a window drops below 50% the arc stops reaching the notch, so "past halfway" becomes a visible shape.

**幾何：** Centre (11.00, 11.00). Outer arc (5-hour): centreline R 8.25, stroke 1.50, edges r 7.50/9.00. Inner arc (7-day): centreline R 5.25, stroke 1.50, edges r 4.50/6.00. Counter A between arcs 1.50. Both arcs start at bearing 228° (lower left, 0° = top, clockwise) and sweep 264° to 132°; bottom gap 96.0°, centred on 180°. Half the sweep is 132°, which lands exactly on 0° — that is why the gap is 96 and not 90 or 100. Each arc fills from the lower-left terminal via pathLength=100 + stroke-dasharray. 50% tick: a 1.00pt notch (mask rect x 10.50–11.50, y 1.60–6.90) cut through both strokes at top dead centre. Creature: filled mass, bbox x 8.35–13.65 (5.30 wide) × y 8.55–13.62 (5.07 tall), max radius 3.00 from centre, so counter B to the inner arc is 1.50. Agent dots: d 2.50 (r 1.25), centre y 18.25 (edges 17.00/19.50), pitch 4.50 → 2.00pt gap. Slots 1–3 at x 6.50 / 11.00 / 15.50. Clearance from the outermost dot to the outer arc's butt cap: 1.13pt. Compressed (n≥7): d 2.20, pitch 3.50, gap 1.30. Blocked agent = pill 5.00 × 2.50, rx 1.25. Overflow marker = the same pill at 50% alpha. Ghost track: the full 264° sweep at 30% alpha, coincident with the live arc, both radii, always on. Alert: closed ring R 8.25 sw 1.50 (ink 18.00, y 2.00–20.00); chevrons x 6.5/10.0/13.5 → apexes 8.5/12.0/15.5, arms ±2.60 in y, stroke 1.50 round, perpendicular counter 1.27. Battery drawn at 1.10pt, wifi at 1.70pt for optical comparison. Ink height 17.50 in a 22.00 box.

**中間那隻：** One filled mass, no outline, no interior detail, zero eyes awake. Awake: a rounded body 5.30 × 5.07 with two ears tapering to points at (9.30, 8.55) and (12.70, 8.55) and a deep V valley between them at (11.00, 10.40); the sides bulge out to x 8.35/13.65 at the shoulder and the base is a rounded 13.62 baseline. The ears and the shoulder taper carry the entire read — the only organic detail that survives 16pt is silhouette. While agents run it bobs: a 0.95s ease-in-out cycle, translateY -0.50px with scaleY 1.035 on the rise and +0.26px / 0.968 on the settle, transform-origin 50% 96% so it squashes against its own feet rather than floating. Zero agents, it is perfectly still — motion means work, always. Asleep: a different silhouette, not a scaled one. It drops to 3.40pt tall and spreads to 6.53pt wide, a low mound sitting on the same baseline with one ear still cocked up-left at (8.20, 10.30), the back sloping down to a curled tail at the right. Exactly one eye, a closed 1.35 × 0.90 rounded slit knocked out with fill-rule evenodd. It breathes on a 4.4s scale(1.055) — slow enough to read as breath, not a pulse. The awake/asleep contrast is 5.07-tall-and-narrow against 3.40-tall-and-wide, which is a silhouette difference big enough to survive both monochrome and 1x.

**agent 點：** 2.50pt diameter, centre y 18.25, pitch 4.50 → a 2.00pt gap, exactly the measured 1x counter floor (this is why the dot is 2.50 and not 3.00). One dot per running agent. Slots 1–3 at x 6.50 / 11.00 / 15.50 sit entirely inside the 22pt box at zero extra width, and for n≤3 the row is centred on x 11.00. Slot 4 breaks out to the right: 28pt at five agents. Colour coding: blue = running; red pill (5.00 × 2.50, rx 1.25) = blocked on input, a longer shape so the status survives monochrome; 50%-alpha blue pill = the overflow marker. Above six agents the dock compresses to d 2.20 on a 3.50 pitch — a 1.30pt gap, Retina-only, at 1x it reads as a dashed bar. The ceiling is nine dots plus one overflow pill at 44pt wide; past that the count is a lie anyway, so the dock stops being a count and becomes texture — how busy, not how many. In the needs-input state the ring seals and there is no mouth, so the whole row steps 16pt right of the ring and the mark goes to 47pt (one blocked) or 49pt (two).

**變形：** The whole mark changes, as drawn: the two arcs are replaced by a closed alert ring (R 8.25, stroke 1.50, ink 18.00pt from y 2.00 to 20.00 — deliberately the heaviest mark in the set, because it is the only state with a deadline) and the creature is replaced by three right-pointing chevrons at x 6.5/10.0/13.5, apexes 8.5/12.0/15.5, arms ±2.60 in y, 1.50 stroke with round caps and joins, the group optically centred on x 11.00 with 2.25pt to the ring's inner edge. At 22pt this reads as a solid red O with an arrow in it — unmistakable against every other state, which is all it has to do; you are not meant to count the chevrons. Honest failure: the counter between chevrons is perpendicular, not horizontal — a 3.50 pitch projects to only 2.77 across a 1.50 stroke, so the gap is 1.27pt and the three chevrons fuse into one striped wedge at 1x. The @1x representation therefore ships TWO chevrons at pitch 4.50 (projects to 3.51, a true 2.01pt counter) inside a 2.00pt ring. The blocked count never lives in the chevrons — it lives in the dock, as red pills, one per blocked session. In the animation the change is a 0.40s cross-fade between the two drawn states, not a path interpolation; SVG cannot tween a 264° arc into a chevron without script, and a menu-bar icon that needs script to redraw is one that stops redrawing when the main thread is busy.

**1x 誠實報告：** PASS at 1x: the 1.50pt arc stroke (1.5× the floor; its top-dead-centre edges land on y 2.00/3.50 and 5.00/6.50 — whole points but for one half-point edge); the 2.50pt dot (edges on 17.00 and 19.50); the 2.00pt gap between dots (exactly the floor); the creature, which has no interior at all. RETINA-ONLY, stated plainly: the 1.50pt counter between the arcs and the 1.50pt counter from the inner arc to the creature are both under the measured 2.00pt 1x floor and read ~75% open at 1x; the 1.00pt notch straddles a pixel boundary at x 10.50–11.50 and comes back as a dimple rather than a break; the compressed 1.30pt dot gap above six agents; the 1.27pt chevron counter, which fuses all three chevrons; the 1.30pt-wide ear notch, which half-fills so the creature reads as one lump with a soft dimple — the intended failure, since the brief is a filled mass; and the 30%-alpha ghost track, which is a grey hint at 1x, which is all it is for. Outright 1x LOSS: the 0.90pt closed eye on the sleeping creature, which does not matter because the sleep state is carried by the silhouette (3.40 × 6.53 asleep against 5.07 × 5.30 awake), not by the eye. Four things below the floor is three too many to hand-wave, so the mark ships two representations in one NSImage. The @1x rep is redrawn, not scaled: outer stroke 2.00, inner 1.00, both counters 2.00, a 2.00pt notch on whole points (x 10.00–12.00), dots on a 5.00 pitch, and two chevrons instead of three. Both reps are shown side by side in section 6.

**評審必修：**
- (忠於草圖, 28/40) The dot row leaves the mouth at the fourth agent and the mark walks from 22pt to 49pt, shifting every icon to its left — that is the deviation the user will actually live with, and INARC proves it is avoidable by putting the dots on the arc track instead of a lane below it. Also, one notch cut through BOTH arcs is not the two per-arc ticks that were drawn; at 1x it measures 0.46/0.33, i.e. a 50% smear across two columns, so it neither reads as a break nor survives as two marks. Move to 2.0pt notches on whole points at x10-12 in the primary geometry, not only in the @1x rep. Minor: you are pessimistic about your own chevrons — they measure 0.09 and 0.31 between apexes at 1x, so three-ness partly survives.
- (1x 存活率, 27/40) Put the dots back in the mouth at every count — compress them the way Undiluted and Sleeping Gauge do rather than trailing them outside from n=4 and ejecting the row in the alert state; that one change is most of the gap between this and the winner. Then fix the white 5-hour arc disappearing on a light bar in colour mode (define a dark --fg for light contexts as Undiluted does), and make the 50% ticks additive so they still exist below 50%.

**自陳缺點：**
- The mark is 17.50pt of ink, not 16.00 — it sits optically a shade heavier than the Tailscale and SF Symbols references it will stand next to, and there was no way to buy that back without losing either the dock or the second arc.
- The mark's width is a function of agent count: 22pt at 0–3 agents, 28 at five, 44 at the ceiling, 47–49 in the alert state. Every change reflows the menu bar and shifts every icon to the left of it. That is honest but it is not free, and a user with a crowded bar will notice the jitter more than the information.
- The needs-input state is a lurch: the ring seals, the creature vanishes, and the whole dock jumps 16pt to the right in 0.40s. I kept it because hiding the agents while one is blocked hides the thing you are about to be asked about, but it is the least graceful moment in the design.
- Four elements sit under the 1x counter floor (inter-arc counter, creature counter, notch, chevron counter), so the design genuinely needs a separate hand-drawn @1x representation. A single-asset version of this mark does not exist; anyone who ships only the @2x geometry to a non-Retina display gets a grey mush at the top-dead-centre notch and a fused chevron wedge.
- The 50% notch is invisible once a window drops below 50%, because the arc no longer reaches it. I argue that is a feature, but it does mean the tick the user drew is absent exactly half the time.
- The compressed dock above six agents is not countable — 2.20pt dots on a 3.50 pitch with a 1.30pt gap read as a dashed bar even at 2x. Past six the mark reports business, not headcount, and the brief's 'one dot per agent' is only literally true up to nine.
- The sleeping creature's single closed eye dies completely at 1x, so on a non-Retina display the sleep state is silhouette-only. It still reads, but the charm of it is Retina-exclusive.
- Colour is doing real work in the dock — blue running versus red blocked — and in template mode both become the same tint. The pill shape carries it in monochrome, but a 5.00 x 2.50 pill next to a 2.50 dot is a smaller difference than the colour was.

### 加寬畫布 — SK-WIDE（46/80）

**22pt 怎麼塞：** The sketch's own bottom gap is the answer. Both arcs are open at the bottom, so the ring never uses the bottom of its own 22pt box: the lowest ring ink is the arc terminals at y 16.52 (+0.75 stroke radius = 17.27), not y 20. That leaves the entire bottom band free, and the agent row moves into it rather than under it.

Vertical budget, top dead centre downward, in a 22.00pt box with the ring centred at (11, 11):
  y 2.00–3.50   outer arc, 1.50 stroke (r 9.00 → 7.50, centreline R1 8.25)
  y 3.50–5.00   counter A, 1.50
  y 5.00–6.50   inner arc, 1.50 stroke (r 6.00 → 4.50, centreline R2 5.25)
  y 6.50–8.30   counter B, 1.50 at the horizontal cardinals
  y 8.30–13.50  creature, 5.60 × 5.20
  y 16.75–19.75 lamp row, ⌀3.00 on baseline y 18.25
Total ink 17.75pt in 22.00pt: 2.00 top margin, 2.25 bottom. The ring's outer diameter is 18.00 and its perceived (centreline) diameter is 16.50 — within half a point of the 16pt neighbours it sits beside, with the standard circular overshoot on top.

Then the capacity result that decides the whole composition. The outer arc terminals are at (4.87, 16.52) and (17.13, 16.52) with a 0.75pt stroke radius. A 3.00pt lamp centred on y 18.25 needs 2.25pt of centre distance from them, which frees x 6.31 → 15.69 — an 8.88pt span. At pitch 4.50 that is exactly three slots: 6.50, 11.00, 15.50. Three lamps fit inside the mouth at ZERO extra width. The sketch drew three dots; the geometry independently wanted three. That is the binding: for 1–3 agents the mark is a single 22pt object with the lamps literally inside the ring's opening, exactly as drawn.

From the fourth agent the row locks its origin at x 6.50 and grows right, so the mark widens: 24 / 28 / 33pt for 4 / 5 / 6 agents, then compressed mode, to a 55pt worst case. It still reads as one mark because the row starts inside the mouth and only its tail leaves — the ring appears to be emitting the lamps, not wearing a badge next to them. In the needs-input state the mouth closes and the row is ejected to x 22.50, but the three chevrons point right, straight at the row, which re-binds them.

WHAT WAS SACRIFICED. (1) Faithfulness to the sketch above three agents: past three the lamps are beside the ring, not under it. (2) The creature. The sketch's blob is roughly 45% of the mark; mine is 5.60 × 5.20, about 24%, because four parallel strokes plus two 1.50 counters consume the radius first. It is a mass with an eared top, not a character. (3) The 50% ticks became notches — subtractive, not additive — because an added tick needs a mark plus two gaps and there is no radial room. (4) The whole 1.50 counter system is Retina-first; a second, coarser 1x representation ships alongside it. (5) A fixed-width item: the menu bar reflows as agents spawn.

**幾何：** All values in points; 1pt = 1px in the page. Box 22.00 tall, ring centred at (11.00, 11.00).

ARCS
  Outer (5-hour): centreline radius R1 = 8.25, stroke 1.50, edges r 9.00 / 7.50. Outer diameter 18.00.
  Counter A: r 7.50 → 6.00 = 1.50.
  Inner (7-day): centreline radius R2 = 5.25, stroke 1.50, edges r 6.00 / 4.50.
  Counter B: r 4.50 → creature edge 3.00 = 1.50 at the horizontal cardinals (the tightest approach is at 3 and 9 o'clock, the two crispest points on the circle).
  Stroke 1.50 = 8.3% of the 18.00 outer diameter — the same ratio as SF Symbols Regular (1.33 on 16).
  Caps: butt, so the depleting tip is a clean radial cut.

SWEEP
  0° = top, angles increase clockwise. Each arc starts at 228° (bottom-left) and sweeps 264° clockwise to 132° (bottom-right). Mouth = 96.0°.
  Terminals: outer (4.869, 16.520) and (17.131, 16.520); inner (7.098, 14.513) and (14.902, 14.513).
  Arc length drawn = remaining fraction × 264°. Half of 264° is 132°, which lands exactly on 0° — so the tip crossing top dead centre IS the 50% event. 72% remaining ends at 58.1°; 82% ends at 84.5%°; 6% ends at 249.1°, a stub in the lower left.
  Implemented as one full-sweep path per radius with pathLength="100" and stroke-dasharray "<remaining> 100", so depletion is a single animatable number.

TICKS (notches)
  A 1.00pt vertical slot, x 10.50 → 11.50, y 1.60 → 6.90, applied as an SVG mask over both arcs. At the outer radius that removes 1.00pt of arc = 6.95°; at the inner radius 1.00pt = 10.91°. Both edges are vertical lines on whole points at any scale factor.

CREATURE
  Awake: bbox x 8.20–13.80, y 8.30–13.50 (5.60 × 5.20), centre (11.00, 10.90). Two ear peaks at x ≈ 9.50 and 12.50 with a valley bottom at (11.00, 9.50) — valley depth 1.18. Base corner radius 1.60. Minimum clearance to ring ink 1.06 (diagonally, at the inner arc terminals); 1.70 at the horizontal cardinals.
  Asleep: bbox x 7.90–14.10, y 10.00–13.70 (6.20 × 3.70). Flattens 5.20 → 3.70 (−29%) and widens 5.60 → 6.20. One closed eye as a punched capsule, x 10.75–13.05, y 11.05–12.25 (2.30 × 0.90), even-odd.

LAMPS
  Baseline y = 18.25. Normal: ⌀3.00, gap 1.50, pitch 4.50 — the dot is two 1.50 modules, the gap is one, so the row is built from the ring's own module.
  1–3 agents: row centred on x 11.00 → slots 11.00 / 8.75+13.25 / 6.50+11.00+15.50. Width stays 22.
  4–6 agents: origin fixed at x 6.50, pitch 4.50. Width 24 / 28 / 33.
  7–12 agents: compressed to ⌀2.60, gap 1.00, pitch 3.60. Width 43 at ten, 50 at twelve.
  13+ : 11 lamps then a terminal capsule 4.60 × 2.60 meaning "and more". Width 52, the hard cap.
  Blocked agent: a capsule 5.00 × 3.00, rx 1.50, sorted to the end of the row, advancing pitch + 2.00 — the row's rhythm breaks in monochrome, not only in red.
  Needs-input: row origin moves to x 22.50 at pitch 4.50. Worst case 55pt (6 agents, 3 blocked).

CHEVRONS (needs-input interior)
  Three, stroke 1.50, round caps. Tips at x 8.50 / 12.00 / 15.50 on y 11.00; arms back 2.00 and up/down 2.60 to y 8.40 and 13.60. Pitch 3.50 → perpendicular counter 1.27. Cluster ink 10.50 × 6.70 inside the closed ring's 15.00 interior; clearance 2.25 at the rightmost tip, 1.55 at the leftmost arm ends.
  Closed ring: circle r 8.25, stroke 1.50, alert colour.

EXHAUSTED TRACK
  The outer full-sweep path at 30% alpha, 1.50 stroke, so the silhouette keeps its size when the arc reaches zero.

STALE
  Explicit-endpoint arcs at the last-known sweep, stroke-dasharray 1.40 / 1.40, whole mark at 40% alpha.

1x REPRESENTATION
  Outer stroke 2.00 (r 9.00 → 7.00, centreline 8.00), counter A 2.00 (7.00 → 5.00), inner stroke 1.00 (5.00 → 4.00, centreline 4.50), counter B 2.00, creature 4.00 × 3.80 as a plain dome, lamps ⌀3.00 at pitch 5.00 on baseline y 18.50, two chevrons at 4.20 pitch. Every edge integral, every counter ≥ 2.00.

**中間那隻：** A filled mass, never an outlined drawing, and with no eyes at all while awake — the measured floors kill organic interior detail at this size, so the whole character has to live in the silhouette.

FORM. 5.60 wide × 5.20 tall, sitting inside the inner arc with 1.50 of counter at the horizontal cardinals. A wide rounded base (corner radius 1.60) with a top edge that rises into two ear peaks separated by a 1.18pt valley. The asymmetry of a two-peaked top against a flat-bottomed base is the entire read: it is not a dot, it has a head, it faces you. Deliberately wider than tall so its nearest approach to the inner ring happens at 3 and 9 o'clock, which are the crispest points on a rasterised circle, rather than on the antialiased diagonals.

MOVING. While agents run it bobs: −0.55pt at 40% of the cycle with a 3% vertical stretch, then +0.28pt with a 3.5% squash at 72%, transform-origin at 50% 92% so it rocks on its base rather than floating. 0.95s at rest in the gallery, 0.80s in the scenario. A 0.55pt excursion is 11% of its height — small in absolute terms, unmistakable in the periphery, which is the only place a menu bar icon is ever seen. When nothing runs, it is perfectly still. Not slowed, not dimmed: still. Motion is the signal, so the absence of motion has to be total.

SLEEPING. It flattens and sinks: height 5.20 → 3.70, width 5.60 → 6.20, bbox top from y 8.30 down to y 10.00. That is a 29% loss of height, which is an enormous silhouette change and the reason the sleep state survives anywhere, at any scale, with or without colour. The ears flatten to shallow bumps. One closed eye — exactly one, never two — is punched out as a 2.30 × 0.90 capsule with even-odd fill, sitting in the upper third. It breathes on a 4.4s cycle at ±5% scale from a 50%/95% origin, roughly one twelfth the rate of the working bob, so "asleep" is legible from the tempo alone before you resolve the shape. In colour builds it drops to the muted foreground; in template mode to 72% alpha.

The eye is decoration and I treat it as such: at 1x a 0.90pt cut into a 3.70pt mass is a 25% smudge. The sleep read is carried by the flattening, and the eye is a Retina reward.

**agent 點：** One lamp, one running agent. They live on baseline y 18.25, which is inside the mouth — the opening the two arcs leave at the bottom is exactly where they sit, so for small counts the mark is a single 22pt object with the lamps in the ring's own gap.

SIZE AND PITCH. ⌀3.00 with a 1.50 gap, pitch 4.50. The dot is two 1.50 modules wide and the gap is one, so the row is cut from the same module as the ring's stroke and counters. That shared rhythm is most of why the row reads as part of the mark rather than a separate indicator strip.

CAPACITY AND GROWTH.
  1–3: centred on x 11.00, entirely inside the mouth, width 22pt. Three is the measured capacity of the gap (free span x 6.31 → 15.69 = 8.88pt), which is also the number the sketch drew.
  4–6: origin locks at x 6.50 and the row trails right. Widths 24 / 28 / 33pt.
  7–12: compression. ⌀3.00 → 2.60, gap 1.50 → 1.00, pitch 4.50 → 3.60. Ten agents is 43pt, twelve is 50pt.
  13+: 11 lamps plus a terminal capsule 4.60 × 2.60 that means "and more". 52pt, and that is the hard cap — I refuse to keep growing a menu bar item past the width of three neighbouring glyphs.

COLOUR CODING, WITH A SHAPE BEHIND IT. Running = solid, in the agent colour (#409cff / system blue). Blocked = the alert colour AND a capsule 5.00 × 3.00 instead of a circle, sorted to the end of the row. The shape change is the point: a template image has no colour, so status has to survive as geometry. In the silhouette test the blocked lamps are visibly longer and the row's even rhythm visibly breaks. Finishing agents scale to zero over 0.26s on a slight overshoot curve; the row does not reflow behind them, so a completion never shuffles the ones still running.

Queued agents get nothing. The user asked for "how many agents are running", and a lamp for something that has not started would be a lie about load.

PAST THE POINT THEY NO LONGER FIT. Two thresholds, and both are honest about what is lost. At seven the row stops being countable-by-glance anyway (subitising tops out around four) and switches to compressed pitch, where length is the signal and the individual lamps are a Retina-only refinement — at 1x the 1.00 gaps fuse and the row reads as one bar whose length still rises monotonically with agent count. At thirteen the count is capped and the capsule says so. I would rather the mark say "more than twelve" than imply a precision the pixels cannot carry.

In the needs-input state the mouth closes, so the row is ejected to origin x 22.50 and slides there over the same 0.4s as the ring morph. It looks like the ring spitting the lamps out, and the chevrons that replace the creature point right, directly at them.

**變形：** Drawing 2 shows a CLOSED outline where drawings 1 and 3 show an open one, so the morph is not just a recolour — the mouth shuts. That is the strongest state change available to a bottom-open ring, and it costs nothing structurally.

WHAT CHANGES, in 0.4s, all at once:
  1. Both arcs are replaced by a single closed circle at R1 8.25, stroke 1.50, in the alert red. The 96° gap closes. The inner arc is suppressed — two concentric red rings plus chevrons is illegible at 22pt, and the 7-day window has no deadline, so it can wait.
  2. The creature is replaced by three chevrons.
  3. The lamp row slides 16.00pt right, from origin x 6.50 to x 22.50, because the closed ring now occupies the space they were sitting in.

THE CHEVRONS. Stroke 1.50 with round caps, tips at x 8.50 / 12.00 / 15.50 on the horizontal centreline, arms going back 2.00 and out 2.60 to y 8.40 and 13.60. Pitch 3.50. Cluster ink 10.50 × 6.70, centred in the closed ring's 15.00pt interior with 2.25pt of clearance at the rightmost tip and 1.55pt at the leftmost arm ends. They pulse 1 → 0.6 opacity with a 0.6pt leftward drift on a 1.05s cycle — a slow beckon, not a flash. Alert states in a menu bar have to be able to sit there for two minutes without becoming punishment.

HOW IT READS AT 22pt. Honestly: at 22pt you do not count three chevrons, you read a right-pointing wedge inside a solid red circle. Three is what you see at 2x when you actually look at it, and it is what makes the mark specific rather than generic. What carries at a glance is the silhouette flip — the ring you have been seeing all day as an open C with a tail is suddenly a closed O with something dense inside it, and it is red. That change is visible at the edge of vision, which is where it needs to work.

The chevrons also do the composition's job in the one state where the mouth can no longer hold the lamps: they point right, straight at the ejected row. So the mark still says "these agents, over there, are waiting on you" rather than splitting into two unrelated objects.

Perpendicular counter between adjacent chevrons is 1.27pt, below the 2.00pt 1x floor. At 1x they fuse into a solid wedge — which still means "go / input needed", so the degradation is meaningful rather than mush. The 1x representation drops to two chevrons at 4.20pt pitch to claw back a legal counter.

**1x 誠實報告：** The primary geometry is Retina-first and I am not going to pretend otherwise. A 1.50 stroke on a 1.50 counter is a 3.00pt module; the measured 1x counter floor is 2.00pt. So the mark ships as a two-representation NSImage, and here is exactly what happens in each.

SURVIVES 1x
  Arc stroke 1.50pt. Above the 1.0 floor, 8.3% of the 18pt outer diameter. Peak alpha reaches 1.0 only at the four cardinal tangents and runs 0.65–0.95 on the diagonals — but that is true of every circular glyph ever shipped, including SF Symbols' own "circle". It reads as a solid thin line.
  The 1.00pt notch at top dead centre. This is the best-rasterising element in the design. The arc is horizontally tangent there, so the notch is bounded by two vertical lines at x 10.50 and x 11.50 — whole device pixels at 1x and 2x alike. It comes back 85–100% open at 1x. Making the 50% tick subtractive rather than additive did not only save radial budget; it moved the only fine detail in the mark to the one place on a circle where a cut rasterises perfectly.
  Overall ink 17.75 in 22.00. Whole-pixel top edge at y 2.00. The bottom edge at y 19.75 is a quarter-point, but it belongs to a circular lamp with no straight edge to misalign, so it costs nothing.
  The lamp masses themselves. A solid 3.00pt disc is never in doubt at any scale.
  The sleep silhouette. The body flattens 5.20 → 3.70, which is 29% of its height — scale-independent.

RETINA ONLY — these genuinely fail at 1x
  Counters A and B, 1.50pt. This is the single biggest 1x failure. The two arcs stay fully open at 12, 3, 6 and 9 o'clock, but on the 45° diagonals the antialiased stroke edges bleed into the gap and it fills to roughly 25–35%. At 1x the double ring reads as one thick ring with a light seam. The 7-day and 5-hour windows stop being two distinct readings. This is why the second representation exists.
  Lamp gaps, 1.50pt. The row reads as a beaded bar past about four lamps at 1x. Countable to 3–4 at 1x, to 6 at 2x.
  Compressed row, ⌀2.60 with 1.00 gaps. Fuses into a single capsule at 1x. Countability is Retina-only; length still encodes count monotonically, which is the honest fallback for 7–14 agents.
  Creature ear valley, 1.18pt deep. At 1x it is a dimple, not two ears — the creature degrades to an irregular-topped mass. Still a mass, which is the only thing that matters.
  Sleeping eye slot, 2.30 × 0.90. A 0.90pt cut into a 3.70pt body is a 25% smudge at 1x. Pure Retina decoration.
  Chevron perpendicular counter, 1.27pt. The three chevrons fuse into a solid right-pointing wedge at 1x.
  Stale dashes, 1.40 / 1.40. Fuse at 1x and the arc goes solid. Nothing is actually lost here because staleness is carried by the 40% alpha, which is scale-independent.

THE 1x REPRESENTATION. Same 18pt of ink, re-spent on a coarser module so every edge lands on a whole point and every counter meets the floor: outer stroke 2.00 (r 9.00 → 7.00), counter A 2.00 (7.00 → 5.00), inner stroke 1.00 (5.00 → 4.00), counter B 2.00, creature 4.00 × 3.80 as a plain dome, lamps ⌀3.00 at pitch 5.00 on baseline 18.50, two chevrons at 4.20 pitch. It costs the ears, one chevron and a third of the creature. The hierarchy arguably improves: the 5-hour window becomes visibly the heavier ring, which is the one you actually care about minute to minute. Both representations are rendered side by side in section 06 of the page.

One thing colour cannot carry: the amber burn-rate warning is a colour-only channel and is stripped entirely in template mode. On the real data — 72% remaining but 47 minutes to zero at 92%/h — a template build shows a healthy-looking 72% arc and says nothing about the burn. The only other channel I have is the creature's bob rate, which is a weak signal for a hard deadline. That is an unsolved hole in the monochrome build and I would rather flag it than paper over it.

**評審必修：**
- (忠於草圖, 24/40) You call the TDC notch 'the best-rasterising element in the design... bounded by two vertical lines at x 10.50 and x 11.50 — whole device pixels at 1x and 2x alike... 85-100% open at 1x'. At 1x, 1pt = 1px and pixel boundaries are integers: 10.50 and 11.50 are half-points. Measured, the notch column comes back 0.45 and 0.29 — two 50% columns, a dimple, not a break. Those are whole device pixels at 2x only. Your own sibling entry admits this about the identical geometry. Fix the claim and the geometry (2.0pt on whole points). Second: stop comparing your 16.50 centreline diameter to the 16.00pt Tailscale reference — that reference is ink extent; your ink is 17.75 and you are the only entry that does not admit being oversized. Third: the alert ejects the lamp row 16pt right and drops the 7-day arc, so at the moment you most need one glyph you have two objects and half a gauge.
- (1x 存活率, 22/40) Restore a track ring in the normal states so the mark reads as the bottom-open circle that was drawn instead of a wifi swoosh — it costs no spatial budget and it is the difference between this design having an identity and not. Then keep the lamps inside the mouth at all counts rather than trailing them right, and replace the subtractive notch with the added tick the user actually drew.

**自陳缺點：**
- Above three agents the design departs from the sketch. The user drew the dots in the bottom gap; my row only stays there for 1–3 lamps, and from the fourth it trails out to the right of the ring. Three is the honest measured capacity of a 96° mouth at this size, but it does mean the mark you see most of the day (4–6 agents) is not quite the mark that was drawn.
- The creature is 24% of the mark; the sketch's is roughly 45%. Four parallel strokes plus two 1.50pt counters eat the radius before the centre gets any. It is a legible mass with an eared silhouette, not a character with any personality to speak of, and at 1x it loses even the ears.
- The 1.50 counter system is Retina-first and fails the measured 2.00pt 1x floor. On a non-Retina display the two concentric arcs merge into one thick ring on the diagonals, which is precisely the reading the whole design depends on. It needs a second, coarser NSImage representation to be correct, and that representation is a visibly different drawing.
- The 50% ticks became notches, so they vanish below 50% remaining. I turned that into a feature — seeing the notch means more than half is left — but it is a rationalisation of a constraint, and between roughly 48% and 52% the arc tip and the notch merge into an ambiguous double break.
- Lamp countability caps out around six even at 2x, and the design admits it by switching to a length-encoded compressed row at seven. Between 7 and 12 agents you are reading a bar, not counting lamps, and past 12 you get 'more than twelve' and nothing finer.
- The item width swings from 22pt to 55pt as agents spawn and block, so every menu bar item to its left slides. There is no way around this if one lamp means one agent, and it will be the most-complained-about property of the design in daily use.
- The needs-input state drops the 7-day arc entirely. For as long as you are blocked, one of the two quota readings is simply gone. Defensible for a transient alert, indefensible if a session sits blocked for twenty minutes.
- The amber burn-rate warning is colour-only and disappears in template mode. On the real data (72% remaining, 47 minutes to zero) a template build shows a comfortable-looking arc and gives no hint of the burn.
- Normal states draw no track ring, faithful to the sketch, so at very low quota the mark's silhouette shrinks and it loses optical weight against its neighbours exactly when it most needs attention. I only restore a 30% track in the exhausted state, which is a partial fix.
- The sleeping pose reads as a flattened lozenge with a slot rather than unmistakably as a sleeping animal. It is clearly a changed state, but 'asleep' is carried more by the empty ring around it than by the creature itself.
- @keyframes names cannot be scoped to a root class, so the eleven skw-* animation names in this page are global. Everything else is under .sk-wide.

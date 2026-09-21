# 選單列標記 — 四個修正後的五種融合法

> 互動頁：https://claude.ai/artifact/5ksKPEbiEz79scZWrNUgJa
> mockup：`final-mockups/*.html` · 等寬證明：`docs/evidence/width-invariance-parallax.png`

## 使用者給的四個修正

1. **圓角化** — 不要尖角，全部改成圓角或弧形邊緣
2. **agent 點不得凸出** — 用不同方式融合進去；**寬度在每個狀態都必須一樣**
3. **外圈依阻塞數等分** — N 個 session 在等你，外圈就切成 N 等份
4. **50% 標記用缺口或小圓** — 不可凸出，也不可做成短刺

## 結果

五案全部交出固定 22pt，每個狀態 bounding box 一致。

| 排名 | 做法 | 總分 /80 | 修正落實度 | 1x 與繪圖 |
|---|---|---|---|---|
| 1 | 生物自己扛（Parallax） | 63 | 第 2 | 第 2 |
| 2 | 珠子在軌道上（Beads on the Arc Track） | 62 | 第 1 | 第 3 |
| 3 | 內圈分段（fm-segring） | 58 | 第 3 | 第 1 |
| 4 | 嘴巴合起來（Mouth Gauge） | 51 | 第 4 | 第 4 |
| 5 | 內軌道（Orbit） | 47 | 第 5 | 第 5 |

> 兩位評審結論相反：修正落實度給 beads「SHIP」，1x 評審給 segring。

## 兩個跨案的關鍵發現

### 1. 50% 標記在真實數據下看不看得見

使用者的真實數據是 5h 剩 72%、7d 剩 82%——**兩條弧都已越過頂點**。
- `beads` / `core`：圓點畫在暗軌上、亮弧下面 → 超過 50% 就被蓋住，**在真實數據下隱形**
- `segring`：唯一一個 50% 標記在使用者真正會看的狀態下存在的
- `mouth`：**全場最好** — 0.65 alpha 扁平圓盤，與內外 band 邊界同時相切，兩方向各 0.35 對比階，永遠可見
- 沒有人用缺口：缺口是 counter，1x 下限 2.00pt = 外圈 15.8°／內圈 29.6°，而 15.8° 斷口正是阻塞分段的語言，會被誤讀成「有一個在等你」

### 2. `stroke-linejoin: round` 是假圓角

它只磨圓轉角**外側**，內側仍是尖銳凹角。三案的 chevron 因此在警示狀態下仍有尖點——
而那是唯一必須立刻反應的狀態。只有 `core` 與 `segring` 在描邊前做了真正的弧形 fillet。

## 建議的合併（四塊移植）

1. **底座 = beads** — 唯一整條徑向堆疊通過每條下限的（兩個 counter 都剛好 2.00pt，數字重算到小數點後三位吻合）
2. **50% 標記 = mouth 那顆** — 修掉真實數據下隱形的問題
3. **chevron = core 的真 fillet** — 不用 linejoin:round
4. **補常駐暗珠軌** — 修掉 beads 在 0 隻 agent 時墨水盒從 16.00×16.00 掉到 16.00×13.41 的問題

### 生物自己扛 — Parallax（63/80）

**agent 融合：** The agent count is a ring cut into N equal pieces — the same sentence correction 3 speaks, applied to the same circle. The two arcs already leave a 100° opening at the bottom of the outer ring (r 7.25). That opening, inset 27.65° at each end so it can never touch the arcs' round caps, leaves a 44.7° rail on which the count lives. Every unit is a round-capped segment of zero centreline length — a 1.50pt disc on the rail circle, the same stroke and the same cap as the ring it belongs to.

0 agents: dim rail track only (0.32α), present in every gauge state. 1: one unit at bottom dead centre (φ −90°). 2: units at −90 ± 13.968°, chord 3.500pt, ink gap 2.00pt — clears the 1× counter floor exactly. 3: units at −90° and −90 ± 19.857°, chord 2.500pt, ink gap 1.00pt — clears the 2× floor, closes at 1×. 4 or more: the units merge into one continuous 44.7° bar, 7.16pt of ink.

This is where it stops being exact, and I will not pretend otherwise. 5, 10 and 15 agents render as the identical picture. A unary code of fifteen needs about 45pt of arc at the 2.0pt counter floor; the bottom opening supplies 12.65pt. It is arithmetic, not taste.

The creature carries the coarse band as a redundant channel, which is what rescues the count at 1×: still and low = 0; awake, up 0.30pt, rocking ±2.5° = 1–3; driving, leaning 5° about its base, rocking ±3.5° at 0.62s = 4 or more. At 1× the three-unit gaps close and the rail fuses into a bar, so a fused bar with an upright creature reads three and a fused bar with a leaning creature reads four-plus. The degradation always errs toward "more", never toward "fewer".

Width never changes because nothing was ever added beside the mark. The rail sits on the outer ring's own radius, inside the 22 × 22pt item box, and its dim track runs to y 19.00 whether or not an agent is running — which is also what holds the ink box at exactly 16.00 × 16.00pt in idle, in every agent count, in needs-input at every N, and asleep. Margins are 3.00pt on all four sides. Cross-checked against the shipping references: Tailscale's StatusBarIcon ink is 16.00 × 16.00 and SF Symbol "circle" at pointSize 16 is 16.00 × 16.00. This is the first entry across the rounds to actually land on 16.

**50% 標記：** I took the circle, and the notch is disproved rather than dismissed.

The notch first. A gap cut into a stroke is a counter and is governed by the 2.0pt floor at 1×. On the outer arc (r 7.25) a 2.00pt gap subtends 2.0 / 7.25 = 15.81°; on the inner arc (r 4.15) it subtends 27.61°. Those are not ticks, they are breaks — the outer one is wider than the alert ring's own inter-segment gap looks at small N, and on a *remaining-quota* arc a break is ambiguous with the arc simply ending there, which is the one reading the mark cannot afford. Shrink it to stay under 6° and it measures 0.76pt and closes completely at 1×. There is no size at which a notch is both legible and not a break. So: circle.

The circle, solved. The disc is not punched through and it is not oversized. Its diameter equals the band width exactly — 1.50pt on the outer arc, 1.40pt on the inner — and it is centred on the arc centreline at top dead centre, so it is tangent to r 8.00 and to r 6.50 (outer) and to r 4.85 and r 3.45 (inner). It protrudes in neither direction. In true geometry it is stricter than tangent: the band curves away from the disc's flanks, so the disc touches each band edge at exactly one point and lies strictly inside the band everywhere else.

That leaves the real problem the brief names — how a disc the same width as the stroke can be visible at all. It is not solved with geometry, because geometry is what forbids both alternatives. It is solved with an **alpha step**. The disc is drawn in the *track* layer at full ink while the track itself is at 0.32α: a step of 0.68 across a 1.50pt filled mass, which is above every floor and needs no counter. When remaining is above 50% the live arc passes over the disc and subsumes it — and that is not a loss, it is the reading: the arc extending past top dead centre *is* the above-half signal, and the disc appearing is the below-half signal. At exactly 50% the arc's round cap lands concentric with the disc and the terminus reads as a single dot, which is the threshold confirming itself.

Proof at 16× is in section 2, with the band developed flat so tangency can be checked against a straight edge, plus the rejected notch drawn to scale beside it at its floor-clearing 32px width.

Floors: the disc is a filled mass of 1.50 / 1.40pt, above the 1.25pt practical stroke floor, and it is not a counter, so the 2.0pt counter floor does not apply to it. This is the one detail in the mark that survives 1× outright.

**圓角稽核：** Every vertex in the mark, with its radius. There is no zero-radius vertex and no cusp anywhere.

Outer arc, both terminals — round cap, R 0.750. Outer track, both terminals — round cap, R 0.750. Inner arc and inner track terminals, four of them — round cap, R 0.700. Outer 50% disc — a full circle, R 0.750, no vertex at all. Inner 50% disc — full circle, R 0.700. Creature crown lobes ×2 — convex arc, R 0.950. Creature crown valley — concave fillet, R 0.600, tangent to both lobes (|V−L| = r_lobe + r_valley = 1.550). Creature flank-to-lobe and flank-to-base ×4 — straight segments on the common tangent of two equal 0.950 circles, so G1-continuous with no vertex. Creature base corners ×2 — convex arc, R 0.950. Sleeping eye — a closed ellipse, 0.950 × 0.500 semi-axes, no cusp (a lens would have two, which is why it is not a lens). Tally units — full circles, R 0.750. Tally saturated bar ×2 terminals — round cap, R 0.750. Alert segment terminals — round cap, R 0.750. Alert ring at N=1 — a closed circle, no vertex. Chevron terminals ×6 — round cap, R 0.625.

The chevrons are the case worth spelling out. A two-legged chevron has an apex join whose *inner* side is a zero-radius corner no matter what stroke-linejoin is set to, so I did not draw one. Each chevron is a single circular arc of radius 2.104pt with round caps — computed from a 3.75pt chord and a 1.15pt sagitta. The user asked for rounded corners or arc edges; an arc has no corner to round. The alert interior therefore contains zero joins.

Two radii sit below the ~0.75pt threshold at which a curve resolves as a curve at 1×: the crown valley at 0.600 and the chevron caps at 0.625. Neither becomes a point — they become slightly blunter curves. The objection being answered was a sharp V between two pointed peaks; the V is now a 0.600pt fillet only 0.458pt deep, so even where the fillet cannot resolve the crown reads as one dome, never as a spike.

**外圈分段：** The outer ring at r 7.25, stroke 1.50, round caps. A 2.00pt ink gap needs a 27.936° centreline separation, because the chord is 2R·sin(Δ/2) and 14.5·sin(13.968°) = 3.500pt, less 0.75pt of round cap at each end. That gap is fixed at every N; the segments shrink.

N=1 — a continuous closed ring, no gaps. Confirmed by the drawing itself and by the logic: one segment with one gap would read as an incomplete ring, indistinguishable from the gauge.
N=2 — 2 × 152.064°, gaps at 3 and 9 o'clock.
N=3 — 3 × 92.064°.
N=4 — 4 × 62.064°.
N=5 — 5 × 44.064°, 7.08pt of ink per segment, 3.5:1 segment-to-gap.
N=6 — 6 × 32.064°, 5.56pt of ink, 2.8:1. This is the ceiling.
N≥7 — the ring holds at six and the exact number goes to the menu.

The ceiling is derived, not chosen: a segment stops reading as a segment and starts reading as a dash below about 2.5× the gap, i.e. 5.0pt of ink. N=6 gives 5.56pt and clears it; N=7 gives 4.55pt and does not. Honest caveat on top of that: five and six already need deliberate counting rather than a glance. One, two and three are instant.

Phase matters and is set by parity, for a reason. For even N the segments are centred on top and bottom dead centre (gaps at 90° + 180/N + k·360/N); for odd N the gaps are centred on top dead centre (gaps at 90° + k·360/N). Top dead centre is the mark's reference point — it is where both 50% discs live — so in alert it is always a deterministic landmark. The useful consequence is that bottom dead centre is never inside a gap at any N ≤ 7 (the nearest gap centre is at least 25.7° away), so the ink box stays exactly 16.00 × 16.00pt in every alert state, odd or even.

In needs-input the inner arc is dropped entirely — quota is not the message when a human is being waited on — and the interior carries three right-pointing chevrons, group 10.20pt wide and 5.00pt tall, arc radius 2.104pt, stroke 1.25pt, pitch 3.90pt. The whole mark takes the amber; it is the one state that is not a template image.

**共用語言：** Yes — one visual language, deliberately, and it is the strongest thing in the entry.

The rule is: **a ring is cut into N equal pieces, separated by a 2.00pt gap.** Needs-input cuts the whole 360° of the outer ring. The agent tally cuts the 100° opening that the very same outer ring already leaves at the bottom. Same circle, same radius 7.25, same 1.50pt stroke, same round caps, same gap derived from the same chord arithmetic. The tally is not a second counter bolted onto a gauge; it is the outer ring counting in the place where the outer ring is absent.

The opportunity the brief flagged is real and I took it. The alternative — dots in a row, a filled proportion bar, a needle — would have meant the mark spoke two grammars, one for "how many agents" and one for "how many blocked", and a 16pt icon cannot afford to teach two grammars.

Where the shared language does not reach, I say so rather than fake it. The 360° ring holds six pieces; the 44.7° opening holds three. Same rule, wildly different budgets, because one is eight times longer than the other. So the tally's fourth state is saturation, not a fourth piece, and the creature supplies the bit that distinguishes three from four-plus. That is the language admitting its limit, not abandoning it.

Both ceilings are stated on the face of the mark's own documentation rather than buried: the alert ring holds at six, the tally holds at "four or more", and the menu behind the icon carries the exact numbers past either.

**中間那隻：** A filled mass, 4.10 × 3.35pt, no interior detail, no eyes awake, built entirely from arcs and their common tangents.

Crown: two lobes of R 0.950, centres (9.90, 10.35) and (12.10, 10.35), tops at y 9.40. Between them a concave fillet of R 0.600 centred at (11, 9.258), tangent to both lobes, floor at y 9.858 — a valley 0.458pt deep. That shallowness is deliberate twice over: the objection was a sharp V between two peaks, and at 16pt the crown has to read as one mass. At 2× it is a visible soft dip; at 1× the two lobes merge into a single dome. There is no vertex either way.

Flanks: straight segments on the outer common tangent of the crown lobe and the base corner, both R 0.950 — tangent-continuous at both ends, so no corner exists to round. Base: two corners of R 0.950 with a 1.70pt flat between them, bottom at y 12.90. Maximum envelope radius 2.148pt, which sets counter B at 1.30pt over the crown and flanks and 1.16pt at the two inner-arc terminals.

Motion, all event-triggered and all terminating. Still (0 agents): no transform, no animation at all. Awake (1–3): rises 0.30pt and rocks ±2.5° about a pivot at (11, 12.60), period 1.1s. Driving (4+): leans 5° about (11, 12.90), rises 0.30pt, rocks ±3.5° at 0.62s. The lean was checked against the inner arc, not guessed — at 5° the crown's outer corner reaches r 2.263 and keeps 1.19pt of clearance; at 6° it would eat into that.

Sleep, when either window is exhausted: the body flattens to 0.86 anchored on its base, so the crown drops 0.47pt to y 9.969 while the base stays at 12.90, and the lobe arcs become elliptical (ry 0.817, valley ry 0.516) — the crown folds down rather than shrinking. One eye appears, exactly one, as a closed ellipse 1.90 × 1.00pt centred at (11, 11.45), punched through the mass with fill-rule evenodd. Its 1.00pt minor axis is exactly the 2× counter floor and closes completely at 1× — which costs nothing, because sleep is also carried by the dropped crown, the flattened body and the emptied arc. At 1× the creature is simply a settled mass.

Under Reduce Motion the rises and the lean stay — they are transforms, not animations — so the creature still distinguishes still from awake from driving with no motion at all.

**半徑預算：** 8.00pt of radius, spent outward from the centre: creature mass 0 → 2.148, counter B 2.148 → 3.45 (1.30pt), inner arc stroke 3.45 → 4.85 (1.40pt), counter A 4.85 → 6.50 (1.60pt), outer arc stroke 6.50 → 8.00 (1.50pt). Total 8.00 → 16.00pt of ink.

What it sacrifices: both counters. 1.60pt and 1.30pt are under the 2.0pt 1× counter floor. At 1× the two arcs fuse into a banded double-line and the creature's crown touches the inner arc; at 2× both clear the 1.0pt floor by 60% and 30% respectively. I bought two things with that money — a 4.10pt-wide creature that can actually hold a posture, and a 1.50pt outer stroke that is 20% over the practical floor rather than sitting on it. The alternative allocation, 2.0pt counters honoured at 1×, leaves the creature about 1.2pt across, which is a speck and cannot express anything.

The inner arc is also deliberately thinner than the outer, 1.40 against 1.50. That is not a saving, it is a reading: the outer arc is the 5-hour window, which moves fast and needs the longer and heavier stroke; the inner is the 7-day window, which barely moves.

Pixel parity, stated exactly and not overclaimed: 1.50pt strokes on half-point centrelines put band edges on whole device pixels at the four cardinal points — including top dead centre, where both 50% discs sit and where the mark's only tangency claim is made. Everywhere else on a circle the rasteriser antialiases whatever you do, and claiming otherwise would be false.

**1x 誠實報告：** At 2× — every current Mac — everything in this mark clears its floor, most of it by 20–60%. At 1× it loses three things and keeps the rest, and each loss is covered redundantly.

Clears 1×: outer arc stroke 1.50pt (20% over the 1.25 practical floor); inner arc stroke 1.40pt; tally stroke and units 1.50pt; both 50% discs (1.50 / 1.40pt filled masses carried by a 0.68 alpha step, not by geometry — the one load-bearing detail that survives outright); the tally gap at N=2, 2.00pt, set *from* the floor; the alert segment gaps, 2.00pt at every N.

At the floor: chevron stroke 1.25pt, the only stroke sitting exactly on the practical floor. It is full-saturation amber rather than template grey, so it has contrast headroom a grey stroke would not.

Fails 1×, clears 2×: counter A between the arcs, 1.60pt — the pair reads as one banded double-line, which still reads as a gauge. Counter B between inner arc and creature, 1.30pt typical and 1.16pt at the inner-arc terminals — the crown touches the arc. The tally gap at N=3, 1.00pt — it fuses to a bar, so the error is always "more", never "fewer", and the creature's posture separates 3 from 4+. Chevron counters, 1.50pt at the tails and 2.03pt at the apexes — the three chevrons fuse into one right-pointing mass; direction and urgency survive, only the count of three is lost, and three was never the message. Chevron-to-ring clearance 1.40pt. Sleeping eye minor axis 1.00pt — it closes completely, and sleep is still carried by the dropped crown, the flattened body and the emptied arc.

Does not resolve as a curve at 1×: crown valley R 0.600 and chevron caps R 0.625. Both become blunter, neither becomes a point.

The thing I will not claim: the 0.32α dim tracks. A 1.50pt stroke at 0.32 peaks at alpha 0.32 with zero fully-opaque pixels at 1×. It renders as faint grey and nothing more. That is acceptable only because the track's sole job is to supply context so a depleted arc never reads as a rendering fault — every actual value is carried by full-ink elements sitting on top of it.

Ink height in needs-input is exactly 16.00pt at every N because of the parity rule on segment phase; it would have dropped to 15.79pt at odd N under the obvious phasing, which is why the phasing is not the obvious one.

**評審必修：**
- (修正落實度, 33/40) Stop justifying the counter breach with a false counterfactual: 8.00 - 1.50 - 1.40 - 2.00 - 2.00 leaves 1.10pt of radius, i.e. a 2.20pt creature, not 'about 1.2pt across' - beads and segring both build one. Either buy counter A back to 2.00 and ship a 2.2pt creature, or restate the trade honestly as 4.10pt of creature bought with a 1x gauge fusion.
- (1x 與繪圖, 30/40) The creature numbers do not close. Lobe centres at (9.90,10.35)/(12.10,10.35) with R0.95 put the envelope at 2.228 from (11,11), not the claimed 2.148, so counter B is 1.222pt, not 1.30pt — the tightest clearance in the mark is 6% worse than published. Creature height is 3.50pt (9.40 to 12.90), not 3.35pt. Counter A is 1.65pt, not 1.60pt (that one errs honest). Separately: at N=2 and N=6 the parity rule puts gaps at 0 and 180 degrees, so the alert ink width is 15.571pt, not the claimed 16.00 — the rule protects the height and breaks the width.

**自陳缺點：**
- 5, 10 and 15 running agents render as the identical picture. The tally is exact to three (to two at 1x) and then saturates. The mark can say "four or more" and nothing finer; the exact number lives in the menu. This is arithmetic — a unary code of fifteen needs ~45pt of arc at the 2.0pt counter floor and the bottom opening supplies 12.65pt — but it is still a real loss against the brief's "one unit per running agent".
- The method asked the creature to carry the count in its body and it cannot. One agent-step spread across a 3.35pt-tall creature is ~0.22pt, a fifth of the stroke floor. I built it, measured it, and replaced it with the tally. The creature carries only a three-level band (still / awake / driving), and that band is doing real work as the 1x disambiguator rather than being decoration.
- Both radial counters fail the 1x floor — 1.60pt between the arcs and 1.30pt (1.16pt at the arc terminals) between the inner arc and the creature. At 1x the whole interior reads as one nested mass rather than three separated elements. Every allocation in this budget sacrifices something; this one sacrifices 1x separation to buy a creature large enough to hold a posture.
- The 50% disc is invisible above 50% remaining, because the live arc passes over it. I argue this is information-bearing — the disc appearing is the below-half signal — but a reviewer wanting a permanently visible reference tick will not get one, and no permanently visible version exists that does not either protrude or become a counter.
- The crown valley is only 0.458pt deep with a 0.600pt fillet. At 1x the two lobes merge into a single dome and the creature loses its ears entirely. Deepening the valley means either a smaller fillet radius (which starts reading as the sharp V the user objected to) or a wider crown (which eats counter B). I chose the dome.
- Three chevrons cannot resolve at 1x: the tail counters are 1.50pt against a 2.0pt floor, so they fuse into one right-pointing mass. Direction and urgency survive, the count of three does not. Making them resolve would mean a chevron group wider than the ring's interior.
- The sleeping eye closes completely at 1x — its 1.00pt minor axis is exactly the 2x floor and nothing more. The sleep pose survives on the dropped crown and flattened body alone at 1x.
- The dim 0.32-alpha tracks never produce a fully opaque pixel at 1x. They read as faint grey. They are structurally necessary — they hold the ink box at 16.00pt tall in idle and stop a depleted arc reading as a bug — but their own legibility at 1x is not something I can defend.
- Pixel parity is exact only at the four cardinal points. Everywhere else on a circle the rasteriser antialiases regardless of centreline placement.
- The alert ring's count is only reliably subitised to three or four. Five and six require deliberate counting, and seven and above are not encoded at all — the ring holds at six.

### 珠子在軌道上 — Beads on the Arc Track（62/80）

**agent 融合：** The agent count lives on the outer circle itself, inside the 100° bottom gap the two gauges leave — so it costs zero width and zero height, and the item box is 22 × 22pt with 16.00 × 16.00pt of ink in every state.

Geometry: bead track radius 7.25 (the same circle as the 5h gauge), bead = a filled circle of ø1.25, concentric inside the 1.50 band with a 0.125 inset on each side, so a bead is visibly subordinate to the gauge it rides on. Pitch 2.90pt = 22.918° (ink 1.25 + gap 1.65). Beads are centred as a group on bottom dead centre and grow outward symmetrically: N=1 at −90°; N=2 at −90 ± 11.459°; N=3 at −66.7°, −90°, −113.3°.

The track holds exactly three. At N=3 the outermost bead's cap edge sits 2.05pt (arc) / 2.02pt (chord) from the gauge terminal's cap edge — the 1× counter floor, exactly — so beads never fuse with the gauge. There is no room for a fourth: a fourth unit costs another 2.90pt and only 2.05pt of clearance remains on each side.

Past three the track is FULL, and full is its own signal: at N≥4 the three beads fuse into one continuous round-capped bar spanning the same 7.15pt of visible strip (path −67.08° to −112.92°, stroke 1.25). Meaning: "more than the track can count." It is unambiguous because a solid 7.15pt bar never occurs at N≤3 (N=1 is a single 1.25pt dot, N=3 is a dotted line of the same total length), and because the bar keeps its 2.05pt end clearance, the ring never closes — so a busy normal state can never be mistaken for the closed alert ring.

0 → 1: the first bead fades and scales in at bottom dead centre over 0.25s. 1 → 2: the single bead slides 1.45pt to its new position and the second fades in at the mirror position; adds and removes are always symmetric about BDC, so the group never appears to drift. 3 → 4: the two gaps close (0.18s) into the bar. 4 → 3: the bar splits again. Removal is the same run backwards. Every transition is inside the fixed gap.

5, 10 and 15 agents therefore render identically, and I say so on the page rather than pretending. At 16pt you cannot resolve five discrete units in 9pt of arc; the exact number belongs in the dropdown. Width invariance is proved in section 3: 11 states share one ruler, box top y=0, ink top y=3.00, ink bottom y=19.00, box bottom y=22.00, identical in all of them.

In needs-input the bead track is suspended, because the ring closes over the gap and the blocked count takes the whole circle. That is also the answer to "how a blocked agent bead is distinguished": it stops being a bead and is promoted to the ring.

**50% 標記：** I chose the CIRCLE, and it is a low-water dot: a filled circle on the arc centreline whose diameter equals that arc's stroke width — ø1.50 at (11, 3.75) on the 5h band, ø1.25 at (11, 7.125) on the 7d band. It is tangent to the outer band edge and to the inner band edge simultaneously, so it protrudes 0.00pt outward and 0.00pt inward. Section 2 proves this at 16×: the dashed r8.00 / r6.50 and r4.50 / r3.25 edge arcs pass exactly through the dot's poles.

Why not the notch. I checked the arc-length arithmetic rather than assuming it. A gap cut into a stroke is a counter, so it needs 2.00pt at 1×. On the outer arc 2.00pt subtends 15.8°; on the inner arc it subtends 29.6°. Two problems, either of which is fatal: (a) a 15.8° break at top dead centre is exactly the visual language I use for the blocked-count cuts (visible gap 2.00pt) — the 50% mark would read as "one session is blocked"; (b) the notch is not even a true counter here, because the dim full-length track sits behind the lit arc, so the "gap" is a 1.00→0.30 alpha step, not a hole, and the previous round's measurements show alpha-only detail at this size going mushy. A 1.0pt notch closes at 1× outright. So the notch cannot be made to clear the floor without destroying the segmentation language, and I dropped it.

Now the circle's own trap, solved rather than dodged. To be visible a circle must differ from the stroke. Bigger than the stroke → protrudes (forbidden). A hole punched through → a counter, and the biggest hole that fits inside a 1.50pt band is 1.00pt, leaving 0.25pt slivers of stroke above and below it — both under the 1.00pt stroke floor, so at 1× the hole degenerates into the notch I just rejected. Neither works.

The resolution is to stop demanding that the dot be visible at all times. The dot is drawn at full alpha ON the dim track, UNDER the lit arc. Below 50% remaining, the lit arc has not reached top dead centre, so the dot stands alone: a solid full-black disc on a 30% grey track — maximum possible contrast, a filled mass rather than a hairline, and no counter anywhere. Above 50%, the lit arc covers the dot and they fuse invisibly — which costs nothing, because the arc reaching over the top IS the statement that you are above half. The question "am I past halfway?" is answered either way, and the crossing itself is legible: the arc's round cap arrives exactly on the dot and swallows it.

So the mark costs zero counters, never protrudes, and never depends on a sub-pixel feature. The real data (72% and 82%) hides both dots; the gallery and the 16× close-up therefore also show 45% / 20%, where both are exposed, and the asleep state shows the dot alone at the top of a fully dim track.

**圓角稽核：** Nothing in the mark terminates in a point. Every vertex, listed:

CREATURE (a closed chain of seven arcs joined tangentially by straight segments — G1 at every join, so it has no corners at all, not even rounded ones). Requested → applied (the solver clamps any radius that would overrun its edge):
- V1 upper-left (9.86, 10.72) 0.44 → 0.440, convex, interior 153.0°
- V2 left ear (10.38, 9.70) 0.40 → 0.315, convex, interior 68.5°
- V3 crown valley (11.00, 10.40) 0.34 → 0.340, CONCAVE, interior 83.1°
- V4 right ear (11.62, 9.70) 0.40 → 0.315, convex, interior 68.5°
- V5 upper-right (12.14, 10.72) 0.44 → 0.440, convex, interior 153.0°
- V6 lower-right (12.14, 11.92) 0.56 → 0.560, convex, 90.0°
- V7 lower-left (9.86, 11.92) 0.56 → 0.560, convex, 90.0°
Smallest radius anywhere in the creature: 0.315pt.

ARC TERMINALS: 5h round caps r0.750 (×2), 7d round caps r0.625 (×2). Never butt.
AGENT BEADS: filled circles r0.625; the fused bar's ends are round caps r0.625.
50% MARKS: filled circles r0.750 (outer) and r0.625 (inner) — a circle has no vertex.
ALERT SEGMENTS: round caps r0.750 at both ends of every segment; the swarm dashes likewise.
CHEVRONS: the apex is NOT a round join (a round line-join still leaves a sharp re-entrant corner on the inside). It is an explicit arc fillet of r0.75 on the centreline, which exceeds half the 1.20 stroke, so the outer silhouette radius is 1.35 and the inner silhouette radius is 0.15 — positive, therefore rounded. Tail caps are round, r0.600.
SLEEPING CREATURE: a stadium, both ends fully round, r0.495.
GUIDE/TICK SPURS: there are none. The mark has no spurs at all.

Radii below the floors: the crown valley fillet (0.340) and the ear fillets (0.315) are sub-pixel at 1×, and the dimple they form (mouth 0.51pt, depth 0.29pt) closes at both 1× and 2×. It is an open silhouette notch, not a counter, so it degrades to a flattening rather than a rendering fault — the creature reads as a dome below 8× and as two lobes above it. That is stated in the rasterisation table rather than claimed away. The chevron apex fillet (0.75) and every cap radius (0.6–0.75) are above the floors.

**外圈分段：** When N sessions are blocked, the outer circle closes into a full ring at the alert colour (#FF9F0A) and divides into N equal segments.

Gap: the cut is a counter, so it must clear 2.00pt at 1×. With round caps the path gap is 2.00 + 1.50 (stroke) = 3.50pt, which at R 7.25 is 27.66°. Circumference is 45.55pt, so visible segment length = 45.55/N − 2.00.

N=1: a continuous, uncut ring. One blocked session is not a partition, and cutting a ring into "one part" would be a lie about the geometry. The real data (1 session blocked for 2 minutes) therefore renders as the closed amber ring with chevrons.
N=2: two 20.78pt half-rings. N=3: three 13.18pt thirds. N=4: 9.39pt. N=5: 7.11pt. N=6: 5.59pt. N=7: 4.51pt.

Cut placement: the first cut is centred at top dead centre (90°), then every 360/N. So N=2 cuts at 90° and 270°, N=3 at 90°, 210°, 330°. Putting a cut at TDC means the ring always visibly breaks where the eye lands first, and it rhymes with the 50% mark sitting at the same angle on the gauge.

Ceiling: N=7. The rule is that a segment must stay at least twice the length of the gap that separates it, otherwise the ring stops reading as "divided" and starts reading as "dotted". At N=7 the ratio is 4.51 : 2.00 = 2.25:1; at N=8 it is 1.85:1 and the read collapses. (Honestly: comfortable counting round a 16pt ring stops at about four. Seven is the geometric limit, not the cognitive one, which is why the exact number is always in the dropdown.)

Past the ceiling: N≥8 renders a distinct "swarm" texture — 11 uniform dashes, each 2.07pt visible with 2.07pt gaps, both above the 1× counter floor. It is unmistakably different from a continuous ring (N=1) and from a 2–7 partition (whose segments are long and unequal in number, not uniform), and it means "eight or more". The one ambiguity I accept: a viewer who counts the swarm gets 11 for any N≥8.

The alert state suspends the agent beads, because the closed ring occupies the bottom gap. That is deliberate: when a human is being waited on, how many agents are running is not the question.

**共用語言：** Yes — one language, deliberately, and it is the same circle.

The outer circle has three jobs and one grammar: "an arc, cut by gaps". Its top 260° is the 5h gauge; its bottom 100° gap carries the agent beads; when a human is being waited on it closes into a full 360° ring and cuts itself into one part per blocked session. The beads sit at R 7.25, the same radius as the gauge, with the same round-capped terminals — an agent bead is literally the outer ring continuing through its own gap, and the blocked partition is the same ring closed and divided. Nothing is bolted on: there is no second counter object anywhere in the mark.

Where I deliberately conjugate the language differently: the alert ring PARTITIONS a fixed whole (the segments resize as N grows, because a ring is always full and N is always at least 1), while the agent track ACCUMULATES fixed-size units (beads of constant ø1.25 at constant 2.90pt pitch, because the count starts at zero and the empty track must read as "nothing running"). Cutting the bottom gap into N equal parts would have been the purer echo, and I tried it: the gap has only 7.15pt of usable strip, so equal parts at the 2.00pt counter floor top out at two, and at three the segments fall below their own cap diameter. Constant-pitch beads get the same three units with a truthful 1.65pt gap and give idle a clean, empty gap. So: same grammar, different inflection, for a defensible reason — and the two never appear at once, since the alert ring occupies the bead track.

The gauge's own 50% mark stands slightly apart: it is a dot, not a cut, precisely so that it cannot be confused with a segmentation cut. That is a deliberate separation inside the shared language, not an inconsistency — cuts mean "how many", the dot means "half".

**中間那隻：** A filled mass, 2.28 × 1.98pt, sitting at the centre with its crown at y 9.94 and its feet at y 11.92. Max radius from the mark centre is 1.243pt, which holds the counter to the 7d band at 2.007pt — above the 2.00pt floor, verified numerically along the whole outline rather than assumed from the bounding box.

Redrawn crown: the pointed ears and the sharp V are gone. Two lobes now meet in a concave fillet of r0.340 with ear fillets of r0.315, giving a dimple 0.51pt wide and 0.29pt deep. At 1× and 2× that dimple closes and the creature reads as a plain rounded dome; from about 8× it reads as a two-lobed crown. I state that instead of pretending an organic silhouette survives 2.3pt. Everything else about it is arcs: the whole outline is a tangent-continuous chain of seven circular arcs, the smallest 0.315pt, with no corner anywhere. No eyes, no interior detail at all — a solid mass, which is the only thing that rasterises honestly at this size.

Motion: it bobs −0.35pt and back, 1.15s ease-in-out, and only while agents are running. Nothing runs when the agent count is zero: the creature is still in idle, still while asleep. The bob is a transform on a separate layer, so it costs nothing in the alpha channel and nothing in the bounding box. Under prefers-reduced-motion the bob is removed and the creature simply sits — no information is lost, because the beads, not the motion, carry the agent count.

Sleep: when a quota window is exhausted the creature drops 0.36pt and flattens into a stadium 1.60 × 1.00pt (r0.495, both ends fully round), curled at the bottom of the interior, clearance 2.03pt to the 7d band. It has NO eye. A closed-curve eye is a counter, and no counter can exist inside a 1.0pt-thick mass — the floor is 2.0pt. Sleep is read from the pose plus the dim gauge, not from a face. In the asleep state the 50% dot at the top of the exhausted arc is exposed, which is a second, independent signal that the window is empty.

**半徑預算：** 8.00pt of radius, spent to the last point, and it buys exactly 16.00 × 16.00pt of ink in a 22 × 22pt box — the Tailscale/SF-Symbol target that nobody hit last round:

  creature 1.25 | counter 2.00 | 7d stroke 1.25 | counter 2.00 | 5h stroke 1.50 = 8.00

Both counters sit exactly on the 2.00pt 1× floor, not above it, and both strokes sit inside the 1.3–1.8pt band (1.50 = 9.4% of the mark, 1.25 = 7.8%, slightly under the band — the price of a second gauge).

What it sacrifices, plainly: THE CREATURE. Once both counters are pinned at 2.00 and both strokes are at their minimum honest weights, the centre has 1.25pt of radius left, so the creature is a 2.3pt pebble. It cannot have ears that survive, cannot have an eye, cannot have a face. I chose to spend the budget on the two gauges and the counters between them, because the gauges are what the item is for, and to put the creature's character into its motion and its sleep pose instead of its silhouette. If I had taken the full 9.00pt available the creature could have been 3.3pt across, but the mark would be 18pt of ink — which is precisely the failure the measurements called out.

Second sacrifice: pixel parity on the inner arc. The outer silhouette lands on whole pixels in both axes (x and y = 3.00 and 19.00), which is the edge that matters for crispness; the 7d band's edges land on y 6.50 / 7.75, so that arc antialiases at 1×. Moving it to a half-point centreline would have cost one of the 2.00pt counters, and I would rather have a slightly soft inner arc than a counter that fills in.

**1x 誠實報告：** Honest ledger, 1× and 2×:

HOLDS AT 1×: 5h stroke 1.50 (above the 1.25 practical floor). Counter 5h→7d 2.00 (exactly the floor). Counter 7d→creature 2.007. Bead end clearance 2.02pt chord. Alert cut 2.00pt visible. Swarm dash 2.07/2.07. Both 50% dots (ø1.50 and ø1.25 filled masses — and, crucially, no counter at all, which is why this half-mark choice survives where a notch does not). Outer silhouette edges on whole pixels at x,y = 3.00 / 19.00.

AT THE FLOOR: 7d stroke 1.25pt. This is the practical minimum from the measurements and it greys slightly at 1×; I would not go to 1.0 after the previous round measured a 1.0pt arc going grey down most of its length. The dim track at alpha 0.30 is grey by design — it only has to prove the arc exists.

DOES NOT HOLD AT 1×, stated rather than claimed away:
- Bead gap 1.65pt. Two beads resolve at 1×; three merge into a short bar at 1× and resolve at 2×. So on a non-Retina display the mark distinguishes 0, 1, 2 and "several", not 0–3. Everything since 2012 is 2×.
- Chevron clear gap 1.00pt. At 1× the three chevrons merge into one zigzag band. It still reads "forward / waiting on you", and the state is carried by colour, by the closed ring and by the interior swap, not by counting three chevrons.
- Crown dimple, mouth 0.51 / depth 0.29. Closes at 1× AND at 2×. It is an open notch, not a counter, so it degrades to a flat crown; the creature is a dome below 8×.
- Inner band edges at y 6.50 / 7.75 antialias at 1× (see budget).

Bead ø1.25 at 1× is a single 1.25px dot: at the edge, but it is a filled mass, the most robust primitive available, not a hairline.

What I will NOT claim: that five, ten or fifteen agents are countable at 16pt (they are not — they all render as the fused bar); that eight or more blocked sessions are countable (they render as an 11-dash texture); that the creature's two lobes are visible in a menu bar.

**評審必修：**
- (修正落實度, 34/40) The width-invariance table claims ink bottom y=19.00 in all eleven states; at N=0 nothing is drawn in the gap and the 260-degree dim track's caps stop at y 16.41, so idle ink is 16.00 x 13.41. Add a permanent dim bead track (core's rail) so the claim becomes true.
- (1x 與繪圖, 28/40) There is no dim bead track in the r-a0 def, so at 0 agents the bottom ink stops at the arc terminal cap, y=16.41. At 1-3 agents it is y=18.875, and in alert y=19.00. The ink box is therefore 16.00 x 13.41 idle and 16.00 x 15.875 running — the mark grows a chin the moment work starts — while section 3 claims ink bottom y=19.00 identical in all eleven states. Draw the three-bead track dim and always-on, the way segring and mouth draw theirs, and the claim becomes true.

**自陳缺點：**
- The creature is 2.3pt across — a pebble. Hitting 16.00pt of ink with both counters at the 2.00pt floor leaves nothing else, so the character has to live in the motion and the sleep pose, not the silhouette. Anyone who wants the hand-drawn creature to be recognisable at real size will be disappointed.
- The agent count stops at three. 5, 10 and 15 agents render identically as the fused bar. The mark says '3+', and the exact number is only in the dropdown.
- At 1× (external non-Retina displays) the 1.65pt bead gap merges, so three agents read as 'several'. Only 0, 1, 2 and 'many' survive there.
- Both 50% dots are invisible whenever the window is above half — which includes the real data, 72% and 82%. The mark is legible either way, but a reviewer looking for the dot in the hero state will not find it, and that behaviour has to be explained rather than seen.
- The crown dimple (0.51 × 0.29pt) is invisible below about 8×, so the two-lobed crown the user drew exists only in the construction views.
- Eight or more blocked sessions all render as the same 11-dash swarm, which a viewer might miscount as exactly 11.
- The 7d arc at 1.25pt is at the practical stroke floor and greys slightly at 1×; its band edges (y 6.50 / 7.75) antialias because I spent the parity budget on the two 2.00pt counters instead.
- Three chevrons with a 1.00pt clear gap merge into a zigzag band at 1×; the needs-input state then depends on colour, the closed ring and the interior swap rather than on the chevron count.
- The alert state suspends the agent beads entirely, so while a session is blocked the mark says nothing about how many agents are still running.

### 內圈分段 — fm-segring（58/80）

**agent 融合：** The count lives on the outer ring's own centreline (R 7.25), in the 110 degree opening the two arcs already leave at the bottom. Three cells, always present as dim pips at alpha 0.28, each a disc of d 1.50 (= the outer stroke width) centred at -62.66, -90 and -117.34 degrees. Visible gap between cells 1.96pt; clearance from each cell to the nearest arc terminal cap 2.00pt. Arithmetic: the opening is 12.657pt of arc at R 7.25; subtract 2 x 2.00pt terminal clearance and the cap allowance and the usable strip is 8.419pt, which holds exactly three 1.50pt pips with two 1.96pt gaps (3 x 1.50 + 2 x 1.96 = 8.42). Four does not fit and I do not pretend it does: 4 x 1.50 + 3 x 2.00 = 12.00pt, 42% more arc than exists. States: 0 = three dim pips, nothing lit; 1 = first pip (nearest the right-hand terminal, continuing the gauge's clockwise reading order) inked; 2 = two; 3 = three; 4 or more = the three cells and their gaps fuse into one continuous 8.42pt bar at full ink, which is unambiguous because N=1 is a single 1.50pt pip, not a bar. So the mark distinguishes 0, 1, 2, 3 and "four or more"; the exact number above three is menu territory. The width never changes because the strip is inside the 16.00pt ink circle in every state: extreme ink at 5, 10 and 15 agents is the same 8.00pt radius as at 0. In needs-input the ring closes over the opening and the agent count is suppressed - the ring is carrying the blocked count instead, and only one of the two questions matters at that moment.

**50% 標記：** A circle, not a notch, and the notch was rejected on two independent grounds. Rasterisation: a gap cut into a stroke is a counter and needs 2.00pt of arc at 1x, which is 15.8 degrees on the outer ring and 29.6 degrees on the inner ring - 12% of a 250 degree sweep destroyed on the ring that can least afford it. Function, which is the worse failure: when remaining is near 50% the arc's own round terminal arrives at top dead centre, and a gap there is indistinguishable from the end of the arc, so the reference would fail at exactly the reading it exists for. The circle: a filled disc whose diameter is exactly the stroke width - 1.500 on the outer ring, 1.250 on the inner - centred on the arc centreline at top dead centre. Outer disc: centre (11, 3.750), r 0.750, spans y 3.000 to 4.500, which is precisely the band. Inner disc: centre (11, 7.125), r 0.625, spans y 6.500 to 7.750, again precisely the band. Protrusion outward 0.000pt, spur inward 0.000pt; it is tangent to both edges and can touch nothing else. The visibility problem is solved tonally rather than geometrically, so no counter is ever created: the disc is a 0.35 alpha hole punched by a luminance mask in the live fill where the fill still covers top dead centre, and a full 1.00 alpha disc sitting on the 0.28 track once remaining has dropped past 50% and the fill head has receded past it. Either way there is a 0.6-or-greater alpha step across a full stroke-width disc with no sub-pixel geometry anywhere. The crossing is visible in the gallery ("5h at 38%") and live in the scenario at the 15s mark, where the pip flips from tonal to solid as the arc drains past it.

**圓角稽核：** Seventeen vertex classes, none of them a point. Outer arc terminals and the outer fill head: round caps, R 0.750. Inner arc terminals and inner fill head: round caps, R 0.625. 50% mark outer: full circle R 0.750. 50% mark inner: full circle R 0.625. Agent pips (3): full circles R 0.750. Agent strip ends when fused: round caps R 0.750. Creature crown lobes (2): convex arcs R 0.620. Creature crown valley: concave fillet R 0.350, tangent to both lobes (centre at (11, 11.1876), tangent points at (11.2273, 10.9214) and its mirror). Creature body bottom: convex arc R 1.250. Creature side walls: straight segments that meet both the body arc and the lobe arcs at their east/west points, so the joins are G1 tangent-continuous - the outline has zero vertices, it is five arcs and two lines. Sleeping pose: the same path scaled 1.00 x 0.62, whose crown becomes elliptical with a minimum radius of curvature of 0.238. Alert ring segment ends (2N): round caps R 0.750. Chevrons: the apex is filleted in the path at R 0.700 before stroking at 1.10, which gives an outer apex radius of 1.250 and an inner apex radius of 0.150 - so even the concave inside corner is an arc, not the cusp a plain stroked polyline would give. Chevron tails: round caps R 0.550. Two radii are below every floor and are declared as such: the chevron inner apex at 0.150 and the sleeping crown at 0.238 exist to keep the vector cusp-free, not to be seen.

**外圈分段：** Blocked count, on the closed alert ring at R 7.25, stroke 1.50. Visible gap 2.00pt = 15.86 degrees; the path gap is 3.50pt = 27.66 degrees because each round cap gives back 0.75pt. The first gap sits at bottom dead centre so the alert form echoes the resting one, and the rest are spaced at 360/N. N=1 is a continuous ring with no gap at all - a single 2.00pt break in a ring reads as a flaw, not as a count. N=2: two segments of 152.34 degrees path, 20.78pt visible. N=3: 92.34 degrees, 13.18pt. N=4: 62.34 degrees, 9.39pt. N=5: 44.34 degrees, 7.11pt. N=6: 32.34 degrees, 5.59pt, which is still 3.7 times the stroke width. The physical ceiling is 9 (segments of 3.06pt, about 2 x stroke), but the perceptual ceiling is lower: six equal segments around a ring can still be counted at a glance, eight cannot. So the cap is 6 and it holds there - seven or more blocked sessions render as six segments and the exact number is in the menu. "Six or more people are waiting on you" is as actionable as an exact count at 16pt. Note the deliberate asymmetry with the agent strip: the strip overflows by fusing into a solid bar, which the ring cannot do because a solid ring already means N=1; the ring overflows by saturating, which the strip cannot do because it has a dim track behind it that would make saturation invisible. Each overflow rule is unambiguous inside its own ring.

**共用語言：** Yes - one language, deliberately, but applied to one ring rather than two. Both counts are the same operation: a ring at R 7.25 cut into equal parts separated by 2.00pt gaps, with round caps. The blocked count takes the whole 360 degrees of that circle; the agent count takes the 110 degrees of the same circle that the resting arcs leave open. Nothing new is drawn for either, and the two forms are visibly siblings. What I did not do is follow the method literally and segment the inner ring by agent count, and the arithmetic is the reason rather than taste. The inner sweep is 17.58pt of arc at R 3.875. Five agents need four gaps; at the 2.00pt 1x counter floor that is 8.00pt, 46% of the gauge, and the gauge still has to be read as a length. Shrinking the gaps to fit puts them at 1.00pt or below, where they close up at 1x and five agents render as an unbroken arc - the count silently disappears on exactly the displays where it is hardest to read. The coexistence problem itself is soluble on paper (segment the dim track as well as the fill, so the cell structure stays visible at any fill level and the quota is still a length minus a constant), and I want to be clear that I am not claiming otherwise; what is not soluble is doing it inside 17.58pt of arc without gaps that eat the reading. So I took the fallback the brief allows, and put the segmentation on a stretch of ring that is already empty. The conflict between count and fill is not solved on one stroke. It is avoided, on the same circle, in the same language.

**中間那隻：** Redrawn from scratch as a filled mass with no interior detail and no vertices: a bottom arc of R 1.250 centred on the mark centre, two vertical side walls at x = 11 +/- 1.25 running from y 11.00 up to y 10.45, two crown lobes of R 0.620 centred at (11 +/- 0.63, 10.45) whose east and west points coincide with the side walls, and a concave valley fillet of R 0.350 tangent to both lobes. The lobes' tangency with the walls makes every join G1, so the previous pointed ears and the sharp V between them are both gone - the crown is now two domes with a rounded trough. Overall 2.50pt wide, 2.42pt tall, inside r 1.25, giving a uniform 2.00pt counter to the inner ring everywhere including at the ring's terminal caps. Motion, only while agents run: a 1.35s bob of 0.34pt with a 2.2 degree sway, event-triggered and terminating - in the scenario it starts when the first agent appears and stops the instant the count returns to zero. It is implemented as a separate nested group so the still and moving creatures are the same path, and Reduce Motion simply keeps the still one. Sleep, when a window is exhausted: the same path scaled 1.00 x 0.62 and dropped 0.475 so it rests on the floor of its cell, 2.50 x 1.50pt, crown flattened to a dimple. There is no eye, awake or asleep, and that is a deliberate refusal rather than an omission: a closed-curve eye inside a 2.50pt mass would be a counter of at most 0.95 x 0.30pt, which is 70% under even the 1.00pt 2x counter floor, so it would fill solid at every scale on every display. Sleep is instead carried redundantly by the thing that is actually legible at 16pt - an outer ring with no ink left in it - with the settled pose as the secondary cue.

**半徑預算：** From the centre, 8.00pt exactly: creature 1.25, counter B 2.00, inner stroke 1.25, counter A 2.00, outer stroke 1.50. Ink is therefore 16.00 x 16.00pt in a 22.00 x 22.00pt box - the 16 that nobody hit last round, hit exactly rather than approached. Both counters sit precisely on the 2.00pt 1x floor and neither narrows anywhere, including where the inner arc's terminal caps come closest to the creature, because the creature is a disc of r 1.25 and the cap centre is at r 3.875 with cap radius 0.625: 3.875 - 0.625 - 1.25 = 2.00. What it sacrifices, plainly: (1) the creature. At 2.50pt across it is 15.6% of the mark, the smallest element in it, and it can carry no interior detail, no eye and a crown notch that closes up at 1x. (2) The inner ring runs at 1.25pt, the practical stroke floor, so the 7-day window is permanently the lighter of the two - defensible as hierarchy, but it is a compromise, not a decision. (3) Exact agent counting stops at three. (4) The inner 50% pip, at 1.25pt, is a 2x-and-above read. I bought pixel-exact counters and a 16.00pt ink box, and paid for them with the creature's mass and the inner ring's weight.

**1x 誠實報告：** What clears at 1x: outer stroke 1.50; inner stroke 1.25 (at the practical floor, no margin); counter A 2.00 and counter B 2.00 (both exactly at the floor); agent pip d 1.50; strip-to-terminal clearance 2.00; alert ring gaps 2.00 for N up to 6; and the full-ink 50% pip on the 0.28 track, which is a 3.6x alpha step over a full stroke-width disc. What does not, stated as failure: the agent pip gap is 1.96, 2% under the floor - it holds at 1x but it is short, and I would rather name 0.04pt than round it away. The 50% pip on live ink is tonal, not geometric; on the outer ring it resolves to roughly 1.5 device px at 1x with a post-antialiasing alpha floor near 0.55, a visible dip rather than a crisp dot, and on the inner ring at 1.25pt it is effectively a 2x feature - at 1x the half-way reading is carried by the outer pip alone, which sits directly above it. The creature's crown notch is 1.26pt wide and 1.01pt deep, well under the 2.00pt counter floor; because it is an open notch and not an enclosed counter it degrades to a dimple rather than vanishing, so at 1x the creature reads as a single rounded dome - still a mass, which is all it was ever meant to be. The chevron stroke is 1.10, under the 1.25 practical floor, and greys at 1x; the chevron gaps are 1.00, half the 1x counter floor and exactly at the 2x floor, so at 1x the three chevrons fuse into one arrowhead mass. I accept that because the chevrons carry no count - the ring does - and needs-input is the one state allowed hue, which survives greying better than form does. The chevron inner apex at R 0.150 and the sleeping crown curvature at R 0.238 are sub-pixel at every scale and are not claimed as visible. Pixel parity: at top dead centre the outer band spans y 3.00 to 4.50, so the outer edge lands on a whole device pixel at 1x and the inner edge on a half - a 1.50pt stroke cannot have both, and the outer edge was prioritised; at 2x it is 3 device px with the centreline on a half-pixel, which is correct parity. The inner ring at 1.25pt spans 6.50 to 7.75 and is on a half-pixel at both ends at 1x and at 2x: it is soft at every scale, and that is the direct price of holding both counters at exactly 2.00pt.

**評審必修：**
- (修正落實度, 27/40) 'The creature is a disc of r 1.25 ... neither counter narrows anywhere' is false on its own coordinates: lobe centre (11.63, 10.45) plus r 0.620 reaches r 1.456 from (11,11), so counter B is 1.794pt, not 2.00. Either pull the lobes in to r 1.25 or restate the budget.
- (1x 與繪圖, 31/40) Chevron stroke is 1.10pt, under the 1.25pt practical floor, and it is the interior of the one state that must never be missed — take it to 1.25 and re-derive the 1.00pt inter-chevron gaps from there. Also: the stated opening arc of 12.657pt is the 100-degree figure; the entry uses 110 degrees, which is 13.919pt. The 8.419pt usable strip is right, so the pip layout survives, but the published number is wrong. And the pip gap is 1.96pt by arc measure, 1.93pt by chord — quote the chord, it is what rasterises.

**自陳缺點：**
- Exact agent counting stops at three. Five, ten and fifteen agents all render identically as one fused bar. This is forced by 8.42pt of usable arc against a 2.00pt counter floor, but it means the real scenario value - five agents - lands in the saturated state, and anyone who wants the number has to open the menu.
- The creature is 2.50pt across, 15.6% of the mark and the smallest element in it. Its crown notch dies at 1x, it has no eye awake or asleep, and at real size on a non-Retina display it is close to a dot that moves. The design leans on motion and on the depleted ring to carry what the form cannot.
- The inner ring is never pixel-exact. At 1.25pt it is 2.5 device px at 2x and 1.25 at 1x, so both band edges straddle pixels at every scale. The 7-day window is permanently the softer, lighter gauge.
- The 50% mark on live ink is a tonal dip rather than a hard edge. On the inner ring at 1.25pt it is effectively a 2x-and-above feature; at 1x the half-way reference is carried by the outer pip alone.
- It also has a threshold quality that some will dislike: above 50% the pip is a subtle darkening, below 50% it is a solid dot. The mark is quieter exactly when you are fine and louder when you are not, which is intentional, but it does mean the two states do not look like the same object.
- Needs-input suppresses the agent count entirely - the ring cannot show both. If several agents are running while a session is blocked, the running work becomes invisible until the block clears.
- The alert interior is the weakest element at 1x: a 1.10pt stroke with 1.00pt gaps means the three chevrons merge into one mass and the stroke greys. The state is legible only because it is the one state carrying colour, which is a dependency I would rather not have.
- The bottom opening is visually empty when nothing is running - three dim pips and nothing else - so the idle mark's ink is 16.00 wide by 12.91 tall even though its box is square. Some will read that as bottom-heavy or unfinished.
- The sweep was widened from the settled 220/-35 to 215/-35 (a 110 degree opening instead of 100) to buy the third agent cell. That is within the brief's "about", but it is a change to a settled number and should be called out rather than slipped in.
- Two radii - the chevron inner apex at 0.150 and the sleeping crown at 0.238 - satisfy the no-points rule in the vector and nowhere else. They are honest geometry but they are not honest pixels.

### 嘴巴合起來 — Mouth Gauge（51/80）

**agent 融合：** The bottom opening is a fixed seven-socket register, not a row of dots. Five sockets sit on the outer ring centreline (r 7.25) at −50/−70/−90/−110/−130°, 20° pitch, each a ⌀1.50pt circle — exactly the outer stroke width, so a filled socket reads as the ring continuing. Two sockets sit on the inner ring centreline (r 3.875) at −70/−110°, 40° pitch, each ⌀1.25pt. Every socket is always present at 0.22 alpha and fills to 1.00 when occupied, so the ink bounding box is identical whether the register is empty or sealed. N = outer + 5×inner: 0 = mouth wide open (7 dim sockets); 1 = centre socket only; 3 = symmetric trio; 4 = two symmetric pairs with the CENTRE SOCKET EMPTY; 5 = a solid run of five; 6–10 = 1–5 outer plus one inner tooth; 11–15 = 1–5 outer plus two inner; >15 = all seven filled, mouth sealed, meaning "many". The precision problem — telling four from five — is solved by the hole, not by length: four is the only state with a gap at bottom dead centre, so it is a different figure from five rather than a slightly shorter one, and the eye never has to count past five on either track. The width never changes because nothing is ever added outside r = 8.00; the count is expressed purely as a fill state of geometry that is already in the silhouette. Ink is 16.00 × 16.00pt in all thirteen states, item box 22 × 22pt.

**50% 標記：** I chose the CIRCLE, and the rejection of the notch is arithmetic, not taste. A notch is a counter, so it is on the 2.00pt 1× floor. To leave 2.00pt of visible gap in a round-capped 1.50pt stroke the path must be cut by 2.00 + 1.50 = 3.50pt of caps, which at r 7.25 is 27.7° — 11.5% of the 240° sweep, removed from the one arc whose length IS the number. A 1.00pt notch clears nothing and closes up at 1×. So the gap cannot clear the floor without corrupting the value; notch rejected, as the brief said to do if it could not be proven. The disc then has the problem the brief names, and the way out is to stop solving it with geometry. Geometry: outer disc centre (11, 3.75), r 0.75, so it spans exactly r 8.00 → 6.50 — tangent to the band's outer edge and tangent to its inner edge, overhang 0.00, spur 0.00. Inner disc centre (11, 7.125), r 0.625, spans exactly r 4.50 → 3.25. Its diameter IS the stroke width of the ring it sits on, so it can protrude in neither direction by construction. Separation is by TONE, not by a gap: a document-level mask knocks the ring out completely under each disc, and the disc is repainted at a flat 0.65 alpha. 0.65 is deliberately the midpoint between the lit arc (1.00) and the dim track (0.30), so the mark carries the same 0.35 alpha step in both directions — a tonal pinch when the arc covers top dead centre (above 50%), a bright dot when the arc has already ended (below 50%), and a state change exactly at the boundary where a gauge most wants an event. There is no counter anywhere, so no counter floor applies; alpha survives template-image conversion because AppKit keeps the alpha channel and discards only colour; and a tonal step has no minimum feature size the way a gap does — it cannot close up and it cannot vanish. Deliverable 2 carries a dedicated 16× close-up of both marks with the two band edges drawn as dashed rules and a 1×-device-pixel grid behind them, showing the disc touching both rules and crossing neither.

**圓角稽核：** Nothing in the mark terminates in a point. Creature crown: two lobe apexes at r 0.95 (was two sharp peaks), joined by a concave valley fillet of r 0.45 (was a V notch); shoulder fillets r 0.60 each side; base bowl r 1.90; the two base corners r 0.95 as path fillets — the whole outline is one closed curve of arcs and cubics with zero straight-line joins. Arc terminals: round caps, never butt — r 0.75 on the outer 1.50pt arc (×2 ends), r 0.625 on the inner 1.25pt arc (×2). Agent teeth: r 0.75 (outer ×5) and r 0.625 (inner ×2) — they are circles, so they have no vertex at all. 50% marks: r 0.75 and r 0.625 — also circles, also vertex-free. Chevrons: apex r 0.625 (stroke-linejoin round on a 1.25pt stroke), tails r 0.625 (stroke-linecap round), ×3 apexes and ×6 tails. Alert segment terminals: round caps r 0.75, up to 2N of them. Sleeping eye slot: a stadium of r 0.225. Two radii sit below the 1× floor and I say so on the page: the crown valley (0.45pt → 0.9px) and the eye slot (0.225pt). Both fail TOWARD roundness — the valley closes into a single dome, the slot closes into solid mass — so neither can produce a point at any rasterisation.

**外圈分段：** When N sessions are blocked, the outer ring becomes a closed ring divided into N equal segments. N = 1 is a continuous unbroken ring with no gaps at all — one thing is not a count, so nothing is cut. For N ≥ 2 the ring is cut into N arcs of (360/N − 20)° separated by N gaps of 20°, with the first gap centred on bottom dead centre so the figure stays symmetric about the vertical and reads as a deliberate division rather than a broken stroke. Measured: N=2 → 2 × 160°, N=3 → 3 × 100°, N=5 → 5 × 52°, N=6 → 6 × 40°. A 20° gap at r 7.25 is 2.53pt of arc, less 1.50pt of round caps = 1.02pt of visible clear — above the 1.0pt stroke floor at 1×, above the 2.0pt counter floor only at 2×, which is stated honestly in the rasterisation table. The ceiling is N = 6: below 40° a segment is 5.06pt of arc, and shorter than that the segments stop reading as arcs and start reading as dashes. Past 6 the ring switches to a fixed 6-segment "many" ring drawn at 1.75pt instead of 1.50pt — thickened INWARD, outer edge still at r 8.00 — so the overflow state is visibly heavier without the ink box changing by a fraction of a point. The alert ring is the only place colour is used; everything else is a template image.

**共用語言：** Yes — one language, used on two rings, and the mark is built so the two never collide. The language is: an equal division of a ring encodes "how many of these there are". Correction 3 applies it to the OUTER ring in the needs-input state: N blocked sessions divide the closed ring into N equal segments. The agent register applies the same idea to the same ring in the working state: the mouth opening is divided at a fixed 20° pitch into five equal sockets on the outer ring plus two at 40° pitch on the inner, and each socket filled is one unit. Both are "read the count from equal divisions of a circle", both use the same ⌀1.50pt / ⌀1.25pt module — a socket is exactly a round cap of the ring it sits on — and both express the count as a change in the ring itself rather than as an added element. They can never be confused, because they are mutually exclusive states and the mark changes colour and interior between them: agent sockets exist only in the template (no colour) state and live only in the bottom 120°, while alert segmentation exists only in the alert colour, closes the ring completely and replaces the interior with three chevrons. The one place I deliberately diverged is the pitch: the agent register uses a FIXED pitch with a fixed slot count, while the alert ring divides the whole 360° into N variable-width parts. That is not inconsistency, it is the precision fix — a fixed lattice lets you count four versus five by the hole at bottom dead centre, which a variable division cannot do, and the alert count rarely exceeds three so variable division is safe there.

**中間那隻：** A single closed filled mass, 3.80 × 3.30pt, no interior detail, zero eyes awake — organic detail dies at this size, so there is none. The outline is one path of cubics: from the crown's central valley it rises through a fillet of r 0.45 into two lobes of r 0.95, drops through shoulder fillets of r 0.60, and closes on a base bowl of r 1.90 with corner fillets of r 0.95. Nothing on it is a straight line and nothing is a point — this is the direct answer to correction 1, which was aimed at the two pointed ears and the sharp V between them in the previous build. Motion: a 1.15s bob — translate −0.40pt and scale 1.035 at the midpoint, ease-in-out — bound to agents > 0. It is not decorative and it is not permanent: it starts when the first agent starts and stops with the last agent, and under prefers-reduced-motion it is dropped entirely with no loss of information, because the agent count is carried by the socket register and not by the motion. Sleep pose: the same mass squashed to scale(1.02, 0.90) and dropped 0.35pt, so the crown flattens and the baseline settles — and exactly one eye, a closed curve, as a 1.05 × 0.45pt stadium slot (r 0.225) knocked out of the mass by a mask. Sleep is legible without it: the outer arc is empty, so its only ink is the terminal dot and the 50% disc on a dim track, and that emptiness plus the dropped pose carries the state at 1× where the 0.45pt slot does not survive.

**半徑預算：** 8.00pt of radius, spent as: outer ring stroke 1.50 (r 8.00 → 6.50), counter A 2.00 (6.50 → 4.50), inner ring stroke 1.25 (4.50 → 3.25), counter B 1.25 (3.25 → 2.00), creature envelope 2.00 (2.00 → 0). Total exactly 8.00, ink exactly 16.00 × 16.00pt — the Tailscale / SF-Symbol target that nobody hit last round. What it sacrifices, plainly: the brief allowed about 9.00pt of radius and I spent only 8.00, because hitting 16.00pt ink exactly was worth more than a comfortable interior. That whole missing point comes out of two places. First, counter B is 1.25pt, well under the 2.00pt 1× counter floor, so at 1× the creature's halo against the inner ring fills grey and the creature reads as a mass sitting in a ring rather than a mass with clear air around it. Second, the creature itself is only 3.80 × 3.30pt — small, and that is the real cost of the 16.00 target. I protected counter A at 2.00pt instead, because it is the one counter that fully clears at 1× and it is the counter that has to work: if the two quota arcs fuse, the gauge stops being a gauge. The inner ring is 1.25pt, at the practical stroke floor, and I use that weight difference rather than apologising for it — the 1.50 / 1.25 contrast is what separates the 5-hour window from the 7-day window with no colour at all.

**1x 誠實報告：** Honest account, no 1× claims I cannot support. Clears at 1×: the outer ring and both dim tracks at 1.50pt (9.4% of mark height, inside the 8–11% band); counter A at 2.00pt, the only counter that fully meets the floor; every round cap and every tooth at r 0.75 / 0.625. Degrades at 1×, stated as such: the inner ring at 1.25pt greys along much of its length — kept, because the weight contrast is load-bearing; counter B at 1.25pt fills grey; the outer tooth notch is 1.02pt of clear and the inner 1.40pt, both under the 2.00pt counter floor, so adjacent teeth merge and the exact agent count is lost at 1× — what survives is open / part / sealed, so magnitude survives and the number does not; the alert segment gap is 1.02pt, so at 1× a segmented ring reads as one continuous ring and N degrades to "blocked", while the alert itself stays unmistakable from colour, the closed ring and the chevrons; the chevron apex at r 0.625 reads blunt rather than sharp, which fails toward correction 1; the crown valley at r 0.45 closes into a single dome; the 0.45pt sleeping eye slot vanishes entirely at 1× and is marginal at 2×, so sleep is carried by the pose and the emptied outer arc instead. The 50% disc is the case I had to reason about rather than measure off a table: it is not a counter and cannot close up, but its 1× behaviour is a ~0.22 alpha dip across the two device pixels either side of x = 11 — a soft grey pinch, not a crisp dot. At 2× it is a flat 0.65 over a 3 × 3 device-pixel patch against 1.00 or 0.30, unambiguous. Summary claim: at 2× — every Mac shipped since 2012 — everything resolves including both exact counts; at 1× the mark keeps its silhouette, both quota readings, its alert and its sleep, and loses both numbers. Pixel parity: ring edges at r 8.00 / 6.50 / 4.50 / 3.25 / 2.00 from a whole-point centre land at 16 / 13 / 9 / 6.5 / 4 device px at 2×, four of five whole; the 1.50 and 1.25pt strokes are centred on quarter-point radii 7.25 and 3.875 so their edges, not their centrelines, snap to the grid.

**評審必修：**
- (修正落實度, 25/40) The 20-degree alert gap gives 2.518pt of chord minus 1.50pt of caps = 1.018pt visible, half the 2.00pt counter floor, so the blocked count is invisible at 1x by construction. Widen the gap to 27.9 degrees (2.00pt visible) and accept a ceiling of 5-6, or the segmentation is decorative.
- (1x 與繪圖, 26/40) The chevron apexes are stroke-linejoin:round on a 1.25pt stroke. That rounds the outer side of the join and leaves the inner side a sharp re-entrant vertex — three of them, in the one state the user is meant to react to. beads, segring and core all name this trap explicitly and route around it with a path-level fillet or a single arc; this entry walks into it and reports it as solved. Second: the 20-degree alert gap is 1.031pt of visible clear at r7.25, half the 2.0pt counter floor, so correction 3's segmentation closes up at 1x and N reads as 1. Widen to 27.7 degrees of path like everyone else, or state that the blocked count is a 2x-only feature.

**自陳缺點：**
- The 50% disc's 1x contrast is genuinely marginal: about a 0.22 alpha dip over two device pixels when the arc covers it. It is visible as a soft grey pinch and it can never close up or vanish, but on a non-Retina display it is not a crisp mark, and I have not claimed otherwise.
- Exact counting dies at 1x on both tracks. The 1.02pt tooth notch and the 1.02pt alert segment gap are both under the 2.00pt counter floor, so at 1x five agents look like a sealed mouth and three blocked sessions look like one. Only magnitude survives.
- Counter B is 1.25pt, under the 1x counter floor. That is the direct price of hitting exactly 16.00pt ink instead of spending the full 9.00pt radius the brief allowed, and it leaves the creature small (3.80 x 3.30pt) with a halo that fills grey at 1x.
- The agent ceiling is 15 and the blocked ceiling is 6. Past those the mark says 'many' and stops counting. That is a deliberate cap, but it is a real information loss for anyone who runs twenty agents.
- Four-versus-five depends entirely on noticing one empty socket at bottom dead centre. At 2x that hole is 2.04pt of clear and reads cleanly, but it is a single cue with no redundancy, and a user who has not learned the pattern may read four as 'nearly five' rather than as four.
- The inner ring at 1.25pt is at the practical stroke floor and greys along its length at 1x. I turned that into a feature (weight distinguishes the 7-day window from the 5-hour one) but it is still a stroke that does not hold solid black at 1x.
- The sleeping eye is 0.45pt tall and does not survive 1x; it is marginal even at 2x. Sleep is legible from the pose and the emptied arc, so nothing breaks, but the one detail the brief allowed the creature is the least durable thing in the mark.
- The construction view is drawn at 20x rather than the requested 10x. At 10x (220px) the annotation numerals collide with each other and with the drawing; I chose legibility over the stated magnification and say so on the page.

### 內軌道 — Orbit（47/80）

**agent 融合：** The item is a fixed 22.00 x 22.00pt square in every state. Nothing the agent count does can change it, because the agent readout is an arc concentric with the two gauges at centreline r 1.95pt — the innermost ring in the mark — and its outermost ink (dot radius 0.45 on that centreline) reaches r 2.40pt, which is 5.60pt inside the 8.00pt silhouette edge. The count cannot approach the edge because it is geometrically incapable of leaving the interior disc.

How each count reads, by the CELL RULE (below): 0 agents — the orbit is empty, no ink at all in the mouth, the creature is still. 1 agent — one cell, its mark centred at bottom dead centre: a single 0.90pt disc at (11.00, 14.25). 2 agents — two cells, marks at phi -59 deg and -121 deg, i.e. (12.0043, 13.9715) and (9.9957, 13.9715); chord between centres 2.0086pt, visible counter 1.108pt. 3 agents — three cells, marks at phi -90, -28, -152: (11.00, 14.25), (12.7217, 13.2155), (9.2783, 13.2155); same 1.108pt counters. 4 and above — the cells fall below the merge threshold, so the orbit saturates to one continuous 0.90pt arc from phi -148 to -32 (124 deg swept, 4.22pt of centreline, 5.12pt of ink with the round caps), reading "four or more". 5, 10 and 15 agents are therefore all the same picture, and the exact number lives in the menu. That ceiling is 3, it is stated on the page, and it is the honest price of putting the counter on a 12.25pt-circumference orbit.

Because the orbit's ink is bounded by r 2.40 and the outer arc's cap ink is bounded by r 8.00, the bounding box is literally the same set of extreme points in all eleven states in the width-invariance row: x 3.000 to 19.000 (16.000pt), y 4.300 to 17.6746 (13.3746pt). Needs-input does not change it either: the alert ring shares the outer arc's centreline r 7.35 and stroke 1.30, so its ink edge is the same 8.00pt circle, and the chevrons reach only r 4.38.

**50% 標記：** I chose (b), the CIRCLE, and I chose it because I could not make the notch legal. Here is the proof, then the circle's construction.

WHY THE NOTCH FAILS. Correction 1 requires round caps on every arc terminal. A notch cut into a stroke creates two new terminals, and each round cap bulges half a stroke width (0.65pt) back into the gap. So the visible counter equals the dash gap minus one full stroke width: visible = G - 1.30. To clear the 2.0pt counter floor at 1x I need G = 3.30pt of arc. On the outer arc (centreline r 7.35, circumference 46.1814pt) that is 25.7 deg; on the inner arc (centreline r 4.15, circumference 26.0752pt) it is 45.6 deg. The inner arc's total sweep is 260 deg, so a legal notch would eat 17.5% of the gauge, and at 45.6 deg it is visually a second mouth at twelve o'clock. Worse, it is the same size as the alert ring's segmentation gap (3.41pt), so the mark would be using one gesture for two unrelated meanings. Even dropping to the 2x floor (1.0pt visible, G = 2.30pt) costs 31.8 deg on the inner arc. The notch is dead. I could only have saved it with butt caps, which correction 1 forbids.

THE CIRCLE, AND HOW IT ESCAPES THE TRAP. The trap as stated is: a disc larger than the stroke protrudes (forbidden), and a disc distinguished by a surrounding hole is a counter (below floor). Both horns assume the bead must be legible while the live arc is passing over it. It does not.

Construction. Outer bead: a filled disc, centre (11.0000, 4.9500), radius 0.6500pt — exactly half the 1.30pt stroke. Inner bead: centre (11.0000, 8.1500), radius 0.6500pt. Each sits on its arc's centreline at top dead centre, which is the exact midpoint of the 260 deg sweep. Tangency proof, outer: the arc's stroke band at TDC runs y 4.3000 (outer edge, r 8.00) to 5.6000 (inner edge, r 6.70). The bead spans y 4.3000 to 5.6000. It is tangent to both edges and crosses neither, so it protrudes 0.0000pt outward and 0.0000pt inward. Inner: band y 7.5000 to 8.8000, bead y 7.5000 to 8.8000, again 0.0000 in both directions. Tangentially it spans 1.30pt of arc, which is 5.07 deg on the outer arc and 8.97 deg on the inner.

Both beads are painted at full opacity UNDER the live arc and OVER the 26%-opacity track. This makes the mark self-revealing exactly when it matters:
- Remaining above 50%: the live arc has already swept past TDC, the bead is covered by identical full-opacity ink, and it is invisible. Correct, because when the arc visibly crosses twelve o'clock you already know you are above half. There is no counter, so no floor to violate.
- Remaining at 50%: the live arc's round cap arrives exactly at the bead and fuses with it. The threshold reads as a slight thickening, then as a bead about to detach.
- Remaining below 50%: the arc's leading cap has retreated past TDC and the bead stands alone as a full-opacity 1.30pt disc on a 26% track. Contrast is 100% against 26% alpha — an alpha edge, not a counter. Nothing has to be 2.0pt wide for it to read.

So the bead never needs a hole, never needs to be bigger than the stroke, and never fails a floor. Its own ink is 1.30pt across, above the 1.0pt stroke floor: at 1x a 1.3px disc on pixel centre lands roughly alpha 0.8 in its core pixel and is visible. With the real data (5h 72% remaining, 7d 82% remaining) neither bead shows, which is correct; the gallery therefore also renders a 38% state where the outer bead is exposed, and the 16x close-up shows the covered and exposed cases side by side with the band edges drawn.

Cost, stated plainly: the bead carries no information while quota is above half. I regard that as the feature. The alternative designs all bought above-half legibility with a counter that dies at 1x, i.e. they bought nothing and paid for it in gauge sweep.

**圓角稽核：** Global rule applied: no vertex in the mark terminates in a point. Every one is a circular arc, a round cap, a round join or a concave fillet.

ARCS AND TRACKS
1. Outer 5h arc, left terminal at phi 220 deg — stroke-linecap round, radius 0.65pt (half of the 1.30pt stroke).
2. Outer 5h arc, right terminal at phi -40 deg — round cap, r 0.65.
3. Outer 5h arc, live leading end (wherever quota has drained to) — round cap, r 0.65.
4, 5, 6. Inner 7d arc, same three terminals — round caps, r 0.65.
7-10. The two dim tracks, four terminals — round caps, r 0.65.
All six arc ends are drawn with stroke-linecap:round; butt caps appear nowhere in the file.

50% MARKS
11. Outer bead — a complete circle, r 0.65pt. A circle has no vertex.
12. Inner bead — complete circle, r 0.65pt.

AGENT ORBIT
13-15. Orbit dots — complete circles, r 0.45pt each. No vertex.
16, 17. Orbit saturation arc, both terminals — round caps, r 0.45pt.

CREATURE
18. Left crown — a 0.60pt-radius circular arc centred (10.20, 10.95), swept 142.4 deg. The crown peak is the arc itself; there is no apex vertex to round.
19. Right crown — same, centred (11.80, 10.95), r 0.60.
20. Crown valley — a concave fillet of radius 0.30pt, centred (11.00, 10.5377), tangent to both crown circles at (10.7333, 10.6751) and (11.2667, 10.6751). This is the vertex the user objected to. Previously the two crown circles were tangent, producing a zero-angle cusp; the 0.30pt fillet removes it. Valley floor y 10.8377, crown tops y 10.35, so the valley is 0.4877pt deep.
21, 22. Crown-to-flank junctions at (9.60, 10.95) and (12.40, 10.95) — G1 tangent continuity: the crown circle's extreme left/right point has a vertical tangent and the flank is vertical. Curvature steps from 1/0.60 to 0; there is no corner and no angle.
23, 24. Bottom corners — 0.95pt radius arcs, centres (10.55, 11.25) and (11.45, 11.25).
25, 26. Flank-to-bottom-corner junctions at (9.60, 11.25) and (12.40, 11.25) — tangent, vertical to arc, no corner.
27, 28. Bottom-corner-to-base junctions at (10.55, 12.20) and (11.45, 12.20) — tangent, arc to horizontal, no corner.
29. Sleeping pose — the same path under transform translateY(0.50) scaleY(0.86) about (11.00, 12.20). A uniform affine map of an all-arc outline is still an all-arc outline; every radius above is scaled 0.86 in y (crown 0.60 becomes a 0.60 x 0.516 ellipse arc, fillet 0.30 becomes 0.30 x 0.258). Minimum resulting radius 0.258pt.

CHEVRONS (needs-input)
30-32. Three apexes — stroke-linejoin:round on a 1.00pt stroke, so each apex is a 0.50pt-radius arc. The included angle is 121.4 deg, well above the miter threshold, and linejoin round removes any question.
33-38. Six tails — stroke-linecap:round, r 0.50pt each.

ALERT RING
39+. Every segment end, 2N of them for N blocked sessions — round caps, r 0.65pt.

NOTHING IS STILL A POINT. The smallest radius anywhere in the awake mark is 0.30pt (the crown valley fillet); in the sleeping mark it is 0.258pt. Both are below the 1x raster floor and are reported as such in the rasterisation note: at 1x the valley closes and the creature reads as a single dome. That is a loss of charm, not of information.

**外圈分段：** ONE RULE FOR BOTH RINGS — THE CELL RULE. Take the ring's drawable arc, divide it into N equal cells, and centre one mark in each cell. The mark's centreline length is (arc length / N) - G, where G is a fixed LINEAR gap so the counter between adjacent marks is constant regardless of N. With round caps the visible counter is G - stroke. If the formula returns a length at or below zero, the cell has collapsed and the ring saturates. This is one rule expressed at two radii; on the big ring a cell is long and the mark reads as a segment of ring, on the tiny orbit a cell is short and the mark collapses to a disc.

ALERT RING (needs-input, N blocked sessions). Closed circle, centreline r 7.35pt, stroke 1.30pt, circumference 46.1814pt. G = 3.4100pt, so the visible counter is 3.41 - 1.30 = 2.1100pt, which clears the 2.0pt counter floor at 1x. In pathLength-360 units the gap is 26.58 deg, and the dash pattern is (360/N - 26.6) on, 26.6 off, with stroke-dashoffset -13.3 so one gap is centred at phi 0 and the set is symmetric.

  N=1: continuous closed ring, zero gaps. Stated explicitly because the cell rule would otherwise put one 3.41pt gap in it for no reason. One blocked session is a ring.
  N=2: two marks of 19.681pt (153.4 deg each), gaps at phi 0 and 180 — two half rings, top and bottom.
  N=3: three marks of 11.984pt (93.4 deg), gaps at phi 0, 120, 240.
  N=4: 8.135pt (63.4 deg).
  N=5: 5.826pt (45.4 deg).
  N=6: 4.286pt (33.4 deg).
  N=7: 3.186pt (24.7 deg).
  N=8: 2.363pt (18.4 deg), ink length with caps 3.663pt. This is the readable ceiling.
  Geometric hard limit is N=13 (46.1814/13 = 3.552 > 3.41); N=14 returns a negative mark. But readability fails first: at N=9 the mark is 1.72pt of centreline, 3.02pt of ink, and nine 3pt dashes around a 14.7pt circle are no longer countable at a glance.
  PAST THE CEILING: for N >= 9 the ring renders 8 segments and saturates. The mark means "eight or more"; the exact figure is in the menu. Nothing else changes — no extra tick, no motion, no colour shift — because anything added at this size becomes noise.

AGENT ORBIT (running agents). Same rule, centreline r 1.95pt, stroke 0.90pt, drawable sweep 124 deg = 4.22pt of centreline. G would need to be 0.90 + 1.00 = 1.90pt to clear even the 2x floor, so cells collapse almost immediately: the marks are discs of 0.90pt and what the rule actually controls is their spacing.
  N=1: one disc at phi -90.
  N=2: two discs at phi -59 and -121, chord 2.0086pt, visible counter 1.108pt.
  N=3: three discs at phi -90, -28, -152, same 1.108pt counters between neighbours.
  N=4: four cells of 31 deg would put the centres 1.042pt apart (chord), i.e. a counter of 0.142pt. The discs merge into a blob. Dead.
  CEILING 3. PAST IT: for N >= 4 the orbit saturates the other way — the cells close up and it becomes one continuous 0.90pt arc from phi -148 to -32, meaning "four or more". This is the opposite overflow behaviour to the alert ring, and deliberately so: on the alert ring "continuous" is already taken by N=1, whereas on the orbit N=1 is a single disc, which leaves "continuous" free to mean saturation. Same rule, same failure mode, opposite spare slot. I would rather explain that asymmetry than force a false symmetry that misreads one of the two rings.

**共用語言：** Yes — one visual language, one rule, two radii. The rule is the CELL RULE: divide the ring's drawable arc into N equal cells and centre one mark in each, with a fixed linear gap so the counter between marks never changes with N. The alert ring (centreline r 7.35, 46.18pt of circumference) has long cells, so each mark reads as a segment of ring — the thing the user drew. The agent orbit (centreline r 1.95, 12.25pt of circumference) has cells shorter than the stroke is wide, so each mark collapses under its own round caps into a disc. Same construction, same dash logic, same round caps, same saturate-at-the-ceiling behaviour; the expression differs only because a piece of arc shorter than its own stroke width IS a disc.

That is what makes the mark one object rather than a gauge with two counters bolted on. Both counts are "how many pieces is this ring in". Both have a ceiling set by the same inequality (cell length minus gap at or below zero). Both saturate past it rather than lying. The two ceilings differ — 8 and 3 — purely because the circumferences differ by a factor of 3.8, and I report both rather than pretending one number covers the mark.

Where I deliberately broke symmetry, and why: the overflow rendering. The alert ring saturates by freezing at 8 segments, because on that ring "continuous" already means N=1 and reusing it would make one blocked session and nine blocked sessions identical. The orbit saturates by becoming continuous, because on the orbit N=1 is a single disc, so "continuous" is an unused slot and is the most legible way to say "more than I can count". Forcing the same overflow on both would have cost the alert ring its N=1 reading — a real loss, to buy a symmetry nobody can see at 22pt. The gauges themselves stay outside this language entirely: they are unbroken arcs with a single bead, never segmented, so a segmented ring always and only means "a count", and an unbroken arc always and only means "an amount". Those two meanings never collide because segmentation appears on the outer ring only in the needs-input state, when the gauges are not drawn at all.

**中間那隻：** FORM. A filled mass, 2.80pt wide by 1.85pt tall, built entirely from arcs and two short straight flanks. Outline, as a single closed path in the 22pt viewBox with centre (11.00, 12.30):

M 12.40 10.95  A .6 .6 0 0 0 11.2667 10.6751  A .3 .3 0 0 1 10.7333 10.6751  A .6 .6 0 0 0 9.60 10.95  L 9.60 11.25  A .95 .95 0 0 0 10.55 12.20  L 11.45 12.20  A .95 .95 0 0 0 12.40 11.25  Z

Two crown bumps of radius 0.60pt centred at (10.20, 10.95) and (11.80, 10.95), peaks at y 10.35. Between them, a CONCAVE FILLET of radius 0.30pt centred (11.00, 10.5377), tangent to both crowns at (10.7333, 10.6751) and (11.2667, 10.6751), valley floor y 10.8377. That fillet is the whole of correction 1 as it applies to the creature: in the previous build the two crowns met in a sharp V, and now they meet in an arc. Valley depth 0.4877pt. Flanks are 0.30pt vertical segments meeting the crowns with vertical tangents, so there is no corner. The base is a 0.90pt flat between two 0.95pt corner arcs. No interior detail, no eyes awake, one closed filled region.

FIT. Maximum radius from the mark centre is 2.169pt (the outer flank of a crown), leaving counter B = 3.50 - 2.169 = 1.331pt to the inner arc's inner edge. Clearance down to the orbit: creature base y 12.20, nearest orbit ink is the bottom-dead-centre disc whose top edge is y 13.80 — 1.600pt. The tightest point in the whole interior is the creature's bottom-right corner arc against the 3-agent outboard disc: centre distance 2.340pt minus 0.95 minus 0.45 = 0.940pt.

MOTION. Still whenever no agent is running — idle, blocked, asleep, and quota-only changes all leave it motionless. While agents run it BOBS: translateY between 0 and -0.35pt, 1.6s, ease-in-out, alternating, and it stops when the last agent finishes. It is a rigid translation of the whole mass, so no radius changes and no edge is crossed: at the top of the bob the crown reaches r 2.519 and counter B is still 0.981pt. Nothing animates permanently, nothing animates when the machine is idle. Under prefers-reduced-motion the bob is removed and the creature sits at its rest position; no information is lost, because the agent count is carried entirely by the orbit discs and the running/not-running distinction by whether the orbit has any ink at all.

SLEEP. Triggered when either quota window reaches zero. The same path under translateY(0.50) scaleY(0.86) about (11.00, 12.20): the mass settles onto the floor of the interior and the crown flattens from 1.85pt of height to 1.591pt, peak y moving from 10.35 to 11.109. Both arcs are simultaneously at zero so only the two dim tracks remain, the orbit is empty, and nothing moves. NO EYE. The brief allows exactly one, as a closed curve, if the pose needs it — it does not, and more to the point it cannot have one: a 0.55pt closed stadium placed inside a 1.591pt-tall mass leaves at most 0.54pt of ink above it and 0.28pt below, both under the 1.0pt stroke floor, so the mass would break apart at 1x and read as debris. Sleep is therefore carried by three simultaneous signals — the lowered flattened pose, both tracks empty of live ink, and the absence of motion — any two of which survive alone.

**半徑預算：** SPENT: 8.00pt of the ~9.00pt available. THE FIRST SACRIFICE IS THE LAST 1.00pt ITSELF, given up on purpose so that the enclosing circle is exactly 16.00pt in diameter — matching Tailscale's shipping StatusBarIcon at 16.00 and SF Symbol "circle" at pointSize 16 at 16.00. Last round's five entries measured 17.0, 17.5, 18.0, 18.0, 18.5; they were spending the full radius. I would rather be the right size than have room.

THE STACK, centre outward, measured on the vertical axis:
  1.30pt  outer 5h arc stroke        r 8.00 -> 6.70   (8.1% of the 16.00 mark, inside the 1.3-1.8pt band)
  1.90pt  counter A                  r 6.70 -> 4.80
  1.30pt  inner 7d arc stroke        r 4.80 -> 3.50
  1.10pt  counter B                  r 3.50 -> 2.40
  0.90pt  agent orbit stroke         r 2.40 -> 1.50
  1.50pt  free core                  r 1.50 -> 0
  ------
  8.00pt

The creature is NOT in that column, and that is the whole trick of this entry. It occupies the interior disc out to r 2.169 in the UPPER sector only; the orbit occupies r 1.50-2.40 in the LOWER sector only. They share the interior angularly instead of radially, so the orbit costs zero radial points at twelve o'clock, where the budget actually binds.

WHAT IT SACRIFICES, precisely, four things:
1. Counter A is 1.90pt, 0.10pt short of the 2.0pt 1x floor. This is the closest any two-arc gauge can come while holding the outer diameter at 16.00pt: 8.00 - 1.30 - 1.30 - 3.50 = 1.90 with the interior fixed at r 3.50. To buy the missing 0.10 I would have to thin the arcs to 1.25pt, which last round was measured going grey at 1x.
2. Counter B is 1.10pt — clears the 2x floor (2.2 device px) and fails 1x.
3. The creature is 2.80 x 1.85pt, roughly 40% of the area a no-orbit layout would give it (a no-orbit build could hand the creature the full r <= 2.40 disc, 4.80pt across). The orbit did not take radius from the creature; it took the creature's BOTTOM, forcing a shallow 1.85pt mass with a 0.4877pt crown valley instead of a tall one.
4. The orbit's counting ceiling is 3. A 12.25pt circumference at r 1.95 cannot resolve more. Five, ten and fifteen agents all render as the same saturated arc.

WHAT IT REFUSES TO SACRIFICE: the alert ring's 2.11pt segmentation counters (above the 1x floor), the 1.30pt arc strokes (above the 1.25pt practical floor and inside the band), the 16.00pt outer diameter, and the fixed 22.00pt item width.

**1x 誠實報告：** Honest 1x account. 1pt = 1 device px at 1x, 2 at 2x. Floors: stroke 1.0pt with 1.25pt practical for arcs, counter 2.0pt at 1x and 1.0pt at 2x.

SURVIVES 1x
- Outer and inner arc strokes, 1.30pt. Above the 1.25pt practical floor. SF Symbol circle at Light (1.01pt) gave only 4 of 102 touched pixels full black; 1.30pt is measurably darker and holds along its length.
- Both 50% beads, 1.30pt of solid ink. A 1.3px disc keeps a near-opaque core pixel.
- Alert ring stroke 1.30pt, and its segmentation counters at 2.110pt — the only counter in the mark that clears the 1x floor outright. Segmentation is therefore the one count that is fully readable on a non-Retina display.
- Creature mass: 2.80 x 1.85pt of solid fill. Reads as a mass. It is a mass by design; there is no interior detail to lose.
- The 16.00pt outer silhouette and the 100 deg mouth.

FAILS AT 1x, SURVIVES AT 2x
- Counter B, 1.10pt (2.2px at 2x). At 1x the creature's crown and the orbit ink touch the inner arc's inner edge.
- Orbit stroke 0.90pt (1.8px at 2x). At 1x it is a grey smear rather than a disc.
- Orbit inter-disc counters, 1.108pt (2.2px at 2x). At 1x the 2- and 3-agent patterns fuse; the orbit degrades to "activity present / absent" and the COUNT IS LOST at 1x. I am not claiming otherwise.
- Creature-to-outboard-disc clearance, 0.940pt (1.88px at 2x) — 0.12pt under even the 2x floor, so at 2x it is a hairline and at 1x the 3-agent state touches the creature.
- Chevron-to-chevron counters, 1.000pt (exactly 2px at 2x). At 1x the three chevrons merge into a zigzag band; the alert state still reads, because the ring, the colour and the segmentation all survive, but "three chevrons" becomes "a zigzag".

FAILS AT 1x AND 2x
- Counter A, 1.900pt. 0.10pt under the 1x floor, comfortable at 2x (3.8px). At 1x the two arcs read as a slightly soft double line rather than two crisp rings. This is the single compromise I would defend hardest, because the alternative was thinning the strokes into the grey zone.
- Crown valley fillet, radius 0.300pt, valley depth 0.4877pt. Invisible at 1x, about 1px at 2x. At 1x the creature is one rounded dome. Charm lost, information intact.
- Sleeping pose's scaled fillet, 0.258pt minimum radius. Same.

PIXEL PARITY, stated rather than overclaimed. The outer edge of the outer arc sits at exactly r 8.00 from (11.00, 12.30), so at top dead centre it lands on y 4.300 and at the horizontal on x 3.000 and 19.000 — whole device pixels at 1x and 2x. The 1.30pt stroke cannot then put its inner edge on a whole pixel (5.600 is whole in y but the band is 1.3 wide, so around the curve the edges land wherever the tangent takes them); NO fractional stroke can. I snapped what a circular stroke lets you snap — the four cardinal edge crossings — and I am not going to claim more. The centre y of 12.30 was chosen so the ink box (4.300 to 17.6746) has its midpoint at 10.987, i.e. 0.013pt off the 22pt box centre.

WHAT WAS DONE ABOUT THE FAILURES. Three things. First, no state depends on a single sub-floor feature: sleep is carried by pose plus both tracks empty plus stillness; needs-input by colour plus the closed ring plus the chevrons, of which the ring alone survives everything. Second, the 50% bead was deliberately designed to need no counter at all, which is why it is the only sub-2pt feature in the mark that fully survives 1x. Third, at 1x the orbit's loss of count is a graceful one — it still says "agents are running", which is the bit that matters, and the exact number was always in the menu.

**評審必修：**
- (修正落實度, 24/40) The agent readout is built below the absolute floors: 0.90pt stroke (under the 1.0pt stroke floor), 1.108pt inter-disc counters, and 0.940pt creature-to-disc clearance which is under even the 2x counter floor - at three agents the count touches the creature. Move the count back onto the outer ring's own radius and stroke.
- (1x 與繪圖, 23/40) The mark is centred at (11,12.30) so the OPEN form's bbox sits square in the box. That guarantees the CLOSED form does not: the alert ring at centreline r7.35 stroke 1.30 runs to y=20.30 against y=17.675 in every gauge state — the box grows 2.62pt downward and the bottom margin collapses to 1.70pt against a 4.30pt top. The entry asserts 'the bounding box is literally the same set of extreme points in all eleven states. Needs-input does not change it either.' It does. Recentre at (11,11). Second: the agent orbit stroke is 0.90pt, below the 1.0pt absolute stroke floor — the element carrying the count is the only sub-floor stroke in the field — and its 0.94pt clearance to the creature fails even the 2x floor, so at N=3 the count touches the creature. Third, the chevron apex has the same stroke-linejoin:round problem as mouth, asserted here as 'removes any question'; it does not.

**自陳缺點：**
- The orbit's counting ceiling is 3. Five running agents, ten and fifteen all render as the same saturated arc, so the real-data state (5 agents) shows 'four or more' rather than five. A design whose brief says 'one unit per running agent' is only honouring that up to 3.
- At 1x the orbit loses the count entirely — its stroke is 0.90pt and its inter-disc counters are 1.108pt, both under the 1x floor — so on a non-Retina display the agent readout degrades to a binary 'something is running'.
- Counter A between the two gauge arcs is 1.90pt, 0.10pt under the 2.0pt 1x counter floor. It is the closest a two-arc mark can get while holding the outer diameter at exactly 16.00pt, but it is still under.
- The 50% bead carries no information while quota is above 50%: it is covered by the live arc and invisible. It only announces itself once you cross the threshold. That is defensible but it does mean four of the states in the gallery show no 50% mark at all.
- The creature is 2.80 x 1.85pt — about 40% of the area it would get without the orbit. At 1x it is a 3 x 2 pixel blob with no discernible crown, and the 0.4877pt valley that resolves correction 1 is invisible below 2x.
- The creature's bottom-right corner sits 0.940pt from the outboard disc in the 3-agent state, which is under even the 2x counter floor (1.88 device px). At 2x it is a hairline; at 1x they touch.
- Drawn ink height is 13.375pt, not 16. The enclosing circle is exactly 16.00pt and that is the number I optimised, but anyone measuring the alpha bounding box vertically will read 13.4 and can fairly call the mark visually small in a 22pt bar.
- Three chevrons at 1.00pt counters merge into a single zigzag at 1x. The needs-input state still reads via the ring and the colour, but the specific 'three chevrons' gesture is a 2x-and-above detail.
- The alert state drops the inner 7d arc entirely, so while any session is blocked the two quota gauges are unreadable. Blocking is transient, but the information is genuinely gone for its duration.
- Segmentation gaps on the alert ring (3.41pt) and a legal 50% notch (3.30pt) would have been nearly identical in size — I avoided the collision by choosing the bead, but it means the mark has no spare 'gap' gesture left for any future state.

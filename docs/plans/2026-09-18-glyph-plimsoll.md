> ⚠️ **已被取代（2026-09-18）。** 使用者檢視後判定「不夠好看、UI 不夠好」，並指出 Stats / UTUVO Orbit 的做法才對：
> **選單列只放簡單好認的圖示（可以有數字），細節全部放進點開後的面板。**
> Plimsoll 這種「刻意不放數字、需要學會怎麼讀」的抽象儀表因此作廢。
> 本文件保留作為設計紀錄與幾何參考（even-odd 合成、snap 規則、動畫終止契約仍然有參考價值）。
> 現行方向見 `2026-09-18-panel-directions.md`。

# Glyph 規格：Plimsoll

> 由 5 設計 → 3 評審 → 1 綜合的工作流產出。互動預覽：https://claude.ai/artifact/KhrPRjrFqEHiszDjUKxdrs
> 機器可讀原始規格：`2026-09-18-glyph-plimsoll.spec.json`

**固定寬度：** 36pt（NSStatusItem 另加 16pt padding，實際約 52pt）

## 概念

A single fixed 36pt vessel in which the five-hour window is a solid mass whose WIDTH is how much you have spent and whose HEIGHT is how many agents are spending it, and the seven-day window is one load line drawn on the same axis — ink where the track is still empty, a clean slot punched through the mass where the hour has already passed it — with the vessel's own shutter owning data freshness, so a reading the app no longer trusts is not dimmed, it is structurally not drawable.

## 為什麼是這個

The winner's real prize was the two-dimensional interior fill: width is consumption-so-far, height is live concurrency, so the mass's AREA is pressure and the height is literally the rate at which the width will grow — the derivative sitting on the integral in one rectangle. Every judge wanted that grafted everywhere. Its one fatal flaw was that the second quota had been exiled to a perimeter ring: a decoder you must learn, with non-uniform precision inside the caps, anchored on a 0.30-alpha hairline that a bright wallpaper eats first.

Plimsoll kills the ring and puts the seven-day window on the SAME horizontal axis as a single 1pt rule — and then makes one move that collapses four separate problems into one geometric fact. The rule and the mass are composited with a single even-odd fill, so the rule is ink where the track is empty and a hole where the mass has reached it. That gives, for free and with no legend, rail, colour or second shape:

(1) Which window binds. Two marks on one axis, both fixed in meaning forever — the mass front is ALWAYS the five-hour window, the load line is ALWAYS the seven-day. Whichever is further right is biting. This is a spatial comparison like two hands on a watch, and unlike the runner-up it never swaps its referent between glances, which was the single perceptual hazard the judges called disqualifying.

(2) The slack between them. The distance from the mass front to the load line is exactly how much room the other window still gives you.

(3) Robustness. When the line is behind you it is a white slot in a black mass; when it is ahead of you it is a black rule on an empty track. It is maximally legible in both, on any wallpaper, with no contrast rule and no alpha discrimination — the two presentations are figure and ground of the same mark. Nothing in this glyph requires telling 0.10 alpha from 0.20 through menu-bar vibrancy, which is what sank two of the five entries.

(4) The name. A Plimsoll line is the load mark painted on a ship's hull: it is submerged exactly when you are overloaded. Here the load line submerges exactly when the hour has out-spent the week. The metaphor is not decoration; it is a literal description of the compositing rule.

The third insight is stolen from the smallest entry and is the best epistemics anyone proposed: freshness owns the shutter, not a badge. Live is a clean vessel; minutes old is a lid resting in the gutter; tens of minutes and the lid thickens while the mass's leading edge feathers into uncertainty — the app stops asserting exactly where the front is because it does not know; past an hour the shutter is SHUT, a wall-to-wall bar across a vessel with nothing in it. "Never show a stale number as if it were current" stops being a rule someone must remember and becomes a thing the renderer cannot do.

And restraint is structural rather than stylistic: idle-and-fresh is an outline with a 2pt sliver in it and one hairline, which disappears into the bar; ten agents against an exhausted window is a solid slug pressed against a hardened wall. There is no font, no numeral, no blend mode, no offscreen layer, no sub-pixel mark, and no repeating timer anywhere in the product except for at most 24 seconds per blocking event.

## 幾何

```
COORDINATE SYSTEM
Canvas is ALWAYS 36.0 x 22.0 pt, origin bottom-left, y up (AppKit non-flipped). Rendered 72 x 44 px at 2x. The states[] SVGs use viewBox "0 0 36 22" with y DOWN: svgY = 22 - specY. The form is vertically symmetric about y = 11, so every container and track number is numerically identical in both systems; only the mass (which stands on the floor) differs, and its SVG y is given as 16 - hA.

Never set statusItem.length to .variableLength. Set it to 36. NSStatusItem adds its own fixed padding outside the image (measured 16pt on this machine), giving a constant ~52pt item. Neighbours can never shift because the image size is state-independent in every state including the alert.

THE VESSEL (the container; one stroked rounded rect, the only mark that is always present)
  CALM    path rect x 1.55 -> 34.45, y 4.55 -> 17.45 (32.90 x 12.90), corner radius 3.00, stroke 1.10 centred.
          => ink outer x 1.00..35.00, y 4.00..18.00; clear inner x 2.10..33.90, y 5.10..16.90.
  PRESSED path rect x 1.80 -> 34.20, y 4.80 -> 17.20 (32.40 x 12.40), corner radius 2.80, stroke 1.60 centred.
          => ink outer identical (1.00..35.00 x 4.00..18.00); clear inner x 2.60..33.40, y 5.60..16.40.
  The outer silhouette is IDENTICAL in both, so the escalation is a weight change, never a size change.
  There is no nub, no tab and no cap: this must not be read as the system battery.

THE TRACK (the measured field; never itself drawn)
  x 3.00 -> 33.00  =>  T = 30.00 pt
  y 6.00 -> 16.00  =>  H = 10.00 pt
  1% = 0.300 pt = 0.600 device px at 2x. Honest read precision at a glance: +/- 4 percentage points.
  Uniform 0.80 pt gutter to the calm clear area on all four sides (0.40 pt when pressed). Because the gutter g = 0.8 and the inner corner radius r = 2.4 satisfy r <= g*sqrt(2)/(sqrt(2)-1) = 2.73, the track's corners lie inside the rounded corners: NO CLIPPING IS EVER REQUIRED. Do not install a clip path.

SNAPPING (mandatory; this is the anti-shimmer rule)
  Every computed x and y is snapped to the nearest 0.50 pt = 1 device pixel at 2x before drawing:
  snap(v) = round(v * 2) / 2.
  Consequence: every reading is quantised to 1.67 percentage points, and the glyph is visually motionless while a value wobbles inside one pixel.

--- VALUE 1 : five_hour utilisation p5 in [0,1] -> THE MASS's WIDTH ---
  front = snap(3.00 + 30.00 * p5)
  w5 = (p5 <= 0.005) ? (sessionsPresent ? 1.50 : 0.00) : max(2.00, front - 3.00)
  The 2.00 pt floor guarantees a nonzero window is never invisible; the 1.50 pt stub at exactly 0% with sessions open says "alive, nothing spent".
  Mass rect: x 3.00 -> 3.00 + w5, y 6.00 -> 6.00 + hA.
  Corner radii: LEFT pair  rl = min(0.80, hA/2.5, w5/2.5)
                RIGHT pair rr = min(0.30, hA/2.5, w5/2.5)
  The right edge is the measurement, so it is kept near-square. The left is the heel of the mass and is softened so it nests.
  JAM: when p5 >= 0.995 the mass extends to x = 33.60 instead of 33.00, crossing the 0.40 pt gutter and touching the pressed vessel's inner wall. The mass physically reaches the wall. This is a silhouette event at exactly 100% and costs no new mark and no colour.
  UNKNOWN p5: p5 and p7 arrive in one payload, so an unknown p5 is an unknown reading; render the UNKNOWN face (Value 5).

--- VALUE 2 : seven_day utilisation p7 in [0,1] -> THE LOAD LINE ---
  wBar = (p7 > p5) ? 1.50 : 1.00
  barLeft = clamp(snap(3.00 + 30.00 * p7 - wBar/2), 3.00, 33.00 - wBar)
  Rect: x barLeft -> barLeft + wBar, y 6.00 -> 16.00. FULL TRACK HEIGHT, ALWAYS.
  THE COMPOSITING RULE (this is the design): the mass rect and the load-line rect are two subpaths of ONE path filled with the EVEN-ODD rule. Therefore:
      load line beyond the mass front  ->  it draws as a standing rule on the empty track
      load line behind the mass front  ->  it punches a clean slot through the mass and continues above the mass as a rule
  Ink is identical (alpha 1.00) in both cases. No blend mode, no mask, no second alpha, no contrast rule.
  WHY THE TWO WIDTHS: a knockout slot needs to be narrow to stay legible inside a mass (1.00 pt = 2 device px); a standing rule in empty space needs weight to hold its own (1.50 pt = 3 device px). The rule is pure legibility and it happens to redundantly reinforce the semantics — the heavier mark is always the one that is ahead of you.
  WHEN THEY COINCIDE: if |barLeft + wBar/2 - front| < 1.0 pt the even-odd result is a small notch plus a small post at the front. There is NO special case, because the marks coincide precisely when the two windows are at the same level, which is true information.
  UNKNOWN p7: same payload as p5 -> UNKNOWN face.

--- VALUE 3 : running agent count n -> THE MASS's HEIGHT ---
  no Claude Code sessions at all      -> hA = 1.00
  sessions present, n agents running  -> hA = (n <= 3) ? 2.00 + 1.00*n : min(10.00, 5.00 + 0.50*(n - 3))
  Table: none=1.0 | idle(n=0)=2.0 | 1=3.0 | 2=4.0 | 3=5.0 | 4=5.5 | 5=6.0 | 6=6.5 | 7=7.0 | 8=7.5 | 9=8.0 | 10=8.5 | 11=9.0 | 12=9.5 | 13+=10.0 (flush with the track ceiling).
  Every value is a multiple of 0.50 pt, i.e. an exact device pixel at 2x, so the mass never has a fuzzy top edge.
  1/2/3 are 1.00 pt apart (the subitising range, where humans count exactly). 4..12 are 0.50 pt apart = 2 device pixels per agent, which is discriminable and reads as density. 13+ is the ceiling.
  At 3 agents the mass is 5.0 pt; at 10 it is 8.5 pt — a 70% increase in area at constant width. That is the fan-out signal.
  AGING CLAMP: when freshness = AGING, hA is clamped to 9.00 so the descending lid presses on the mass rather than truncating it (see Value 5).
  UNKNOWN n (the local session scan failed): hA = 5.00 and the mass is drawn HOLLOW — its outline rect plus the same rect inset 0.90 pt, both added to the even-odd path, giving a 0.90 pt open frame. "This dimension is not measured." Square corners, deliberately unlike any solid state. needs-input is NOT asserted in this condition; the app never invents an alarm out of a failed read.

--- VALUE 4 : needs-input -> FULL INVERSION TO THE PURPLE SLAB (highest precedence) ---
  Trigger: one or more sessions with status == waiting AND a waitingFor payload (a session stalled behind its own subagents is busy, not waiting). Sourced from LOCAL session state only, so it is never stale and never combines with the ghosting.
  SLAB: filled rounded rect x 1.00 -> 35.00, y 4.00 -> 18.00, radius 3.60. Exactly the calm vessel's outer silhouette, so the bounding box, the width and the position are unchanged. isTemplate = false.
  KEYLINE: stroke the path inset 0.40 (x 1.40 -> 34.60, y 4.40 -> 17.60, radius 3.20) at 0.80 pt in the keyline colour. This is what guarantees separation from an arbitrary wallpaper.
  QUOTA UNDERLAY (the alert preserves its data instead of discarding it): the SAME even-odd interior path — mass + load line, projection wedge suppressed — filled in #FFFFFF at alpha 0.36. Width, height and the load line all survive the morph. Nothing is thrown away at the one moment both facts matter.
  CHEVRONS (the user's own prompt glyph): white #FFFFFF, stroke 2.00 pt, round cap and join, drawn over the underlay at full opacity.
      chevron k (k = 0 is rightmost): polyline (xk, 7.60) -> (xk + 2.60, 11.00) -> (xk, 14.40), xk = 29.00 - 4.20*k
      k=0 at x 29.00, k=1 at x 24.80, k=2 at x 20.60. Rightmost ink reaches 32.60, inside the slab.
  BLOCKED COUNT: 1 blocked -> 1 chevron. 2 or 3 -> 2 chevrons. 4+ -> 3 chevrons. The stack grows leftward, toward you.
  IF freshness is STALE or UNKNOWN while blocked: the underlay is replaced by a single white bar at alpha 0.24, x 2.20 -> 33.80, y 10.40 -> 11.60 (the shut shutter, in white). The glyph shouts about the prompt without inventing a quota number.
  The pressed and jam escalations do not apply in this state; the slab has no outline to harden.

--- VALUE 5 : data freshness -> THE VESSEL's SHUTTER ---
  Five tiers, quantised, with a 10 s dead band at each boundary. No tweening between them.
  LIVE (<= 60 s)          Nothing extra is drawn. A clean vessel is a live vessel.
  RECENT (60 s - 5 min)   LID in the gutter: rect x 3.00 -> 33.00, y 16.20 -> 16.80 (0.60 pt), at container-layer alpha 0.42. It occludes nothing. A footnote, deliberately not glanceable.
  AGING (5 - 60 min)      LID descends and thickens: rect x 3.00 -> 33.00, y 15.20 -> 16.80 (1.60 pt), alpha 0.75. hA clamps to 9.00 (mass top 15.00) leaving a 0.20 pt gap, so the lid visibly presses.
                          MASS FRONT FEATHERS: ramp = min(3.00, 0.60 * age_minutes) pt. Over x from (front - ramp) to front the mass's alpha falls 1.00 -> 0.10. Uncertainty about the number is drawn as uncertainty about where its edge is.
                          LOAD LINE GOES DASHED: 1.60 on / 1.40 off, phase starting at y = 6.00 (segments 6.0-7.6, 9.0-10.6, 12.0-13.6, 15.0-16.0). Still full ink, still even-odd — structural degradation, not tonal.
                          PROJECTION WEDGE SUPPRESSED. You cannot forecast from data you do not have.
  STALE (> 60 min)        SHUT. The vessel is stroked SOLID at 1.10 pt, alpha 0.85 — loud, not a ghost, because "you are flying blind" deserves a full-strength mark. The interior contains exactly one mark: a wall-to-wall bar, x 2.10 -> 33.90, y 10.40 -> 11.60 (1.20 pt), full ink.
                          Nothing else is drawn. There is no quota on screen to be misread as current.
                          DISAMBIGUATION from a real reading: a mass always stands on the floor (y 6.00) and always stops 0.80 pt short of both walls. The shut bar floats at mid-height and touches both walls. Those two signatures cannot coexist.
  UNKNOWN (never fetched / auth failed / account mismatch / parse error)
                          Vessel stroked DASHED, 2.00 on / 1.60 off, 1.10 pt, alpha 0.55. Interior: one short centred dash, x 14.00 -> 22.00, y 10.60 -> 11.40 (0.80 pt), alpha 0.55. An em dash in a broken frame: the universal "no value", and unmistakably not 0% (0% still shows a solid vessel, a 1.5 pt stub and a load line).

--- VALUE 6a : burn rate -> THE PROJECTION WEDGE ---
  p_proj = p5 + (20-minute EWMA of consumption per minute) * (minutes remaining in the five-hour window)
  GATE (all must hold, or nothing is drawn): freshness in {LIVE, RECENT} AND p_proj >= p5 + 0.10 AND p5 >= 0.20.
  apex_x = clamp(snap(3.00 + 30.00 * min(p_proj, 1.00)), 4.20, 31.80)
  Triangle: (apex_x - 1.20, 16.00), (apex_x + 1.20, 16.00), (apex_x, 14.40). It HANGS FROM THE TRACK CEILING, pointing down at where you will be when this window closes.
  It is added to the same even-odd interior path, so if the mass has reached the ceiling the wedge knocks out of it instead of sitting on it. One compositing rule for the entire interior.
  A downward triangle is the only non-rectilinear mark in the glyph, so it can never be confused with the load line or the mass.
  UNKNOWN burn (fewer than 20 minutes of rate history, or freshness not LIVE/RECENT): not drawn. Absence is no claim.
  NOTE: burn is also encoded for free and continuously by the mass's HEIGHT, because height is concurrency and concurrency is the rate at which width grows. The wedge is the discrete "you will hit the wall" escalation on top of that.

--- VALUE 6b : which window is binding -> SPATIAL, ZERO INK ---
  Whichever of {mass front, load line} is further right is the window that will stop you. Both marks have permanently fixed identities (front = five-hour, line = seven-day), so the meter's subject never changes between glances. Reinforced redundantly by the load line's width (1.50 pt when it is ahead of the front, 1.00 pt when behind).
  PRESSED ESCALATION: the vessel switches from CALM to PRESSED when max(p5, p7) >= 0.85, releasing at 0.82 (mandatory hysteresis). It is driven by the MAXIMUM, so "you are close to a wall" is signalled whichever wall it is, including the case where the seven-day window binds and the mass is small.
  UNKNOWN: if the payload is unknown, the vessel shows the UNKNOWN face and asserts nothing about binding.

Z-ORDER (back to front), calm path
  1. vessel stroke (weight/alpha/dash per pressed + freshness)
  2. lid rect, if RECENT or AGING
  3. ONE even-odd fill: mass + load line (+ wedge if gated) -- a single fillPath(using: .evenOdd)
  4. AGING only: destination-out linear gradient clipped to the mass rect, producing the feathered front
  5. STALE only: the shut bar.  UNKNOWN only: the centred dash.
Nothing else is ever drawn.

INK MODEL (two levels, and that is the whole tonal system)
  VALUE LAYER      alpha 1.00 always. Everything that carries a number.
  CONTAINER LAYER  exactly one alpha at a time: 0.42 calm | 0.95 pressed | 0.85 stale | 0.55 unknown. The RECENT lid draws at 0.42, the AGING lid at 0.75.
  No mark anywhere in this design requires discriminating one intermediate alpha from another, which is the failure mode that sank the two most information-dense competitors.
  accessibilityDisplayShouldIncreaseContrast: calm 0.42 -> 0.62, RECENT lid 0.42 -> 0.62, unknown 0.55 -> 0.75. The value layer is unaffected because it is already 1.00.
```

## 動畫契約

```
EXACTLY ONE THING IN THE ENTIRE APPLICATION IS EVER ALLOWED TO MOVE: the opacity of the chevron group, and only while one or more sessions are blocked on the human.

WIDTH IS IMMUTABLE. 36.0 pt in every state, including the morph into and out of the alert. The alert is a figure/ground inversion at an identical bounding box, which is a larger salience jump than a size change could ever be and costs the neighbouring menu-bar items nothing. There is no entry wipe: the slab replaces the vessel on a single frame, because a state that has just begun does not need ceremony, it needs to be there.

WHAT MOVES
  Property:  opacity of the chevron group only. The slab, the keyline and the quota underlay never move.
  Range:     1.00 -> 0.45 -> 1.00
  Period:    1.50 s per full cycle
  Curve:     easeInEaseOut, cubic-bezier(0.42, 0.00, 0.58, 1.00) on each half
  Cycles:    4, i.e. 6.00 s, then it STOPS at opacity 1.00 and holds perfectly still.

TERMINATION AND RE-ARM RULE (this is the whole restraint argument)
  The 6 s breath fires once on the leading edge of needs-input. It re-arms exactly three more times and never again:
    - whenever the blocked-session count INCREASES (the chevron count changing is news),
    - once at T + 60 s,
    - once at T + 300 s.
  Ceiling: 4 x 6 s = at most 24 seconds of motion per blocking event. After that the glyph is a static purple slab with static chevrons — still the loudest object in the bar, no longer moving.
  EXIT is instant and untransitioned: the moment the last block clears, the template image is reassigned with no fade. An animation on exit would train the eye to look at something that no longer needs it.

COST
  Implemented as 12 pre-rendered NSImages (opacity sampled along the ease curve; symmetric, so the loop has no seam), swapped by a single Timer at 12 Hz with tolerance 0.02 on RunLoop.main in .common mode so it survives menu tracking. Per tick the only work is button.image = frames[i]. The 12 frames cost ~2 ms to build, once per arrival.
  THE APP HAS NO REPEATING TIMER AT ALL outside those windows. Invalidate the timer and release the frame array the instant the breath completes — not merely pause it. Suspend on NSWorkspace.screensDidSleepNotification and session lock, and never create the frames at all when ProcessInfo.isLowPowerModeEnabled is true.

REDUCE MOTION
  accessibilityDisplayShouldReduceMotion == true: no frames, no timer, ever. The chevron group is drawn statically at 1.00 and the keyline goes to 1.00 pt at the increase-contrast alpha. The state loses nothing essential, because its salience comes from inversion, pigment and silhouette, not from motion.

WHAT MUST NEVER MOVE, UNDER ANY CIRCUMSTANCE
  - The mass's width. It changes when the data changes, instantly, with no tween. An animated quota bar in a menu bar is a slot machine.
  - The mass's height. During a 10-agent fan-out the height steps up through the ladder in discrete jumps; a tweened counter would be a strobe in the corner of the eye.
  - The load line. It jumps to its new x and stays there.
  - The projection wedge. It appears and disappears between polls with no fade.
  - The vessel's stroke weight at the 85% threshold, the jam at 100%, the lid at every freshness tier, the shut bar, the unknown dash, the feathered front.
  - The slab, the keyline and the quota underlay inside the alert.
  - The glyph's width, height or position, in any state, at any time.
  - Launch. There is no entrance animation.
  - Nothing pulses, breathes or spins for quota pressure, however high. Quota exhaustion is a thing you watch approach over hours; giving it an alarm channel would devalue the one channel that has a deadline.

REDRAW GATING
  Everything above is a static NSImage. Redraws are gated on the quantised render key (see implementation_notes), so an unchanged glyph is never rasterised and never re-assigned. Idle: minutes between redraws. Mid fan-out: at most about one per second. This is what keeps the icon genuinely motionless in peripheral vision, which is the only reason a 6-second breath four times a day is impossible to miss.
```

## Template / 顏色策略

```
HYBRID, with the split placed on meaning: isTemplate = true in every state except needs-input, which is the only coloured state and the only animated state. Colour and motion are therefore synonymous with "a human decision is blocking work right now", and nothing else is ever allowed to borrow that signal — not 99% quota, not fifteen agents, not an exhausted window, not stale data.

TEMPLATE PATH (14 of the 15 faces)
Draw everything as pure opaque black with per-mark alpha and set image.isTemplate = true. AppKit derives the menu-bar rendering from the ALPHA CHANNEL alone, which buys light bars, dark bars, macOS wallpaper tinting, the highlight inversion when the popover is open, and Reduce Transparency, all for free and all matching the battery and wifi glyphs beside it. Template rendering honours alpha rather than thresholding it, which is what makes the 0.42 vessel, the 0.75 aging lid and the 0.10-alpha feathered front legal moves rather than hacks.

The design deliberately spends almost nothing on this channel: there are exactly TWO ink levels (value layer 1.00, container layer one-of-four), and no value is ever carried by an alpha difference. The judges killed two concepts for asking a translucent menu bar over an arbitrary wallpaper to resolve 0.10 from 0.20. Here, if the vessel washed out completely, every one of the six values would still be readable from the marks that remain — the vessel only supplies the 100% reference, and it hardens to 0.95 at exactly the moment (>= 85%) when that reference matters most.

ALARM PATH (needs-input only), isTemplate = false
The slab is an OPAQUE filled shape. Opacity is the defence: the translucent wallpaper behind the menu bar is simply irrelevant to it, which is the property the one state with a deadline needs.

  light menu bar          slab #6B5FE0   keyline rgba(0,0,0,0.22)     marks #FFFFFF
  dark menu bar           slab #7B6FEC   keyline rgba(255,255,255,0.38) marks #FFFFFF
  increase-contrast light slab #4F40CF   keyline rgba(0,0,0,0.45) at 1.0 pt  marks #FFFFFF
  increase-contrast dark  slab #6B5FE0   keyline rgba(255,255,255,0.65) at 1.0 pt  marks #FFFFFF
  quota underlay          #FFFFFF @ 0.36 (0.46 under increase-contrast)
  stale substitute bar    #FFFFFF @ 0.24

Measured contrast of white marks on the slab: 4.84:1 on #6B5FE0, 3.94:1 on #7B6FEC. Every coloured mark is a stroke of 2.00 pt or a fill of 1.00 pt or wider, which is well past the large-object 3:1 threshold in both appearances; the keyline then guarantees the slab itself separates from any backdrop, light or dark, photographic or flat.

Canonical brand purple is #7266EA (the user's own terminal accent). The two rendered variants are +/- 6% lightness from it, so it still reads as the same purple as their status line — the glyph is recognisably part of their setup, not a generic system alert.

WHY COLOUR IS RATIONED TO EXACTLY ONE STATE
Colour in a menu bar is a finite resource: the moment a second hue exists, both stop meaning anything specific. This user will sit above 85% of the five-hour window for hours a day — a concept that spends amber there teaches the eye to ignore amber by Thursday, and then the one moment with a deadline is lost. Quota pressure is therefore entirely structural and entirely monochrome: at 89% the mass is a long slug and the wall is hard; at 100% the mass is touching the wall. Those pictures are already unambiguous and they cost no pigment. needs-input is instantaneous, rare and human-actionable, so it takes the pigment, the inversion and the only animation — all three at once, so peripheral vision can dispatch on chroma alone with zero false positives.

WHY NOT AN EYE
The family is QuotaMonster / BulletMonster / FocusMonster and a creature reading was available. It is declined. A blinking lens on a coloured pill is the cuteness this user does not want, and — more seriously — a pulsing coloured circle in the menu bar collides with the one shape macOS has already claimed for "you are being recorded", which is a dangerous false positive to ship. The family resemblance is carried by the vessel silhouette and the brand purple, not by a face.

DIFFERENTIATE WITHOUT COLOUR
accessibilityDisplayShouldDifferentiateWithoutColor needs no extra code path: the alert is already a complete figure/ground inversion with a unique silhouette (a solid slab where every other state is an outline) and a unique mark (the chevron stack, which exists nowhere else). The purple is confirmation, never the carrier.

APPEARANCE PLUMBING
Resolve from statusItem.button.effectiveAppearance (NOT NSApp's — the menu bar follows the wallpaper's luminance and can be dark while the app is light), via appearance.bestMatch(from: [.aqua, .darkAqua]). Observe the button's effectiveAppearance by KVO, plus the distributed AppleInterfaceThemeChangedNotification and NSApplication.didChangeScreenParametersNotification. Only the two alert images ever need re-rendering; the template images never do. Never mutate isTemplate on an image already assigned to the button — build the new image, set the flag, then assign.
```

## 實作備註

```
RASTERISATION
  NSImage(size: NSSize(width: 36, height: 22), flipped: false) { rect in draw(state, rect); return true }
The handler is re-invoked per backing scale factor, so 1x and 2x both come out correct with no manual scaling and the image is automatically right when the window moves to an external display. flipped: false gives a bottom-left origin that matches the geometry spec one to one — type the numbers in directly. Set image.isTemplate AFTER the closure and BEFORE assigning to statusItem.button.image; never mutate the flag on an image already on the button.

DRAW PATH, in order, per redraw
1. VESSEL. NSBezierPath(roundedRect: pathRect, xRadius: r, yRadius: r); set lineWidth; setLineDash for the UNKNOWN face; stroke with NSColor.black.withAlphaComponent(containerAlpha).
2. LID (RECENT / AGING only). ctx.fill(lidRect) at 0.42 / 0.75.
3. THE INTERIOR, ONE PATH, ONE CALL. Build a single CGMutablePath:
     - the mass, as a manual rounded rect. CGPath(roundedRect:) cannot do asymmetric radii, so construct it with move + addArc(tangent1End:tangent2End:radius:) for the four corners, passing rl for the left pair and rr for the right pair. addArc(tangent1End:...) degrades gracefully to a sharp corner when the radius is clamped to 0, so no branch is needed for tiny masses.
     - the load line: one rect, or the four dash rects when AGING.
     - the projection wedge triangle, if gated.
     - the hollow-mass inner rect, if the agent count is unknown.
   Then: ctx.addPath(p); ctx.setFillColor(black); ctx.fillPath(using: .evenOdd)
   This ONE call produces the entire compositing behaviour: ink on the empty track, holes in the mass, hollow frames. DO NOT use blend modes. A template image is read through its alpha channel, and .xor / .destinationOut on alpha is fragile across appearance changes and offscreen caches; the even-odd winding rule gives the symmetric difference natively, in the alpha domain, with no state to restore.
4. AGING FEATHER only:
     ctx.saveGState()
     ctx.clip(to: massRect)                       // critical: the clip is the MASS rect, so the load line's ink above the mass is untouched
     ctx.setBlendMode(.destinationOut)
     ctx.drawLinearGradient(clear -> black@0.90, start: (front - ramp, 0), end: (front, 0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
     ctx.restoreGState()                          // also restores the blend mode
5. STALE: ctx.fill(shutBar). UNKNOWN: ctx.fill(dash) at 0.55.
Nothing else is ever drawn on the calm path.

ALERT PATH
  1. fill the slab rounded rect with the resolved purple
  2. stroke the inset keyline at 0.80 (1.00 under increase-contrast)
  3. setFillColor(white @ 0.36); fill the SAME even-odd interior path (wedge omitted) — or the white shut bar @ 0.24 when the payload is stale/unknown
  4. stroke each chevron polyline: white @ chevronOpacity, 2.00 pt, .round cap and join
  image.isTemplate = false.

PIXEL DISCIPLINE
  Every mark is a filled rect, a filled triangle or a filled rounded rect with edges pre-snapped to 0.50 pt. The ONLY strokes in the whole design are the vessel outline, the alert keyline and the chevrons, all of which are centred on paths whose coordinates are chosen so that the stroke's ink lands on whole 0.50 pt boundaries (e.g. 1.55 +/- 0.55 = 1.00 and 2.10). Snap every computed coordinate with round(v*2)/2 before it reaches Core Graphics. This is what stops the mass front shimmering as a value drifts.

NO 1x FALLBACK IS REQUIRED
  There is no text, no font metric, no reverse type and no mark thinner than 0.60 pt. At 1x the thinnest marks (the RECENT lid at 0.60 and the load line at 1.00) land on 1 device pixel and survive intact; the 0.50 pt quantisation degrades to 1 px quantisation and the readings are unchanged. Unlike the numeral-based concepts, this glyph does not have to change character on a second display, and there is no per-screen branch — which an NSImage could not honour anyway, since one image serves every screen the status item appears on.

RENDER CACHE KEY (Hashable, fully pre-quantised — this is what keeps the icon motionless)
  struct GlyphKey: Hashable {
    let front:   Int16      // mass front, in 0.5 pt units
    let height:  Int8       // mass height, in 0.5 pt units (2...20)
    let bar:     Int16      // load-line LEFT edge, in 0.5 pt units
    let barWide: Bool       // p7 > p5
    let wedge:   Int16?     // apex in 0.5 pt units, nil when gated off
    let fresh:   Freshness  // live | recent | aging | stale | unknown
    let ramp:    Int8       // feather ramp in 0.5 pt units, AGING only
    let pressed: Bool       // max(p5,p7) >= 0.85, released at 0.82
    let jammed:  Bool       // p5 >= 0.995
    let hollow:  Bool       // agent count unknown
    let blocked: Int8       // 0 = calm; 1 | 2 | 3 = chevron count
    let frame:   Int8       // breath frame 0...11; 0 in every static state
    let dark:    Bool       // only affects the alert path
    let contrast: Bool
  }
  Quantising at the KEY boundary rather than at draw time is the whole trick: identical keys mean an identical image, so skip both the rasterisation and the button.image assignment. Keep an LRU of 48 NSImages. Flush the entries whose `dark` or `contrast` flag no longer matches on an appearance change; the template entries survive appearance changes untouched because macOS recolours them.

COST PER REDRAW
  Worst case: one stroked rounded rect, one even-odd fill of at most 7 subpaths (mass + 4 dash rects + hollow inner + wedge), one clipped 3 pt gradient, one small rect. Roughly 6 path operations into a 72 x 44 px backing — well under 0.2 ms on Apple silicon. Draw cost is irrelevant; REDRAW FREQUENCY is the thing the key controls. Poll quota on a 30 s timer with jitter; take agent and blocked counts from the local session signal as they change. Expect single-digit redraws per hour when idle and at most about one per second during a fan-out.

HYSTERESIS AND DEAD BANDS (all mandatory, or the glyph twitches)
  - pressed engages at max(p5,p7) >= 0.85, releases below 0.82
  - jam engages at p5 >= 0.995, releases below 0.985
  - freshness tier boundaries carry a 10 s dead band each way
  - the projection wedge requires two consecutive samples past its gate to appear, and two below to vanish
  A menu-bar icon that flickers on a threshold is worse than one that is slightly out of date.

ACCESSIBILITY
  Rebuild button.image?.accessibilityDescription and button.toolTip from the same render state on every key change. The glyph deliberately carries no numerals, so this is where precision lives:
    "5 hour 68 percent, 7 day 47 percent, 10 agents running, live, on pace for 94 percent"
    "4 sessions waiting for you, 5 hour 57 percent"
    "Quota data stale, last reading 84 minutes ago"
  Observe accessibilityDisplayShouldReduceMotion, ...ShouldIncreaseContrast and ...ShouldDifferentiateWithoutColor via NSWorkspace.shared.notificationCenter (accessibilityDisplayOptionsDidChangeNotification).

STATUS ITEM
  statusItem.length = 36. Never .variableLength. Keep an off-screen detector — (button.window?.frame.origin.y ?? 0) < 0 — because relegation past the 216 pt ceiling is silent; at ~52 pt of item this design has large headroom, but the check costs nothing.

FAILURE FALLBACK
  If the draw handler throws or the model is nil, render the UNKNOWN face. Never leave a stale image on the button and never render blank — a blank status item is indistinguishable from a crashed app.

TESTABLE SURFACE (no screenshot permission on this machine)
  The geometry is a pure function of GlyphKey. Unit-test: massWidth(p5), massHeight(n, sessionsPresent) across the whole ladder including the AGING clamp, loadLineLeft(p7, p5) including both widths and both clamps, the even-odd subpath set for each freshness tier, the wedge gate and its apex clamp, the pressed/jam hysteresis, and the freshness boundaries at exactly 60 s, 5 min and 60 min. Then assert in-process that image.size == NSSize(36, 22) and image.isTemplate == (blocked == 0) for all fifteen faces. Colour and optical balance need human eyes; everything else above is testable without AppKit rendering.
```

## 已知缺點

- The load line reads as a HOLE far more often than as a rule, because this user's five-hour window normally leads the seven-day one. A hole in a mass is a weaker percept than a mark on a track, and at idle heights (a 2 pt mass) the slot is a 1 pt gap in a 2 pt sliver — nearly invisible. The reading survives only because the line's ink continues above the mass, which means the same mark has two very different saliences depending on the state, and the user learns the low-salience one last.
- Ink is proportional to FIVE-HOUR trouble, not total trouble. When the week is the binding window — a 38% mass with an 87% load line — the glyph is visually quiet at exactly the moment the user is most constrained. The pressed vessel is the only compensation and a stroke-weight change is a genuinely weaker channel than mass. This is the price of refusing to let the mass swap its referent, and I would pay it again, but it is a real hole in the 'area is pressure' claim.
- Agent resolution is gone above twelve. Thirteen, fifteen and thirty agents all render as a mass flush with the ceiling. Between four and twelve the steps are 0.50 pt — two device pixels per agent — which is discriminable comparing two glyphs side by side but not from memory an hour later. The exact fan-out is a popover fact, permanently.
- The vessel at 0.42 alpha and 1.1 pt is still the weakest mark, and it carries the 100% reference that gives the mass front its meaning. Over a bright, busy wallpaper with menu-bar translucency it can wash toward nothing, and then 60% and 90% become hard to separate. The >= 85% hardening fixes the case that matters most and does nothing at all between 50% and 84%, which is where this user lives most afternoons.
- The STALE face discards the agent count entirely. Ten agents running against a dead quota endpoint shows a shut shutter and no sign that work is in flight. This is deliberate — the alternative risks a remembered number being read as current — but it means the glyph is least informative exactly when something is broken, and 'the quota API is down' and 'the app has crashed' produce a similar impression.
- The projection wedge is the one mark whose meaning cannot be inferred without being told. It also appears and disappears between polls with no transition, which for the first several sightings is indistinguishable from a rendering glitch in the corner of the eye. It is a reward for having read the docs, not a warning.
- Blocked-session count compresses to 1 / 2-3 / 4+. Two blocked sessions and three look identical. Worse, a stack of chevrons is a shape the platform already uses for 'next' and 'fast forward', so a first-time viewer may read it as an affordance rather than a count.
- The alert slab is opaque and therefore does not participate in macOS wallpaper tinting. On a strongly tinted menu bar it will be the only item in the row not harmonised with the wallpaper, and will read as slightly foreign next to the system glyphs. That is the price of being unmissable and it is chosen deliberately, but it is visible.
- There are no numerals anywhere, by construction. There is no way to read '73%' off this glyph, ever, without clicking. For a user whose terminal status line is a hand-tuned true-colour precision instrument, a +/- 4 percentage-point gauge in the place they look most often may feel like a downgrade rather than a distillation.
- 36 pt of image is about 52 pt of item — roughly 1.3x the system battery. It is fixed and never jumps, which is the courtesy the brief asked for, but it is not cheap on a notched Air with many third-party items, and there is no graceful compact variant: below about 28 pt the track falls under 0.28 pt per percentage point and the load-line knockout stops reading inside a short mass.
- The pressed transition at 85% is a step change in stroke weight across the entire outline, so the icon visibly changes material when it crosses. Even with the 82% release hysteresis, a user who hovers near the threshold will see it flip a couple of times a day, and each flip pulls the eye for a non-event. A slower, continuous ramp was rejected because it would have reintroduced the multi-alpha discrimination this design exists to avoid.
- RECENT freshness is a 0.6 pt bar in the gutter and is effectively invisible at a glance. Three of the five tiers are glanceable (aging, stale, unknown) and one is a deliberate footnote, which means the glyph cannot answer 'is this live right now' — only 'is this current enough'. There will be a moment when the user wishes it had told them.
- Everything snaps to 0.50 pt, so every reading is quantised to about 1.67 percentage points and the glyph sits perfectly still while a value moves from 61% to 62%. Anyone expecting a live readout will call it stuck; the tooltip is the only cure.
- 'Sessions open but idle' (mass 2.0 pt) versus 'no sessions at all' (1.0 pt) is a one-point height difference on a mark that may be only a few points wide at low quota. It is the least reliable distinction in the design, it is the one a bright wallpaper degrades first, and two of the six values would be more robust if I had simply refused to encode this one.

## 狀態清單

- `zero-sessions` — 5h 14%, 7d 37%, no Claude Code sessions running at all, data live. The mass is a bare 1.0 pt sliver on the floor — the quota is still reported honestly because it is still true, but the vessel is dormant. The seven-day load line is ahead of the mass front, so it draws as a 1.5 pt standing rule on the empty track: the week is the binding window, and you can see the slack between the front and the line at a glance. Nothing is dimmed; the whole glyph is at full value ink.
- `idle-calm` — 5h 31%, 7d 44%, two sessions open, zero agents executing, data live. This is what the user sees most of the day and it is designed to be ignorable: an outline, a 2 pt sliver and one hairline. The only difference from zero-sessions is the mass doubling in height from 1.0 to 2.0 pt — sessions are open, nothing is working. The load line still stands ahead of the front, so the week remains the binding constraint.
- `busy-3-agents` — 5h 52%, 7d 41%, 3 agents running, data live, burning toward roughly 71% by window close. The five-hour window has overtaken the week, so the load line has SUBMERGED: it is now a clean 1.0 pt slot punched through the mass, with its ink continuing above as a hairline. That is the whole design in one picture — the same mark, ink above the waterline and a hole below it. The mass is 5.0 pt tall; the little downward wedge hanging from the ceiling at 71% is where this window ends up if nothing changes.
- `busy-10-agents` — 5h 68%, 7d 47%, 10 agents fanned out, data live, projecting 94%. Against busy-3 the width has advanced only 5 pt but the mass has grown from 5.0 to 8.5 pt tall — almost all of the visual change is the concurrency, and the total ink has roughly doubled without the glyph moving, resizing or gaining a single new mark. The height is literally the rate at which the width will grow, which is why the projection wedge has slid to the far right and is nearly against the wall.
- `quota-high` — 5h 89%, 7d 61%, 4 agents, data live, projected to exhaust the five-hour window before it resets. Two things change at once and neither is a colour: the mass has run most of the track, and the vessel has switched from CALM (1.1 pt at 42%) to PRESSED (1.6 pt at 95%) — the wall you are heading for has become hard, at exactly the moment the 100% reference is the number you actually need. The wedge is clamped against the right end of the track. The load line sits submerged at 61%, showing how much room the week still has.
- `quota-critical` — 5h 100%, 7d 74%, 6 agents still running and about to start failing. The mass crosses the last 0.6 pt of gutter and physically TOUCHES the pressed wall — a silhouette event at exactly 100%, costing no new mark and no pigment. The load line at 74% is submerged deep inside the mass, which tells you the useful thing: the week is nowhere near spent, so the popover's reset countdown is the number to look at. Still entirely monochrome. This is a state you watched arrive over hours; giving it an alarm channel would devalue the one state that has a deadline.
- `seven-day-binding` — 5h 38%, 7d 87%, 5 agents, data live. The state that proves the fixed-referent decision: the hour is comfortable and the mass is small, but the load line has surfaced far to the right at 87% and thickened to 1.5 pt, and the vessel is PRESSED because the escalation is driven by the maximum of the two windows, not by the mass. You learn in one glance not only that you are constrained but WHICH window is doing it — the long one, so slowing down inside this session will not help. No legend, no rail, no colour, and neither mark has changed what it means.
- `needs-input` — One session blocked on a permission prompt or a question. The vessel inverts: same 36 pt width, same silhouette, same position, now a solid purple slab with a 0.8 pt keyline that guarantees separation from any wallpaper. The quota SURVIVES the morph as a white 36% underlay — mass width, mass height and the load-line slot all still readable — because at exactly this moment both facts matter. The knocked-out chevron is the user's own prompt glyph: the prompt is waiting for you. This is the only coloured state and the only state that moves.
- `needs-input-multiple` — Four sessions blocked at once, 6 agents still running underneath. The chevron stack grows leftward, toward you: 1 blocked is one chevron, 2 or 3 is two, 4 or more is three. It is a magnitude, not a tally, which is the right resolution — you do not act differently on four versus five, you act differently on one versus a pile. The quota underlay is unchanged and the mass is visibly taller than in the single-block state, because the agents are still working while you are the bottleneck.
- `needs-input-breath-dim` — The second cached alert frame, showing the trough of the arrival breath: the chevron group alone drops to 45% opacity while the slab, keyline and quota underlay hold perfectly still. Twelve frames are interpolated between this and the full-opacity frame along an easeInEaseOut curve, 1.5 s per cycle, four cycles, then it stops dead at full opacity and the app has no running timer again. Total motion budget: at most 24 seconds per blocking event, re-armed only when the blocked count rises and once each at T+60 s and T+300 s.
- `data-recent` — 5h 43%, 7d 39%, 2 agents, the reading is 90 seconds old. A 0.6 pt lid has appeared in the gutter above the track. It occludes nothing and it is deliberately not glanceable — the numbers are still entirely trusted, and pretending to distinguish 30-second-old from 4-minute-old data would be false precision on a gauge whose own read precision is four percentage points. This is the mildest possible degradation signal: present if you look, invisible if you do not care.
- `data-aging` — 5h 51%, 7d 46%, 3 agents, the reading is 22 minutes old — polling has broken. Three structural changes, no dimming: the lid has descended and thickened to 1.6 pt and now presses on the mass; the mass's leading edge has FEATHERED over a 3 pt ramp, because the app will no longer assert exactly where the front is; and the load line has gone DASHED, because knowledge of it is no longer continuous. The projection wedge is suppressed outright — you cannot forecast from data you do not have. Everything degrades by changing shape, never by changing tone, so none of it can be washed out by a bright wallpaper.
- `stale-data` — The last successful read was over an hour ago. The shutter is SHUT: a wall-to-wall 1.2 pt bar floating at mid-height inside a vessel that holds nothing. There is no quota on screen to be misread as current — the requirement is met by geometry, not by a rule someone has to remember. It is drawn at full weight, not ghosted, because 'you are flying blind' deserves a full-strength mark and because a 45% ghost over a bright wallpaper is indistinguishable from 'I cannot find the icon'. A real reading always stands on the floor and always stops short of both walls; this bar does neither, so the two can never be confused.
- `unknown-data` — No reading has ever succeeded this launch: first run, failed auth, account mismatch or a parse error. The vessel itself dashes out and fades to 55%, and the interior holds a single short centred dash — the universal 'no value' in a frame that is visibly not intact. It cannot be confused with 0% on both windows, because 0% still draws a solid vessel, a 1.5 pt stub on the floor and a load line at the far left. Empty plus broken frame plus dash mark means the app has nothing to tell you, which is a different fact from having nothing to report.
- `agents-unknown` — 5h 46%, 7d 52%, quota live and healthy, but the local session scan failed so the agent count cannot be determined. The mass is drawn HOLLOW — a 0.9 pt open frame at a neutral 5 pt height — because its height is the dimension that is not measured. The width and the load line are untouched and still fully trustworthy, so the glyph degrades exactly one channel instead of the whole reading. needs-input is deliberately not asserted in this condition: the app never invents an alarm out of a failed read.
- `needs-input-while-stale` — The precedence edge case, and the one place the two dominant rules collide. needs-input is read from local session state, so it stays current even when the quota endpoint has gone dark. The deadline wins: the purple slab and the chevron run normally. But the quota underlay is replaced by the shut shutter in white at 24%, so the glyph screams about the prompt without inventing a number. The stale shutter is recognisably the same mark it is in the monochrome stale face, carried through the inversion.
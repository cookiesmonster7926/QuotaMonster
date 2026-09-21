# Round 3 — 選單列重做 + 面板合併

> 互動比較頁（含 CSS 循環動畫）：https://claude.ai/artifact/3aSZB7AvHpPWrF575WYhTC
> mockup 原始碼：`menubar-mockups/*.html`、`panel-mockups/merge-*.html`

## 使用者的需求（原話）

選單列圖示要整合：現在有在用嗎 · 5hr and 7day 的用量狀態 · 是否有需要輸入的（透過不同的形式顯示，像是變色、提醒圖示變幻等等）· 有 agent 完成了嗎。

拆成四個訊號、三種性質：

| 性質 | 訊號 | 難點 |
|---|---|---|
| 持續狀態 | 5h / 7d 用量 | 慢、要精確 |
| 即時活動 | 在不在跑、跑多兇 | **上一輪 15 個變體全部沒編碼這個** |
| 緊急持續狀態 | 有人在等你 | 要撐過習慣化 |
| 瞬時事件 | 剛剛有 agent 完成 | 是「瞬間」不是「狀態」，要自己衰減 |

## 選單列評分（滿分 80）

| 方向 | 總分 | 訊號設計評審 | 工藝評審 |
|---|---|---|---|
| 離散細胞場（Kerf, 72pt） | 61 | 第 1 | 第 2 |
| 生物行為（The Grazer — a creature whose , 62pt） | 57 | 第 2 | 第 4 |
| 純字體（THE READOUT, 78pt） | 54 | 第 3 | 第 3 |
| 借用既有語言（Drawdown, 72pt） | 54 | 第 5 | 第 1 |
| 雙窗口幾何（CHANNEL, 76pt） | 47 | 第 4 | 第 5 |

> **兩位評審結論相反。** 訊號設計把 segment 排第一、signal 排最後；工藝評審完全倒過來，並對 signal 寫下「這是唯一一個我真的會放進選單列的」。沒有共識 → 由使用者選。

### 離散細胞場 — Kerf（61/80）

**主張：** The icon is a strip of material being cut: the material is your quota, the saw teeth standing on it are the agents running right now, and every other signal is something that happens to that one object rather than a badge bolted beside it.

**整合方式：** Five channels on one field, 72x22pt. (1) THE SPINE fills from the left and is always the binding window — whichever of 5H/7D will bite first; the 2-char tag names it and the digits are its number, so no percentage is ever unlabelled. (2) THE SHELF is a 2.3pt foot filling from the far end: the non-binding window, subordinate by construction. When 7D becomes binding the two SWAP ROLES (spine becomes 7D, shelf becomes 5H, tag flips) instead of both shouting — one field, one meaning at a time. (3) THE RESERVED ZONE is the load-bearing integration and the answer to "can activity and quota share one form": it is burn_rate x time_to_reset, drawn from the frontier into the open corridor. Activity IS the rate at which quota is consumed, so the agents' cost is drawn in quota units inside the quota field. Ten agents make it long; zero agents make it vanish. Quota and activity are not two gauges, they are cause and effect of one length. (4) THE CARRIAGE, a 2pt block straddling the bar at the frontier, is presence/absence of work — it is the head of the saw, so the mark for "working" belongs where the cutting happens and nowhere else. (5) THE CREST, one tooth per agent, stands on the material about to be cut. Exhaustion-before-reset is not a new mark: it is the reserved zone CLAMPING at the wall, which lights a 3pt inward chevron. Staleness is a property of the drawing (dashed frame + 48% opacity), so it costs no channel at all.

**活動編碼：** Two levels, both at the frontier. Level 1, is-it-working: the carriage — a 2pt full-height block straddling the corridor at the consumption frontier. Present iff any session is busy; absent at idle. A session busy with zero subagents is carriage-with-no-crest, which is a distinct and meaningful state. Level 2, how-hard: the crest of discrete teeth, one per running agent, 2x5.3pt each, anchored at the frontier and growing into the open corridor. A three-tier legibility ladder matched to the perceptual facts: 1-4 agents at 3.4pt pitch (countable pre-attentively, you read the number without counting); 5-9 at 2.9pt (still discrete, reads as "a handful"); 10+ at 2.2pt where the teeth touch and the crest steps 1pt taller (no longer countable, reads as density). Marks clamp at ten, so 12, 15 and 40 all render as the same saturated comb and the field can never overflow — the exact count lives in the popover. Above ~80% spent there is no room ahead of the frontier, so the crest clamps back over the already-cut material rather than overrunning the wall. Intensity also reaches the quota channel automatically: more agents means more burn means a longer reserved zone, so the two marks move together without being redundant (one counts, one costs).

**瞬時完成訊號：** A completion is a cell extinguishing — the transient falls out of the structure instead of being bolted on, because the thing that announces it is the removal of a mark that was already there. Sequence: the finishing tooth flares to 1.42x for 120ms, collapses to zero height over 380ms, and leaves a 1pt KERF MARK sitting in its slot on the bar's top edge. The mark decays linearly to nothing over 6s, and — critically — the crest does NOT re-pack until the mark has fully decayed. The gap in the comb is the receipt, and its lifetime is the decay window; re-pack is a single 300ms slide gated on decay completion, never a periodic motion. The two seconds after a fan-out of seven drains to zero: the seven teeth collapse right-to-left with a 60ms stagger (a ~400ms cascade you can read the direction of), leaving seven ticks standing over an empty bar. At t+0.8s you glance up and see a comb of fading ticks and no crest — "seven things just finished here, nothing is running now". The carriage stays lit if the session is still alive. By t+6.4s the ticks are gone and the icon is back to the clean two-tone rectangle. Under reduced motion the tooth is replaced by its tick instantly and the tick steps down in three opacity stages — no information is lost, only the flare.

**緊急狀態：** Needs-input is a change of STATE of the whole object, not an added badge, and the primary carrier is silhouette rather than colour. The teeth RETRACT INTO the caret over 300ms — the thing that was cutting now points at you, which is a transformation of a mark already present. Simultaneously the corridor interior closes under a 45-degree hold hatch, so the material is visibly clamped. Quota stays readable through the hatch, justified by the fact that nothing is burning while you are the bottleneck. Three redundant carriers: silhouette (a crest of small teeth becomes one large arrow), texture (hatch), colour (a warm ember, deliberately not the amber of the fifteen rejected variants, and the ONLY colour anywhere in the design — the gallery includes a monochrome proof showing the state is still unambiguous with the accent stripped to ink). Habituation is defeated by escalating with MASS, not motion. Tier 1, under 60s: caret at 1.0, three 500ms knocks on entry and then motion stops permanently and never restarts — if you missed the knock the static morph is still sitting there. Tier 2, past 60s: the caret grows 22% in a one-way 380ms step and a hold rule appears under the entire icon, including the digits, so the whole object reads as held. Both tiers are static end states. Multiple blocked sessions render as one caret each up to three (cap acknowledged as a weakness given four concurrent sessions). Unblock is a single 350ms collapse and the teeth spring back.

**動作預算：** Nothing loops; every animation is triggered by a real event and terminates. Tooth strike (spawn): 260ms, overshoot 1.18 then settle to 1.0, one-shot, ends. Tooth flare + collapse (completion): 120ms + 380ms, one-shot, ends at zero height. Kerf-mark decay: 6s linear to zero opacity (compressed to 3s in the 20s demo loop), then the element is gone; never repeats. Crest re-pack: 300ms, fires once and only after the kerf mark has fully decayed — gated, not periodic. Block morph: 300ms one-shot on entering needs-input, ends in the static held state. Needs-input knock: 3 x 500ms = 1.5s total, exactly three cycles and then it stops forever; it never restarts, not on a timer and not on escalation. Tier-2 escalation: 380ms once at 60s, a one-way growth into a new static state. Unblock: 350ms one-shot. Reserved zone: eased ~400ms per update, roughly one update per agent spawn or exit — data, not a loop. Frontier advance: 0.5pt/minute at a 92%/h burn, continuous but below the perception threshold and deliberately not dramatised (which is why the demo loop holds the frontier still and moves the reserved zone instead — that is the honest depiction). Under prefers-reduced-motion all transforms are suspended: teeth appear and disappear without flare or collapse, kerf marks step opacity instead of decaying smoothly, and needs-input enters directly at tier 2 with no knocks. Count, completion, urgency and staleness are all still carried by static differences in the mark.

**評審必修：**
- (訊號設計, 34/40) Fix the >80% case — the crest leaving the frontier breaks 'the saw is where the cutting is' exactly when quota is tightest, which for this user is routine, not rare — and raise the blocked-caret cap from 3 to at least 4.
- (工藝與原生度, 27/40) The 6.4px / 0.5-opacity tag is the ONLY thing naming which window the big digits belong to, and it will not render — at 1x it is mush, at 2x it is marginal, and the whole spine/shelf role-swap collapses without it. Either raise the tag to 9pt minimum and delete a different part to pay for it, or abandon the swap and hard-assign the spine to 5H. Second: the reserved zone is the best merge anyone found here (burn x time-to-reset drawn in quota units, inside the quota field, clamping at the wall to produce the warning) — it needs the 90s smoothing and the 20-minute chevron deadband you already identified, or it will twitch and habituate.

**自陳缺點：**
- Only one window carries a number at a time. You read the binding window exactly and know the other is not worse, but you cannot read '7D 18%' off the bar without opening the popover. A deliberate trade against the rejected two-lines-of-digits variant, and still a real loss.
- 72pt is on the wide side — Stats' CPU module with a chart is 40-60pt. Well under the ~216pt cliff and fixed-width, but a user with twenty menu-bar items pays for it. A 46pt digits-off mode (tag + corridor only) should be a preference; it keeps every signal except the exact percentage.
- The crest clamps back over already-cut material above ~80% spent, so the teeth no longer sit exactly on the frontier. It stays legible and countable, but the 'the saw is where the cutting is' story breaks down precisely when quota is tightest.
- The reserved zone is a projection, and projections lie. A 92%/h instantaneous burn extrapolated over 2h12m is aggressive; a fan-out that ends in 40 seconds makes the zone briefly wrong. It needs smoothing over ~90s of burn history, and the chevron should require the shortfall to exceed 20 minutes before it lights or it will habituate.
- Teeth above ten are a lie by omission: 12, 15 and 40 all render as the same saturated comb. That is the correct pre-attentive answer ('a lot') but it means the icon cannot distinguish a healthy fan-out from a runaway one. The popover must.
- At 2.2pt pitch the 10+ crest needs a Retina display. On a 1x external monitor it degrades to a grey smear — still readable as density, no longer readable as discrete marks. The 1-9 tiers are safe at 1x.
- Three carets is the ceiling for blocked sessions; four or more render identically to three. With four concurrent sessions that ceiling sits exactly at the edge of this user's real workload.
- The hold hatch reduces quota contrast while blocked. Still readable, but measurably worse, and justified only by the claim that quota is not the actionable signal in that moment.
- The icon has one more part than the rejected variants did (tag, digits, spine, shelf, reserved zone, chevron, carriage, crest, kerf marks). Most are mutually exclusive or subtle, but it is a dense object and it does require one explanation before it reads fluently.

### 生物行為 — The Grazer — a creature whose behaviour is the readout（57/80）

**主張：** A single 62pt side-view animal that fills up with the 5-hour window it has eaten, stands on the ground that is what's left of the 7-day window, raises one quill per running agent, sheds a quill when an agent finishes, and turns its whole body to face you when a human is blocking work.

**整合方式：** Four signals, four different physical properties of one body, and two of them honestly share a channel. (1) The quills on the back are the agent count — the RATE. (2) The pale ghost running ahead of the solid body fill is where the 5-hour window lands one hour from now at the current burn — the INTEGRAL of that rate. Rate and integral drawn on the same body is the honest version of "activity and quota share one form", and they are kept as two marks rather than one because ten cheap agents can burn less than two Opus sessions with fat contexts, so agent count is genuinely not burn rate. (3) The 7-day window is not a second gauge but the GROUND: a full-length hairline for the week's extent, with the heavy portion being what remains. When the week becomes the binding constraint the ground ends early with a visible cliff tooth, the creature's front foot overhangs nothing, and it crouches to conserve — pure shape, no colour. (4) Completion is not a new mark: the agent's own quill flicks, detaches and rises away. (5) Urgency is not an added badge: the side view becomes a front view. The silhouette changes category, which is the loudest thing a 22pt mark can do without moving or shouting. The 5h fill and the 7d ground both survive the morph, so the urgent state takes the whole object without blanking the other channels. Precedence is one rule — blocked beats everything — and every other combination composes freely because no two signals touch the same property. Colour is spent on exactly one condition: the eye, amber, only when a human is blocking. Under 5pt² of amber in the entire design. High quota is carried by weight (a nearly solid body), overrun by three ticks past the snout, staleness by a dashed outline. Nothing else is ever allowed to go amber — a deliberate rejection of the fifteen previous variants, all of which signalled "blocked" by ambering the whole object.

**活動編碼：** Quills rising from the dorsal ridge, one per running agent, quantized so small fluctuations don't re-animate: 1–6 agents map 1:1 to six quill slots; 7–9 shows six at medium height; 10+ shows six grown 60% taller, sheared forward 11°, with the spine arched — visibly bristling. Zero agents means a completely smooth back and a closed eye-slit, which is unmistakably "nothing is happening". The eye opening is the binary "is it working right now". Intensity has a second, independent readout: the pale projection ghost, whose length is the burn rate expressed as "where the 5h window will be in one hour". At idle the ghost sits exactly on the solid fill and is invisible; at 1 agent it opens a small gap; at 92%/h it pins at the snout and spills past it as 1–3 severity ticks. In the real data (28% used, 92%/h, exhaustion 1h25m before reset) all three ticks are lit — the creature is eating past its own nose. That warning fires from shape alone; it costs no colour and no motion.

**瞬時完成訊號：** An agent finishing transforms a mark that is already on the icon rather than adding one. Its quill flicks up 14% over 120ms (detach), then rises 5.2pt while fading to zero over the next 580ms. Total 700ms, then nothing is left. The spine re-spaces over 180ms. A fan-out of seven draining to zero therefore reads as a brief flurry of quills leaving on a stagger, a single 260ms body settle when the count reaches zero, the eye slitting shut, and then absolute stillness — the stillness IS the completion signal. The design point: the transient announces a change in a state that remains readable afterwards. If you miss the moment, you still see fewer quills, or a closed eye, and the fill has stopped advancing. The moment is the derivative of a state you can still read, which is why a transient can live in a persistent icon without leaving residue. Under prefers-reduced-motion the equivalent loses nothing: the finished quill stays exactly where it is and goes dashed at 50% opacity for 2.0s, then is removed. Same mark, transformed, no movement.

**緊急狀態：** The whole object changes state rather than gaining a badge. Over 220ms the side view compresses to 66% and the front view expands in — the creature turns and looks at you. The silhouette changes category, from a profile with a spine to a symmetrical front-on mound with spines fanned around the crown and an eye in the middle. The eye is the only amber in the app: an ink ring with an amber core, reading as an aperture rather than a face. The numeral swaps from percent-used to the oldest wait time. Multiplicity is the same mark multiplied, not a new mark: one blocked session is one lens, two is a pair, three or more is a triangle of three — the monster grows an eye per blocked session. Habituation defence is a slowly-changing static form rather than a repeating twitch: the wait number keeps growing (2m → 12m → 41m), the creature leans 1pt toward the clock as the wait lengthens, and the eyes blink once every 60s for 160ms with a HARD STOP at 10 minutes. After that it is completely still and the growing number carries it. Under reduced motion the turn is instant and the blink is dropped; nothing is lost because the lean and the number were doing the escalation anyway. Honest note: one blocked session — the common case, and the real data — deliberately gets the least face-like treatment.

**動作預算：** quill raise: 160ms ease-out, 40ms stagger, on agent start, terminates. quill release: 700ms (120ms detach flick + 580ms rise & fade), on agent finish, terminates. spine re-space: 180ms after any quill-count change, terminates. settle: 260ms squash-release, once, only when the agent count reaches zero, terminates. turn to face: 220ms, once per block event, terminates. turn back: 200ms, once when the block clears, terminates. blink: 160ms, once per 60s while blocked, HARD STOP at 10 minutes — the only animation on a clock, and it has a cap. fill / ghost: 400ms ease, only on a change of ≥1%, terminates. Total idle motion: zero. There is no animation whose trigger is "time passed" except the capped blink, so a quiet machine gives a completely still menu bar. Every animation is event-triggered and every one has a termination rule. Under prefers-reduced-motion all of it is disabled and each signal has a static equivalent that loses no information.

**評審必修：**
- (訊號設計, 33/40) Prove the front-view silhouette is distinguishable from the side view at 22pt over a translucent wallpaper before the entire urgent design rests on it, and delete the two-eye state rather than offsetting it.
- (工藝與原生度, 24/40) You cited Stats and UTUVO Orbit and then drew a mascot. Kill the front-view face outright — the two-eye state at 22pt is a smiley, and offsetting the pair vertically does not fix a face, it fixes a symmetry. Second, and fatal as drawn: the ghost is 0.19 opacity and the reference ground is 0.20. Over an arbitrary translucent wallpaper those are not dim channels, they are absent ones — which means the burn-rate projection, your headline integration, is the least visible thing on the icon. Every channel sits at 0.40 ink or it is not a channel. The quill/detach transient is genuinely the best transient in the set and deserves to be transplanted onto a geometric mark.

**自陳缺點：**
- The two-eye state (exactly 2 blocked sessions) is the closest thing here to cute — two round eyes facing you at 22pt sits one step from a smiley. The common case of one blocked session is deliberately a single lens, which reads as an aperture, and three eyes is unsettling rather than sweet; it is only the middle rung that wobbles. The fix is to offset the pair vertically so it stops being symmetrical.
- The 7-day window gets the least resolution of the four signals. You can see the ground shortening over a week and you can see when it binds, but you cannot read 18% off it. Deliberate — the week is almost never the question — but a real cost; the number lives in the popover.
- The 5h fill is coarse: 28% and 34% look identical. The numeral is doing all the precision work; the shape only serves the peripheral glance.
- The numeral changes what it reports in exactly one state — percent used normally, oldest wait time while blocked. Justified by how different the creature looks in that state, but it is a genuine ambiguity for anyone who glances only at the digits.
- Quills saturate at six, so twelve agents and eight agents both read 'bristling'. Beyond six concurrent agents the difference is arguably not actionable from a menu bar, but it is information thrown away.
- The projection ghost encodes a one-hour horizon, which is an arbitrary constant. It separates 10%/h from 92%/h cleanly on this data, but it would need re-tuning if typical burn rates shifted.
- During a block the ghost/overrun readout is present but competes with the amber eye for attention in a very small area; in practice the burn-rate nuance is likely lost while blocked.

### 純字體 — THE READOUT（54/80）

**主張：** It is a single line of instrument type — cursor, figure, index — where the cursor is a terminal caret whose height is the live agent load, the figure is whichever quota window is actually binding, and the index is the other window named by one letter; there is no icon beside the number because the number, its cursor and its index ARE the icon.

**整合方式：** Three honest merges, plus one deliberate non-merge.

(1) ACTIVITY AND 5-HOUR QUOTA SHARE THE TENTHS DIGIT. Burn rate is, physically, agents × time — so the rate at which the tenths digit of the quota figure substitutes IS the activity level. At 92%/h the tenths ticks every 3.9s; at one agent (~13%/h) every 28s; at idle it is frozen. No separate activity mark exists because activity is already visible as the speed of a digit that has to be on screen anyway. This is the merge the previous fifteen rounds never found.

(2) THE TWO QUOTA WINDOWS SHARE ONE FIGURE SLOT BY BINDING PRECEDENCE. The large figure is always the window that actually constrains you; the 8.5pt index is always the runner-up, prefixed with its letter (D18 = 7-day at 18%, H12 = 5-hour at 12%). Because the index is *named*, one glyph identifies both numbers. When 7-day becomes binding they swap seats and the letter flips D→H. This is not the rejected "two stacked tiny lines": one figure is 12.5pt and primary, one is 8.5pt and subordinate, and which is which is itself the signal.

(3) THE COMPLETION EVENT AND THE ACTIVITY MARK SHARE THE CURSOR. An agent finishing is not a new mark — it is the existing cursor thickening for 180ms while it steps down one unit. The announcement and the information are the same gesture.

(4) DELIBERATELY NOT MERGED: colour. Quota pressure is weight (500→700). Burn crisis is a unit change plus a ledger rule. Both stay monochrome so that amber and red mean exactly one thing — a human is blocking work. Colour is spent once.

**活動編碼：** Two coupled channels, one instantaneous and one confirming.

INSTANTANEOUS: the leading cursor. At rest it is an underscore (5pt wide, 1.5pt tall) on the baseline — the terminal's idle caret. When work starts it becomes a 3pt block whose height is the concurrent agent count: 1→3.5pt, 2→5pt, 3→6.5pt, 5→8pt, 7→9.5pt, 10+→11.5pt, which deliberately overshoots the 8.7pt cap height of the digits beside it so a full fan-out is taller than any glyph in the item. It saturates at 10+ because 10 and 14 agents are the same fact. Height is read in one glance without counting.

CONFIRMING: the tenths digit of the figure, ticking at the true burn rate (0.1% per 3.9s at 92%/h). It is not decoration — it is the actual number changing because the actual quota is being spent. Watch it for four seconds and you know whether the machine is earning or coasting.

Idle is therefore doubly coded: the cursor is an underscore AND the digit is frozen. Nothing on the object moves when nothing is happening.

**瞬時完成訊號：** The design problem is that a moment cannot be a state, so the completion is built as a transformation of a mark already present, with an automatic decay to the mark's resting value.

At the instant an agent finishes, three things happen in one beat: the cursor's height steps down one unit (instant substitution, 0ms — the object never slides), the cursor thickens from 3pt to the full 5pt column for 180ms, and its ink jumps to 100% and then eases back to its resting 72% over 700ms. The thickening is the "look now"; the step-down is the information; the ink decay is the automatic forgetting. No badge appears, nothing is added, and after 700ms the object is indistinguishable from an object that never flashed.

THE TWO SECONDS AFTER A SEVEN-AGENT FAN-OUT DRAINS. Because the flash decay is 700ms and rapid completions re-trigger it, a burst of finishes never fully decays between hits — the cursor simply stays lit and visibly deflates, 7→6→5→4→3→2→1, reading as one continuous event rather than seven unrelated blips. That is correct: a fan-out draining is one thing happening, not seven. On the last completion the cursor reaches zero, is replaced by the underscore, and a single 900ms ease takes the ink from 100% down to the idle 50%. That is the settle. Total elapsed from last agent to fully at rest: 900ms. Nothing is queued behind it, nothing repeats, and the terminal state of every completion animation is by construction the idle state — which is the termination rule made structural rather than enforced.

Under reduced motion the thicken becomes a discrete 180ms substitution and the decay becomes a 700ms full-ink hold that then steps back. It is still a transient; it just has no ramp.

**緊急狀態：** The whole object changes state rather than gaining a badge: THE READOUT STOPS BEING A NUMBER. The cursor and figure are replaced by a 49×15pt slab with knocked-out figures, and what the figures now read is not quota at all — it is how long the session has been waiting for you. The quota number is gone because when a human is the bottleneck the quota number is not the relevant fact.

Two things fight habituation, neither of them brightness.

First, THE SIGNAL GROWS BECAUSE YOU IGNORED IT. The wait clock counts up: 0m, 2m, 7m, 23m. A user who sees this icon four hundred times a week cannot habituate to it because it is never the same stimulus twice — its magnitude is a direct function of their own neglect.

Second, ESCALATION BY TYPOGRAPHIC FORM, IN DISCRETE STEPS TIED TO REAL ELAPSED TIME. Under 1 minute: outlined slab, amber rule, amber figures — quiet, ignorable, because a 40-second prompt does not deserve an alarm. 1–5 minutes: solid amber fill, dark ink knocked out, figures bold. Past 5 minutes: the polarity inverts — red ground with light knockout. The dark-on-amber / light-on-red flip means the pairing itself changes, not just its intensity. On each minute boundary crossed, one 250ms brightness knock fires — a one-shot, once per sixty seconds, a 0.4% duty cycle, never a loop.

The stalled agent is still drawn, knocked out, inside the slab at its correct height: work is parked, not gone. When several sessions are blocked, the index slot — which always holds "the runner-up fact" — switches from the other quota window to the count (×2), reusing an existing slot instead of adding a mark. The clock shows the oldest wait. On answer, the slab retracts in 300ms and the figure returns.

**動作預算：** Fixed 78pt in every state; the item never resizes, so neighbours never jump. Complete inventory:

1. CURSOR HEIGHT STEP (agent count changes) — 0ms, instant glyph substitution. The cursor never slides. Terminates immediately by definition.
2. COMPLETION THICKEN — 3pt→5pt→3pt, 180ms, steps(1,end), one-shot per finished agent.
3. COMPLETION INK DECAY — 100%→72%, 700ms ease-out, one-shot. A new completion restarts it; with nothing to restart it, it reaches rest and stops.
4. DRAIN SETTLE — 100%→50% ink on the rest mark, 900ms ease-out, one-shot, fires only on the N→0 transition.
5. TENTHS TICK — 0ms, instant digit substitution, fired by the real burn rate (≈1 per 3.9s at 92%/h, ≈1 per 28s at one agent). Stops entirely at idle. Terminates because it is event-driven, not a loop.
6. RANGE CHANGE (28.4% ↔ 47m) — 200ms crossfade, one-shot, gated by hysteresis: 60s sustained over-projection to enter, 120s under to leave, so it cannot flutter.
7. BLOCK MORPH IN — slab scaleX .15→1 plus figure fade, 260ms, one-shot.
8. MINUTE KNOCK — brightness 1→1.5→1, 250ms ease-out, one-shot, at most once per 60s while blocked.
9. BLOCK MORPH OUT — 300ms, one-shot, on answer.

There is no infinite animation anywhere. When nothing is happening the object is a static piece of type: underscore, frozen figure, index. The termination rule is structural rather than policed — every animation's end value is the object's resting value, so the object cannot come to rest in a state that is still shouting.

REDUCED MOTION: 2 becomes a discrete substitution, 3 and 4 become discrete holds at full ink then a step back, 6/7/8/9 become instant steps. No information is lost because every signal lives in which glyph is showing — cursor height, figure, unit, weight, index letter, slab state — and the transitions only ever said "look now".

**評審必修：**
- (訊號設計, 28/40) The activity channel cannot rest on a digit that ticks once per 28 seconds — either give the cursor a second dimension so it stops reading as a bar chart of a number, or concede this is a gauge and a number and redesign the merge.
- (工藝與原生度, 26/40) The ticking tenths digit is a permanently-mutating status item under exactly this user's load — a 4-session, 10-subagent evening means a glyph changing every 3.9 seconds, forever. That is the 'always moving' failure wearing a data costume, and the fact that it is real data does not exempt it. Freeze the figure to whole percent; let the cursor height carry rate. Second: the readout changes what quantity it reports in TWO independent ways (crisis 28.4% -> 47m, blocked -> wait clock), so the digits have three possible referents. Pick one. Third: the 8.5px index at 46% opacity on a translucent bar is not a mark, it is a smudge.

**自陳缺點：**
- The tenths tick is a slow channel. At one agent it fires once every 28 seconds, so 'is it working, roughly how hard' from the digit alone needs 5-30 seconds of watching. The cursor height carries the instantaneous read and the tick only confirms it — but if a user never learns to read the cursor height, the activity channel effectively degrades to a binary underscore-vs-block.
- D18 / H12 is cryptic on first encounter. A new user has to be told once that the index letter names the OTHER window. The popover must teach it, and a user who never opens the popover will read the small figure as decoration. I accepted this because naming both windows in full would cost width the bar does not have.
- The range change (28.4% -> 47m) is the best idea here and also the riskiest: the readout silently changes what quantity it reports. Hysteresis stops it fluttering, but a user glancing at '47' without registering the 'm' could read it as a percentage. The bold weight and the ledger rule are the only distinguishers besides the unit glyph itself.
- Burn crisis — the warning the brief says matters most — is deliberately monochrome, because amber is reserved for blocked. A reasonable person could argue that 47 minutes to exhaustion deserves colour more than a 40-second permission prompt does, and that I have spent my one colour on the wrong signal.
- Cursor height saturates at 10+, so a 10-agent and a 24-agent fan-out are visually identical. That is intentional but it does throw away information a heavy fan-out user might want.
- The blocked slab covers the quota figure entirely. For as long as a session is blocked — which can be many minutes — the user has no quota reading at all without opening the popover. The trade is deliberate (one object, one message) but it is a real loss.
- Everything depends on tabular monospace numerals rendering correctly at 12.5pt on a 22pt content box. On a Retina display with SF Mono this is crisp; the design has not been proven on a non-Retina external monitor, where a 3pt-wide cursor and a 1pt ledger rule may both soften badly.
- A rapid burst of completions keeps the cursor lit continuously, which I argue reads correctly as one event — but during a sustained ten-agent workflow with constant churn it could approximate a permanently bright cursor, which is close to the 'always moving' failure the brief forbids.

### 借用既有語言 — Drawdown（54/80）

**主張：** It is the battery everybody already reads, pointed at your quota — with the next half-hour of consumption drawn as a dimmed shadow inside the fill, so "how much is left" and "is it working right now" are literally the same mark.

**整合方式：** Four signals, three channels, and only one of them is new ink. (1) The 5-hour window IS the battery fill (solid = uncommitted, dim = committed, together = the true level) and the 7-day window is a 1pt tick on the same 0-100% "percent of allowance remaining" axis — same unit, so one axis is honest. (2) Live activity shares the fill's channel completely: the shadow is the portion of the fill that the current burn rate will consume in the next 30 minutes. Idle = no shadow; 1 agent = 3pt; 10 agents = 10pt. This is honest rather than decorative because activity is the derivative of quota — the shadow is not a second gauge, it is the same fill marked as already-spent. A stranger reads "this much is about to go" with no training. (3) The completion transient is a transformation of marks that already exist: the shadow retracts by that agent's share, a 2.4pt bite is cut at the front and closes, and a ghost hairline holds the old front position and fades. Nothing new appears, so nothing has to be dismissed. (4) Urgency is a state change of the whole object, not an addition to it: the cell inverts to a solid slab with the two levels cut through as slots. Colour is spent exactly once, on one red sliver at the empty wall meaning "you will exhaust this window before it resets" — the low-fuel lamp. Blocked uses no colour at all, which is what keeps the red meaningful.

**活動編碼：** The dimmed shadow at the leading edge of the fill: the next 30 minutes of consumption at the current burn rate, drawn to scale on the same axis as the level itself, with a 1pt full-height front line marking "where you will be in 30 minutes". Intensity is encoded as LENGTH, driven by burn rate rather than agent count (so ten cheap agents do not out-shout one expensive one — which is the honest reading, since the quota only knows spend). 1 agent ≈10%/h → 3pt (a floor, so "something is running" is never sub-pixel); 5 agents ≈48%/h → 7.4pt; 10+ agents at the real 92%/h → 10pt, nearly half the tank in half an hour. Critically this channel is STATIC — it steps between still states as agents come and go, rather than looping, so "busy for 12 minutes" does not mean "animating for 12 minutes". Presence/absence of the shadow is the entire idle-vs-working read and it survives at 22pt over any wallpaper because the front line is a hard edge.

**瞬時完成訊號：** An agent finishing is three simultaneous changes to marks that are already on screen, and no new mark: (a) a 2.4pt bite is cut clean through the fill at the front — a real transparent slit showing the wallpaper, held 140ms then closed over 280ms; (b) the shadow retracts by that agent's share of the burn over 260ms, and the fill edge steps left by what was actually consumed over 240ms; (c) a 0.9pt ghost hairline is left standing at the front's old position at 45% and fades to nothing over 1.1s. Total life: 1.4s, then gone without residue. The two seconds after a fan-out of seven drains to zero are the payoff: a rapid staircase as the shadow retracts 10pt → 8.2pt → 4.6pt → 0, the red lamp releasing as the runway recovers past the reset, one last ghost dissolving, and then a plain, completely still battery sitting at a visibly lower level. The event announces itself AND leaves a correct reading behind — the ghost is not decoration, it is a measurement of what that agent cost. Under reduced motion the fades become instant swaps and the ghost simply holds for 900ms and vanishes; no information is lost because every part of it is a position, not a movement.

**緊急狀態：** The whole object inverts. The stroked shell and its fill are replaced by a solid slab of the bar's own label colour with the same silhouette, and the two levels survive as slots cut through it (1.6pt at the 5-hour level, 1.1pt at the 7-day). A photographic negative is the largest change a 28x14pt monochrome mark can make, it is equally unmissable on a light bar, a dark bar and a translucent wallpaper, it needs no hue at all — which is what protects the one red the design does spend — and it is dead still, so it persists indefinitely without becoming wallpaper. At the real data the two slots land adjacent and read as a pause bar, which is exactly the semantic. Habituation is beaten by information, not by more motion: entry is a 220ms morph plus three 600ms pulses (never dimmer than 50%, so it reads as a pulse and not a fault) and then absolute stillness, while the number switches from runway to your wait time and keeps climbing — 0m, 2m, 12m. With more than one session blocked the field becomes count-plus-oldest ("2·9m"). Ignoring it makes the icon more specific, never twitchier. One further single 600ms pulse fires at the 5-minute threshold; that is the entire escalation budget.

**動作預算：** Nothing loops; every animation is one-shot, triggered by a state change, and terminates in a still frame. Level step on consumption 240ms ease-out. Shadow length change 260ms ease-out. Completion bite 140ms hold + 280ms close = 420ms. Ghost hairline 1.1s fade then removed. Red lamp ignition 3 pulses x 300ms = 900ms then steady; release 300ms fade. Blocked morph 220ms invert, then 3 pulses x 600ms = 1.8s, then absolutely still for however long it takes. Blocked 5-minute escalation: one 600ms pulse, and that is the entire escalation budget. Un-block 220ms revert. Longest continuous motion the icon can ever produce: 1.8s. Over a day of ~200 agent events that is roughly 80 seconds of movement in 24 hours, under 0.1% of wall-clock time. The mockup's 16s loop is ~55% motion only because it is a highlight reel; the ruler under it shades every moving interval against every still one so the ratio is auditable, and it states the compression (dwell ≈40x, transitions and decays at 1:1). prefers-reduced-motion converts every tween to steps(1,end): positions, lengths, the inversion and the lamp all still change, the pulses are dropped, and the ghost holds 900ms then vanishes. Every signal has a static encoding, so reduced motion costs only the speed of noticing, never the information.

**評審必修：**
- (訊號設計, 24/40) Stop being a battery, and encode agent count — the system battery is two icons away, the naive read of the solid/dim split is wrong about the headline number, and refusing the activity channel is refusing a quarter of the brief.
- (工藝與原生度, 30/40) Ship the tipless variant by DEFAULT — a second battery two icons from the system battery is a real confusion, not a footnote — and give agent count somewhere to live. The brief asked for '5 agents running' at the glance layer and you deliberately refused it; burn rate is the right INTENSITY channel but it is not the same question. A 3-state pip or a second numeral is cheap at 72pt. Also floor the 0.9pt ghost hairline to 1pt.

**自陳缺點：**
- It is a second battery in the menu bar. On a laptop the system battery sits two icons away and at a glance they can be confused. Mitigated by the attached number, the always-present 7-day tick, the shadow texture the system battery never has, and an optional tipless variant shown in the gallery — but I would want a week of real use before calling it solved.
- The solid/dim split means the naive 'how full is it' read lands on the UNCOMMITTED level, not the raw one. At 28% used with 92%/h burning, the solid portion is only ~26% of the tank although 72% remains. I argue uncommitted is the actionable figure, but a stranger will say 'nearly empty' and be wrong about the raw number.
- Two windows on one 0-100% axis is the part that must be learned rather than known. Percent-remaining is genuinely the same unit for both, so the axis is honest, but they reset on different clocks and the icon cannot show that. The 7-day mark stays a quiet tick until it becomes the binding wall and only then cuts the fill — progressive disclosure, still a convention.
- The number has two possible referents (projected exhaustion when the lamp is lit, reset when it is dark). The lamp disambiguates, but a user who hasn't registered the lamp can misread 47m as 'resets in 47 minutes'. A car's range readout has the same ambiguity; I would still user-test it.
- The 30-minute projection horizon is a tuned constant, not something the user asked for. Too short and 10 agents look like 1; too long and everything saturates against the wall. 30 minutes gives a clean 3 / 5.2 / 10pt spread at THIS user's rates — a lighter user's shadow would barely move.
- The red lamp fires whenever the projection exhausts before reset, which for a 4-session, 10-subagent user may be a large part of a working evening. I have framed it as a fuel lamp rather than an alarm, but if it is lit three hours a night it stops meaning anything; the honest fix is a threshold in the popover, not a second colour.
- Burn rate is noisy over short windows. The shadow steps whenever the estimate moves, so it needs real smoothing (60-90s trailing estimate plus a deadband) or the icon twitches between still states — which would violate the spirit of the no-permanent-motion rule even with nothing looping.
- Agent COUNT is not recoverable from the icon, only spend rate. 'Are 7 running or 2' requires the popover. I believe that is the right trade, but it is a deliberate refusal of one thing the brief asked for at the glance layer.

### 雙窗口幾何 — CHANNEL（47/80）

**主張：** A 76×22pt channel with a floor and a roof: the floor is a real plot of the 5-hour window's spend with a forecast fired off its leading edge, the roof is the 7-day window closing over it, and every other signal is a modulation of that one geometry rather than a badge beside it.

**整合方式：** Three channels carry four signals. (1) GEOMETRY carries both quota windows: the floor's height is 5-hour spend, the roof's hairline fill is 7-day spend with a pace tick at where the week should be by now, and the clear air between floor and roof is literally your remaining room. When the week actually becomes the binding constraint the roof descends out of the frame line into the plot and the forecast collides with the roof instead of the top — the week is drawn as the boundary condition it is, not as a second gauge. (2) THE LEADING EDGE carries live activity, and it can honestly share the quota mark because activity IS the derivative of quota: the forecast's slope is the burn rate, and the stack of cells sitting on the floor's leading edge is the crew currently pushing that slope. Agent count and burn rate are the same physical fact seen twice. (3) INK DENSITY carries confidence and urgency on one continuous axis: hollow = stale (I no longer trust this), normal = live, solid = a human is blocking work. Because these three channels are orthogonal in perception (position / texture / mass), all four signals can be read simultaneously without any of them stealing from another. The completion event is not a fourth channel at all — it is a transformation inside channel 2 into channel 1 (a cell is absorbed by the floor). Colour is spent exactly once, on the cut, and its rule is: colour means a human must act; ink and geometry mean machine state.

**活動編碼：** One cell per running agent, 3×1pt, stacked upward from the floor's top at NOW — countable at a glance for 1–7, and at 8+ it saturates into a solid column with a notch cut near the top meaning "more than fits". Intensity is read twice and redundantly: the cell count, and the angle of the dotted forecast leaving the leading edge, which is the actual burn rate (1 agent ≈ 24°, 5 agents ≈ 62°, 10+ ≈ 75°). Idle is not a special look you must learn — with nothing running there are no cells and the floor terminates in a flat cap with no forecast at all, because you cannot project from a zero burn. Liveness without permanent animation: every cell rise and every absorb is a discrete 280–320ms event, and while a fan-out is live those events arrive every few seconds, so the column naturally twitches when work is live and is dead still when it is not. Between events the real fill also advances about 1pt per 30s of heavy burn, which is data moving, not decoration.

**瞬時完成訊號：** The finished agent's own cell is the mark that transforms — nothing new appears. t+0ms: the top cell detaches and sinks 280ms into the floor. t+280ms: the floor steps up by exactly the quota that agent spent (real, permanent, and honestly sub-pixel for one agent), and a 180ms ripple runs outward along the floor's top edge and dies. t+280ms→2.3s: the new increment holds a bright top edge — the afterglow — so the graph briefly remembers where the last work landed; it then fades over 600ms and is gone. For a fan-out of seven draining to zero, that absorb repeats seven times about 500ms apart, the floor steps up seven times, and then the batch-complete signal fires ONCE and only on a drain to zero: a single 700ms bright bar tracing the NEW floor level left to right across the rest of the window and exiting at the reset edge. It is the floor's own level, drawn, not a new glyph. By t+2.4s after the last absorb the afterglow has decayed, the column is empty, the cap is back, and the icon is a perfectly still diagram whose only trace of the burst is that the floor is about 1pt higher than it was. Reduced motion: the sink and the ripple become an instant step, and the sweep becomes a static hairline at the new level shown for 2s — no information lost.

**緊急狀態：** The whole object changes state rather than gaining an addition. The floor swells upward over 220ms until it fills the entire channel — a solid 36×16pt mass — and the timeline is CUT: a 1.7pt gap opens at NOW with a single red hairline in it. That is a polarity flip, not a colour change: the icon's total ink roughly triples, which the peripheral visual system detects even when you have stopped looking, and it works identically as a white slab on a dark bar, a black slab on a light bar, and over any wallpaper. Nothing is lost: the floor, the roof and the week's fill boundary survive as knockouts punched through the mass, and the stalled agents appear as counted holes (1 blocked agent = 1 hole, 4 = 4). Multiple blocked sessions break the cut into that many dashes — three sessions, three dashes — so the count is in the mark that already exists. Habituation is answered by escalation rather than repetition: a 500ms rim flare at t=0, then the block grows a red wait tally along its bottom edge, one pixel per 15s, so the thing you habituated to at minute one is a visibly different shape at minute six; at 2, 6 and 15 minutes it fires a double-blink (not the same single blink again), and at full tally it gains a 1pt outline halo. The forecast is deliberately destroyed while blocked — you are the bottleneck, so the burn rate is meaningless. Clearing collapses the mass back down into the floor in 200ms and the diagram returns.

**動作預算：** agent starts: cell scales up from its own base, 320ms, terminates. agent finishes: cell detaches and sinks 280ms + ripple along the floor's top edge 180ms, terminates. afterglow: bright top edge on the new increment holds 2.0s then fades 600ms, terminates. fan-out drained to zero: one 700ms level-sweep left to right that exits the frame — fires once per drain, never on a single completion, terminates. dry zone first appears: hatch slides in from the reset edge 600ms — fires once per threshold crossing, not once per poll, terminates. block opens: 220ms swell + cut, terminates. block flare: 500ms rim at t=0, then a double blink at 2min / 6min / 15min — escalating, each instance terminates. block clears: 200ms collapse, terminates. Nothing else animates, ever. There is no idle loop, no pulse, no breathing: between discrete events the icon is a still diagram, which is exactly why the one moment that matters is still visible after four hundred sightings a week. TERMINATION RULE: every animation is triggered by a discrete state change in the data and has a fixed, bounded duration; none repeats while its trigger persists (the blocked flare re-fires only on a longer schedule with a different waveform, which is escalation, not looping). prefers-reduced-motion: all of the above become instantaneous state changes — the sink becomes a step, the sweep becomes a static hairline at the new level for 2s, the flares are dropped entirely; the state gallery is the complete static equivalent and loses no information.

**評審必修：**
- (訊號設計, 26/40) The roof and the floor cannot run different x-axes inside one 22pt frame — give the 7-day window a non-temporal encoding (a ceiling height, a boundary, a tick) or the mark is two gauges bolted vertically.
- (工藝與原生度, 21/40) 3 x 1pt agent cells and 0.75/0.8/0.85pt hairlines do not exist at 1x and barely exist at 2x — a stack of seven 1pt cells is a grey column, not a count. Floor every cell to 2pt and every stroke to 1pt, then re-measure whether seven still fit in 22pt; if they do not, the activity channel needs redesigning, not shrinking. Second: two time bases on one x-axis (floor = this 5h window, roof = the week) is not a seam you can teach away in a popover — it is the reading rule for the whole object. Third: you admit one agent's real floor step is sub-pixel, which means the ripple and the afterglow are decoration standing in for data. Fourth: a red tally growing 1px per 15s plus double-blinks at 2/6/15 minutes is a nagging clock, not escalation.

**自陳缺點：**
- The roof's horizontal axis is the week while the floor's is this 5-hour window — same footprint, two time bases. They rhyme (both fill left to right toward their own reset at the right edge) but it is a genuine seam, and it is the one thing the popover has to teach once.
- The 7-day number is never printed. The roof gives position to about ±1.5% and 'ahead of / behind pace' instantly, but the exact 18% lives only in the popover. The fix if that is unacceptable is 8pt more width, not a second number stacked under the first.
- A single real absorb moves the floor by a fraction of a point, so at 1× the geometry change from one finished agent is sub-pixel; the ripple and the afterglow are carrying the perception. Only a whole fan-out produces a floor step you can actually see on the bar.
- The blocked state destroys the forecast while it is up. That is deliberate — you are the bottleneck, so the burn rate is meaningless — but it does mean the quota reading degrades at exactly the moment you are staring at the icon.
- At 85%+ the agent cells have no room above the floor and knock downward into it instead. It works and it keeps the count in place, but it is a second reading rule for one rare case.
- The blocked state is a large solid slab, which is unmissable by design but is also the loudest thing in the menu bar; a user with a session blocked for an hour will find it genuinely aggressive. That is the intended trade, not an accident, but it is a trade.
- The floor is an area chart, and a heavy user whose window has been flat for four hours will see almost no floor at all — the icon leans hard on the roof, ground and reset rules for structure in that case.
- Counting cells past about five is a glance-and-estimate, not a read; the saturation notch at 10+ is a threshold, not a number.

## 面板合併評分（滿分 80）

| 方向 | 總分 |
|---|---|
| 釘住+捲動（Pinned Urgency, Scrolled Detail） | 60 |
| 加寬雙欄（Two-Column (雙欄額度)） | 56 |
| 摺疊展開（Progressive Panel — collapse by defa） | 56 |

### 釘住+捲動 — Pinned Urgency, Scrolled Detail（60/80）

**高度解法：** Measured in a real browser at 1pt = 1px, not estimated. Panel is exactly 400 × 620pt, a flex column where five bands are `flex:0 0 auto` and only the session list is `flex:1 1 auto; min-height:0` — so the scroll band absorbs whatever is left and the panel can never grow.

REAL BUDGET (measured, sums to 619 + 1pt of 0.5pt border top/bottom = 620):
  A  header (mark + 3-cell roll-up + 額度 QUOTA row + 3-cell quota row) .... 128.5pt
  B  quota cards (5-hour 131 + gap 4 + 7-day 88) ........................... 223.0pt
  C  工作階段 SESSIONS label + hairline ..................................... 22.3pt
  D  blocked card (f1-e3) ................................................... 95.0pt
  F  footer strip ........................................................... 25.0pt
  ------------------------------------------------ PINNED TOTAL 493.8pt (80%)
  E  session list scroll viewport ......................................... 125.2pt (20%)

The scroll viewport is 125pt against 246pt of list content — 51% visible, 4.2 rows at the 30pt row height. It is a window, not a slit, but it is genuinely the minority of the panel and I am not going to pretend otherwise. On a 13" MacBook (865pt below the bar) this leaves 245pt of headroom instead of the 9pt the 856pt version had.

HOW I GOT FROM 856 TO 620:
1. Structural, worth ~230pt: the session list stopped being laid out and started being clipped. Everything urgent (all three quota readouts, the burn warning, the blocked card) is above the clip; only non-blocked sessions and their agent subtrees scroll.
2. Metric, worth ~35pt: I first built at generous spacing and measured 85pt of scroll — the slit the brief predicted. I then took one pass of disciplined trims, all staying inside macOS norms: header figure 25→23pt, idrow 30→28, section rows 20→18, card padding 7→6, track margins 7/5→6/4, blocked card 103→95, footer 26→25, charts 36→34pt tall. That moved scroll from 85 → 125pt, a 47% gain in the only band that needed it.
3. Nothing was cut. Both quota cards keep identical anatomy (title + English subtitle + reset right / two colour-keyed readout rows / chart spanning both rows / progress bar / footline), the header keeps its full four-part rhythm in all three cells, and the workflow subtree keeps all four running agents as rows plus the done row plus the collapsed row.

SCROLL AFFORDANCE, SHOWN HONESTLY: the list is rendered already scrolled 12pt, so the `usage-97` parent row is visibly sliced by the top fade and `design:creature-motif` is sliced by the bottom fade. Both 13pt fades are drawn, and a 3pt macOS-style overlay scrollbar sits at right:3.5pt with its thumb at 5% / 53% — the true proportions for a 125pt window on a 246pt list at that scroll offset.

THE LEVER I DID NOT PULL, so you can: collapsing the 7-day card's two readout rows onto one line buys 14pt more scroll (125 → 139) at the cost of the card-to-card anatomical parallel that makes the quota block look authored. That is your call, not mine.

**圖表單位問題：** I did not label the two halves — I removed the second unit entirely, and got the visual weight back for free.

THE PROBLEM: the mirrored sparkline plotted cumulative % used above the baseline and instantaneous %/h below. Those are different quantities with different units, and mirroring them implies they are symmetric halves of one thing. The centre line meant nothing.

WHAT I CHOSE: one series, one unit — burn rate in %/h across the 5-hour window so far. The reason this is not a loss is that cumulative % used is the integral of burn rate, so it was never independent information: the area under this curve *is* the 28%. Showing the same fact twice on a mirrored axis was the actual dishonesty.

HOW THE WEIGHT SURVIVED: the mirrored version got its mass from having two filled zones divided by a line. I kept exactly that structure but made the divider mean something — the dotted rule sits at the window average, 10 %/h, labelled in-chart as `均速 10`, with a faint neutral band filling 0→10 underneath it. So you still read "a band, a line, a shape leaving the band", but now both zones are %/h and the line is a real reference value. The chart is titled in its own corner: `%/h · 燃燒率`.

WHAT THIS BUYS BEYOND HONESTY: the encoding now states the warning by itself. The first ~2h48m of samples sit inside the average band; the tail leaves it and climbs to 9× the rule, with a ringed dot on the current value. The shape of the chart and the sentence in the amber strip below it (`約 47 分鐘後用盡`) are now the same claim, which the mirrored version could never be, because half of it was cumulative and monotonic and therefore always went up regardless.

Cumulative 28% did not disappear — it moved to where a cumulative quantity belongs, the full-width progress bar directly beneath the chart, solid blue up to 28% with a neutral hatched remainder. Two facts, two marks, two units, no shared axis.

The 7-day chart got the same treatment for consistency: `%/日 · 近 7 天` labelled in-chart, one unit, stacked green with a purple Fable cap, and I rescaled the columns (max 4.0 %/day over 21pt) specifically so the unit label can never collide with the tallest column.

**琥珀預算：** Amber has one meaning in this panel: **act now — something is being spent or wasted while you read this.** Everything that is merely informative is neutral. The rule is state-driven, not category-driven, which is what stops it leaking.

AMBER IS ALLOWED IN EXACTLY TWO STORIES:

Story 1 — the burn is about to exhaust the window:
  · the `燃燒率 burn` swatch and its `92%/h` value
  · the burn-rate chart (stroke, area gradient, current-value dot)
  · the warning strip: amber 2.5pt left rail, amber border, amber text
  The governing rule: burn renders amber only because 92 %/h is >3× the 10 %/h window average. At normal burn this swatch, this chart and this value all render neutral and the strip does not exist. Amber is a state here, not a colour assignment for "burn".

Story 2 — a session is blocked on you:
  · the `1 BLOCKED` roll-up cell in the header (amber tint + amber hairline border)
  · the blocked card: 3pt left rail, amber border, amber tinted fill
  · `等待你回覆`, the elapsed `2m`, and the consequence line `1 個 agent 跟著停住`
  · the stalled agent's own duration bar inside that card
  · the menu-bar status item's 5pt blocked dot

EVERYTHING ELSE WAS DEMOTED TO NEUTRAL — this is the fix:
  · CTX pressure bars (34% / 12% / 61%) — grey `--neutral` fill on a grey track. These were competing for the same alarm channel and they are not alarms; 61% context is a fact, not a request.
  · the hatched remainder of the 5-hour progress bar — a neutral diagonal hatch (`--hatch` = white/black at .20 and .055), not amber hatching. The hatch now means "not yet spent", which is a texture, not a warning.
  · the 7-day pace marker at 34.5% — neutral 1.5pt tick.
  · status pills: IDLE neutral, BUSY blue. Status dots: blue / neutral grey.
  · the workflow pip meter: 3 green done, 4 blue running. No amber anywhere in the workflow.
  · the PERMISSION strip inside the blocked card is deliberately recessed and NEUTRAL (inset fill, grey hairline, grey `PERMISSION` label, white mono command). The card around it already carries the alarm; repeating amber inside it would have flattened the card's own hierarchy and made the command harder to read, which is the one string you actually have to parse before you answer.

Count on screen: 3 amber regions for the burn story, 5 for the blocked story, 0 elsewhere. Both stories reduce to the same instruction, so a glance that lands on amber anywhere is always the same glance.

Light material uses a darkened amber for text (`#9A5A00`) against a fill/rail amber (`#E08A00`) so the same hue survives on a pale translucent background without dropping below readable contrast; dark material uses `#FF9F0A` fill with `#FFB03A` text.

**評審必修：**
- (訊號設計, 31/40) 125pt of scroll against 246pt of content means you scroll past the blocked card's own siblings every single time — pull the 14pt lever you named and find a second 30pt; and give the permission strip a deny affordance before it ships against `git push --force`.
- (工藝與原生度, 29/40) You swapped the approved chart's composition for a different encoding. The dense screenshot's chart WAS cumulative rising to a 100% rule with a dashed projection intersecting at +47m and a reset marker at 03:40 — i.e. the warning drawn as a geometry. Your burn-rate-only chart is honest, but it demotes '47 minutes, 1h25m before reset' from a picture you can point at to a sentence in an amber strip, and it squashes 2h48m of history into the bottom 3pt so the early window is decorative. Transplant progressive's chart (cumulative, 100% rule, amber projection, exhaustion ring, 1h25m bracket) into this shell — it is both more faithful AND single-unit. Second: 125pt of scroll against 494pt pinned is 20%; take the 14pt you identified AND progressive's collapse on the 7-day card and get the list to ~180pt.

**自陳缺點：**
- The scroll region is 125pt of a 620pt panel — 20%. I measured it honestly and it is a real window (4.2 rows, 51% of the list), but the pinned region does eat 80% of the panel, and that is the structural cost of the merge angle you chose. If a session has a deep workflow subtree, as usage-97 does, you will scroll to see the second and third sessions every single time. The 14pt available from collapsing the 7-day card's readouts onto one row is the only lever left that does not break something you approved.
- The drawn scrollbar thumb is static. The scroll container really scrolls with the wheel, but the thumb I drew at 5%/53% will not move when you do, because no scripts are allowed. In the shipped AppKit version this is a real NSScroller and the problem disappears; in this mockup it is a lie that only shows up if you actually scroll.
- The 'partially scrolled' state is faked with margin-top:-12px on the inner list, not with a real scroll offset. The consequence is that the top 12pt of the usage-97 row cannot be scrolled back into view in the mockup — it is clipped, not scrolled past. Visually identical, structurally not the same thing.
- The two amber stories sit 40pt apart vertically — the burn warning strip at the bottom of the 5-hour card and the blocked card two bands below it. They read as one alarm zone, which is fine when both are firing, but I have not seen what it looks like when only the burn is firing and the blocked card is absent. The 7-day card and the sessions label row would then sit between the strip and nothing, and the amber may look orphaned.
- The 5-hour burn chart is 148 × 34pt and the values span 4 to 92 %/h linearly, so the entire first 2h48m of history compresses into the bottom 3pt of the chart. That squashing IS the message — the current burn is 9× the average — but it means the early history is decorative, not readable. If you ever want to read the shape of the early window you need a second view, not this chart.
- I moved the freshness string to the header and changed the footer's label to the action 重新整理. That is the correct de-duplication, but it means the footer's refresh glyph no longer tells you anything about age — if someone's eye goes to the bottom-left first, as it does in Stats, they now get a verb instead of a fact.
- The blocked card's keyboard chip reads ⌘↵ 允許. I did not design what the second shortcut is — there is no visible affordance for denying the permission, only for allowing it, which is a slightly dangerous default for a `git push --force` prompt.
- The light material is set to 64% opacity so vibrancy reads honestly on a wallpaper, but on a genuinely busy photo the 9.5pt tertiary text (paths, footlines, chart unit labels) will be the first thing to lose contrast. I only tested it against the synthetic gradient wallpaper in the mockup.
- The panel is 400pt wide, splitting the difference between the dense direction's 420 and the stats direction's 380. The 5-hour card's readout column plus the 152pt chart consume 358 of the 358pt available inside the card — there is exactly zero slack. A longer burn value (e.g. 100%/h) or a translated label would push the chart.
- The 'another 2 agents done' collapsed row and the one shown done agent (design:state-machine-kinetic) together reconcile the 3-done/4-running arithmetic, but that reconciliation is only obvious if you do the sum. The 3/7 pip meter is doing the real work; the collapsed row is nearly redundant and costs 17pt of the scarcest band on the panel.

### 加寬雙欄 — Two-Column (雙欄額度)（56/80）

**高度解法：** Measured in headless Chrome, not estimated. Final panel: **560.0 × 620.0pt exactly** (file: panel-mockups/twocol.html).

WHAT BOUGHT THE HEIGHT — width. The two quota cards sit side by side: 282pt (5-hour) + 12pt gutter + 234pt (7-day) = 528pt of content inside a 560pt panel. Stacking them the way the Stats direction did costs a second full card height; the card measures 155.3pt, so side-by-side returns ~165pt (card + gap) to the stack in one move. The cards are deliberately unequal: the 5-hour card is the one with two readouts, a 125pt split-axis chart and the amber warning, so it gets the extra 48pt; the 7-day card's chart is only 7 columns wide (75pt) and doesn't need it.

WHAT IS PINNED (measured, sums to 499pt):
  header 143.5 · quota block 174.3 · SESSIONS label 14 · blocked card 109 (+15 margin) · footer 32 · 3 hairlines.
WHAT SCROLLS: the session list. Viewport = 620 − 499 = **121pt**, content 260pt. The panel is `height:620px; display:flex; column`, every pinned block is `flex:0 0 auto`, the scroll wrapper is `flex:1 1 auto; min-height:0` — so the panel height is fixed by construction and the list absorbs everything, which is exactly the behaviour a fifth session needs.

WHAT WAS CUT OR COMPRESSED vs the 856pt version:
  · one whole card height removed by the side-by-side move;
  · the duplicate freshness string deleted from the footer (it now reads refresh glyph + 重新整理 + ⌘R chip), kept only in the header where it qualifies the numbers it describes;
  · row heights tightened to 30 (session) / 28 (workflow) / 24 (agent) / 22 (collapsed row) — still inside the 28–36pt band for the primary rows;
  · card internal padding 9×12, section paddings 9–10, big quota figure 27pt not 32;
  · the 7-day card's "same anatomy" slot holds a single-line neutral pace note instead of a second warning block, which also stretches it to match the 5-hour card's height (both land at 155.3pt);
  · both alert strips live *inside* their cards, so the two cards are one grid row and nothing has to be vertically fudged.

SCROLL AFFORDANCE, SHOWN HONESTLY — two states, one per material:
  · DARK = resting state. A real `overflow-y:auto` scroller (you can wheel it), overlay scrollbar (width 0, no layout cost, like macOS), bottom 22pt mask-image fade. `design:max-density` is visibly cut and fading at the bottom edge.
  · LIGHT = partially scrolled. The same list frozen at scrollTop 118 of a 145pt range. Top row (`design:max-density`) is clipped mid-row, there are top *and* bottom fades, and a 3.5pt drawn thumb sits at top 54pt / height 51pt — computed from the measured 121/266 ratio, not eyeballed. The pinned blocks above have not moved a pixel between the two panels.
Masks are used for the fades rather than opaque gradient overlays, so the faded content dissolves into the vibrancy material instead of into a painted rectangle. `mask-image` is on a descendant of the `backdrop-filter` element, never an ancestor, and there is no `filter` property anywhere in the file (linted). Panel shadow is box-shadow only.

STILL A POPOVER, NOT A WINDOW: arrow notch at the top, aligned to the QuotaMonster status item's centre in the simulated 33pt menu bar (notch x=341 within the panel, item centre x=375 on the wallpaper); 12pt corner radius; NSVisualEffectView-style translucency with a 0.5pt rim; no title bar, no traffic lights, no resize affordance; portrait 0.90:1. A window at this size would be landscape and chrome-topped.

WIDTH ACTUALLY EARNS ITS KEEP IN THE AGENT ROWS: each agent row gets a 176pt duration bar on a shared 0–5m02s scale (83.4 / 75.5 / 69.9 / 57.9 / 100%), so you can rank the four running design agents by eye — at 380pt that bar would be ~60pt and useless. Session rows fit dot + id + full untruncated path + pill + elapsed + CTX bar + % on one line with ~110pt of slack, so `~/Antigravity/usage` never ellipsises.

**圖表單位問題：** I kept the mirrored silhouette the user liked and turned the fold into a **declared axis break** rather than deleting it or pretending it's one axis.

WHAT I BUILT: a single hairline axis at y=20.5 spans the chart. The upper band grows **up** from it — cumulative % of the 5-hour window consumed, self-scaled to its own max (28). The lower band grows **down** from it — instantaneous %/h, scaled 0–100. They share only the x-axis (time across the elapsed 2h48m). Nothing is mirrored about a common zero, because the two halves never claim a common scale.

THE THREE THINGS THAT MAKE IT UNMISREADABLE:
1. Each band carries its own unit label, in its own colour, in a left gutter inside the chart: blue `%` above the axis, amber `%/h` below it.
2. The band colours are the *same two swatch colours* as the readout rows immediately to the left — blue square 已使用 28%, amber square 燃燒率 92%/h. So the reader arrives at the chart already holding both units and both current values; the chart only has to supply shape.
3. A 0.5pt vertical hairline now separates the readout column from the chart. Without it, "28%" and the chart's "%" label ran together and could read as "28%%" — that was a real defect in my first render and the separator killed it.
An end-of-series dot in each band marks the current value, so each half's peak is anchored to a number the reader can see stated in words 8pt to the left.

WHY NOT A SINGLE HONEST ENCODING: I tried two. Plotting only burn rate deletes the slow-then-spike cumulative shape, which is the whole story of "the window average is 10%/h but you are at 92%/h right now" — that shape is *why* the 47-minute projection is believable. Normalising cumulative-% onto the same 0–100 axis as %/h turns the 28% series into a flat sliver with no readable shape. Two labelled, separately-scaled bands on a shared time axis keeps the visual weight and is honest, provided the labels are present — which they are.

RISK I ACCEPT AND STATE: because each band is self-scaled, the *heights* of the two lobes are not comparable to each other. The unit labels and the colour binding are what prevent that comparison from being attempted; they do not make it impossible. That is the residual cost of keeping the form.

The 7-day chart has no such problem: one unit (% per day), 7 columns, green stack with a purple Fable cap, columns summing to the stated 18% with 1% Fable, shared baseline. Its progress bar carries a neutral marker at 34.5% = elapsed time, which is what generates the neutral pace note beneath it.

**琥珀預算：** Amber has exactly **one owner: "this needs you, now."** Every amber element is either the blocked session or the burn-out projection — those are the only two things in the panel that a human can act on this minute.

ALLOWED TO BE AMBER (and nothing else is):
1. Header roll-up — the `1 BLOCKED` cell: amber tint box (15% fill) + 0.42 amber border + amber figure and label. The `4 SESSIONS` and `5 AGENTS` cells are plain, same padding, no box.
2. SESSIONS section-label summary — `1 等待` only. `2 BUSY · 1 IDLE` are tertiary grey. It is amber because it points at the card directly below it.
3. The blocked session card, in full: 3pt amber left rail, 0.5pt amber border, 15% amber tint, `等待你回覆`, the elapsed `2m`, the consequence line `1 個 agent 跟著停住` with its amber elbow glyph, and the `STALLED` tag on the nested agent.
4. The burn story on the 5-hour card: the 燃燒率 swatch, the `92%/h` value, the lower half of the split-axis sparkline, and the warning strip `照目前燃燒率，約 47 分鐘後用盡 — 比重置早 1h 25m` with its 2.5pt amber rail. This is the same owner: the warning strip *is* that series, so colouring the series to match is one statement, not two.
5. Outside the panel: the menu-bar status item's blocked dot. Same meaning, and it is the reason you opened the popover.

WHAT BECAME NEUTRAL (all of it was a candidate for amber in the source directions):
· CTX micro-bars — `--pn-neut` grey fill on a `--pn-track` grey rail, at 34% / 12% / **61%**. The 61% one is the biggest temptation in the panel and it is grey. Context pressure is information, not an action.
· The hatched remainder of the 5-hour progress bar — an SVG diagonal pattern in white/black at .30/.26 alpha. The consumed part is blue; the hatch says "not yet spent", not "danger".
· All progress tracks, the header mini-bars (5-hour is **blue**, not amber, despite being the burning window), the workflow pip meter (green done / blue running), the BUSY pill (blue), the IDLE pill (grey), the agent duration bars (blue running / green done).
· The stalled agent's bar is a flat neutral fill at 100% with no colour — it is not making progress, so it gets no progress colour.
· **The proof element:** the 7-day card's info strip is a deliberate neutral twin of the amber warning strip — identical geometry, identical 2.5pt rail, grey instead of amber, reading `時間已過 35%，額度只用 18% — 低於配速`. The two sit side by side at the same y. That adjacency is what makes amber legible as a severity signal rather than a house colour.

Honest caveat: under one *meaning*, amber still lands in five places. "Spend amber once" is honoured semantically, not literally — a stricter reading would drop the burn-rate swatch and sparkline half to neutral and leave amber only on the warning strip and the blocked card. I judged that the swatch→series→strip chain has to be one colour or the chart stops being readable, and I would revert it in ten seconds if you disagree.

**評審必修：**
- (訊號設計, 29/40) Kill the mirrored chart — two self-scaled bands whose heights you admit are not comparable is the dishonesty you were asked to remove, not a form worth preserving — then drop the burn swatch and the series half to neutral so amber stops reading as the panel's house colour.
- (工藝與原生度, 27/40) 560pt is not a popover. I rendered it: at 560 x 620 with a two-column quota block this reads as a preferences window with a notch glued on, and neither Stats nor Orbit ever goes two-column. Rebuild at 400pt. Second, and this is the refusal: you were told the mirrored sparkline was dishonest and you kept it. Two self-scaled bands sharing one hairline IS the mirror; declaring an axis break does not remove it, and I measured the two unit labels that carry the entire honesty argument at 8.5px monospace at 0.85 opacity — the smallest type on a 560pt panel is doing its heaviest semantic work. In the render they read as an X of two crossing lines. Third: amber is now the house colour. Header cell + 1 等待 + burn swatch + 92%/h + the chart's whole lower band + the warning strip + a full amber blocked card 40pt below it — that is not one owner, that is a warm panel, and it is visible at a glance in the screenshot. Surrender the swatch and the chart band as you offered. Fourth: 28% appears three times and 18% twice on one screen; the card footline percentages go.

**自陳缺點：**
- 28% is stated three times on one screen (header big figure, card readout row, card footline right-hand value) and 18% twice. I justified it as a glance layer plus a mechanism layer, but the card footline's right-aligned percent is the weakest of the three and is the first thing I would cut if you want the redundancy gone — it buys nothing the readout row above it hasn't already said.
- The scroll viewport is 121pt against 260pt of content: less than half the session tree is visible at rest. With 4 sessions and a 7-agent workflow that already means usage-97's subtree pushes obsidian-4a and wrapx-comsol below the fold. The pinned/scroll split is the right structure, but the ratio degrades with every extra session — a fifth session makes it ~40%.
- The two sparkline bands are self-scaled, so their visual heights are not comparable to each other. The unit labels and the colour binding to the readout swatches prevent the misread; they do not make it impossible. A reader skimming shape only can still conclude the amber lobe is 'bigger' than the blue one, which means nothing.
- Amber appears in five distinct places (BLOCKED cell, 1 等待, blocked card, burn series, warning strip). I claim one owner semantically, but a critic counting swatches will say I spent it five times. The burn-rate swatch and sparkline half are the two I would surrender first.
- The 5-hour warning strip wraps to two lines and leaves '1h 25m' alone on the second — an orphan. At this card width the specified copy cannot fit on one line without dropping below 10pt, so I took the wrap over the type-size hit.
- The light panel's scrollbar thumb is drawn, not live — it is a static depiction of scrollTop 118. If this ships, the thumb must track scrollTop or be removed. The dark panel deliberately has no drawn thumb for exactly this reason, which means the two panels demonstrate the affordance differently.
- 560pt is the top of the range you gave. It reads as a popover on a 13-inch display, but on an 11-inch it is roughly a third of the screen width and the 'is this a window?' question gets harder. There is no headroom left to buy more height with more width.
- The extra width genuinely pays off in the agent rows (176pt shared-scale duration bars) and the session rows (full paths, nothing truncated), but the workflow row does not benefit — the space between wf_79e5d247 and the pip meter is just gap. That row would look identical at 440pt.
- Only the light panel shows the scrolled state, so a reviewer comparing dark vs light material is simultaneously comparing two scroll positions. That confounds the material comparison slightly; the honest alternative was four panels, which I judged worse.
- Fable at 1% renders as a 3px min-width sliver in the header mini-bar rather than its true ~1.7px. That is a small lie about the bar's scale, kept so the purple is visible at all. The footline '幾乎未用' is doing the real work there.
- The blocked card's keyboard chip says ⌘⏎ but the panel never establishes what is focused, so the shortcut is asserted rather than explained. In a real build that chip needs the card to be focusable, or it is decoration.

### 摺疊展開 — Progressive Panel — collapse by default, expand on demand（56/80）

**高度解法：** Measured in the browser at 1pt=1px, the panel is a fixed 372 × 620 flex column. Five blocks are pinned (`flex:none`), one block scrolls (`flex:1 1 auto; min-height:0`).

PINNED = 492pt (all measured, not estimated):
- header 131 — brand row 28 + 8 + section-label row 12 + 6 + three-cell quota row 56, padding 10/10, hairline .5
- quota block 197 — 5-hour card expanded 143 + 6 + 7-day collapsed row 31, padding 8/8, hairline .5
- 工作階段 SESSIONS label row 25
- blocked card 108 — id row 17 + 5 + consequence row 13 + 6 + command strip 26 + 6 + stalled-agent row 16, padding 7/7
- footer 31

SCROLL = 128pt, holding 249pt of session content (usage-97 row 30 + workflow row 26 + five agent rows at 19 + collapsed-done row 18 + gap 6 + two session rows at 30 + padding 14). Thumb is drawn to scale: 64pt tall (128/249 of a 122pt track), sitting at top:11 in the dark panel because the list is scrolled 14pt, and at top:4 in the light panel because it is at rest. The dark panel therefore shows a clipped first row under a top fade plus a bottom fade; the light panel shows only a bottom fade. A .5pt hairline marks where pinned ends and scrolling begins, so the boundary is not implied by the fade alone.

WHAT WAS CUT OR COMPRESSED TO GET FROM 856 TO 620:
1. The 7-day card is collapsed to a 31pt row (was ~150pt expanded). That alone is the merge angle, and it is reversible with one click.
2. Nothing else was deleted — the 5-hour card kept its chart, hatched bar, footline and warning strip, and the session tree kept every row the Stats direction had. The height came out of disclosure, not out of content.
3. The agent sub-rows are 19pt and the workflow row 26pt — a deliberate second tier below the 30pt session rows. Primary rows stay in the 28–36pt band.

THE KEY NUMBER: when the 5-hour card is also collapsed (its normal state), the quota block drops 197 → 85 and the scroll viewport goes 128 → 240pt — the list nearly doubles. The panel height never changes; only the split moves. A fifth session lengthens the scroll content, never the panel.

**圖表單位問題：** I removed the mirror and found a single honest encoding, rather than labelling two halves.

The mirrored sparkline put a level (cumulative % used) and a rate (%/h) on one axis with opposite sign conventions, so the reader had to hold two units and two directions at once. But the rate is the derivative of the level — so one curve already contains both. The chart now plots only cumulative % of the 5-hour window, 0 at the baseline, 100% at a dotted rule labelled 100% 用盡線. One unit, one baseline, no mirror. The caption states the reading rule explicitly: 累計 % of window ・斜率＝燃燒率.

That makes the burn rate visible as geometry instead of as a second series: 2h 48m of near-flat line (the 10 %/h window average), then the last five minutes rear up to a 92 %/h slope. The blue dot and the dotted vertical mark 現在. From there a dashed amber line continues at exactly the current slope until it hits the 100% rule — that intersection *is* the 47-minute exhaustion, drawn as an amber ring. The reset line stands at 5h, and an amber bracket spans the distance between the two, labelled 1h 25m. So every number in the warning strip below is also a shape you can point at, and the "1h 25m before reset" is a measured gap rather than a claim.

Visual weight is preserved, just relocated: the mirror got its drama from symmetry, this gets it from the ramp, the dashed projection breaking the ceiling, and the bracket. The honest cost is that the left 55% of the chart is nearly empty — which is the truth about the last two and a half hours.

The 7-day chart needed no surgery: seven daily columns, one unit (% per day), green stacked with a purple Fable cap, on a visible baseline.

**琥珀預算：** Amber has exactly two owners: THE BLOCKED SESSION and THE BURN WARNING. Nothing else in the panel is allowed to be warm. Complete inventory of every amber element:

Blocked session (7):
1. header roll-up cell 1 BLOCKED — tinted box, hairline border, figure and label
2. blocked card 3pt left rail
3. blocked card border and background tint
4. 等待你回覆
5. the consequence line 1 個 agent 跟著停住 and its pause glyph
6. 1 等待 inside the SESSIONS summary (the rest of that string — 2 BUSY · 1 IDLE — is tertiary grey)
7. the menu-bar status item's blocked dot

Burn warning (5):
8. 燃燒率 burn key swatch in the 5-hour card
9. the dashed projection line in the chart
10. the exhaustion ring where it meets 100%
11. the 1h 25m bracket and its label
12. the warning strip — rail, tint, glyph, and the bold 47 分鐘
(plus, in the collapsed-state demo, the 5-hour row's amber dot and 47 分鐘後用盡, which are the same warning at row scale)

Everything else was made neutral or series-coloured:
- CTX micro-bars: neutral grey fill on a neutral track, at 34 / 12 / 61% — no colour ramp, no red at 61
- the hatched remainder of both progress bars: neutral white/black diagonals, not amber
- the stalled agent's own bar: neutral grey fill on a plain track (blue = advancing, neutral = frozen), so "stalled" is carried by the consequence line, not by painting the bar
- the 7-day pace marker: neutral tick and diamond
- IDLE pill and dot, all elapsed times, agent duration bars, the keyboard chips, footer glyphs, scrollbar and fades: neutral
- workflow pips: green done / blue running
- quota series identity: blue 5-hour, green all models, purple Fable

FRESHNESS: 3 分鐘前 appears once, in the 額度 QUOTA section-label row where it qualifies the numbers it describes. The footer keeps the refresh glyph and ⌘R as an action, with no time string.

**評審必修：**
- (訊號設計, 28/40) Build and measure the collapse/expand transition before the height solution depends on it, and resolve the auto-expand contradiction rather than listing it — surfacing the warning must not be the thing that hides the sessions.
- (工藝與原生度, 28/40) You collapsed the 7-day card to a 31pt row by default. That card — two colour-keyed readouts, the 7-column green stack with the purple Fable cap, the pace marker, the footline — is a component the user approved in a screenshot, and 'one click away' is still not on screen. Ship it expanded and collapse it only when the 5-hour warning fires. Second, the structural problem you did not name: the auto-expand that surfaces the warning is what squeezes the list, so the collapse mechanism pays off precisely when nothing is wrong and gives you 128pt — no better than pinned — in the real data state you were asked to design for. Third: 19pt agent rows and 26pt workflow rows are under the row band you cite and under any sane AppKit hit target; lift them. Fourth: for a panel whose entire thesis is an interaction, there is not one hover, pressed or focus state drawn anywhere.

**自陳缺點：**
- The auto-expand that surfaces the warning is the same thing that squeezes the list: while the 5-hour card is open the scroll viewport is 128pt and shows roughly half the session content. With six or more sessions you would be scrolling during exactly the period when you most want to see everything.
- Agent sub-rows are 19pt and the workflow row 26pt, below the 28-36pt row guidance. Justified as a nested second tier, but it is a real deviation and a smaller hit target than AppKit would want for a clickable row.
- The collapse/expand mechanism is shown, not built. With no scripts the two states are separate renderings; the actual transition is unproven, and animating a height change on a vibrancy-backed popover is precisely the kind of thing that stutters.
- The 7-day pace marker (time elapsed 35%) carries no label inside the panel and is only explained in the annotation card. In the real app it needs a tooltip or it is just a mysterious tick.
- The new chart is honest but sparse on the left: two and a half flat hours of almost nothing. If what the user liked about the mirrored sparkline was the symmetry itself rather than the drama, this does not give that back.
- 28% is now printed three times on one screen (header cell, card key row, card footline right). That redundancy comes from merging both approved directions, but it is redundancy.
- The menu-bar strip is anchoring context for the notch, not a designed status item; the ring-plus-28% mark there is a placeholder and should not be read as a proposal.
- Light-mode amber (#b56700) is a much darker orange than dark-mode (#ffb340). Correct for contrast on a light material, but the identity of 'amber' is not identical across the two.
- Only one scroll position is shown per material. A list scrolled to its very bottom (bottom fade gone, thumb parked) is not illustrated.
- No hover, pressed, focus-ring or keyboard-navigation states are drawn anywhere.

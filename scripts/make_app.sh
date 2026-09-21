#!/usr/bin/env bash
# 組裝 QuotaMonster.app 並安裝到 ~/Applications。
#
# 為什麼不用 Xcode：這台機器的 xcode-select 指向 CommandLineTools，
# 所以 xcodebuild 會失敗。純 SwiftPM 不需要動它。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="QuotaMonster"
BIN_NAME="QuotaMonsterApp"
BUILD="$ROOT/.build/release/$BIN_NAME"
STAGE="$ROOT/.build/app/$APP_NAME.app"
DEST="${1:-$HOME/Applications}"
# ⚠️ 沒有預設值。憑證名稱裡有 Apple ID 與 Team ID —— 寫死等於把個人痕跡
# 推上 GitHub。沒設就走 ad-hoc，下面會印出後果。
# 查自己的名稱：security find-identity -v -p codesigning
IDENTITY="${CODESIGN_IDENTITY:-}"

echo "▸ building"
( cd "$ROOT" && swift build -c release )

# ── 這個檢查不可移除 ──────────────────────────────────────────────
# 預設 swiftc 會編出 minos 28.0，高於執行中的 macOS 27.0。
# 包成 .app 後 LaunchServices 直接以 -10825 拒絕啟動，
# 但當成純 CLI binary 跑又完全正常 —— 會騙過天真的 smoke test。
MINOS="$(otool -l "$BUILD" | grep -A4 LC_BUILD_VERSION | awk '/minos/{print $2; exit}')"
echo "▸ minos = $MINOS"
if [[ "$MINOS" == 2[0-9].* && "${MINOS%%.*}" -gt 20 ]]; then
  echo "✗ minos $MINOS 高於目標。檢查 Package.swift 的 platforms: [.macOS(.v14)]" >&2
  exit 1
fi

echo "▸ assembling bundle"
rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp "$BUILD" "$STAGE/Contents/MacOS/$BIN_NAME"
cp "$ROOT/Resources/Info.plist" "$STAGE/Contents/Info.plist"

# ── app icon ─────────────────────────────────────────────────────
# icon **不入版控**：它的來源是 Sources/QuotaMonsterApp/Glyph/IconRenderer.swift，
# 每次建置現產。好處是 icon 與選單列圖示不可能漂走 —— IconRenderer 的幾何
# 是從 GlyphGeometry（Core）取的，改了那邊，icon 下次建置就跟著改。
#
# ⚠️ 十個尺寸**各自原生渲染**，不是從 1024 縮下來的。全程 NSBezierPath，
#    在目標尺寸重畫比降取樣清楚（16/32 差最多）。
# ⚠️ 用剛建好的那個 binary 來畫，不是 ~/Applications 裡那個舊的。
echo "▸ rendering icon"
ICONSET="$ROOT/.build/app/AppIcon.iconset"
rm -rf "${ICONSET}"
if "$BUILD" --render-icon "${ICONSET}" > /dev/null \
   && iconutil --convert icns --output "$STAGE/Contents/Resources/AppIcon.icns" "${ICONSET}"; then
  echo "  AppIcon.icns ($(wc -c < "$STAGE/Contents/Resources/AppIcon.icns" | tr -d ' ') bytes)"
else
  # icon 畫不出來不該讓整個建置失敗 —— app 本身完全可用，只是 Finder 裡沒有圖。
  # 但**一定要講**：Info.plist 指著一個不存在的 AppIcon，沉默地少一顆 icon
  # 會被當成「設計就是這樣」。
  echo "  ⚠ icon 產生失敗 —— bundle 仍然可用，但 Finder 裡會是一張白紙" >&2
fi

echo "▸ signing"
# 優先用 Apple Development 憑證：它給出穩定的簽章身分，
# TCC（通知授權）比較不會因為每次重建就把授權作廢。
# ⚠️ `-n "$IDENTITY"` 不可省略：IDENTITY 是空字串時 `grep -qF ""` 會 match
# 任何一行輸出，於是走進上面那個分支、拿空字串去 codesign --sign 而失敗。
if [[ -n "$IDENTITY" ]] \
   && security find-identity -v -p codesigning 2>/dev/null | grep -qF "$IDENTITY"; then
  codesign --force --sign "$IDENTITY" "$STAGE" && echo "  signed with: $IDENTITY"
else
  if [[ -z "$IDENTITY" ]]; then
    echo "  ⚠ CODESIGN_IDENTITY 沒設 —— 走 ad-hoc 簽章"
  else
    # ⚠️ 一定要寫 ${IDENTITY}：bash 3.2（macOS 內建的那個）會把後面那個
    # 全形括號的位元組吃進變數名，配上 set -u 就炸成 unbound variable。
    # 〔實測 2026-09-21，本機 bash 3.2.57〕加大括號前這一行就是這樣掛的。
    echo "  ⚠ 找不到憑證「${IDENTITY}」—— 走 ad-hoc 簽章"
  fi
  # 〔推論，未在這台機器上實測〕ad-hoc 簽章沒有穩定的簽章身分，
  # 所以每次重建都可能被 TCC 當成另一個 app。上面那段「優先用 Apple
  # Development 憑證」的註解是同一個推論的另一半。
  echo "    後果：ad-hoc 沒有穩定的簽章身分，重建後通知授權可能要重新給一次。"
  echo "    設 CODESIGN_IDENTITY 可以避免；用下面這行查自己的名稱："
  echo "    security find-identity -v -p codesigning"
  codesign --force --sign - "$STAGE" && echo "  signed ad-hoc"
fi
codesign -dv "$STAGE" 2>&1 | grep -E "Identifier|TeamIdentifier|Signature" || true

echo "▸ installing to $DEST"
mkdir -p "$DEST"
rm -rf "$DEST/$APP_NAME.app"
cp -R "$STAGE" "$DEST/$APP_NAME.app"

# 讓 LaunchServices 確實看到它
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$DEST/$APP_NAME.app" 2>/dev/null || true

echo "✓ $DEST/$APP_NAME.app"

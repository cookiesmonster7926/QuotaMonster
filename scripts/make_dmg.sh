#!/usr/bin/env bash
# 把 QuotaMonster.app 包成一個別人可以下載的 DMG。
#
#   bash scripts/make_dmg.sh                    # 產出 dist/QuotaMonster-<版本>.dmg
#   bash scripts/make_dmg.sh /tmp/out.dmg       # 指定輸出路徑
#
# 環境變數 QM_APP 可以指向別的 .app（預設 .build/app/QuotaMonster.app，
# 也就是 make_app.sh 組出來的那一份）。
#
# 為什麼用 hdiutil 而不是 create-dmg：
#   〔實測 2026-09-21，這台機器〕`which create-dmg` → not found。
#   hdiutil 是 macOS 自帶的，clone 下來就能跑，不必先叫人 brew install 一個東西。
#   代價是沒有背景圖、沒有圖示座標 —— DMG 打開就是兩個圖示（app 與 Applications
#   捷徑）。那是刻意的取捨，不是還沒做完。
#
# ⚠️ 這支腳本產出的 DMG **沒有公證（notarization）**，而且不可能有：
#   公證的前提是 Developer ID 憑證，這個專案只有 Apple Development（免費 Apple ID）。
#   〔實測 2026-09-21〕`spctl -a -vvv ~/Applications/QuotaMonster.app` → `rejected`，
#   即使它已經用 Apple Development 簽過。所以腳本結尾一定會把這件事印出來 ——
#   不印才是說謊。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="QuotaMonster"
APP="${QM_APP:-$ROOT/.build/app/$APP_NAME.app}"

die() { echo "✗ $*" >&2; exit 1; }

OUT=""
for arg in "$@"; do
  case "$arg" in
    -h|--help)
      # 從第 2 行開始印註解，遇到第一行不是註解就停。
      # 寫死行號會在說明變長變短時把 set -euo pipefail 當成說明印出來。
      awk 'NR>1 { if ($0 !~ /^#/) exit; sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"
      exit 0 ;;
    -*)  die "不認得的參數：$arg" ;;
    *)
      [[ -z "$OUT" ]] || die "只吃一個輸出路徑，多給了：$arg"
      OUT="$arg" ;;
  esac
done

# ── 為什麼不自動幫你跑 make_app.sh ────────────────────────────────
# 因為那會讓 DMG 的內容變成「不知道是哪一次建置的東西」：
# make_app.sh 走的是**增量** swift build，而這個 repo 的驗收規矩明說
# 增量建置的 Build complete 是假象（要 rm -rf .build 才算數）。
# 打包腳本的工作是「把一個已知的產物封起來」，不是「順便生一個產物」。
# 附帶一提，make_app.sh 還會安裝到 ~/Applications 並重新登錄 LaunchServices ——
# 那是打包這個動作不該有的副作用。
[[ -d "$APP" ]] || die "找不到 $APP
  先跑： bash scripts/make_app.sh
  （或用 QM_APP=/path/to/QuotaMonster.app 指定別的 .app）"

plist_version() {  # $1 = Info.plist 路徑；讀不到就回空字串
  /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$1" 2>/dev/null || true
}

# 版本號以**.app 裡那一份** Info.plist 為準，因為 DMG 檔名描述的是它裝的東西，
# 不是工作目錄現在的樣子。Resources/Info.plist 是它的來源（make_app.sh 複製過去），
# 兩邊對不上就代表 .app 比原始碼舊 —— 那要講出來，但不能用原始碼那個號碼去命名
# 一個裝著舊 binary 的 DMG。
VERSION="$(plist_version "$APP/Contents/Info.plist")"
[[ -n "$VERSION" ]] || die "$APP/Contents/Info.plist 讀不到 CFBundleShortVersionString"
SRC_VERSION="$(plist_version "$ROOT/Resources/Info.plist")"
if [[ -n "$SRC_VERSION" && "$SRC_VERSION" != "$VERSION" ]]; then
  # ⚠️ 底下的 ${VERSION} 大括號不可以拿掉。
  # 〔實測 2026-09-21〕macOS 自帶的 bash 3.2.57 在 LANG=en_US.UTF-8 下，
  # 會把中文全形標點的**第一個 byte** 當成變數名的一部分：
  #   bash -c 'set -u; V=1; echo "是 $V，但"'  →  V<0xef>: unbound variable
  # 加了 set -u 就是當場死掉，而且只死在這條「版本對不上」的岔路上 ——
  # 一個只有在出事時才會跑到、跑到就自己炸掉的警告。加大括號才擋得住。
  echo "⚠️  .app 是 ${VERSION}，但 Resources/Info.plist 已經是 ${SRC_VERSION}。"
  echo "   這個 DMG 裝的是 ${VERSION}。要出 ${SRC_VERSION} 就先跑 bash scripts/make_app.sh。"
fi

OUT="${OUT:-$ROOT/dist/$APP_NAME-$VERSION.dmg}"
VOLNAME="$APP_NAME $VERSION"

echo "▸ app     = $APP"
echo "▸ version = $VERSION"
echo "▸ out     = $OUT"

# ── staging ─────────────────────────────────────────────────────
# 直接對 .app 的所在目錄下 -srcfolder 會把它旁邊的東西一起包進去，
# 所以一定要一個只有「app + Applications 捷徑」的乾淨目錄。
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/quotamonster-dmg.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

echo "▸ staging"
# 用 ditto 不用 cp -R：〔文件說，我沒有實測兩者的差別〕ditto 是 Apple 給 bundle 用的
# 複製工具，會連 extended attributes 一起帶過去。
# 不管哪一個工具，簽章壞掉的 .app 裝進 DMG 都沒有用，所以複製完當場驗一次 ——
# 〔實測 2026-09-21〕這道檢查對 Apple Development 簽的與 ad-hoc 簽的 .app 都會過。
# 它失敗就代表 DMG 是壞的，不可以往下走。
ditto "$APP" "$STAGE/$APP_NAME.app"
codesign --verify --strict "$STAGE/$APP_NAME.app" \
  || die "複製後的 .app 簽章驗不過，DMG 不做了"

# 這個捷徑就是「拖進去安裝」的那半 —— 沒有它，使用者會從掛載的唯讀映像直接執行。
ln -s /Applications "$STAGE/Applications"

# ── 出片 ────────────────────────────────────────────────────────
# -fs HFS+   ：〔文件說，我只在 macOS 27.0 上實測掛得起來〕APFS 映像在舊系統上
#              掛不動，HFS+ 沒有這個問題；我們只放一個 app，用不到 APFS 的任何東西。
# -format UDZO：壓縮＋唯讀，是 app DMG 的標準格式〔文件說〕。
# -imagekey zlib-level=9：〔實測 2026-09-21，0.1.0 的 .app〕
#              level 9 → 716,234 bytes，不給這個 key（預設）→ 804,403 bytes，
#              小 11%，兩者都在一秒內做完。那就拿這 11%。
# ⚠️〔實測〕macOS 27.0 的 hdiutil 會印 "hdiutil create ... is deprecated"，
#   叫人改用 diskutil image create。它仍然正常產出，而 diskutil 那條路在舊系統
#   上不存在，所以先不換 —— 換的時候要連最低支援版本一起想。
mkdir -p "$(dirname "$OUT")"
echo "▸ hdiutil create"
hdiutil create \
  -srcfolder "$STAGE" \
  -volname "$VOLNAME" \
  -fs HFS+ \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  "$OUT"

# SHA-256 是給發布頁貼的：沒有公證，這串就是下載的人唯一能拿來對帳的東西。
echo
echo "✓ $OUT"
echo "  $(du -h "$OUT" | cut -f1)"
echo "  sha256 $(shasum -a 256 "$OUT" | cut -d' ' -f1)"

# ── Gatekeeper 的真相（不可以刪）─────────────────────────────────
# 這一段不是免責聲明，是使用說明。少了它，下載的人只會看到一個
# 「已損毀」的對話框，然後以為這個 app 壞了。
#
# 下面每一句的出處（這個 repo 的規矩：實測／推論不可以混著寫）：
#   〔實測 2026-09-21〕`spctl -a -vvv <掛載後的 QuotaMonster.app>` → rejected，
#                      origin 是 Apple Development 憑證 —— 簽了，但 Gatekeeper 不收。
#   〔實測 2026-09-21〕`spctl -a -t open --context context:primary-signature -vvv <本 DMG>`
#                      → rejected，source=no usable signature（DMG 本身沒簽）。
#   〔實測 2026-09-21〕`xattr -w com.apple.quarantine …` 再 `xattr -d` 之後，
#                      `xattr -p` 回 "No such xattr" —— 第 3 條指令確實會把屬性拿掉。
#   〔推論，沒有實測〕拿掉隔離屬性之後就打得開、右鍵→打開那條路在新版 macOS 上被收掉、
#                      以及瀏覽器會掛上隔離屬性 —— 這三件事我沒有從瀏覽器下載這個 DMG
#                      實際點兩下驗過。要驗就得真的上傳一份再下載回來。
cat <<'EOF'

────────────────────────────────────────────────────────────
⚠️  這個 DMG 沒有經過 Apple 公證（notarization），而且做不到：
    公證要 Developer ID 憑證，這個專案只有 Apple Development（免費 Apple ID）。
    〔實測〕即使 .app 已經簽過，spctl -a -vvv 仍然回 rejected。

    所以下載的人第一次打開會被 Gatekeeper 擋下來。請把下面這段
    一起寫進 README / release note：

    1. 把 QuotaMonster.app 拖進「應用程式」
    2. 在 Finder 對它按右鍵 →「打開」→ 對話框再按一次「打開」
       （新版 macOS 把這條路收得比較緊，對話框可能只剩「取消」。
        那就改去「系統設定 → 隱私權與安全性」，往下捲會有一顆「仍要打開」）
    3. 還是不行就走終端機，把隔離屬性拿掉：
         xattr -d com.apple.quarantine /Applications/QuotaMonster.app

    （隔離屬性是瀏覽器下載時掛上去的。用 curl / scp 拿到的檔案通常沒有，
      那就不會被擋 —— 也因此「我這邊雙擊得開」不能當成別人也開得了。）
────────────────────────────────────────────────────────────
EOF

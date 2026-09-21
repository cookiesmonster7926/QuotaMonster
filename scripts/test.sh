#!/usr/bin/env bash
# 為什麼需要這支腳本：
# swift-testing 的 framework 放在哪裡，取決於 xcode-select 指到哪裡，而這個 repo
# 要在兩種環境下都跑得起來：開發機（CommandLineTools）與 CI（完整 Xcode）。
#
# 〔實測 2026-09-21，本機 CLT 26.x，兩組對照組都真的跑過〕xcode-select 指向
# CommandLineTools 時，SwiftPM 不會自動補上 swift-testing 的路徑。兩條都缺，
# 而且缺的後果不一樣 —— 所以兩條都不可以拿掉：
#   $DEV/Library/Developer/Frameworks   —— Testing.framework 本體。
#       對照組：什麼都不補 → 編不過，`error: no such module 'Testing'`
#   $DEV/Library/Developer/usr/lib      —— lib_TestingInterop.dylib（Testing 的相依）
#       對照組：只補上面那條 → 編得過、連得起來，但**跑起來才炸**：
#       dyld `Library not loaded: @rpath/lib_TestingInterop.dylib`
# 補上之後就不必為了跑測試去動全域的 xcode-select。
#
# 〔實測 2026-09-21，本機 /Applications/Xcode.app 26.x〕xcode-select 指向完整
# Xcode 時，上面那兩條路徑**都不存在**（Testing.framework 改放在
# Platforms/MacOSX.platform/Developer/Library/Frameworks，由 SwiftPM 自己處理）。
# 舊版這支腳本無條件把它們傳下去，ld 會印
#   `ld: warning: search path '...' not found`
# —— 實測只是 warning、不會讓測試失敗，但那是在對工具鏈說謊，而且下一個看到
# 這則 warning 的人得重新查一次。所以改成：路徑存在才加，不存在就交給 SwiftPM。
#
# ⚠️ 不要把這裡的判斷改成「檢查 xcode-select 指向哪裡」。決定權在**路徑在不在**，
# 不在目錄長什麼名字；Xcode 與 CLT 的版面配置都可能再變。
set -euo pipefail

DEV="$(xcode-select -p)"
FW="$DEV/Library/Developer/Frameworks"
LIB="$DEV/Library/Developer/usr/lib"

# ⚠️ 這裡要寫成 if，不可以寫成 `[[ -d … ]] && FLAGS+=(…)`：
# 條件不成立時那整行的離開碼是 1，配上 `set -e` 會讓腳本在還沒跑到 swift test
# 就以離開碼 1 結束 —— CI 上看起來像「測試掛了」，其實是一個測試都沒跑。
FLAGS=()
if [[ -d "$FW" ]]; then
  FLAGS+=(-Xswiftc -F"$FW" -Xlinker -F"$FW" -Xlinker -rpath -Xlinker "$FW")
fi
if [[ -d "$LIB" ]]; then
  FLAGS+=(-Xlinker -rpath -Xlinker "$LIB")
fi

# ⚠️ `"${FLAGS[@]}"` 在 bash 3.2（macOS 內建的那個）配上 `set -u`，陣列是空的時候
# 會炸成 unbound variable —— 而「陣列是空的」正是完整 Xcode 的情況。
# 所以一定要走 `${FLAGS[@]+...}` 這個寫法。〔實測：兩種環境都跑過〕
exec swift test ${FLAGS[@]+"${FLAGS[@]}"} "$@"

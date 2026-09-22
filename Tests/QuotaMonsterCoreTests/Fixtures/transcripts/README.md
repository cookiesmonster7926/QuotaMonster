# 母 transcript 的記錄樣本

由 `scripts/capture_fixtures.py` 之外的一次性萃取產生（2026-09-22），來源是這台機器上
37 份真實 transcript。**結構完全保留，長散文與識別字串換成同形狀的假值。**

| 檔案 | 它釘住什麼 |
|---|---|
| `spawn-async.jsonl` | `toolUseResult.status == "async_launched"` —— 開出去了，完成會晚點以另一筆記錄抵達 |
| `spawn-sync.jsonl` | `toolUseResult.status == "completed"` —— **這一筆本身就是完成**，不會再有通知 |
| `notify-enqueue.jsonl` | `type:"queue-operation"` / `operation:"enqueue"`，完成證據的主要載體（實測 25/25） |
| `notify-remove.jsonl` | 同一份內容的 `operation:"remove"` 複本 —— **算進去就是雙重計數** |
| `notify-user.jsonl` | `type:"user"` 的那一份（實測只涵蓋 6/25，不可以只看這一種） |
| `notify-failed.jsonl` / `notify-killed.jsonl` | `<status>` 的另外兩個值 |
| `notify-no-status.jsonl` | 沒有 `<status>` 的進度回報（Monitor event）—— **不是「下場不明」，是「不是完成」** |
| `notify-workflow.jsonl` / `notify-bash.jsonl` | workflow（9 字元 `w`）與背景 bash（9 字元 `b`）—— 不可以算成 agent |

⚠️ 這是一個**沒有官方契約**的內部格式，沒有版本標記。這些樣本來自
Claude Code 2.1.222–2.1.278，不是穩定性保證。

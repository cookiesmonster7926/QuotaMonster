#!/usr/bin/env python3
"""從真實資料產生測試 fixture，並強制去識別化。

安全規則（不可放寬）：任何含有 sk-ant- 的內容一律拒絕寫出並以非零碼結束。
這條規則是有來由的 —— 研究階段曾有 agent 執行 security find-generic-password -g，
把 OAuth token 寫進了本機 transcript。fixture 腳本必須主動防這件事。
"""
import json, os, re, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIX = os.path.join(ROOT, 'Tests', 'QuotaMonsterCoreTests', 'Fixtures')
SECRET = re.compile(r'sk-ant-[A-Za-z0-9_-]{10,}')
FAKE_ACCOUNT = '00000000-0000-4000-8000-000000000001'
FAKE_SESSION = '11111111-1111-4111-8111-111111111111'
NOW_MS = 1789660000000          # 固定基準時間，讓測試可重現

def write(rel, obj):
    path = os.path.join(FIX, rel)
    text = obj if isinstance(obj, str) else json.dumps(obj, indent=1, ensure_ascii=False)
    if SECRET.search(text):
        sys.exit(f'REFUSED: {rel} contains a credential')
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, 'w').write(text)
    print(f'  {rel}')

# ── 額度快取 ────────────────────────────────────────────────────────
real = json.load(open(os.path.expanduser('~/.claude.json'))).get('cachedUsageUtilization')
if not real:
    sys.exit('no cachedUsageUtilization on this machine')
util = dict(real['utilization'])

# ⚠️ 與 statusline fixture 同樣的理由：真實資料提供**形狀**，數值必須釘死。
# 不釘的話，使用者的實際用量一變，重跑這支腳本就會讓一批綠燈測試無緣無故變紅。
for _key, _pct in (('five_hour', 30), ('seven_day', 19)):
    if isinstance(util.get(_key), dict):
        util[_key] = {**util[_key], 'utilization': _pct}
if isinstance(util.get('limits'), list):
    _pinned = {'session': 30, 'weekly_all': 19, 'weekly_scoped': 1}
    util['limits'] = [
        {**e, 'percent': _pinned.get(e.get('kind'), e.get('percent'))}
        for e in util['limits']
    ]

def cache(age_sec, u=None, account=FAKE_ACCOUNT):
    return {'fetchedAtMs': NOW_MS - age_sec * 1000,
            'accountUuid': account,
            'utilization': u if u is not None else util}

print('claude_json fixtures:')
write('claude_json/fresh.json',   {'cachedUsageUtilization': cache(42)})          # < 5 min
write('claude_json/aging.json',   {'cachedUsageUtilization': cache(23 * 60)})     # 5..60 min
write('claude_json/expired.json', {'cachedUsageUtilization': cache(61 * 60)})     # > 60 min
write('claude_json/account_mismatch.json',
      {'cachedUsageUtilization': cache(42, account='99999999-9999-4999-8999-999999999999')})
write('claude_json/no_cache.json', {'someOtherKey': True})

partial = {k: v for k, v in util.items() if k != 'seven_day'}
partial['seven_day'] = None
write('claude_json/missing_windows.json', {'cachedUsageUtilization': cache(42, partial)})

extra = dict(util)
extra['a_key_anthropic_has_not_shipped_yet'] = {'utilization': 5, 'resets_at': None}
write('claude_json/unknown_keys.json', {'cachedUsageUtilization': cache(42, extra)})

# ── session 註冊表 ─────────────────────────────────────────────────
def sess(**kw):
    base = {'pid': 4242, 'sessionId': FAKE_SESSION, 'cwd': '/tmp/fixture-project',
            'startedAt': NOW_MS - 600_000, 'procStart': 'Thu Sep 17 15:15:21 2026',
            'version': '2.1.274', 'peerProtocol': 1,
            'peerFeatures': ['notify_idle'], 'kind': 'interactive', 'entrypoint': 'cli',
            'pidDomain': 'darwin', 'messagingSocketPath': '/tmp/cc-socks/4242.sock',
            'name': 'fixture-01', 'nameSource': 'derived', 'nameSince': NOW_MS - 600_000,
            'status': 'busy', 'updatedAt': NOW_MS - 1000, 'statusUpdatedAt': NOW_MS - 1000}
    base.update(kw)
    return base

print('session fixtures:')
write('sessions/busy.json',   sess(status='busy'))
write('sessions/idle.json',   sess(status='idle', pid=4243, sessionId=FAKE_SESSION[:-1] + '2'))
write('sessions/shell.json',  sess(status='shell', pid=4244, sessionId=FAKE_SESSION[:-1] + '3'))
write('sessions/waiting_input.json',
      sess(status='waiting', waitingFor='input needed', pid=4245,
           sessionId=FAKE_SESSION[:-1] + '4'))
write('sessions/waiting_permission.json',
      sess(status='waiting', waitingFor='permission prompt', pid=4246,
           sessionId=FAKE_SESSION[:-1] + '5'))
# 2.1.272 少欄位 —— 同一台機器上實際觀察到的版本歪斜
old = sess(pid=4247, sessionId=FAKE_SESSION[:-1] + '6', version='2.1.272')
for k in ['pidDomain', 'nameSince', 'peerFeatures', 'statusUpdatedAt']:
    old.pop(k, None)
write('sessions/old_version.json', old)
# crash 後 resume：同一個 sessionId 兩筆，保留 startedAt 較新者
write('sessions/dup_old.json', sess(pid=4248, startedAt=NOW_MS - 900_000, name='stale'))
write('sessions/dup_new.json', sess(pid=4249, startedAt=NOW_MS - 300_000, name='current'))
# 讀到寫入中的空檔 —— 0.1 秒間隔快照實測捕捉到過
write('sessions/zero_bytes.json', '')
write('sessions/truncated.json', '{"pid": 4250, "sessionId": "abc", "cw')

# ── agent 樹 ────────────────────────────────────────────────────────
# 真實結構（實測 187 個 meta.json + 所有 journal.jsonl 統計得出）：
#   156× workflow-subagent：**沒有 toolUseId、沒有 parentAgentId**，只能靠目錄路徑
#    12× 一般 agent 深度 1：有 toolUseId
#     9× 一般 agent 深度 2+：有 toolUseId + parentAgentId
#     8× 極簡（Explore）：只有 agentType/description/spawnDepth/toolUseId
#     2× 內建型別：多一個 isBuiltIn
#   journal type：started / result / failed / launched
SESSION = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa'
AGENTS = 'agents'

def meta(rel, obj, mtime=None):
    write(f'{AGENTS}/{rel}', obj)
    if mtime:
        p = os.path.join(FIX, AGENTS, rel)
        os.utime(p, (mtime, mtime))

def blob(rel, text, mtime=None):
    write(f'{AGENTS}/{rel}', text)
    if mtime:
        p = os.path.join(FIX, AGENTS, rel)
        os.utime(p, (mtime, mtime))

SESSION_START = NOW_MS / 1000 - 600          # session 十分鐘前啟動
BEFORE_START  = SESSION_START - 4 * 86400    # 四天前 —— resume 累積的殘骸

print('agent-tree fixtures:')
slug = f'-tmp-fixture-project'
sub = f'{slug}/{SESSION}/subagents'

# 協調者 transcript：帶兩個 Task 的 tool_use
orch = '\n'.join(json.dumps(x) for x in [
    {'type': 'assistant', 'uuid': 'u-1', 'message': {'role': 'assistant', 'content': [
        {'type': 'tool_use', 'id': 'toolu_PLAIN1', 'name': 'Task',
         'input': {'description': 'Explore the codebase'}}]}},
    {'type': 'assistant', 'uuid': 'u-2', 'message': {'role': 'assistant', 'content': [
        {'type': 'tool_use', 'id': 'toolu_STALE', 'name': 'Task',
         'input': {'description': 'A job from a previous resume'}}]}},
])
blob(f'{slug}/{SESSION}.jsonl', orch)

# 一般 agent：深度 1，靠 toolUseId 連到母 transcript
meta(f'{sub}/agent-plain1.meta.json',
     {'agentType': 'general-purpose', 'description': 'Explore the codebase',
      'toolUseId': 'toolu_PLAIN1', 'spawnDepth': 1,
      'requestShape': 'foreground', 'requestNonInteractive': False})
blob(f'{sub}/agent-plain1.jsonl', '{"type":"assistant"}\n', mtime=SESSION_START + 60)

# 一般 agent：深度 2，靠 parentAgentId 連到上面那隻
meta(f'{sub}/agent-plain2.meta.json',
     {'agentType': 'general-purpose', 'description': 'Verify the build',
      'toolUseId': 'toolu_CHILD', 'parentAgentId': 'plain1', 'spawnDepth': 2,
      'requestShape': 'foreground', 'requestNonInteractive': False})
blob(f'{sub}/agent-plain2.jsonl', '{"type":"assistant"}\n', mtime=SESSION_START + 90)

# 極簡形狀（實測 8 筆長這樣）＋ 一個我們沒看過的 key，必須不能讓解析失敗
meta(f'{sub}/agent-minimal.meta.json',
     {'agentType': 'Explore', 'description': 'Read the docs',
      'toolUseId': 'toolu_MIN', 'spawnDepth': 1, 'isBuiltIn': True,
      'aFieldAnthropicHasNotShippedYet': 42})
blob(f'{sub}/agent-minimal.jsonl', '{"type":"assistant"}\n', mtime=SESSION_START + 30)

# resume 累積的殘骸：meta 還在，但 jsonl 比 session 啟動時間還舊
meta(f'{sub}/agent-stale.meta.json',
     {'agentType': 'general-purpose', 'description': 'A job from a previous resume',
      'toolUseId': 'toolu_STALE', 'spawnDepth': 1})
blob(f'{sub}/agent-stale.jsonl', '{"type":"assistant"}\n', mtime=BEFORE_START)

# workflow 扇出：三隻，一隻完成、一隻失敗、一隻還在跑
wf = f'{sub}/workflows/wf_fixture01'
for name, label in [('w1', 'build:alpha'), ('w2', 'build:beta'), ('w3', 'build:gamma')]:
    meta(f'{wf}/agent-{name}.meta.json',
         {'agentType': 'workflow-subagent', 'description': label,
          'workflowPhase': 'Build', 'spawnDepth': 1,
          'requestShape': 'foreground', 'requestNonInteractive': False})
    blob(f'{wf}/agent-{name}.jsonl', '{"type":"assistant"}\n', mtime=SESSION_START + 120)
blob(f'{wf}/journal.jsonl', '\n'.join(json.dumps(x) for x in [
    {'type': 'launched'},
    {'type': 'started', 'key': 'k1', 'agentId': 'w1', 'label': 'build:alpha', 'phase': 'Build'},
    {'type': 'started', 'key': 'k2', 'agentId': 'w2', 'label': 'build:beta', 'phase': 'Build'},
    {'type': 'started', 'key': 'k3', 'agentId': 'w3', 'label': 'build:gamma', 'phase': 'Build'},
    {'type': 'result', 'key': 'k1', 'agentId': 'w1', 'result': {'ok': True}},
    {'type': 'failed', 'key': 'k3', 'agentId': 'w3'},
]))

# 同一個 sessionId 出現在第二個 project slug 底下，但**沒有**兄弟 transcript。
# 實測 11 個 session 目錄中有 1 個是這種情況，判別依據就是兄弟檔在不在。
blob(f'-tmp-other-project/{SESSION}/subagents/.keep', '')

print('\nOK — no credential ever reached disk')

# 被中止的 workflow：journal 裡兩隻 started、永遠等不到 result/failed。
# 權威訊號在 <sessionId>/workflows/<wf_id>.json 的 status：
#   實測值只有 completed / failed / killed 三種終結狀態。
wf2 = f'{sub}/workflows/wf_killed01'
for name in ['k1', 'k2']:
    meta(f'{wf2}/agent-{name}.meta.json',
         {'agentType': 'workflow-subagent', 'description': f'aborted:{name}',
          'workflowPhase': 'Build', 'spawnDepth': 1})
    blob(f'{wf2}/agent-{name}.jsonl', '{"type":"assistant"}\n', mtime=SESSION_START + 120)
blob(f'{wf2}/journal.jsonl', '\n'.join(json.dumps(x) for x in [
    {'type': 'launched'},
    {'type': 'started', 'key': 'k1', 'agentId': 'k1', 'label': 'aborted:k1', 'phase': 'Build'},
    {'type': 'started', 'key': 'k2', 'agentId': 'k2', 'label': 'aborted:k2', 'phase': 'Build'},
]))
# 執行紀錄：一個被中止、一個還活著（沒有終結狀態）
write(f'{AGENTS}/{slug}/{SESSION}/workflows/wf_killed01.json',
      {'runId': 'wf_killed01', 'status': 'killed', 'agentCount': 2})
write(f'{AGENTS}/{slug}/{SESSION}/workflows/wf_fixture01.json',
      {'runId': 'wf_fixture01', 'agentCount': 3})
print('  (+ aborted-workflow fixtures)')

# ── statusLine payload ─────────────────────────────────────────────
# 來源：安裝 tee 之後 Claude Code 真的餵進來的那一份（v2.1.275 實測）。
# 拿不到真實檔案時退回內建樣板 —— 樣板的形狀就是實測那一份，不是猜的。
#
# 實測到、與文件不同的兩點：
#   - 沒有 hook_event_name（hook payload 才有）
#   - 整個 payload 沒有任何帳號識別，所以這個來源做不了 accountUuid 比對
#
# resets_at 是 **Unix epoch 秒的整數**（~/.claude.json 那邊是 ISO-8601 字串）。
NOW_S = NOW_MS // 1000
CACHE_DIR = os.path.expanduser('~/Library/Application Support/QuotaMonster/statusline')

STATUSLINE_TEMPLATE = {
    'session_id': FAKE_SESSION,
    'transcript_path': f'/tmp/fixture-project/{FAKE_SESSION}.jsonl',
    'cwd': '/tmp/fixture-project',
    'scratchpad_dir': '/tmp/fixture-scratchpad',
    'prompt_id': '22222222-2222-4222-8222-222222222222',
    'effort': {'level': 'xhigh'},
    'session_name': 'fixture session',
    'model': {'id': 'claude-opus-5[1m]', 'display_name': 'Opus 5 (1M context)'},
    'workspace': {'current_dir': '/tmp/fixture-project',
                  'project_dir': '/tmp/fixture-project', 'added_dirs': []},
    'version': '2.1.275',
    'output_style': {'name': 'default'},
    'cost': {'total_cost_usd': 32.63, 'total_duration_ms': 1761000,
             'total_api_duration_ms': 400000,
             'total_lines_added': 1105, 'total_lines_removed': 6},
    'context_window': {'total_input_tokens': 260585, 'total_output_tokens': 628,
                       'context_window_size': 1000000,
                       'current_usage': {'input_tokens': 2, 'output_tokens': 628,
                                         'cache_creation_input_tokens': 1196,
                                         'cache_read_input_tokens': 259387},
                       'used_percentage': 26, 'remaining_percentage': 74},
    'exceeds_200k_tokens': True,
    'fast_mode': False,
    'thinking': {'enabled': True},
    'rate_limits': {'five_hour': {'used_percentage': 9, 'resets_at': NOW_S + 7200},
                    'seven_day': {'used_percentage': 42, 'resets_at': NOW_S + 172800}},
}


def deidentify_statusline(p):
    """把真實 payload 換成 fixture 用的假身分，並把時間錨回 NOW_MS。"""
    p = json.loads(json.dumps(p))                       # 深拷貝
    p['session_id'] = FAKE_SESSION
    p['transcript_path'] = f'/tmp/fixture-project/{FAKE_SESSION}.jsonl'
    p['cwd'] = '/tmp/fixture-project'
    p['session_name'] = 'fixture session'
    p['prompt_id'] = '22222222-2222-4222-8222-222222222222'
    if 'scratchpad_dir' in p:
        p['scratchpad_dir'] = '/tmp/fixture-scratchpad'
    if isinstance(p.get('workspace'), dict):
        p['workspace'] = {**p['workspace'], 'current_dir': '/tmp/fixture-project',
                          'project_dir': '/tmp/fixture-project'}
    # resets_at 錨回固定基準，否則 fixture 過幾小時就自己過期了
    rl = p.get('rate_limits')
    if isinstance(rl, dict):
        for key, offset in (('five_hour', 7200), ('seven_day', 172800),
                            ('spend_limit', 2592000)):
            if isinstance(rl.get(key), dict):
                rl[key]['resets_at'] = NOW_S + offset
    p.pop('prompt_cache', None)        # 與額度無關，而且欄位最多、最會變

    # ⚠️ 會變動的數值一律換成固定值。
    # 真實 payload 提供的是**形狀**（有哪些鍵、巢狀怎麼長、未來版本多了什麼），
    # 數值則必須是固定的，否則每跑一次這支腳本，fixture 就變一次，
    # 已經綠燈的測試會無緣無故變紅。實際踩過：重跑之後 7 天從 42 變 44、
    # context 從 27 變 48，三個測試當場失敗。
    if isinstance(p.get('rate_limits'), dict):
        if 'five_hour' in p['rate_limits']:
            p['rate_limits']['five_hour']['used_percentage'] = 9
        if 'seven_day' in p['rate_limits']:
            p['rate_limits']['seven_day']['used_percentage'] = 42
        if 'spend_limit' in p['rate_limits']:
            p['rate_limits']['spend_limit']['used_percentage'] = 62.8
    if isinstance(p.get('context_window'), dict):
        p['context_window'].update({
            'total_input_tokens': 274547, 'total_output_tokens': 628,
            'context_window_size': 1000000,
            'used_percentage': 27, 'remaining_percentage': 73})
        if isinstance(p['context_window'].get('current_usage'), dict):
            p['context_window']['current_usage'] = {
                'input_tokens': 2, 'output_tokens': 628,
                'cache_creation_input_tokens': 5383,
                'cache_read_input_tokens': 269162}
    if isinstance(p.get('cost'), dict):
        p['cost'].update({'total_cost_usd': 33.09, 'total_duration_ms': 1784501,
                          'total_api_duration_ms': 2170148,
                          'total_lines_added': 1105, 'total_lines_removed': 6})
    return p


real_payload = None
if os.path.isdir(CACHE_DIR):
    for name in sorted(os.listdir(CACHE_DIR)):
        if not name.endswith('.json') or name.startswith('_'):
            continue
        try:
            with open(os.path.join(CACHE_DIR, name)) as f:
                real_payload = json.load(f)
            break
        except Exception:
            continue

base_sl = deidentify_statusline(real_payload) if real_payload else STATUSLINE_TEMPLATE
print('statusline fixtures (%s):' % ('真實 payload' if real_payload else '內建樣板'))


def sl(**overrides):
    p = json.loads(json.dumps(base_sl))
    for k, v in overrides.items():
        if v is _DROP:
            p.pop(k, None)
        else:
            p[k] = v
    return p


class _DropSentinel:
    pass


_DROP = _DropSentinel()

write('statusline/live.json', sl())

# 首次 API 回應之前：整個 rate_limits 缺席。缺席 ≠ 0%
write('statusline/no_rate_limits.json', sl(rate_limits=_DROP))

# 窗口重置後 Claude Code 直接把它從 payload 拿掉（二進位 MSn 過濾）
write('statusline/window_dropped.json',
      sl(rate_limits={'seven_day': base_sl['rate_limits']['seven_day']}))

# /compact 之後、第一次 API 呼叫之前
write('statusline/null_context.json',
      sl(context_window={**base_sl['context_window'], 'current_usage': None,
                         'used_percentage': None, 'remaining_percentage': None}))

# resets_at 已經過去 —— 理論上 Claude Code 會先擋掉，我們自己再擋一次
write('statusline/reset_passed.json',
      sl(rate_limits={'five_hour': {'used_percentage': 77, 'resets_at': NOW_S - 60},
                      'seven_day': base_sl['rate_limits']['seven_day']}))

# wQe(t) = Math.round(t*1000)/10 —— 會吐出一位小數。用 intValue 讀會截成 30
write('statusline/fractional.json',
      sl(rate_limits={'five_hour': {'used_percentage': 30.6, 'resets_at': NOW_S + 7200},
                      'seven_day': {'used_percentage': 41.25, 'resets_at': NOW_S + 172800}}))

# gateway 才有的第三個窗口
write('statusline/spend_limit.json',
      sl(rate_limits={**base_sl['rate_limits'],
                      'spend_limit': {'used_percentage': 62.8, 'resets_at': NOW_S + 2592000}}))

# 未來版本新增的鍵不可造成解析失敗
write('statusline/unknown_keys.json',
      sl(a_key_anthropic_has_not_shipped_yet={'nested': [1, 2, 3]},
         rate_limits={**base_sl['rate_limits'],
                      'a_window_we_have_never_seen': {'used_percentage': 5,
                                                      'resets_at': NOW_S + 60}}))

# 連 context_window 都沒有（未來版本移除、或非互動 session）
write('statusline/minimal.json', sl(rate_limits=_DROP, context_window=_DROP))

# 第二個 session —— 多 session 的 context 壓力要分得開
write('statusline/other_session.json',
      sl(session_id='11111111-1111-4111-8111-111111111112',
         cwd='/tmp/other-project',
         context_window={**base_sl['context_window'], 'used_percentage': 71,
                         'remaining_percentage': 29}))

# 荒謬的數值不可以讓整個 app 當掉。Int(Double) 在 Swift 裡超出範圍會 trap，
# 而 1e20 是完全合法的 JSON 數字。
write('statusline/absurd_percent.json',
      sl(rate_limits={'five_hour': {'used_percentage': 1e20, 'resets_at': NOW_S + 7200},
                      'seven_day': {'used_percentage': -5, 'resets_at': NOW_S + 172800}}))

# 型別不對（字串而不是數字）—— 未來版本改型別時不可以變成一個假的數字
write('statusline/string_percent.json',
      sl(rate_limits={'five_hour': {'used_percentage': '9', 'resets_at': NOW_S + 7200}}))

# resets_at 遠在十年後：二進位的 MSn 過濾同時有下界與上界
# （resets_at > now && resets_at < now + 一年），我們只實作了下界
write('statusline/far_future_reset.json',
      sl(rate_limits={'five_hour': {'used_percentage': 9, 'resets_at': NOW_S + 10 * 31536000},
                      'seven_day': base_sl['rate_limits']['seven_day']}))

# 只剩 spend_limit（另外兩個窗口都已重置被丟掉）
write('statusline/spend_only.json',
      sl(rate_limits={'spend_limit': {'used_percentage': 62.8, 'resets_at': NOW_S + 2592000}}))

# 被 SIGKILL 打斷的寫入 / 讀到寫入中的空檔
write('statusline/truncated.json', json.dumps(base_sl)[:150])
write('statusline/zero_bytes.json', '')

print('\nOK — no credential ever reached disk（statusline 已去識別化）')

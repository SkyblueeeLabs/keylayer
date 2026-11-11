#!/usr/bin/env node
// 共享规格的「可执行参考实现」：Node 上即可验证 40 项回归用例。
// Windows (Rust) 与 macOS (Swift) 两端实现都应与此参考行为一致。
// 用法: node spec/verify.mjs        （也可被 scripts/check.mjs import）
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
export const spec = JSON.parse(fs.readFileSync(path.join(here, 'keybindings.json'), 'utf8'));

/** 参考实现：输入按键与修饰键状态，输出动作。与平台键码无关。 */
export function remap({ key, mods = [], held = [], cmdOnly = false, frontApp = null, enabled = true }) {
  if (!enabled) return { action: 'pass', shift: false, command: false };
  const has = (m) => mods.includes(m) || held.includes(m);

  // 右 Ctrl + b/g：打开固定网址（AHK 的 >^ 前缀）
  if (has('rightCtrl')) {
    if (key === 'b') return { action: 'open-url:baidu', shift: false, command: false };
    if (key === 'g') return { action: 'open-url:google', shift: false, command: false };
    return { action: 'pass', shift: false, command: false };
  }

  // 右 Alt 改 Shift（AHK 33 行 RAlt::Shift）
  if (key === 'RightAlt') return { action: 'shift-down', shift: false, command: false };

  // Control 组合一律放行，避免误伤系统快捷键
  if (has('ctrl')) return { action: 'pass', shift: false, command: false };

  const triggered = cmdOnly ? has('cmd') : (has('cmd') || has('alt'));
  if (!triggered) return { action: 'pass', shift: false, command: false };

  const binding = spec.bindings.find((b) => b.key === key);
  if (!binding) return { action: 'pass', shift: false, command: false };

  // delete-line 在 VS Code 内放行原键（AHK 64 行 WinActive）
  if (binding.action === 'delete-line' && frontApp && /^Code/i.test(frontApp)) {
    return { action: 'pass', shift: false, command: false };
  }

  return {
    action: binding.action,
    shift: has('shift'),
    command: binding.action === 'line-start' || binding.action === 'line-end',
  };
}

/** 跑完共享规格里的全部用例，返回结果（不退出进程，便于被检查器调用）。 */
export function runCases() {
  const failures = [];
  for (const c of spec.cases) {
    const got = remap(c);
    const okAction = got.action === c.expect;
    const okShift = c.shift === undefined || got.shift === c.shift;
    if (okAction && okShift) continue;
    failures.push(`${c.name}: got=${JSON.stringify(got)} expect=${JSON.stringify(c)}`);
  }
  return { total: spec.cases.length, passed: spec.cases.length - failures.length, failures };
}

const isMain = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  const r = runCases();
  console.log(`共享规格 v${spec.version}: ${spec.bindings.length} 条映射, ${spec.cases.length} 项用例`);
  const coverage = spec.scriptCoverage ?? [];
  const tally = {};
  for (const c of coverage) tally[c.status] = (tally[c.status] || 0) + 1;
  console.log(`原脚本 ${coverage.length} 条规则覆盖: ${Object.entries(tally).map(([k, v]) => `${k}=${v}`).join('  ')}`);
  for (const f of r.failures) console.log(`FAIL  ${f}`);
  console.log(r.failures.length === 0 ? `\n${r.passed}/${r.total} 通过` : `\n${r.failures.length} 项失败`);
  process.exit(r.failures.length === 0 ? 0 : 1);
}

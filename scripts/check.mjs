#!/usr/bin/env node
// 双端一致性检查：跑共享用例 + 校验生成代码是否最新 + 确认三端确实引用了生成代码。
// 用法: node scripts/check.mjs   （CI 与提交前都跑这个）
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { runCases } from '../spec/verify.mjs';
import { renderAll, specHash } from './gen-sources.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
let failed = 0;

// 1) 共享规格的回归用例
const r = runCases();
if (r.failures.length) {
  for (const f of r.failures) console.log(`FAIL  ${f}`);
  failed += 1;
} else {
  console.log(`OK    共享用例 ${r.passed}/${r.total}`);
}

// 2) 生成代码与规格是否一致
for (const f of renderAll()) {
  const target = path.join(ROOT, f.path);
  if (!fs.existsSync(target)) {
    console.log(`FAIL  缺少生成文件 ${f.path}（运行 npm run spec）`);
    failed += 1;
    continue;
  }
  if (fs.readFileSync(target, 'utf8') !== f.content) {
    console.log(`FAIL  生成文件已过期 ${f.path}（运行 npm run spec）`);
    failed += 1;
  } else {
    console.log(`OK    生成文件最新 ${f.path}`);
  }
}

// 3) 三端是否真的引用了生成代码（防止「生成了但没用」）
const refs = [
  ['src/KeyLayerCore.swift', 'Generated.macBinding'],
  ['windows/src-tauri/src/lib.rs', 'generated::by_key'],
  ['windows/src-tauri/src/lib.rs', 'mod generated;'],
  ['ui/index.html', 'bindings.js'],
  ['ui/index.html', 'tokens.css'],
  ['ui/index.html', 'var(--panel-width)'],
  ['src/KeyLayerApp.swift', 'Tokens.panelWidth'],
  ['src/KeyLayerApp.swift', 'Generated.keyCapRows'],
];
for (const [file, needle] of refs) {
  const p = path.join(ROOT, file);
  const ok = fs.existsSync(p) && fs.readFileSync(p, 'utf8').includes(needle);
  if (!ok) {
    console.log(`FAIL  ${file} 未引用 ${needle}`);
    failed += 1;
  } else {
    console.log(`OK    引用检查 ${file} -> ${needle}`);
  }
}

console.log(`\nspec-hash ${specHash} · ${failed === 0 ? '全部通过' : `${failed} 项失败`}`);
process.exit(failed === 0 ? 0 : 1);

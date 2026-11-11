#!/usr/bin/env node
// 规格驱动的代码生成：spec/keybindings.json 是唯一真相源，
// 由此生成 Swift / Rust / JS 三端的键位数据，避免四处手改。
// 用法: node scripts/gen-sources.mjs
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const SPEC_PATH = path.join(ROOT, 'spec/keybindings.json');
const TOKENS_PATH = path.join(ROOT, 'ui/tokens.json');
const raw = fs.readFileSync(SPEC_PATH, 'utf8');
const tokensRaw = fs.readFileSync(TOKENS_PATH, 'utf8');
export const spec = JSON.parse(raw);
export const tokens = JSON.parse(tokensRaw);
// 行为规格 + 设计令牌共同决定生成内容，任一方变化都会让 hash 改变
export const specHash = crypto.createHash('sha256').update(raw + tokensRaw).digest('hex').slice(0, 12);

// 键帽网格布局（双端 UI 共用）
const KEY_CAP_ROWS = [['u', 'i', 'o'], ['j', 'k', 'l'], ['d', 'h', 'y'], ['n', 'm', 'ralt']];

function caps() {
  const out = {};
  for (const b of spec.bindings) {
    out[b.key] = { label: b.key.toUpperCase(), desc: b.label, group: b.group };
  }
  const ralt = spec.modifierRemap.find((m) => m.from === 'RightAlt');
  out.ralt = { label: '右Alt', desc: '⇧', group: 'modifier', win: ralt?.win ?? 165, mac: ralt?.mac ?? 61 };
  return out;
}

const q = (s) => JSON.stringify(String(s));
const header = (comment) => [
  `${comment} 自动生成 — 请勿手动编辑`,
  `${comment} 来源: spec/keybindings.json`,
  `${comment} 重新生成: npm run spec`,
  `${comment} spec-hash: ${specHash}`,
  '',
];

function swiftSource() {
  const L = header('//');
  L.push('struct GenBinding {',
    '    let key: String',
    '    let macKeyCode: Int64',
    '    let winVK: Int',
    '    let action: String',
    '    let label: String',
    '    let group: String',
    '}',
    '',
    'enum Generated {',
    '    static let bindings: [GenBinding] = [');
  for (const b of spec.bindings) {
    L.push(`        GenBinding(key: ${q(b.key)}, macKeyCode: ${b.mac}, winVK: ${b.win}, action: ${q(b.action)}, label: ${q(b.label)}, group: ${q(b.group)}),`);
  }
  L.push('    ]', '', '    static let actionKeyCodes: [String: (mac: Int64, win: Int, needsCommand: Bool)] = [');
  for (const [name, v] of Object.entries(spec.actionKeyCodes)) {
    L.push(`        ${q(name)}: (${v.mac}, ${v.win}, ${v.macMod === 'command'}),`);
  }
  L.push('    ]', '', '    static let urlActions: [(mac: Int64, win: Int, url: String)] = [');
  for (const u of spec.urlActions) {
    L.push(`        (${u.mac}, ${u.win}, ${q(u.url)}),`);
  }
  L.push('    ]', '', '    static let vscodeBundleIDs: Set<String> = [');
  for (const id of spec.appWhitelist.macOSBundleIDs) L.push(`        ${q(id)},`);
  L.push('    ]', '', '    static let keyCapRows: [[(id: String, label: String, desc: String, group: String)]] = [');
  const c = caps();
  for (const row of KEY_CAP_ROWS) {
    const items = row.map((id) => `(${q(id)}, ${q(c[id].label)}, ${q(c[id].desc)}, ${q(c[id].group)})`).join(', ');
    L.push(`        [${items}],`);
  }
  L.push('    ]', '',
    '    static func macBinding(_ code: Int64) -> GenBinding? {',
    '        bindings.first { $0.macKeyCode == code }',
    '    }',
    '    static func winBinding(_ vk: Int) -> GenBinding? {',
    '        bindings.first { $0.winVK == vk }',
    '    }',
    '}');
  return L.join('\n') + '\n';
}

function rustSource() {
  const L = header('//');
  L.push('#[allow(dead_code)]',
    '#[derive(Clone, Copy)]',
    'pub struct Binding {',
    "    pub key: &'static str,",
    '    pub win_vk: u8,',
    '    pub mac_key: i64,',
    "    pub action: &'static str,",
    "    pub label: &'static str,",
    "    pub group: &'static str,",
    '}',
    '',
    '#[rustfmt::skip]',
    'pub static BINDINGS: &[Binding] = &[');
  for (const b of spec.bindings) {
    L.push(`    Binding { key: ${q(b.key)}, win_vk: ${b.win}, mac_key: ${b.mac}, action: ${q(b.action)}, label: ${q(b.label)}, group: ${q(b.group)} },`);
  }
  L.push('];', '',
    "pub fn by_key(key: &str) -> Option<&'static Binding> {",
    '    BINDINGS.iter().find(|b| b.key == key)',
    '}',
    '',
    '#[allow(dead_code)]',
    "pub fn by_win_vk(vk: u8) -> Option<&'static Binding> {",
    '    BINDINGS.iter().find(|b| b.win_vk == vk)',
    '}',
    '',
    '#[rustfmt::skip]',
    "pub static URL_ACTIONS: &[(&str, u8, &str)] = &[");
  for (const u of spec.urlActions) {
    L.push(`    (${q(u.key)}, ${u.win}, ${q(u.url)}),`);
  }
  L.push('];', '',
    "pub static WHITELIST_PREFIXES: &[&str] = &[");
  for (const n of spec.appWhitelist.windowsProcessNames) {
    L.push(`    ${q(n.replace(/\.exe$/i, '').toLowerCase())},`);
  }
  L.push('];', '',
    '#[rustfmt::skip]',
    "pub fn vk_to_key(vk: u8) -> &'static str {",
    '    match vk {');
  for (const b of spec.bindings) L.push(`        ${b.win} => ${q(b.key)},`);
  for (const u of spec.urlActions) L.push(`        ${u.win} => ${q(u.key)},`);
  for (const m of spec.modifierRemap ?? []) L.push(`        ${m.win} => ${q(m.from)},`);
  L.push('        _ => ""', '    }', '}');
  return L.join('\n') + '\n';
}

function jsSource() {
  const L = header('//');
  L.push('window.KeyLayerBindings = {',
    `  specHash: ${q(specHash)},`,
    `  rows: ${JSON.stringify(KEY_CAP_ROWS)},`,
    `  caps: ${JSON.stringify(caps(), null, 2)}`,
    '};');
  return L.join('\n') + '\n';
}

function cssTokensSource() {
  const L = [
    '/* 自动生成 — 请勿手动编辑 */',
    '/* 来源: ui/tokens.json */',
    '/* 重新生成: npm run spec */',
    `/* spec-hash: ${specHash} */`,
    '',
  ];
  L.push(':root {');
  for (const [k, v] of Object.entries(tokens.cssVars)) L.push(`  ${k}: ${v};`);
  L.push('}');
  return L.join('\n') + '\n';
}

function rgbTuple(hex) {
  const h = String(hex).replace('#', '');
  const r = (parseInt(h.slice(0, 2), 16) / 255).toFixed(3);
  const g = (parseInt(h.slice(2, 4), 16) / 255).toFixed(3);
  const b = (parseInt(h.slice(4, 6), 16) / 255).toFixed(3);
  return `Color(red: ${r}, green: ${g}, blue: ${b})`;
}

function swiftTokensSource() {
  const L = [
    '// 自动生成 — 请勿手动编辑',
    '// 来源: ui/tokens.json',
    '// 重新生成: npm run spec',
    `// spec-hash: ${specHash}`,
    '',
  ];
  L.push('import SwiftUI', '', 'enum Tokens {');
  for (const [k, v] of Object.entries(tokens.metrics)) {
    L.push(`    static let ${k}: CGFloat = ${v}`);
  }
  for (const [k, v] of Object.entries(tokens.swiftColors)) {
    L.push(`    static let ${k} = ${rgbTuple(v)}`);
  }
  L.push('',
    '    static func groupAccent(_ group: String) -> Color {',
    '        switch group {');
  for (const [g, colorName] of Object.entries(tokens.groupColors)) {
    L.push(`        case ${q(g)}: return ${colorName}`);
  }
  L.push('        default: return ink', '        }', '    }', '',
    '    static func groupSoft(_ group: String) -> Color {',
    '        switch group {');
  for (const [g, colorName] of Object.entries(tokens.groupColors)) {
    L.push(`        case ${q(g)}: return ${colorName}Soft`);
  }
  L.push('        default: return ink', '        }', '    }', '}');
  return L.join('\n') + '\n';
}

export const outputs = [
  { path: 'src/Generated.swift', render: swiftSource },
  { path: 'src/GeneratedTokens.swift', render: swiftTokensSource },
  { path: 'windows/src-tauri/src/generated.rs', render: rustSource },
  { path: 'ui/bindings.js', render: jsSource },
  { path: 'ui/tokens.css', render: cssTokensSource },
];

export function renderAll() {
  return outputs.map((o) => ({ path: o.path, content: o.render() }));
}

export function writeAll(files = renderAll()) {
  for (const f of files) {
    const target = path.join(ROOT, f.path);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.writeFileSync(target, f.content, 'utf8');
  }
  return files;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const files = writeAll();
  console.log(`规格 ${specHash}: 生成 ${files.length} 份平台代码`);
  for (const f of files) console.log('  ', f.path);
}

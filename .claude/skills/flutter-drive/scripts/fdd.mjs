#!/usr/bin/env node
// 常驻守护进程：保持 VM Service 连接，向应用注入 agent.dart，串行执行 fd.mjs 转发来的命令。
// 由 fd.mjs 按需拉起；脚本文件变化、空闲 30 分钟后自动退出。
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, statSync, unlinkSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:net';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = process.cwd();
const STATE = join(ROOT, '.dart_tool/flutter_drive');
const SOCK = join(STATE, 'fd.sock');
const LOG = join(STATE, 'run.log');
const SHOTS = join(STATE, 'shots');
const EVAL_LIB = 'package:flutter/src/widgets/binding.dart';
const VERSION = process.argv[2];
const IDLE_EXIT_MS = 30 * 60 * 1000;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
class UserError extends Error {}
const fail = (msg) => { throw new UserError(msg); };

// ---------- 代理脚本 ----------
const agentSrc = readFileSync(join(HERE, 'agent.dart'), 'utf8');
const AGENT_VER = createHash('sha1').update(agentSrc).digest('hex').slice(0, 8);
const AGENT_EXPR = agentSrc
  .split('\n')
  .filter((l) => !l.trim().startsWith('//'))
  .join(' ')
  .replace(/\s+/g, ' ')
  .replace('__FD_VERSION__', AGENT_VER);

// ---------- VM Service ----------
let ws, wsUri, isolateId, evalLibId, installed = false, nextId = 0;
const pending = new Map();

function rpc(method, params = {}) {
  if (!ws || ws.readyState !== WebSocket.OPEN) fail('与应用的连接已断开，重新 launch');
  return new Promise((res, rej) => {
    const id = String(++nextId);
    pending.set(id, { res, rej });
    ws.send(JSON.stringify({ jsonrpc: '2.0', id, method, params }));
  });
}

async function connect(uri) {
  ws?.close();
  ws = new WebSocket(uri);
  wsUri = uri;
  isolateId = null;
  ws.onmessage = (e) => {
    const m = JSON.parse(e.data);
    const p = pending.get(m.id);
    if (!p) return;
    pending.delete(m.id);
    m.error ? p.rej(new UserError(m.error.data?.details ?? JSON.stringify(m.error).slice(0, 800))) : p.res(m.result);
  };
  ws.onclose = () => {
    for (const p of pending.values()) p.rej(new UserError('应用已断开（退出或崩溃？用 logs 查看）'));
    pending.clear();
  };
  await new Promise((res, rej) => {
    ws.onopen = res;
    ws.onerror = () => rej(new UserError('连不上 VM Service（应用已退出？重新 launch）'));
  });
}

function currentUri() {
  const f = join(STATE, 'vm_uri');
  if (!existsSync(f)) fail('没有运行中的会话：先执行 launch.sh');
  const u = readFileSync(f, 'utf8').trim();
  return u.endsWith('/ws') ? u : u.replace(/^http/, 'ws').replace(/\/?$/, '/ws');
}

// 每次请求前确认：连接指向最新的会话、isolate 未因热重启更换、代理已注入
async function ensureReady() {
  const uri = currentUri();
  if (!ws || ws.readyState !== WebSocket.OPEN || uri !== wsUri) await connect(uri);
  const vm = await rpc('getVM');
  const iso = vm.isolates.find((i) => i.name.includes('main')) ?? vm.isolates[0];
  if (iso.id !== isolateId) {
    isolateId = iso.id;
    evalLibId = null;
    installed = false;
  }
  if (installed) return;
  const info = await rpc('getIsolate', { isolateId });
  evalLibId = info.libraries.find((l) => l.uri === EVAL_LIB).id;
  if (!info.extensionRPCs?.includes(`ext.fd.${AGENT_VER}.snap`)) {
    for (let i = 0; i < 40 && (await evaluate('WidgetsBinding.instance.firstFrameRasterized')) !== 'true'; i++) await sleep(250);
    await evaluate(AGENT_EXPR);
  }
  installed = true;
}

async function evaluate(expr, lib) {
  let targetId = evalLibId;
  if (lib) {
    targetId = (await rpc('getIsolate', { isolateId })).libraries.find((l) => l.uri.includes(lib))?.id;
    if (!targetId) fail(`找不到库：${lib}`);
  }
  const r = await rpc('evaluate', { isolateId, targetId, expression: expr.replace(/\n\s*/g, ' '), disableBreakpoints: true });
  if (r.type === '@Error' || r.type === 'Error') fail(r.message);
  if (r.valueAsStringIsTruncated) {
    return (await rpc('getObject', { isolateId, objectId: r.id, offset: 0, count: r.length })).valueAsString;
  }
  return r.valueAsString ?? `${r.kind} ${r.class?.name ?? ''}`;
}

// 调用代理扩展；代理以 ERR/STALE/NONE 开头的结果视为失败
async function agent(name, params = {}) {
  const clean = Object.fromEntries(Object.entries(params).filter(([, v]) => v !== undefined).map(([k, v]) => [k, String(v)]));
  const { r } = await rpc(`ext.fd.${AGENT_VER}.${name}`, { isolateId, ...clean });
  if (/^(ERR|STALE|NONE)/.test(r)) fail(r.replace(/^ERR /, ''));
  return r;
}

// ---------- 截图 ----------
let rootWidget;
async function shot(out, name = 'shot', { scale = 1, rect } = {}) {
  mkdirSync(SHOTS, { recursive: true });
  await agent('settle');
  const [w, h] = (await agent('info')).match(/(\d+)x(\d+)/).slice(1).map(Number);
  if (!rootWidget || rootWidget.iso !== isolateId) {
    const r = await rpc('ext.flutter.inspector.getRootWidget', { isolateId, objectGroup: 'fd' });
    rootWidget = { iso: isolateId, id: r.result.valueId };
  }
  // 根节点边界是物理像素，输出尺寸由 width/height 决定；区域截图按 2x 取图后裁剪保留细节
  const k = rect ? 2 : scale;
  const r = await rpc('ext.flutter.inspector.screenshot', {
    isolateId, id: rootWidget.id, width: String(w * k), height: String(h * k), margin: '0', maxPixelRatio: '10', debugPaint: 'false',
  });
  if (!r.result) fail('截图失败');
  const file = resolve(SHOTS, name.endsWith('.png') ? name : `${name}.png`);
  writeFileSync(file, Buffer.from(r.result, 'base64'));
  if (rect) {
    const [x, y, cw, ch] = rect.split(',').map((n) => Math.round(+n * 2));
    execFileSync('sips', ['-c', String(ch), String(cw), '--cropOffset', String(y), String(x), file], { stdio: 'ignore' });
  }
  out(`${file}  (${rect ? `区域 ${rect} @2x` : `${w}x${h} ×${scale}`})`);
}

// ---------- 日志与热重载 ----------
function logs(out, { all = false, grep, n = 80 } = {}) {
  if (!existsSync(LOG)) fail('没有日志：先执行 launch.sh');
  const posFile = join(STATE, 'log_pos');
  const size = statSync(LOG).size;
  let pos = all || !existsSync(posFile) ? 0 : +readFileSync(posFile, 'utf8');
  if (pos > size) pos = 0;
  writeFileSync(posFile, String(size));
  let lines = readFileSync(LOG).subarray(pos).toString().split('\n').filter(Boolean);
  if (grep) lines = lines.filter((l) => new RegExp(grep, 'i').test(l));
  if (lines.length > n) out(`…省略 ${lines.length - n} 行`);
  out(lines.slice(-n).join('\n') || '(无新日志)');
}

async function reload(out, full) {
  const pidFile = join(STATE, 'pid');
  if (!existsSync(pidFile)) fail('flutter run 未在运行，先 launch');
  const start = statSync(LOG).size;
  process.kill(+readFileSync(pidFile, 'utf8'), full ? 'SIGUSR2' : 'SIGUSR1');
  for (let i = 0; i < 240; i++) {
    await sleep(250);
    const t = readFileSync(LOG).subarray(start).toString();
    const done = t.match(/(Reloaded|Restarted)[^\n]*/);
    if (done) return out(done[0]);
    if (/Try again after fixing|compilation failed/i.test(t)) fail(t.trim().split('\n').slice(-30).join('\n'));
  }
  fail('热重载超时，用 logs 查看');
}

function show(out) {
  if (process.platform !== 'darwin') return out('show 仅支持 macOS');
  const pid = execFileSync('pgrep', ['-n', '-f', '\\.app/Contents/MacOS/']).toString().trim();
  const exe = execFileSync('ps', ['-o', 'comm=', '-p', pid]).toString().trim();
  const app = exe.match(/^(.*?\.app)\//)?.[1];
  const bid = execFileSync('defaults', ['read', `${app}/Contents/Info`, 'CFBundleIdentifier']).toString().trim();
  execFileSync('osascript', ['-e', `tell application id "${bid}" to activate`]);
  out('窗口已前置');
}

// ---------- 命令 ----------
const opt = (args, name, def) => {
  const i = args.indexOf(name);
  if (i < 0) return def;
  const v = args[i + 1];
  args.splice(i, 2);
  return v;
};
const flag = (args, name) => {
  const i = args.indexOf(name);
  if (i >= 0) args.splice(i, 1);
  return i >= 0;
};
const isNum = (s) => /^-?\d+(\.\d+)?$/.test(s);
// 目标参数：「x y」坐标，或 @n / 文本
function target(args, numericTail = 0) {
  const head = args.slice(0, args.length - numericTail);
  if (head.length === 2 && head.every(isNum)) return { x: head[0], y: head[1] };
  if (!head.length) fail('缺少目标：@n、文本或 x y');
  return { target: head.join(' ') };
}

const OFFLINE = new Set(['logs', 'errors', 'reload', 'restart', 'stop', 'show']);

async function run(out, cmd, args) {
  switch (cmd) {
    case 'snap':
      return out(await agent('snap', { q: args.filter((a) => !a.startsWith('--')).join(' '), all: flag(args, '--all') ? 1 : 0, rect: flag(args, '--rect') ? 1 : 0 }));
    case 'tap':
      return out(await agent('tap', { ...target(args), hold: opt(args, '--hold') }));
    case 'longpress':
      return out(await agent('tap', { ...target(args), hold: 700 }));
    case 'drag': {
      // drag <目标> dx dy [--ms 300]
      const ms = opt(args, '--ms');
      const [dx, dy] = args.splice(-2);
      return out(await agent('drag', { ...target(args), dx, dy, ms }));
    }
    case 'hover':
      return out(await agent('hover', target(args)));
    case 'scroll': {
      // scroll <目标> dy
      const dy = args.pop();
      return out(await agent('scroll', { ...target(args), dy }));
    }
    case 'type': {
      const submit = flag(args, '--submit');
      return out(await agent('type', { text: args.join(' '), submit: submit ? 1 : 0 }));
    }
    case 'back':
      return out(await agent('back'));
    case 'shot':
      return shot(out, args[0], { scale: +opt(args, '--scale', 1), rect: opt(args, '--rect') });
    case 'burst': {
      // burst <名> <间隔ms> <帧数> [--scale s | --rect x,y,w,h]
      const scale = +opt(args, '--scale', 0.5);
      const rect = opt(args, '--rect');
      const [name = 'burst', every = 100, count = 6] = args;
      for (let i = 0; i < +count; i++) {
        const t = Date.now();
        await shot(out, `${name}_${i}`, { scale, rect });
        await sleep(Math.max(0, +every - (Date.now() - t)));
      }
      return;
    }
    case 'slow':
      await rpc('ext.flutter.timeDilation', { isolateId, timeDilation: String(args[0] ?? 5) });
      return out(`timeDilation ${args[0] ?? 5}`);
    case 'wait':
      await agent('settle', { ms: args[0] ?? 300 });
      return;
    case 'info':
      return out(await agent('info'));
    case 'eval': {
      const lib = opt(args, '--lib');
      return out(await evaluate(args.join(' '), lib));
    }
    case 'show':
      return show(out);
    case 'logs':
      return logs(out, { all: flag(args, '--all'), grep: opt(args, '--grep'), n: +opt(args, '-n', 80) });
    case 'errors':
      return logs(out, { all: flag(args, '--all'), grep: 'exception|error|══|failed|overflow', n: 60 });
    case 'reload':
      return reload(out, false);
    case 'restart':
      return reload(out, true);
    case 'stop': {
      const f = join(STATE, 'pid');
      if (existsSync(f)) process.kill(+readFileSync(f, 'utf8'), 'SIGINT');
      return out('stopped');
    }
    default:
      fail(`未知命令：${cmd}`);
  }
}

async function handle(argv) {
  const lines = [];
  const out = (s) => lines.push(s);
  const chain = [[]];
  for (const a of argv) (a === '--' ? chain.push([]) : chain.at(-1).push(a));
  try {
    if (chain.some(([c]) => !OFFLINE.has(c))) await ensureReady();
    for (const [cmd, ...args] of chain) await run(out, cmd, args);
    return { out: lines.join('\n'), code: 0 };
  } catch (e) {
    lines.push(e instanceof UserError ? `ERR ${e.message}` : `ERR ${e.stack ?? e}`);
    return { out: lines.join('\n'), code: 1 };
  }
}

// ---------- 服务 ----------
mkdirSync(STATE, { recursive: true });
if (existsSync(SOCK)) unlinkSync(SOCK);
let queue = Promise.resolve();
let idleTimer;
const touch = () => {
  clearTimeout(idleTimer);
  idleTimer = setTimeout(shutdown, IDLE_EXIT_MS);
};
function shutdown() {
  try { unlinkSync(SOCK); } catch {}
  process.exit(0);
}

const server = createServer((sock) => {
  let buf = '';
  sock.on('data', (d) => {
    buf += d;
    const nl = buf.indexOf('\n');
    if (nl < 0) return;
    const req = JSON.parse(buf.slice(0, nl));
    touch();
    if (req.version !== VERSION) {
      // 脚本已更新：让客户端重启守护进程
      sock.end(JSON.stringify({ restart: true }) + '\n');
      server.close();
      return setTimeout(shutdown, 50);
    }
    queue = queue.then(async () => sock.end(JSON.stringify(await handle(req.argv)) + '\n'));
  });
  sock.on('error', () => {});
});
server.listen(SOCK, () => console.log(`fdd ${VERSION} listening`));
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
touch();

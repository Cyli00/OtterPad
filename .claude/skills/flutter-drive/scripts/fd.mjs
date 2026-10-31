#!/usr/bin/env node
// fdd.mjs 守护进程的客户端：把命令行转发过去并打印结果。守护进程不在或脚本已更新时自动（重新）拉起。
// 用法见上级目录的 SKILL.md。
import { spawn, execFileSync } from 'node:child_process';
import { closeSync, existsSync, mkdirSync, openSync, statSync, unlinkSync } from 'node:fs';
import { connect } from 'node:net';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = execFileSync('git', ['rev-parse', '--show-toplevel']).toString().trim();
const STATE = join(ROOT, '.dart_tool/flutter_drive');
const SOCK = join(STATE, 'fd.sock');
const DAEMON = join(HERE, 'fdd.mjs');
// 守护进程或代理脚本任一改动都会换版本，触发重启
const VERSION = ['fdd.mjs', 'agent.dart'].map((f) => statSync(join(HERE, f)).mtimeMs).join('-');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function request(argv) {
  return new Promise((res, rej) => {
    const s = connect(SOCK);
    let buf = '';
    s.on('connect', () => s.write(JSON.stringify({ version: VERSION, argv }) + '\n'));
    s.on('data', (d) => (buf += d));
    s.on('end', () => {
      try { res(JSON.parse(buf)); } catch { rej(new Error('守护进程无响应，查看 .dart_tool/flutter_drive/fdd.log')); }
    });
    s.on('error', rej);
  });
}

async function startDaemon() {
  mkdirSync(STATE, { recursive: true });
  if (existsSync(SOCK)) unlinkSync(SOCK);
  const log = openSync(join(STATE, 'fdd.log'), 'a');
  spawn(process.execPath, [DAEMON, VERSION], { cwd: ROOT, detached: true, stdio: ['ignore', log, log] }).unref();
  closeSync(log);
  for (let i = 0; i < 50 && !existsSync(SOCK); i++) await sleep(60);
}

const argv = process.argv.slice(2);
if (!argv.length) {
  console.error('用法：fd.mjs <命令> [参数] [-- <命令> …]，见 SKILL.md');
  process.exit(1);
}
let res;
for (let attempt = 0; attempt < 3 && !res; attempt++) {
  try {
    res = await request(argv);
    if (res.restart) {
      res = undefined;
      await sleep(150);
      await startDaemon();
    }
  } catch (e) {
    if (attempt === 2 || !['ENOENT', 'ECONNREFUSED'].includes(e.code)) {
      console.error(`ERR ${e.message}`);
      process.exit(1);
    }
    await startDaemon();
  }
}
if (res.out) console.log(res.out);
process.exitCode = res.code;

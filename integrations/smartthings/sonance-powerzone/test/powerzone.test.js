'use strict';

const assert = require('node:assert/strict');
const { spawn, spawnSync } = require('node:child_process');
const net = require('node:net');
const path = require('node:path');
const test = require('node:test');

function findLua() {
  const candidates = [
    process.env.LUA_BIN,
    '/opt/homebrew/opt/lua@5.4/bin/lua',
    'lua5.3',
    'lua',
  ].filter(Boolean);
  for (const candidate of candidates) {
    if (spawnSync(candidate, ['-v'], { stdio: 'ignore' }).status === 0) return candidate;
  }
  throw new Error('Lua 5.3-compatible interpreter not found');
}

class PowerZoneTestService {
  constructor({ rejectCommand = null } = {}) {
    this.rejectCommand = rejectCommand;
    this.commands = [];
    this.values = new Map([
      ['API_VERSION', '"1.5"'],
      ['SYSTEM.DEVICE.SERIAL', '"PZ-TEST-0001"'],
      ['SYSTEM.DEVICE.VENDOR_NAME', '"Sonance"'],
      ['SYSTEM.DEVICE.MODEL_NAME', '"PowerZone Connect 254"'],
      ['SYSTEM.DEVICE.FIRMWARE', '"1.8.4"'],
      ['SYSTEM.DEVICE.HWID', '254'],
      ['OUT.COUNT', '4'],
      ['OUT.EQ.COUNT', '4'],
    ]);
    for (let outputId = 1; outputId <= 4; outputId += 1) {
      this.values.set(`OUT-${outputId}.NAME`, `"Zone ${outputId}"`);
      this.values.set(`OUT-${outputId}.EQ.BYPASS`, '1');
      for (let bandId = 1; bandId <= 4; bandId += 1) {
        const prefix = `OUT-${outputId}.EQ-${bandId}`;
        this.values.set(`${prefix}.TYPE`, 'PARAMETRIC');
        this.values.set(`${prefix}.FREQ`, '1000.00');
        this.values.set(`${prefix}.Q`, '1.000');
        this.values.set(`${prefix}.GAIN`, '0.00');
        this.values.set(`${prefix}.BYPASS`, '0');
      }
    }
  }

  matches(pattern, register) {
    if (!pattern.includes('*')) return pattern === register;
    const [prefix, suffix] = pattern.split('*');
    return register.startsWith(prefix) && register.endsWith(suffix);
  }

  handle(socket) {
    let buffer = '';
    socket.setEncoding('utf8');
    socket.on('data', chunk => {
      buffer += chunk;
      for (let newline = buffer.indexOf('\n'); newline !== -1; newline = buffer.indexOf('\n')) {
        const command = buffer.slice(0, newline).replace(/\r$/, '');
        buffer = buffer.slice(newline + 1);
        this.commands.push(command);
        const [verb, register, ...valueParts] = command.split(' ');
        if (command === this.rejectCommand) {
          socket.write(`#${command}|E500: Test rejection\n`);
        } else if (verb === 'GET' && [...this.values].some(([key]) => this.matches(register, key))) {
          for (const [key, value] of this.values) {
            if (this.matches(register, key)) socket.write(`+${key} ${value}\n`);
          }
          socket.write(`*${command}\n`);
        } else if (verb === 'SET' && register && valueParts.length) {
          this.values.set(register, valueParts.join(' '));
          socket.write(`*${command}\n`);
        } else {
          socket.write(`#${command}|E107: Unknown Parameter\n`);
        }
      }
    });
  }
}

async function runLuaScenario(service, mode) {
  const server = net.createServer(socket => service.handle(socket));
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  const { port } = server.address();
  const testScript = path.join(__dirname, 'powerzone_integration.lua');
  const projectRoot = path.dirname(__dirname);
  const localRocks = path.join(projectRoot, '.lua');
  try {
    await new Promise((resolve, reject) => {
      const child = spawn(findLua(), [testScript, mode], {
        cwd: projectRoot,
        env: {
          ...process.env,
          POWERZONE_TEST_HOST: '127.0.0.1',
          POWERZONE_TEST_PORT: String(port),
          LUA_PATH: [
            path.join(__dirname, 'compat', '?.lua'),
            path.join(__dirname, 'compat', '?', 'init.lua'),
            path.join(localRocks, 'share', 'lua', '5.4', '?.lua'),
            path.join(localRocks, 'share', 'lua', '5.4', '?', 'init.lua'),
            path.join(localRocks, 'share', 'lua', '5.3', '?.lua'),
            path.join(localRocks, 'share', 'lua', '5.3', '?', 'init.lua'),
            '',
            '',
          ].join(';'),
          LUA_CPATH: [
            path.join(localRocks, 'lib', 'lua', '5.4', '?.so'),
            path.join(localRocks, 'lib', 'lua', '5.3', '?.so'),
            '',
            '',
          ].join(';'),
        },
      });
      let stdout = '';
      let stderr = '';
      child.stdout.on('data', chunk => { stdout += chunk; });
      child.stderr.on('data', chunk => { stderr += chunk; });
      child.once('error', reject);
      child.once('close', code => {
        if (code === 0) resolve(stdout);
        else reject(new Error(`Lua scenario exited ${code}: ${stderr || stdout}`));
      });
    });
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
}

test('Lua PowerZone client applies and reads presets over real TCP', async () => {
  const service = new PowerZoneTestService();
  await runLuaScenario(service, 'success');
  assert.equal(service.values.get('OUT-2.EQ.BYPASS'), '1');
});

test('Lua PowerZone client leaves EQ bypassed after a rejected write', async () => {
  const service = new PowerZoneTestService({
    rejectCommand: 'SET OUT-1.EQ-3.GAIN 0.00',
  });
  await runLuaScenario(service, 'failure');
  assert.equal(service.values.get('OUT-1.EQ.BYPASS'), '1');
  assert.equal(service.commands.includes('SET OUT-1.EQ.BYPASS 0'), false);
});

'use strict';

const assert = require('node:assert/strict');
const net = require('node:net');
const test = require('node:test');

const {
  PowerZoneApiError,
  PowerZoneClient,
  PowerZoneNetworkError,
} = require('../lib/powerzone-client');

class PowerZoneTestService {
  constructor({ outputs = 4, eqBands = 4, rejectCommand = null } = {}) {
    this.values = new Map([
      ['API_VERSION', '"1.5"'],
      ['SYSTEM.DEVICE.SERIAL', '"PZ-TEST-0001"'],
      ['SYSTEM.DEVICE.VENDOR_NAME', '"Sonance"'],
      ['SYSTEM.DEVICE.MODEL_NAME', '"PowerZone Connect 254"'],
      ['SYSTEM.DEVICE.FIRMWARE', '"1.8.4"'],
      ['SYSTEM.DEVICE.HWID', '254'],
      ['OUT.COUNT', String(outputs)],
      ['OUT.EQ.COUNT', String(eqBands)],
    ]);
    this.commands = [];
    this.rejectCommand = rejectCommand;
    for (let outputId = 1; outputId <= outputs; outputId += 1) {
      this.values.set(`OUT-${outputId}.NAME`, `"Zone ${outputId}"`);
      this.values.set(`OUT-${outputId}.EQ.BYPASS`, '1');
      for (let bandId = 1; bandId <= eqBands; bandId += 1) {
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

async function withServer(service, scenario) {
  const server = net.createServer(socket => service.handle(socket));
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  const { port } = server.address();
  try {
    await scenario(new PowerZoneClient('127.0.0.1', port));
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
}

test('validates and applies presets through a real TCP server', async () => {
  const service = new PowerZoneTestService();
  await withServer(service, async client => {
    assert.deepEqual(await client.validateServer(), {
      apiVersion: '1.5',
      serial: 'PZ-TEST-0001',
      outputs: 4,
      eqBands: 4,
      manufacturer: 'Sonance',
      model: 'PowerZone Connect 254',
      firmware: '1.8.4',
      hardwareId: '254',
    });
    assert.deepEqual(await client.outputNames(), {
      1: 'Zone 1',
      2: 'Zone 2',
      3: 'Zone 3',
      4: 'Zone 4',
    });

    const result = await client.applyPreset(2, 'vocal');
    assert.equal(result.bands, 4);
    assert.equal(service.values.get('OUT-2.EQ.BYPASS'), '0');
    const gains = Array.from({ length: 4 }, (_, index) => (
      Number(service.values.get(`OUT-2.EQ-${index + 1}.GAIN`))
    ));
    assert.equal(Math.max(...gains), 0);
    assert.equal(await client.readPreset(2), 'vocal');

    service.values.set('OUT-2.EQ-1.FREQ', 'not-a-number');
    assert.equal(await client.readPreset(2), null);
    service.values.set('OUT-2.EQ-1.FREQ', '31.25');
    service.values.set('OUT-2.EQ-1.GAIN', '-14.99');
    assert.equal(await client.readPreset(2), null);
    assert.equal((await client.applyPreset(2, 'flat')).bands, 0);
    assert.equal(service.values.get('OUT-2.EQ.BYPASS'), '1');
    assert.equal(await client.readPreset(2), 'flat');
  });
});

test('a rejected write leaves the output EQ safely bypassed', async () => {
  const service = new PowerZoneTestService({
    rejectCommand: 'SET OUT-1.EQ-3.GAIN 0.00',
  });
  await withServer(service, async client => {
    await assert.rejects(() => client.applyPreset(1, 'vocal'), /Test rejection/);
    assert.equal(service.values.get('OUT-1.EQ.BYPASS'), '1');
    assert.equal(service.commands.includes('SET OUT-1.EQ.BYPASS 0'), false);
  });
});

test('rejects an invalid output before writing EQ', async () => {
  const service = new PowerZoneTestService({ outputs: 2 });
  await withServer(service, async client => {
    await assert.rejects(() => client.applyPreset(3, 'vocal'), PowerZoneApiError);
    assert.equal(service.commands.some(command => command.startsWith('SET')), false);
  });
});

test('rejects public targets and command injection before connecting', async () => {
  await assert.rejects(
    () => new PowerZoneClient('1.1.1.1').validateServer(),
    PowerZoneNetworkError,
  );
  assert.throws(
    () => PowerZoneClient.validateCommand('GET API_VERSION\nSET OUT-1.EQ.BYPASS 0'),
    PowerZoneApiError,
  );
});

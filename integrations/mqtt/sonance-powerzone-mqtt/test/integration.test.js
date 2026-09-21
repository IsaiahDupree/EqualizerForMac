'use strict';

const assert = require('node:assert/strict');
const net = require('node:net');
const test = require('node:test');

const { Aedes } = require('aedes');
const mqtt = require('mqtt');

const { PowerZoneMqttBridge } = require('../src/bridge');

class PowerZoneTestServer {
  constructor() {
    this.commands = [];
    this.rejectCommand = null;
    this.values = new Map([
      ['API_VERSION', '"1.5"'],
      ['SYSTEM.DEVICE.SERIAL', '"PZ-MQTT-0001"'],
      ['SYSTEM.DEVICE.VENDOR_NAME', '"Sonance"'],
      ['SYSTEM.DEVICE.MODEL_NAME', '"PowerZone Connect 254"'],
      ['SYSTEM.DEVICE.FIRMWARE', '"1.8.4"'],
      ['SYSTEM.DEVICE.HWID', '254'],
      ['OUT.COUNT', '2'],
      ['OUT.EQ.COUNT', '4'],
      ['OUT-1.NAME', '"Kitchen"'],
      ['OUT-2.NAME', '"Patio"'],
    ]);
    for (let output = 1; output <= 2; output += 1) {
      this.values.set(`OUT-${output}.EQ.BYPASS`, '1');
      for (let band = 1; band <= 4; band += 1) {
        const root = `OUT-${output}.EQ-${band}`;
        this.values.set(`${root}.TYPE`, 'PARAMETRIC');
        this.values.set(`${root}.FREQ`, '1000.00');
        this.values.set(`${root}.Q`, '1.000');
        this.values.set(`${root}.GAIN`, '0.00');
        this.values.set(`${root}.BYPASS`, '0');
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
        const [verb, register, ...parts] = command.split(' ');
        if (command === this.rejectCommand) {
          socket.write(`#${command}|E500: Test rejection\n`);
        } else if (verb === 'GET' && [...this.values.keys()].some(key => this.matches(register, key))) {
          for (const [key, value] of this.values) {
            if (this.matches(register, key)) socket.write(`+${key} ${value}\n`);
          }
          socket.write(`*${command}\n`);
        } else if (verb === 'SET' && register && parts.length) {
          this.values.set(register, parts.join(' '));
          socket.write(`*${command}\n`);
        } else {
          socket.write(`#${command}|E107: Unknown Parameter\n`);
        }
      }
    });
  }
}

function listen(server) {
  return new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => resolve(server.address().port));
  });
}

function connectMqtt(url, options = {}) {
  const client = mqtt.connect(url, { protocolVersion: 4, reconnectPeriod: 0, ...options });
  return new Promise((resolve, reject) => {
    client.once('connect', () => resolve(client));
    client.once('error', reject);
  });
}

function endMqtt(client) {
  return new Promise(resolve => client.end(true, {}, resolve));
}

function publishMqtt(client, topic, payload, options = {}) {
  return new Promise((resolve, reject) => client.publish(topic, payload, options, error => (
    error ? reject(error) : resolve()
  )));
}

function closeServer(server) {
  return new Promise(resolve => server.close(resolve));
}

test('MQTT command reaches real PowerZone TCP and publishes retained state', async t => {
  const resources = {};
  t.after(async () => {
    if (resources.bridge) await resources.bridge.stop();
    await Promise.allSettled([
      resources.observer && endMqtt(resources.observer),
      resources.bridgeClient && endMqtt(resources.bridgeClient),
    ].filter(Boolean));
    if (resources.powerZoneServer) await closeServer(resources.powerZoneServer);
    if (resources.brokerServer) await closeServer(resources.brokerServer);
    if (resources.broker) await resources.broker.close();
  });

  const powerZone = new PowerZoneTestServer();
  const powerZoneServer = net.createServer(socket => powerZone.handle(socket));
  resources.powerZoneServer = powerZoneServer;
  const powerZonePort = await listen(powerZoneServer);

  const broker = await Aedes.createBroker();
  resources.broker = broker;
  const brokerServer = net.createServer(broker.handle);
  resources.brokerServer = brokerServer;
  const brokerPort = await listen(brokerServer);
  const brokerUrl = `mqtt://127.0.0.1:${brokerPort}`;
  const bridgeClient = await connectMqtt(brokerUrl, {
    will: { topic: 'sonance_eq/bridge/availability', payload: 'offline', qos: 1, retain: true },
  });
  resources.bridgeClient = bridgeClient;
  const observer = await connectMqtt(brokerUrl);
  resources.observer = observer;

  const messages = new Map();
  const waiters = [];
  observer.on('message', (topic, payload, packet) => {
    const message = { topic, payload: payload.toString('utf8'), packet };
    messages.set(topic, message);
    for (const waiter of [...waiters]) {
      if (waiter.predicate(message)) {
        waiters.splice(waiters.indexOf(waiter), 1);
        clearTimeout(waiter.timer);
        waiter.resolve(message);
      }
    }
  });
  await new Promise((resolve, reject) => observer.subscribe('#', { qos: 1 }, error => (
    error ? reject(error) : resolve()
  )));

  function waitFor(predicate, timeoutMs = 5000) {
    for (const message of messages.values()) {
      if (predicate(message)) return Promise.resolve(message);
    }
    return new Promise((resolve, reject) => {
      const waiter = { predicate, resolve };
      waiter.timer = setTimeout(() => {
        waiters.splice(waiters.indexOf(waiter), 1);
        reject(new Error('Timed out waiting for MQTT message'));
      }, timeoutMs);
      waiters.push(waiter);
    });
  }

  const bridge = new PowerZoneMqttBridge(bridgeClient, {
    topicPrefix: 'sonance_eq',
    discoveryPrefix: 'homeassistant',
    discoveryEnabled: true,
    powerZonePort,
    refreshIntervalMs: 60000,
    connectTimeoutMs: 1000,
  });
  resources.bridge = bridge;
  await bridge.start();
  await bridge.registerHost('127.0.0.1', powerZonePort);

  const root = 'sonance_eq/pz-mqtt-0001/output/1';
  const discovery = await waitFor(message => (
    message.topic === 'homeassistant/select/sonance_eq_pz-mqtt-0001_output_1/config'
  ));
  const discoveryPayload = JSON.parse(discovery.payload);
  assert.equal(discoveryPayload.command_topic, `${root}/preset/set`);
  assert.deepEqual(discoveryPayload.availability.map(entry => entry.topic), [
    'sonance_eq/bridge/availability', `${root}/availability`,
  ]);
  assert.equal(discoveryPayload.origin.sw_version, '0.1.0');
  assert.equal(messages.get(`${root}/preset/state`).payload, 'Flat');

  await bridge.stop();
  const setCommandsBeforeRetainedCommand = powerZone.commands.filter(command => command.startsWith('SET ')).length;
  await publishMqtt(observer, `${root}/preset/set`, 'Cinema', { qos: 1, retain: true });
  await bridge.start();
  await new Promise(resolve => setTimeout(resolve, 50));
  assert.equal(
    powerZone.commands.filter(command => command.startsWith('SET ')).length,
    setCommandsBeforeRetainedCommand,
  );
  await publishMqtt(observer, `${root}/preset/set`, '', { qos: 1, retain: true });

  messages.delete(`${root}/preset/state`);
  await publishMqtt(observer, `${root}/preset/set`, 'Bass Boost', { qos: 1, retain: false });
  await waitFor(message => message.topic === `${root}/preset/state` && message.payload === 'Bass Boost');
  assert.equal(powerZone.values.get('OUT-1.EQ.BYPASS'), '0');
  assert.equal(powerZone.commands[powerZone.commands.indexOf('SET OUT-1.EQ.BYPASS 1')], 'SET OUT-1.EQ.BYPASS 1');

  const commandMarker = powerZone.commands.length;
  powerZone.rejectCommand = 'SET OUT-1.EQ-3.GAIN -1.00';
  await publishMqtt(observer, `${root}/preset/set`, 'Cinema', { qos: 1, retain: false });
  await waitFor(message => message.topic === `${root}/availability` && message.payload === 'offline');
  const failedCommands = powerZone.commands.slice(commandMarker);
  assert.equal(powerZone.values.get('OUT-1.EQ.BYPASS'), '1');
  assert.equal(failedCommands.includes('SET OUT-1.EQ.BYPASS 0'), false);

  powerZone.rejectCommand = null;
  await bridge.refreshAll();
  assert.equal(messages.get(`${root}/availability`).payload, 'online');

  powerZone.values.set('OUT-1.EQ.BYPASS', '0');
  powerZone.values.set('OUT-1.EQ-1.TYPE', 'NOT_A_MANAGED_CURVE');
  messages.delete(`${root}/preset/state`);
  messages.delete(`${root}/attributes`);
  await bridge.refreshAll();
  await waitFor(message => message.topic === `${root}/preset/state` && message.payload === '');
  const unmanagedAttributes = JSON.parse(messages.get(`${root}/attributes`).payload);
  assert.equal(unmanagedAttributes.managed_preset, false);
  assert.equal(unmanagedAttributes.preset_id, null);
});

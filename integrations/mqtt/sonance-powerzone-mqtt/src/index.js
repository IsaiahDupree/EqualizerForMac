'use strict';

const fs = require('node:fs');

const { Bonjour } = require('bonjour-service');
const mqtt = require('mqtt');

const { PowerZoneMqttBridge } = require('./bridge');
const { loadConfig } = require('./config');
const { isLocalAddress } = require('./powerzone-client');

async function main() {
  const config = loadConfig();
  const mqttOptions = {
    protocolVersion: 4,
    clean: true,
    reconnectPeriod: 5000,
    connectTimeout: 10000,
    username: config.mqttUsername,
    password: config.mqttPassword,
    will: {
      topic: `${config.topicPrefix}/bridge/availability`,
      payload: 'offline',
      qos: 1,
      retain: true,
    },
  };
  if (config.mqttCaFile) mqttOptions.ca = fs.readFileSync(config.mqttCaFile);
  const mqttClient = mqtt.connect(config.mqttUrl, mqttOptions);
  await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('Timed out connecting to the MQTT broker')), 15000);
    mqttClient.once('connect', () => { clearTimeout(timer); resolve(); });
    mqttClient.once('error', error => { clearTimeout(timer); reject(error); });
  });

  const bridge = new PowerZoneMqttBridge(mqttClient, config);
  await bridge.start();
  for (const host of config.manualHosts) {
    bridge.registerHost(host).catch(error => console.error(`Cannot register ${host}: ${error.message}`));
  }

  let bonjour;
  let browser;
  if (config.mdnsEnabled) {
    bonjour = new Bonjour();
    browser = bonjour.find({ type: 'pasconnect', protocol: 'tcp' }, service => {
      const addresses = Array.from(new Set([
        ...(service.addresses || []),
        service.referer?.address,
      ].filter(address => address && isLocalAddress(address))));
      for (const address of addresses) {
        bridge.registerHost(address, Number(service.port) || config.powerZonePort)
          .catch(error => console.error(`Cannot register mDNS PowerZone ${address}: ${error.message}`));
      }
    });
  }

  let stopping = false;
  const shutdown = async () => {
    if (stopping) return;
    stopping = true;
    browser?.stop();
    bonjour?.destroy();
    try { await bridge.stop(); } catch (error) { console.error(error); }
    mqttClient.end(false, {}, () => process.exit(0));
    setTimeout(() => process.exit(1), 5000).unref();
  };
  process.once('SIGINT', shutdown);
  process.once('SIGTERM', shutdown);
}

if (require.main === module) {
  main().catch(error => {
    console.error(error);
    process.exitCode = 1;
  });
}

module.exports = { main };

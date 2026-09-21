'use strict';

const { TextDecoder } = require('node:util');

const { PowerZoneClient } = require('./powerzone-client');
const { PRESETS, getPreset } = require('./presets');

const MAX_PAYLOAD_BYTES = 128;
const BRIDGE_VERSION = '0.1.0';

function safeSegment(value) {
  const result = String(value).trim().toLowerCase().replace(/[^a-z0-9_-]+/g, '-').replace(/^-+|-+$/g, '');
  if (!result) throw new Error('Cannot form a stable MQTT identifier');
  return result;
}

class PowerZoneMqttBridge {
  constructor(mqttClient, config, { logger = console } = {}) {
    this.mqtt = mqttClient;
    this.config = config;
    this.logger = logger;
    this.outputsByCommandTopic = new Map();
    this.outputsByKey = new Map();
    this.registrationTasks = new Map();
    this.refreshTimer = null;
    this.started = false;
    this.messageHandler = (topic, payload, packet) => {
      this.handleMessage(topic, payload, packet).catch(error => this.logger.error(error));
    };
    this.connectionHandler = () => {
      this.announceConnected().catch(error => this.logger.error(error));
    };
  }

  bridgeAvailabilityTopic() {
    return `${this.config.topicPrefix}/bridge/availability`;
  }

  publish(topic, payload, options = {}) {
    return new Promise((resolve, reject) => {
      this.mqtt.publish(topic, payload, options, error => (error ? reject(error) : resolve()));
    });
  }

  subscribe(topic, options = {}) {
    return new Promise((resolve, reject) => {
      this.mqtt.subscribe(topic, options, error => (error ? reject(error) : resolve()));
    });
  }

  unsubscribe(topic) {
    return new Promise((resolve, reject) => {
      this.mqtt.unsubscribe(topic, error => (error ? reject(error) : resolve()));
    });
  }

  async start() {
    if (this.started) return;
    this.started = true;
    this.mqtt.on('message', this.messageHandler);
    this.mqtt.on('connect', this.connectionHandler);
    await this.subscribe(`${this.config.topicPrefix}/+/output/+/preset/set`, { qos: 1 });
    if (this.config.discoveryEnabled) {
      await this.subscribe(`${this.config.discoveryPrefix}/status`, { qos: 0 });
    }
    await this.announceConnected();
    this.refreshTimer = setInterval(() => {
      this.refreshAll().catch(error => this.logger.error(error));
    }, this.config.refreshIntervalMs);
    this.refreshTimer.unref?.();
  }

  async stop() {
    if (!this.started) return;
    this.started = false;
    if (this.refreshTimer) clearInterval(this.refreshTimer);
    this.refreshTimer = null;
    this.mqtt.removeListener('message', this.messageHandler);
    this.mqtt.removeListener('connect', this.connectionHandler);
    await this.unsubscribe(`${this.config.topicPrefix}/+/output/+/preset/set`);
    if (this.config.discoveryEnabled) {
      await this.unsubscribe(`${this.config.discoveryPrefix}/status`);
    }
    await this.publish(this.bridgeAvailabilityTopic(), 'offline', { qos: 1, retain: true });
  }

  async announceConnected() {
    await this.publish(this.bridgeAvailabilityTopic(), 'online', { qos: 1, retain: true });
    await Promise.all(Array.from(this.outputsByKey.values(), output => this.publishDiscovery(output)));
    await this.refreshAll();
  }

  registerHost(host, port = this.config.powerZonePort) {
    const key = `${host}:${port}`;
    const existing = this.registrationTasks.get(key);
    if (existing) return existing;
    const task = this.registerHostLocked(host, port).catch(error => {
      this.registrationTasks.delete(key);
      throw error;
    });
    this.registrationTasks.set(key, task);
    return task;
  }

  async registerHostLocked(host, port) {
    const client = new PowerZoneClient(host, port, { timeoutMs: this.config.connectTimeoutMs });
    const info = await client.validateServer();
    const names = await client.outputNames();
    const serialSegment = safeSegment(info.serial);

    for (let outputId = 1; outputId <= info.outputs; outputId += 1) {
      const key = `${serialSegment}:${outputId}`;
      const root = `${this.config.topicPrefix}/${serialSegment}/output/${outputId}`;
      const output = this.outputsByKey.get(key) || { key, operation: Promise.resolve() };
      Object.assign(output, {
        client,
        info,
        outputId,
        outputName: names[outputId],
        root,
        commandTopic: `${root}/preset/set`,
        stateTopic: `${root}/preset/state`,
        attributesTopic: `${root}/attributes`,
        availabilityTopic: `${root}/availability`,
        errorTopic: `${root}/error`,
      });
      this.outputsByKey.set(key, output);
      this.outputsByCommandTopic.set(output.commandTopic, output);
      await this.publishDiscovery(output);
      await this.refreshOutput(output);
    }
    this.logger.info(`Registered ${info.model} ${info.serial} at ${host}:${port}`);
    return info;
  }

  async publishDiscovery(output) {
    if (!this.config.discoveryEnabled) return;
    const uniqueId = `sonance_eq_${safeSegment(output.info.serial)}_output_${output.outputId}`;
    const topic = `${this.config.discoveryPrefix}/select/${uniqueId}/config`;
    const payload = {
      name: 'EQ Preset',
      unique_id: uniqueId,
      default_entity_id: `select.${uniqueId}`,
      command_topic: output.commandTopic,
      state_topic: output.stateTopic,
      json_attributes_topic: output.attributesTopic,
      options: PRESETS.map(preset => preset.title),
      optimistic: false,
      availability: [
        { topic: this.bridgeAvailabilityTopic() },
        { topic: output.availabilityTopic },
      ],
      availability_mode: 'all',
      payload_available: 'online',
      payload_not_available: 'offline',
      icon: 'mdi:tune-variant',
      device: {
        identifiers: [uniqueId],
        name: `${output.outputName} EQ`,
        manufacturer: output.info.manufacturer,
        model: output.info.model,
        serial_number: output.info.serial,
        sw_version: output.info.firmware,
        hw_version: output.info.hardwareId,
      },
      origin: {
        name: 'Sonance PowerZone MQTT bridge',
        sw_version: BRIDGE_VERSION,
        support_url: 'https://github.com/IsaiahDupree/EqualizerForMac',
      },
    };
    await this.publish(topic, JSON.stringify(payload), { qos: 1, retain: true });
  }

  async refreshOutput(output) {
    try {
      const preset = await output.client.readPreset(output.outputId);
      await this.publish(output.stateTopic, preset?.title || '', { qos: 1, retain: true });
      await this.publish(output.attributesTopic, JSON.stringify({
        preset_id: preset?.id || null,
        managed_preset: Boolean(preset),
        amplifier_serial: output.info.serial,
        amplifier_model: output.info.model,
        output_id: output.outputId,
        output_name: output.outputName,
        api_version: output.info.apiVersion,
      }), { qos: 1, retain: true });
      await this.publish(output.errorTopic, '', { qos: 1, retain: true });
      await this.publish(output.availabilityTopic, 'online', { qos: 1, retain: true });
      return preset;
    } catch (error) {
      await this.markOffline(output, error);
      return null;
    }
  }

  async markOffline(output, error) {
    await this.publish(output.errorTopic, String(error.message || error), { qos: 1, retain: true });
    await this.publish(output.availabilityTopic, 'offline', { qos: 1, retain: true });
    this.logger.error(`PowerZone ${output.info.serial} output ${output.outputId}: ${error.message || error}`);
  }

  async refreshAll() {
    await Promise.allSettled(Array.from(this.outputsByKey.values(), output => (
      this.enqueue(output, () => this.refreshOutput(output))
    )));
  }

  enqueue(output, operation) {
    const task = output.operation.then(operation, operation);
    output.operation = task.catch(() => undefined);
    return task;
  }

  async handleMessage(topic, payload, packet = {}) {
    if (this.config.discoveryEnabled && topic === `${this.config.discoveryPrefix}/status`) {
      if (payload.toString('utf8').trim().toLowerCase() === 'online') {
        await Promise.all(Array.from(this.outputsByKey.values(), output => this.publishDiscovery(output)));
      }
      return;
    }
    const output = this.outputsByCommandTopic.get(topic);
    if (!output) return;
    if (packet.retain) {
      this.logger.warn(`Ignored retained command on ${topic}`);
      return;
    }
    if (payload.length === 0 || payload.length > MAX_PAYLOAD_BYTES) {
      await this.publish(
        output.errorTopic,
        'Rejected an empty or oversized preset command',
        { qos: 1, retain: true },
      );
      return;
    }
    let value;
    try {
      value = new TextDecoder('utf-8', { fatal: true }).decode(payload).trim();
      const preset = getPreset(value);
      await this.enqueue(output, async () => {
        try {
          await output.client.applyPreset(output.outputId, preset.id);
          await this.publish(output.stateTopic, preset.title, { qos: 1, retain: true });
          await this.publish(output.attributesTopic, JSON.stringify({
            preset_id: preset.id,
            managed_preset: true,
            amplifier_serial: output.info.serial,
            amplifier_model: output.info.model,
            output_id: output.outputId,
            output_name: output.outputName,
            api_version: output.info.apiVersion,
          }), { qos: 1, retain: true });
          await this.publish(output.errorTopic, '', { qos: 1, retain: true });
          await this.publish(output.availabilityTopic, 'online', { qos: 1, retain: true });
        } catch (error) {
          await this.markOffline(output, error);
        }
      });
    } catch (error) {
      await this.publish(output.errorTopic, `Rejected preset payload: ${error.message}`, { qos: 1, retain: true });
      this.logger.warn(`Rejected preset command on ${topic}: ${error.message}`);
    }
  }
}

module.exports = { PowerZoneMqttBridge, safeSegment };

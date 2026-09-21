'use strict';

function integer(value, fallback, { min, max }) {
  if (value === undefined || value === '') return fallback;
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < min || parsed > max) {
    throw new Error(`Expected an integer from ${min} to ${max}, received ${value}`);
  }
  return parsed;
}

function topicPrefix(value, fallback) {
  const normalized = String(value || fallback).trim().replace(/^\/+|\/+$/g, '');
  if (!normalized || normalized.includes('\0') || /[+#]/.test(normalized)) {
    throw new Error(`Invalid MQTT topic prefix: ${value}`);
  }
  return normalized;
}

function loadConfig(env = process.env) {
  const mqttUrl = String(env.MQTT_URL || '').trim();
  if (!mqttUrl) throw new Error('MQTT_URL is required');
  const parsedUrl = new URL(mqttUrl);
  if (!['mqtt:', 'mqtts:', 'ws:', 'wss:'].includes(parsedUrl.protocol)) {
    throw new Error('MQTT_URL must use mqtt, mqtts, ws, or wss');
  }

  return {
    mqttUrl,
    mqttUsername: env.MQTT_USERNAME || undefined,
    mqttPassword: env.MQTT_PASSWORD || undefined,
    mqttCaFile: env.MQTT_CA_FILE || undefined,
    topicPrefix: topicPrefix(env.MQTT_TOPIC_PREFIX, 'sonance_eq'),
    discoveryPrefix: topicPrefix(env.HOME_ASSISTANT_DISCOVERY_PREFIX, 'homeassistant'),
    discoveryEnabled: String(env.HOME_ASSISTANT_DISCOVERY || 'true').toLowerCase() !== 'false',
    mdnsEnabled: String(env.POWERZONE_MDNS || 'true').toLowerCase() !== 'false',
    manualHosts: String(env.POWERZONE_HOSTS || '').split(',').map(host => host.trim()).filter(Boolean),
    powerZonePort: integer(env.POWERZONE_PORT, 7621, { min: 1, max: 65535 }),
    refreshIntervalMs: integer(env.REFRESH_INTERVAL_MS, 300000, { min: 10000, max: 86400000 }),
    connectTimeoutMs: integer(env.POWERZONE_TIMEOUT_MS, 5000, { min: 250, max: 60000 }),
  };
}

module.exports = { loadConfig };

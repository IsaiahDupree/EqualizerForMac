'use strict';

const Homey = require('homey');
const { DEFAULT_PORT, PowerZoneClient } = require('../../lib/powerzone-client');

const CAPABILITY = 'sonance_eq_preset';
const REFRESH_INTERVAL_MS = 60_000;

module.exports = class PowerZoneOutputDevice extends Homey.Device {
  async onInit() {
    this.outputId = Number(this.getStoreValue('outputId'));
    this.serial = String(this.getStoreValue('serial'));
    this.discoveryId = String(this.getStoreValue('discoveryId'));
    this.client = this.createClient(this.getSettings());

    this.registerCapabilityListener(CAPABILITY, async preset => this.applyPreset(preset));

    this.discoveryStrategy = this.homey.discovery.getStrategy('powerzone');
    this.discoveryListener = result => {
      this.handleDiscoveryResult(result).catch(error => this.error(error));
    };
    this.discoveryStrategy.on('result', this.discoveryListener);

    const currentResult = Object.values(this.discoveryStrategy.getDiscoveryResults())
      .find(result => result.id === this.discoveryId);
    if (currentResult) {
      await this.handleDiscoveryResult(currentResult);
    } else {
      await this.connectStoredTarget();
    }

    this.refreshTimer = this.homey.setInterval(() => {
      this.refreshPreset().catch(error => this.error(error));
    }, REFRESH_INTERVAL_MS);
  }

  createClient(settings) {
    return new PowerZoneClient(settings.host, Number(settings.port || DEFAULT_PORT));
  }

  async validateIdentity(client) {
    const info = await client.validateServer();
    if (info.serial !== this.serial) {
      throw new Error(`Expected PowerZone ${this.serial}, found ${info.serial}`);
    }
    return info;
  }

  async connectStoredTarget() {
    try {
      await this.validateIdentity(this.client);
      await this.refreshPreset();
      await this.setAvailable();
    } catch (error) {
      await this.setUnavailable(error.message);
    }
  }

  async handleDiscoveryResult(result) {
    if (result.id !== this.discoveryId || !result.address) return;
    const settings = this.getSettings();
    const candidate = new PowerZoneClient(result.address, Number(settings.port || DEFAULT_PORT));
    await this.validateIdentity(candidate);
    this.client = candidate;
    if (settings.host !== result.address) {
      await this.setSettings({ host: result.address });
    }
    await this.refreshPreset();
    await this.setAvailable();
  }

  async refreshPreset() {
    const preset = await this.client.readPreset(this.outputId);
    if (this.getCapabilityValue(CAPABILITY) !== preset) {
      await this.setCapabilityValue(CAPABILITY, preset);
    }
    await this.setAvailable();
  }

  async applyPreset(preset) {
    try {
      await this.client.applyPreset(this.outputId, preset);
      await this.setCapabilityValue(CAPABILITY, preset);
      await this.setAvailable();
    } catch (error) {
      await this.setUnavailable(error.message);
      throw error;
    }
  }

  async onSettings({ newSettings, changedKeys }) {
    if (!changedKeys.includes('host') && !changedKeys.includes('port')) return;
    const candidate = this.createClient(newSettings);
    await this.validateIdentity(candidate);
    this.client = candidate;
    await this.refreshPreset();
  }

  async onDeleted() {
    if (this.refreshTimer) this.homey.clearInterval(this.refreshTimer);
    if (this.discoveryStrategy && this.discoveryListener) {
      this.discoveryStrategy.removeListener('result', this.discoveryListener);
    }
  }
};

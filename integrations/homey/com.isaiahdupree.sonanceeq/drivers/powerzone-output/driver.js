'use strict';

const Homey = require('homey');
const { DEFAULT_PORT, PowerZoneClient } = require('../../lib/powerzone-client');

module.exports = class PowerZoneOutputDriver extends Homey.Driver {
  async onPairListDevices() {
    const strategy = this.homey.discovery.getStrategy('powerzone');
    const discoveryResults = Object.values(strategy.getDiscoveryResults());
    const devices = [];
    const seenDeviceIds = new Set();

    for (const discoveryResult of discoveryResults) {
      if (!discoveryResult.address) continue;
      try {
        const client = new PowerZoneClient(discoveryResult.address, DEFAULT_PORT);
        const info = await client.validateServer();
        const names = await client.outputNames();
        for (let outputId = 1; outputId <= info.outputs; outputId += 1) {
          const deviceId = `${info.serial}:output:${outputId}`;
          if (seenDeviceIds.has(deviceId)) continue;
          seenDeviceIds.add(deviceId);
          devices.push({
            name: `${names[outputId]} EQ`,
            data: {
              id: deviceId,
            },
            store: {
              discoveryId: discoveryResult.id,
              serial: info.serial,
              outputId,
              manufacturer: info.manufacturer,
              model: info.model,
              firmware: info.firmware,
              hardwareId: info.hardwareId,
            },
            settings: {
              host: discoveryResult.address,
              port: DEFAULT_PORT,
            },
          });
        }
      } catch (error) {
        this.error(`Ignoring incompatible _pasconnect._tcp result ${discoveryResult.id}`, error);
      }
    }
    return devices;
  }
};

'use strict';

const Homey = require('homey');

module.exports = class SonanceEqApp extends Homey.App {
  async onInit() {
    this.homey.flow.getActionCard('set_preset').registerRunListener(
      async ({ device, preset }) => device.applyPreset(preset),
    );
    this.log('Sonance EQ is ready');
  }
};

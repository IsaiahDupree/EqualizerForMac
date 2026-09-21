'use strict';

const dns = require('node:dns').promises;
const net = require('node:net');
const { TextDecoder } = require('node:util');

const { PRESETS, getPreset, powerZoneBands } = require('./presets');

const MAX_COMMAND_BYTES = 8192;
const MAX_LINE_BYTES = 16384;
const MAX_RESPONSE_LINES = 4096;
const MAX_OUTPUTS = 128;
const MAX_EQ_BANDS = 128;
const DEFAULT_PORT = 7621;

class PowerZoneApiError extends Error {}
class PowerZoneNetworkError extends PowerZoneApiError {}

function isPrivateIPv4(address) {
  const octets = address.split('.').map(Number);
  if (octets.length !== 4 || octets.some(value => !Number.isInteger(value) || value < 0 || value > 255)) {
    return false;
  }
  return octets[0] === 10
    || octets[0] === 127
    || (octets[0] === 169 && octets[1] === 254)
    || (octets[0] === 172 && octets[1] >= 16 && octets[1] <= 31)
    || (octets[0] === 192 && octets[1] === 168);
}

function isPrivateIPv6(address) {
  const normalized = address.toLowerCase().split('%', 1)[0];
  if (normalized === '::1') return true;
  const firstGroupText = normalized.split(':', 1)[0];
  const firstGroup = Number.parseInt(firstGroupText || '0', 16);
  return (firstGroup & 0xfe00) === 0xfc00 || (firstGroup & 0xffc0) === 0xfe80;
}

function isLocalAddress(address) {
  const normalized = address.split('%', 1)[0];
  const family = net.isIP(normalized);
  if (family === 4) return isPrivateIPv4(normalized);
  if (family === 6) return isPrivateIPv6(normalized);
  return false;
}

function decodeValue(rawValue) {
  const value = rawValue.trim();
  if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
    return value.slice(1, -1);
  }
  const number = Number(value);
  return value !== '' && Number.isFinite(number) ? number : value;
}

function asBoolean(value) {
  if (typeof value === 'string') {
    return ['1', 'true', 'on', 'yes'].includes(value.trim().toLowerCase());
  }
  return Boolean(value);
}

class SocketLineReader {
  constructor(socket, timeoutMs) {
    this.socket = socket;
    this.timeoutMs = timeoutMs;
    this.buffer = Buffer.alloc(0);
    this.lines = [];
    this.waiters = [];
    this.failure = null;
    this.decoder = new TextDecoder('utf-8', { fatal: true });

    socket.on('data', chunk => this.onData(chunk));
    socket.on('error', error => this.fail(error));
    socket.on('close', () => this.fail(new Error('PowerZone closed the connection')));
  }

  onData(chunk) {
    this.buffer = Buffer.concat([this.buffer, chunk]);
    if (this.buffer.length > MAX_LINE_BYTES && !this.buffer.includes(0x0A)) {
      this.fail(new Error('PowerZone response line exceeds the size limit'));
      this.socket.destroy();
      return;
    }

    for (let newline = this.buffer.indexOf(0x0A); newline !== -1; newline = this.buffer.indexOf(0x0A)) {
      let rawLine = this.buffer.subarray(0, newline);
      this.buffer = this.buffer.subarray(newline + 1);
      if (rawLine.at(-1) === 0x0D) rawLine = rawLine.subarray(0, -1);
      if (rawLine.length > MAX_LINE_BYTES) {
        this.fail(new Error('PowerZone response line exceeds the size limit'));
        this.socket.destroy();
        return;
      }
      let line;
      try {
        line = this.decoder.decode(rawLine);
      } catch (error) {
        this.fail(error);
        this.socket.destroy();
        return;
      }
      const waiter = this.waiters.shift();
      if (waiter) waiter.resolve(line);
      else {
        this.lines.push(line);
        if (this.lines.length > MAX_RESPONSE_LINES) {
          this.fail(new Error('PowerZone sent too many response lines'));
          this.socket.destroy();
          return;
        }
      }
    }
  }

  fail(error) {
    if (this.failure) return;
    this.failure = error;
    for (const waiter of this.waiters.splice(0)) waiter.reject(error);
  }

  nextLine() {
    if (this.lines.length) return Promise.resolve(this.lines.shift());
    if (this.failure) return Promise.reject(this.failure);

    return new Promise((resolve, reject) => {
      const waiter = { resolve, reject };
      const timer = setTimeout(() => {
        const index = this.waiters.indexOf(waiter);
        if (index !== -1) this.waiters.splice(index, 1);
        reject(new Error('Timed out waiting for PowerZone'));
      }, this.timeoutMs);
      waiter.resolve = value => {
        clearTimeout(timer);
        resolve(value);
      };
      waiter.reject = error => {
        clearTimeout(timer);
        reject(error);
      };
      this.waiters.push(waiter);
    });
  }
}

class PowerZoneClient {
  constructor(host, port = DEFAULT_PORT, { timeoutMs = 5000 } = {}) {
    this.host = String(host || '').trim().replace(/^\[|\]$/g, '').replace(/\.$/, '');
    this.port = Number(port);
    this.timeoutMs = timeoutMs;
    this.deviceInfo = null;
    this.commandQueue = Promise.resolve();
  }

  static validateCommand(command) {
    const normalized = String(command).trim();
    if (!normalized || normalized.includes('\n') || normalized.includes('\r')) {
      throw new PowerZoneApiError('PowerZone commands must be one non-empty line');
    }
    if (Buffer.byteLength(normalized, 'utf8') > MAX_COMMAND_BYTES) {
      throw new PowerZoneApiError('PowerZone command exceeds the API size limit');
    }
    return normalized;
  }

  async validatedAddresses() {
    if (!this.host || this.host.includes('/') || this.host.includes('@')) {
      throw new PowerZoneNetworkError('Enter a local hostname or IP address only');
    }
    if (!Number.isInteger(this.port) || this.port < 1 || this.port > 65535) {
      throw new PowerZoneNetworkError('PowerZone port must be between 1 and 65535');
    }

    let addresses;
    try {
      addresses = await dns.lookup(this.host, { all: true, verbatim: true });
    } catch (error) {
      throw new PowerZoneNetworkError(`Cannot resolve PowerZone host ${this.host}: ${error.message}`);
    }
    if (!addresses.length) {
      throw new PowerZoneNetworkError(`Cannot resolve PowerZone host ${this.host}`);
    }
    if (addresses.some(({ address }) => !isLocalAddress(address))) {
      throw new PowerZoneNetworkError(
        "PowerZone's control API is unauthenticated; use a private or link-local address and never port-forward it",
      );
    }
    return addresses;
  }

  execute(commands) {
    const normalized = Array.from(commands, PowerZoneClient.validateCommand);
    if (!normalized.length) return Promise.resolve([]);

    const task = this.commandQueue.then(() => this.executeLocked(normalized));
    this.commandQueue = task.catch(() => undefined);
    return task;
  }

  async executeLocked(commands) {
    const addresses = await this.validatedAddresses();
    let lastError;
    let socket;
    for (const { address, family } of addresses) {
      try {
        socket = await this.connect(address, family);
        break;
      } catch (error) {
        lastError = error;
      }
    }
    if (!socket) {
      throw new PowerZoneApiError(
        `Cannot reach PowerZone at ${this.host}:${this.port}: ${lastError?.message || 'no local address'}`,
      );
    }

    const reader = new SocketLineReader(socket, this.timeoutMs);
    const responses = [];
    try {
      for (const command of commands) {
        await new Promise((resolve, reject) => {
          socket.write(`${command}\n`, error => (error ? reject(error) : resolve()));
        });
        const values = {};
        let responseLines = 0;
        while (true) {
          const line = await reader.nextLine();
          responseLines += 1;
          if (responseLines > MAX_RESPONSE_LINES) {
            throw new PowerZoneApiError(`PowerZone returned too many lines for ${command}`);
          }
          if (line === `*${command}`) {
            responses.push(values);
            break;
          }
          if (line.startsWith('#')) {
            const separator = line.indexOf('|');
            const detail = separator === -1 ? line.slice(1) : line.slice(separator + 1);
            throw new PowerZoneApiError(`PowerZone rejected ${command}: ${detail}`);
          }
          if (line.startsWith('+')) {
            const separator = line.indexOf(' ');
            if (separator !== -1) {
              values[line.slice(1, separator)] = decodeValue(line.slice(separator + 1));
            }
          }
        }
      }
      return responses;
    } catch (error) {
      if (error instanceof PowerZoneApiError) throw error;
      throw new PowerZoneApiError(
        `PowerZone communication failed at ${this.host}:${this.port}: ${error.message}`,
      );
    } finally {
      socket.destroy();
    }
  }

  connect(address, family) {
    return new Promise((resolve, reject) => {
      const socket = net.createConnection({ host: address, port: this.port, family });
      const timer = setTimeout(() => {
        socket.destroy();
        reject(new Error('connection timed out'));
      }, this.timeoutMs);
      socket.setNoDelay(true);
      socket.once('connect', () => {
        clearTimeout(timer);
        socket.removeListener('error', onError);
        resolve(socket);
      });
      const onError = error => {
        clearTimeout(timer);
        reject(error);
      };
      socket.once('error', onError);
    });
  }

  async command(command) {
    return (await this.execute([command]))[0];
  }

  async validateServer() {
    const [api, device, outputs, eqBands] = await this.execute([
      'GET API_VERSION',
      'GET SYSTEM.DEVICE.*',
      'GET OUT.COUNT',
      'GET OUT.EQ.COUNT',
    ]);
    const info = {
      apiVersion: String(api.API_VERSION ?? ''),
      serial: String(device['SYSTEM.DEVICE.SERIAL'] ?? ''),
      outputs: Number(outputs['OUT.COUNT']),
      eqBands: Number(eqBands['OUT.EQ.COUNT']),
      manufacturer: String(device['SYSTEM.DEVICE.VENDOR_NAME'] ?? 'Sonance'),
      model: String(device['SYSTEM.DEVICE.MODEL_NAME'] ?? 'PowerZone'),
      firmware: String(device['SYSTEM.DEVICE.FIRMWARE'] ?? ''),
      hardwareId: String(device['SYSTEM.DEVICE.HWID'] ?? ''),
    };
    if (!info.apiVersion || !info.serial || !Number.isInteger(info.outputs) || !Number.isInteger(info.eqBands)) {
      throw new PowerZoneApiError('The device did not return the required PowerZone EQ registers');
    }
    if (
      info.outputs < 1
      || info.eqBands < 1
      || info.outputs > MAX_OUTPUTS
      || info.eqBands > MAX_EQ_BANDS
    ) {
      throw new PowerZoneApiError('The PowerZone device exposes no usable output EQ');
    }
    this.deviceInfo = info;
    return info;
  }

  async outputNames() {
    const info = this.deviceInfo || await this.validateServer();
    const response = await this.command('GET OUT-*.NAME');
    return Object.fromEntries(Array.from({ length: info.outputs }, (_, index) => {
      const outputId = index + 1;
      return [outputId, String(response[`OUT-${outputId}.NAME`] ?? `Output ${outputId}`)];
    }));
  }

  validateOutput(outputId) {
    const normalized = Number(outputId);
    if (!Number.isInteger(normalized) || normalized < 1 || normalized > this.deviceInfo.outputs) {
      throw new PowerZoneApiError(
        `Output ${outputId} is outside this amplifier's 1-${this.deviceInfo.outputs} range`,
      );
    }
    return normalized;
  }

  async applyPreset(outputId, name) {
    const info = this.deviceInfo || await this.validateServer();
    const normalizedOutputId = this.validateOutput(outputId);
    const preset = getPreset(name);
    const root = `OUT-${normalizedOutputId}.EQ`;
    const bands = powerZoneBands(preset.id, info.eqBands);

    if (!bands.length) {
      await this.command(`SET ${root}.BYPASS 1`);
      return { ...info, outputId: normalizedOutputId, preset: preset.id, bands: 0 };
    }

    const commands = [`SET ${root}.BYPASS 1`];
    bands.forEach((band, index) => {
      const prefix = `${root}-${index + 1}`;
      commands.push(
        `SET ${prefix}.TYPE ${band.type}`,
        `SET ${prefix}.FREQ ${band.frequency.toFixed(2)}`,
        `SET ${prefix}.Q ${band.q.toFixed(3)}`,
        `SET ${prefix}.GAIN ${band.gain.toFixed(2)}`,
        `SET ${prefix}.BYPASS 0`,
      );
    });
    for (let bandId = bands.length + 1; bandId <= info.eqBands; bandId += 1) {
      commands.push(`SET ${root}-${bandId}.BYPASS 1`);
    }
    commands.push(`SET ${root}.BYPASS 0`);
    await this.execute(commands);
    return { ...info, outputId: normalizedOutputId, preset: preset.id, bands: bands.length };
  }

  async readPreset(outputId) {
    const info = this.deviceInfo || await this.validateServer();
    const normalizedOutputId = this.validateOutput(outputId);
    const root = `OUT-${normalizedOutputId}.EQ`;
    const commands = [`GET ${root}.BYPASS`];
    for (let bandId = 1; bandId <= info.eqBands; bandId += 1) {
      const prefix = `${root}-${bandId}`;
      commands.push(
        `GET ${prefix}.TYPE`,
        `GET ${prefix}.FREQ`,
        `GET ${prefix}.Q`,
        `GET ${prefix}.GAIN`,
        `GET ${prefix}.BYPASS`,
      );
    }
    const responses = await this.execute(commands);
    const values = Object.assign({}, ...responses);
    if (asBoolean(values[`${root}.BYPASS`])) return 'flat';

    for (const preset of PRESETS) {
      if (preset.id === 'flat') continue;
      const expected = powerZoneBands(preset.id, info.eqBands);
      if (PowerZoneClient.matchesBands(root, expected, info.eqBands, values)) return preset.id;
    }
    return null;
  }

  static matchesBands(root, expected, bandCount, values) {
    for (let bandId = 1; bandId <= bandCount; bandId += 1) {
      const prefix = `${root}-${bandId}`;
      if (bandId > expected.length) {
        if (!asBoolean(values[`${prefix}.BYPASS`])) return false;
        continue;
      }
      const band = expected[bandId - 1];
      if (asBoolean(values[`${prefix}.BYPASS`])) return false;
      if (values[`${prefix}.TYPE`] !== band.type) return false;
      const frequency = Number(values[`${prefix}.FREQ`]);
      const q = Number(values[`${prefix}.Q`]);
      const gain = Number(values[`${prefix}.GAIN`]);
      if (![frequency, q, gain].every(Number.isFinite)) return false;
      if (Math.abs(frequency - band.frequency) > 0.1) return false;
      if (Math.abs(q - band.q) > 0.01) return false;
      if (Math.abs(gain - band.gain) > 0.05) return false;
    }
    return true;
  }
}

module.exports = {
  DEFAULT_PORT,
  PowerZoneApiError,
  PowerZoneClient,
  PowerZoneNetworkError,
  isLocalAddress,
};

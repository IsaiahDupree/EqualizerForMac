class SonanceHomeCard extends HTMLElement {
  constructor() {
    super();
    this.attachShadow({ mode: "open" });
    this._config = {};
    this._hass = null;
    this._built = false;
  }

  setConfig(config) {
    this._config = config || {};
  }

  set hass(hass) {
    this._hass = hass;
    if (!this._built) this._build();
    this._refreshPlayers();
  }

  getCardSize() {
    return 5;
  }

  _build() {
    this._built = true;
    const style = document.createElement("style");
    style.textContent = `
      :host { display:block; }
      ha-card { overflow:hidden; background:linear-gradient(145deg,#071a26,#0b3440); color:#f5ffff; }
      .header { padding:22px 22px 10px; display:flex; align-items:center; gap:12px; }
      .mark { width:38px; height:38px; display:grid; place-items:center; border-radius:12px;
        background:#38e8d6; color:#06242b; font-size:20px; font-weight:900; }
      h2 { margin:0; font-size:20px; letter-spacing:-.02em; }
      .sub { color:#a9c8ce; font-size:12px; margin-top:2px; }
      .body { padding:10px 22px 22px; display:grid; gap:12px; }
      label { display:grid; gap:5px; color:#b9d0d5; font-size:12px; font-weight:700; }
      select,input { width:100%; box-sizing:border-box; border:1px solid #315661; border-radius:10px;
        padding:11px 12px; background:#09232e; color:#fff; font:inherit; outline:none; }
      select:focus,input:focus { border-color:#38e8d6; box-shadow:0 0 0 2px #38e8d633; }
      .row { display:grid; grid-template-columns:1fr 1fr; gap:10px; }
      .actions { display:flex; gap:10px; padding-top:2px; }
      button { flex:1; border:0; border-radius:10px; padding:12px; cursor:pointer; font-weight:800; }
      .send { background:#38e8d6; color:#06242b; }
      .apply { background:#163e49; color:#dffbff; }
      button:disabled { opacity:.45; cursor:not-allowed; }
      .status { min-height:18px; color:#a9c8ce; font-size:12px; }
      .status.error { color:#ffb4ab; }
      .notice { border-left:3px solid #f0b95b; padding:7px 9px; background:#f0b95b14;
        color:#f6ddb0; font-size:12px; border-radius:0 8px 8px 0; }
      [hidden] { display:none !important; }
      @media(max-width:430px) { .row { grid-template-columns:1fr; } }
    `;

    const card = document.createElement("ha-card");
    const header = document.createElement("div");
    header.className = "header";
    const mark = document.createElement("div");
    mark.className = "mark";
    mark.textContent = "S";
    const heading = document.createElement("div");
    const title = document.createElement("h2");
    title.textContent = this._config.title || "Sonance Home";
    const sub = document.createElement("div");
    sub.className = "sub";
    sub.textContent = "EQ · Cast · room routing";
    heading.append(title, sub);
    header.append(mark, heading);

    const body = document.createElement("div");
    body.className = "body";
    this._player = this._selectField("Send to", body);
    this._player.addEventListener("change", () => this._targetChanged());

    const mediaLabel = document.createElement("label");
    mediaLabel.textContent = "Media URL, media-source URI, or provider link";
    this._media = document.createElement("input");
    this._media.type = "text";
    this._media.placeholder = "https://… or spotify://…";
    this._media.autocomplete = "off";
    mediaLabel.append(this._media);
    body.append(mediaLabel);

    const row = document.createElement("div");
    row.className = "row";
    this._preset = this._selectField("EQ preset", row);
    ["None", "Flat", "Bass Boost", "Treble", "Vocal", "Loudness", "Warm Room", "Night", "Small Speaker", "Cinema"]
      .forEach((name) => this._preset.add(new Option(name, name === "None" ? "" : name)));
    this._preset.value = this._config.preset || "Flat";
    this._mediaType = this._selectField("Media type", row);
    [["Music", "music"], ["Audio", "audio"], ["Video", "video"]]
      .forEach(([label, value]) => this._mediaType.add(new Option(label, value)));
    body.append(row);

    this._notice = document.createElement("div");
    this._notice.className = "notice";
    this._notice.hidden = true;
    body.append(this._notice);

    const actions = document.createElement("div");
    actions.className = "actions";
    this._apply = document.createElement("button");
    this._apply.className = "apply";
    this._apply.textContent = "Apply EQ";
    this._apply.addEventListener("click", () => this._applyPreset());
    this._send = document.createElement("button");
    this._send.className = "send";
    this._send.textContent = "Send to device";
    this._send.addEventListener("click", () => this._sendMedia());
    actions.append(this._apply, this._send);
    body.append(actions);

    this._status = document.createElement("div");
    this._status.className = "status";
    body.append(this._status);
    card.append(header, body);
    this.shadowRoot.append(style, card);
  }

  _selectField(title, parent) {
    const label = document.createElement("label");
    label.textContent = title;
    const select = document.createElement("select");
    label.append(select);
    parent.append(label);
    return select;
  }

  _refreshPlayers() {
    if (!this._hass || !this._player) return;
    const selected = this._player.value || this._config.entity || "";
    const players = Object.values(this._hass.states)
      .filter((state) => state.entity_id.startsWith("media_player."))
      .sort((a, b) => (a.attributes.friendly_name || a.entity_id)
        .localeCompare(b.attributes.friendly_name || b.entity_id));
    const signature = players.map((state) => `${state.entity_id}:${state.attributes.friendly_name}`).join("|");
    if (signature !== this._playerSignature) {
      this._playerSignature = signature;
      this._player.replaceChildren();
      players.forEach((state) => {
        const option = new Option(state.attributes.friendly_name || state.entity_id, state.entity_id);
        this._player.add(option);
      });
      if (players.some((state) => state.entity_id === selected)) this._player.value = selected;
      else if (players.length) this._player.value = players[0].entity_id;
    }
    this._targetChanged();
  }

  _targetChanged() {
    if (!this._hass || !this._player) return;
    const state = this._hass.states[this._player.value];
    const isMusicAssistant = Boolean(state && state.attributes.mass_player_type);
    this._apply.disabled = !isMusicAssistant || !this._preset.value;
    this._notice.hidden = isMusicAssistant;
    this._notice.textContent = isMusicAssistant ? "" :
      "This is a direct Home Assistant player. Sending works, but EQ requires its Music Assistant version.";
    if (!isMusicAssistant && this._preset.value) this._preset.value = "";
  }

  async _applyPreset() {
    if (!this._player.value || !this._preset.value) return;
    await this._call("apply_preset", {
      entity_id: this._player.value,
      preset: this._preset.value,
    }, "EQ applied");
  }

  async _sendMedia() {
    const media = this._media.value.trim();
    if (!this._player.value || !media) {
      this._setStatus("Choose a player and enter media first", true);
      return;
    }
    const data = {
      entity_id: this._player.value,
      media_id: media,
      media_type: this._mediaType.value,
    };
    if (this._preset.value) data.preset = this._preset.value;
    await this._call("send_to_device", data, "Sent to device");
  }

  async _call(service, data, success) {
    this._send.disabled = true;
    this._apply.disabled = true;
    this._setStatus("Working…", false);
    try {
      await this._hass.callService("sonance_eq", service, data);
      this._setStatus(success, false);
    } catch (error) {
      this._setStatus(error && error.message ? error.message : String(error), true);
    } finally {
      this._send.disabled = false;
      this._targetChanged();
    }
  }

  _setStatus(message, error) {
    this._status.textContent = message;
    this._status.classList.toggle("error", error);
  }
}

customElements.define("sonance-home-card", SonanceHomeCard);
window.customCards = window.customCards || [];
window.customCards.push({
  type: "sonance-home-card",
  name: "Sonance Home",
  description: "Apply Sonance EQ presets and send media to a Home Assistant player.",
  preview: true,
});

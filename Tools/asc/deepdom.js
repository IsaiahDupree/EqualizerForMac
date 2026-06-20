// deepdom.js — shadow-DOM-piercing automation primitives for App Store Connect (and any web-component SPA).
// Injected into Safari via `do JavaScript`. App Store Connect renders its forms inside nested shadow roots,
// so flat document.querySelector finds nothing — every helper here recurses through `.shadowRoot`.
// Elements are addressed by a `data-asc-id` stamped during fields(), so actions survive across calls
// without serializing brittle CSS paths. Idempotent: re-defining window.__asc is safe.
(function () {
  const A = {
    // All elements matching `sel` anywhere in the tree, descending into every open shadow root.
    deepAll(sel, root) {
      root = root || document;
      let acc = [];
      try { root.querySelectorAll(sel).forEach((e) => acc.push(e)); } catch (e) {}
      root.querySelectorAll('*').forEach((e) => { if (e.shadowRoot) acc = acc.concat(A.deepAll(sel, e.shadowRoot)); });
      return acc;
    },

    // Best-effort human label for an element.
    label(e) {
      const g = (a) => (e.getAttribute && e.getAttribute(a)) || '';
      let l = g('aria-label') || g('name') || g('placeholder') || g('title');
      if (!l && e.labels && e.labels[0]) l = e.labels[0].innerText;
      if (!l && e.id) l = e.id;
      return (l || '').trim();
    },

    // Enumerate every interactive control; stamp each with data-asc-id and return a descriptor list.
    fields() {
      const sel = 'input,select,textarea,button,[role=button],[role=checkbox],[role=combobox],[role=switch],[contenteditable=true]';
      return A.deepAll(sel).map((e, i) => {
        e.setAttribute('data-asc-id', i);
        return {
          id: i, tag: e.tagName, type: e.type || e.getAttribute('role') || '',
          label: A.label(e).slice(0, 70), text: (e.innerText || '').trim().slice(0, 50),
          checked: e.checked === true || e.getAttribute('aria-checked') === 'true',
          disabled: e.disabled === true || e.getAttribute('aria-disabled') === 'true',
          options: e.options ? [].slice.call(e.options).map((o) => o.text) : undefined,
        };
      });
    },

    el(id) { return A.deepAll('[data-asc-id="' + id + '"]')[0]; },

    // Set a value the React/web-component way: native setter + input/change so frameworks notice.
    set(id, val) {
      const e = A.el(id); if (!e) return 'no-el';
      const proto = e.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype
        : e.tagName === 'SELECT' ? HTMLSelectElement.prototype : HTMLInputElement.prototype;
      const setter = Object.getOwnPropertyDescriptor(proto, 'value');
      if (setter && setter.set) setter.set.call(e, val); else e.value = val;
      e.dispatchEvent(new Event('input', { bubbles: true }));
      e.dispatchEvent(new Event('change', { bubbles: true }));
      return 'ok';
    },

    check(id, on) {
      const e = A.el(id); if (!e) return 'no-el';
      const want = on !== false;
      const isOn = e.checked === true || e.getAttribute('aria-checked') === 'true';
      if (isOn !== want) e.click();
      return 'ok';
    },

    click(id) { const e = A.el(id); if (!e) return 'no-el'; e.click(); return 'ok'; },

    // Click the first element (button/option/menu item) whose trimmed text matches exactly (case-insensitive).
    clickText(txt) {
      const t = txt.trim().toLowerCase();
      const e = A.deepAll('button,a,[role=button],[role=option],[role=menuitem],li,span,div')
        .filter((x) => (x.innerText || '').trim().toLowerCase() === t)[0];
      if (!e) return 'no-match'; e.click(); return 'ok';
    },

    // Pick an option in a <select> or a custom combobox by visible text.
    pick(id, optText) {
      const e = A.el(id); if (!e) return 'no-el';
      if (e.tagName === 'SELECT') {
        const o = [].slice.call(e.options).find((o) => o.text.trim() === optText.trim());
        if (!o) return 'no-option'; e.value = o.value;
        e.dispatchEvent(new Event('change', { bubbles: true })); return 'ok';
      }
      e.click(); return 'opened-combobox'; // then use clickText(optText)
    },

    // Does any element matching `sel` (deep) exist / contain text? For wait_for polling.
    exists(sel) { return A.deepAll(sel).length > 0; },
    hasText(txt) {
      const t = txt.toLowerCase();
      return A.deepAll('*').some((e) => (e.innerText || '').toLowerCase().includes(t));
    },
  };
  window.__asc = A;
})();

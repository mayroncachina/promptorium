import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/dev/picker_script.dart';

/// A small DOM in plain JavaScript: elements, attributes, events and the
/// selectors the picker writes (`#id`, `tag`, `.class`, `[attr=v]`,
/// `:nth-of-type(n)`, ` > `). Enough to run [pickerSource] in `node`.
const _fakeDom = r'''
function El(tag, attrs, kids) {
  this.tagName = tag.toUpperCase(); this.nodeType = 1;
  this.attrs = Object.assign({}, attrs || {}); this.children = [];
  this.parentElement = null; this.parentNode = null; this.style = {};
  this.textContent = ''; this.listeners = {};
  this.id = this.attrs.id || '';
  (kids || []).forEach(k => this.appendChild(k));
}
El.prototype.appendChild = function (c) {
  c.parentElement = this; c.parentNode = this; this.children.push(c); return c;
};
El.prototype.removeChild = function (c) {
  this.children = this.children.filter(x => x !== c); c.parentElement = null;
  c.parentNode = null;
};
El.prototype.getAttribute = function (n) {
  return n in this.attrs ? this.attrs[n] : null;
};
El.prototype.setAttribute = function (n, v) {
  this.attrs[n] = String(v); if (n === 'id') this.id = v;
};
El.prototype.removeAttribute = function (n) { delete this.attrs[n]; };
Object.defineProperty(El.prototype, 'previousElementSibling', { get() {
  if (!this.parentElement) return null;
  const s = this.parentElement.children, i = s.indexOf(this);
  return i > 0 ? s[i - 1] : null;
}});
Object.defineProperty(El.prototype, 'outerHTML', { get() {
  const t = this.tagName.toLowerCase();
  const a = Object.keys(this.attrs).map(k => ` ${k}="${this.attrs[k]}"`).join('');
  return `<${t}${a}>${this.textContent}${this.children.map(c => c.outerHTML).join('')}</${t}>`;
}});
El.prototype.cloneNode = function () {
  const c = new El(this.tagName, this.attrs, this.children.map(k => k.cloneNode()));
  c.textContent = this.textContent; return c;
};
El.prototype.getBoundingClientRect = function () {
  return { left: 10, top: 20, width: 348, height: 44 };
};
El.prototype.all = function () {
  return this.children.reduce((a, c) => a.concat([c], c.all()), []);
};
El.prototype.querySelectorAll = function (s) {
  return this.all().filter(e => matches(e, s));
};
El.prototype.addEventListener = function (t, f) {
  (this.listeners[t] = this.listeners[t] || []).push(f);
};

function compound(e, c) {
  const re = /^([a-z0-9]+)?((?:#[\w-]+|\.[\w-]+|\[[\w-]+=(?:"[^"]*"|[\w-]+)\]|:nth-of-type\(\d+\))*)$/;
  const m = re.exec(c); if (!m) throw new Error('seletor: ' + c);
  if (m[1] && e.tagName.toLowerCase() !== m[1]) return false;
  const parts = m[2].match(/#[\w-]+|\.[\w-]+|\[[^\]]+\]|:nth-of-type\(\d+\)/g) || [];
  for (const p of parts) {
    if (p[0] === '#' && e.id !== p.slice(1)) return false;
    if (p[0] === '.' && !(e.getAttribute('class') || '').split(/\s+/).includes(p.slice(1))) return false;
    if (p[0] === '[') {
      const [k, v] = p.slice(1, -1).split('=');
      if (e.getAttribute(k) !== v.replace(/^"|"$/g, '')) return false;
    }
    if (p[0] === ':') {
      const n = +p.match(/\d+/)[0]; let i = 1;
      for (let s = e.previousElementSibling; s; s = s.previousElementSibling) if (s.tagName === e.tagName) i++;
      if (i !== n) return false;
    }
  }
  return true;
}
function matches(e, sel) {
  const parts = sel.split(' > ');
  let node = e;
  for (let i = parts.length - 1; i >= 0; i--) {
    if (!node || node.nodeType !== 1 || !compound(node, parts[i])) return false;
    node = node.parentElement;
  }
  return true;
}
''';

const _harness = r'''
const button = new El('button', { type: 'submit', class: 'btn btn-primary' });
button.textContent = 'Continuar';
const second = new El('button', { type: 'button', class: 'btn' });
const items = [1, 2, 3].map(i => new El('li', { class: 'item' }));
const pwd = new El('input', { type: 'password', value: 'segredo', name: 'senha' });
const big = new El('div', { class: 'big' }); big.textContent = 'x'.repeat(6000);
const ided = new El('h1', { id: 'titulo' });
const html = new El('html', {}, [new El('body', {}, [
  ided,
  new El('form', { class: 'login' }, [pwd, button, second]),
  new El('ul', {}, items),
  new El('div', { class: 'card' }, [new El('span', {})]),
  new El('div', { class: 'card' }, [new El('span', {})]),
  big,
])]);
const document = {
  documentElement: html,
  createElement: t => new El(t),
  querySelectorAll: s => html.querySelectorAll(s).concat(matches(html, s) ? [html] : []),
};
const listeners = {};
const calls = [];
const timers = [];
let pageClicks = 0;
button.addEventListener('click', () => pageClicks++);
const window = {
  location: { hostname: HOST, port: '4003', href: 'http://' + HOST + ':4003/login' },
  scrollX: 0, scrollY: 100, devicePixelRatio: 1,
  setTimeout: (f, ms) => timers.push(f),
  addEventListener: (t, f) => (listeners[t] = listeners[t] || []).push(f),
  removeEventListener: (t, f) => listeners[t] = (listeners[t] || []).filter(x => x !== f),
  getComputedStyle: () => ({ getPropertyValue: p => ({
    'background-color': 'rgb(157, 184, 238)', color: '#fff', display: 'inline-block',
  })[p] || '' }),
  __promptoriumPick: p => calls.push(JSON.parse(p)),
};
function dispatch(type, target, extra) {
  let stopped = false, prevented = false;
  const ev = Object.assign({ type, target,
    preventDefault() { prevented = true; },
    stopPropagation() { stopped = true; },
    stopImmediatePropagation() { stopped = true; } }, extra || {});
  (listeners[type] || []).slice().forEach(f => f(ev));
  if (!stopped) (target.listeners[type] || []).forEach(f => f(ev));
  return { stopped, prevented };
}
const pick = (PICKER)(window, document, OPTS);
const out = { status: pick };
if (pick === 'on') {
  const api = window.__promptoriumPicker;
  const targets = { button, second, li2: items[1], span2: html.all().filter(e => e.tagName === 'SPAN')[1], ided, pwd };
  out.selectors = {};
  for (const k in targets) {
    const s = api.selectorFor(targets[k]);
    out.selectors[k] = { s, count: document.querySelectorAll(s).length,
      same: document.querySelectorAll(s)[0] === targets[k] };
  }
  out.band = html.children.some(e => e.textContent && e.textContent.indexOf('Esc cancela') >= 0);
  dispatch('mousemove', button);
  out.label = html.children.map(e => e.textContent).filter(t => t.indexOf('×') >= 0)[0];
  out.down = dispatch('mousedown', button);
  out.click = dispatch('click', button);
  out.pageClicks = pageClicks;
  out.payload = calls[0];
  const shown = () => html.children.filter(e => e.getAttribute('data-promptorium') && e.style.display === 'block').length;
  out.shownAfterPick = shown();
  out.mark = window.__promptoriumPicker.mark();
  out.shownAfterMark = shown();
  // After the pick, the page gets its clicks back.
  dispatch('click', button);
  out.pageClicksAfter = pageClicks;

  // Esc cancels; html of a password input loses its value; 4 KB cap.
  (PICKER)(window, document, OPTS);
  out.esc = dispatch('keydown', document.documentElement, { key: 'Escape' });
  out.cancel = calls[1];
  out.left = !!window.__promptoriumPicker;
  (PICKER)(window, document, OPTS);
  dispatch('click', pwd);
  out.pwd = calls[2].html;
  (PICKER)(window, document, OPTS);
  dispatch('click', big);
  out.bigLength = calls[3].html.length;
  // A disabled button gets pointerdown but no click: the press picks.
  (PICKER)(window, document, OPTS);
  const down = dispatch('pointerdown', second);
  out.pointer = { stopped: down.stopped, selector: calls[4] && calls[4].selector,
    timers: timers.length };
}
console.log(JSON.stringify(out));
''';

Future<Map<String, dynamic>?> _run(String host) async {
  final node = await Process.run('which', ['node']);
  if (node.exitCode != 0) return null;
  final dir = Directory.systemTemp.createTempSync('picker_');
  addTearDown(() => dir.deleteSync(recursive: true));
  final opts = jsonEncode({
    'port': 4003,
    'binding': pickerBinding,
    'maxHtml': pickerMaxHtml,
    'styles': pickerStyles,
  });
  final js = File('${dir.path}/run.js')
    ..writeAsStringSync(
      [
        'const HOST = ${jsonEncode(host)};',
        'const OPTS = $opts;',
        _fakeDom,
        _harness.replaceAll('PICKER', pickerSource),
      ].join('\n'),
    );
  final r = await Process.run('node', [js.path]);
  expect(r.exitCode, 0, reason: '${r.stderr}');
  return jsonDecode('${r.stdout}'.trim()) as Map<String, dynamic>;
}

void main() {
  test('the selector is unique on the page and the click is captured '
      'without reaching it (R7)', () async {
    final out = await _run('127.0.0.1');
    if (out == null) return markTestSkipped('sem node');
    expect(out['status'], 'on');
    expect(out['band'], isTrue);
    final sel = (out['selectors'] as Map).cast<String, Map>();
    for (final MapEntry(:key, :value) in sel.entries) {
      expect(value['count'], 1, reason: '$key: ${value['s']}');
      expect(value['same'], isTrue, reason: '$key: ${value['s']}');
    }
    expect(sel['ided']!['s'], '#titulo');
    expect(sel['button']!['s'], 'button.btn-primary');
    expect(sel['pwd']!['s'], 'input[name="senha"]');
    expect(sel['li2']!['s'], 'li:nth-of-type(2)');
    expect(out['label'], 'button.btn-primary · 348 × 44');

    expect(out['down'], {'stopped': true, 'prevented': true});
    expect(out['click'], {'stopped': true, 'prevented': true});
    expect(out['pageClicks'], 0);
    expect(out['pageClicksAfter'], 1);

    // Clean element print, then the box for the page print.
    expect(out['shownAfterPick'], 0);
    expect(out['mark'], 'marked');
    expect(out['shownAfterMark'], 1);
    final p = out['payload'] as Map;
    expect(p['selector'], 'button.btn-primary');
    expect(p['url'], 'http://127.0.0.1:4003/login');
    expect(p['html'], contains('Continuar'));
    expect(p['styles'], containsPair('background-color', 'rgb(157, 184, 238)'));
    expect(p['box'], {'x': 10, 'y': 120, 'width': 348, 'height': 44});
  });

  test(
    'Esc cancels; password values and size are kept out (R7, R10)',
    () async {
      final out = await _run('localhost');
      if (out == null) return markTestSkipped('sem node');
      expect(out['esc'], {'stopped': true, 'prevented': true});
      expect(out['cancel'], {'cancel': true});
      expect(out['left'], isFalse);
      expect(out['pwd'], isNot(contains('segredo')));
      expect(out['pwd'], contains('type="password"'));
      expect(out['bigLength'], pickerMaxHtml + 1);
      expect(out['pointer'], {
        'stopped': true,
        'selector': 'button[type=button]',
        'timers': 2, // the mousedown pick above and this one
      });
    },
  );

  test('another host or port is blocked (R10)', () async {
    final out = await _run('exemplo.com');
    if (out == null) return markTestSkipped('sem node');
    expect(out['status'], 'blocked');
    expect(pickerExpression(4003), contains('"port":4003'));
    expect(pickerExpression(4003), isNot(contains('cookie')));
    expect(pickerSource, isNot(contains('localStorage')));
  });
}

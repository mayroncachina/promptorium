import 'dart:convert';

/// The JavaScript the preview injects for "Apontar" (SPEC-051 R7, R10).
///
/// [pickerSource] is a function `(window, document, opts) => api` so the
/// tests run it on a fake DOM; [pickerExpression] is what goes to
/// `Runtime.evaluate`. The script:
/// - runs only on `localhost` / `127.0.0.1` at the preview's port (else it
///   returns `"blocked"`);
/// - shows the band "Promptorium · clique num elemento · Esc cancela" and
///   outlines the element under the mouse with its selector and size;
/// - takes the click (no click reaches the page) and calls the binding with
///   the selector, `outerHTML` (≤ 4 KB, password values removed), the
///   relevant computed styles, the box and the URL;
/// - Esc calls the binding with `{"cancel": true}`.
///
/// It never reads cookies, `localStorage` or password fields.

/// Name of the `Runtime.addBinding` the script calls.
const pickerBinding = '__promptoriumPick';

/// Max `outerHTML` sent to the session.
const pickerMaxHtml = 4096;

/// Computed styles sent with the element (R7).
const pickerStyles = [
  'display',
  'position',
  'width',
  'height',
  'margin',
  'padding',
  'color',
  'background-color',
  'border',
  'border-radius',
  'font-family',
  'font-size',
  'font-weight',
  'line-height',
  'opacity',
  'cursor',
  'gap',
  'flex-direction',
  'justify-content',
  'align-items',
];

const pickerSource = r'''
function (w, d, opts) {
  var host = w.location.hostname;
  if ((host !== 'localhost' && host !== '127.0.0.1') ||
      String(w.location.port) !== String(opts.port)) {
    return 'blocked';
  }
  if (w.__promptoriumPicker) { w.__promptoriumPicker.stop(); }
  var AMBER = '#F2A541';
  var mine = [];
  function make(tag, css, text) {
    var e = d.createElement(tag);
    e.setAttribute('data-promptorium', '1');
    e.style.cssText = css;
    if (text) e.textContent = text;
    d.documentElement.appendChild(e);
    mine.push(e);
    return e;
  }
  var band = make('div',
    'position:fixed;top:0;left:0;right:0;z-index:2147483647;' +
    'padding:6px 12px;background:#14171D;color:#E7E9EE;' +
    'font:500 12px system-ui,sans-serif;border-bottom:2px solid ' + AMBER +
    ';pointer-events:none;text-align:center',
    'Promptorium · clique num elemento · Esc cancela');
  var box = make('div',
    'position:fixed;z-index:2147483646;pointer-events:none;display:none;' +
    'border:2px solid ' + AMBER + ';background:rgba(242,165,65,.12);' +
    'border-radius:3px;box-sizing:border-box');
  var label = make('div',
    'position:fixed;z-index:2147483647;pointer-events:none;display:none;' +
    'padding:2px 6px;background:' + AMBER + ';color:#1A1206;' +
    'font:600 11px ui-monospace,monospace;border-radius:3px;white-space:nowrap');

  function isMine(e) {
    for (var n = e; n; n = n.parentElement) {
      if (n.getAttribute && n.getAttribute('data-promptorium')) return true;
    }
    return false;
  }
  var ident = /^[A-Za-z_-][A-Za-z0-9_-]*$/;
  function esc(s) {
    return ident.test(s) ? s : String(s).replace(/([^A-Za-z0-9_-])/g, '\\$1');
  }
  function q(s) { return '"' + String(s).replace(/(["\\])/g, '\\$1') + '"'; }
  function tag(e) { return e.tagName.toLowerCase(); }
  function unique(s, e) {
    try {
      var all = d.querySelectorAll(s);
      return all.length === 1 && all[0] === e;
    } catch (_) { return false; }
  }
  function classes(e) {
    var c = (e.getAttribute('class') || '').split(/\s+/);
    var out = [];
    for (var i = 0; i < c.length; i++) {
      if (c[i] && ident.test(c[i]) && c[i].length <= 30) out.push(c[i]);
    }
    return out;
  }
  function nth(e) {
    var n = 1;
    for (var s = e.previousElementSibling; s; s = s.previousElementSibling) {
      if (s.tagName === e.tagName) n++;
    }
    return n;
  }
  function candidates(e) {
    var t = tag(e), out = [t], c = classes(e);
    for (var i = 0; i < c.length; i++) out.push(t + '.' + c[i]);
    if (c.length > 1) out.push(t + '.' + c.join('.'));
    var type = e.getAttribute('type');
    if (type && ident.test(type)) out.push(t + '[type=' + type + ']');
    out.push(t + ':nth-of-type(' + nth(e) + ')');
    return out;
  }
  // The shortest selector that matches only [e].
  function selectorFor(e) {
    if (e.id && unique('#' + esc(e.id), e)) return '#' + esc(e.id);
    var attrs = ['data-testid', 'data-test', 'data-cy', 'name', 'aria-label'];
    for (var i = 0; i < attrs.length; i++) {
      var v = e.getAttribute(attrs[i]);
      if (v) {
        var s = tag(e) + '[' + attrs[i] + '=' + q(v) + ']';
        if (unique(s, e)) return s;
      }
    }
    var chain = [];
    for (var n = e; n && n.nodeType === 1; n = n.parentElement) {
      var cs = candidates(n);
      for (var j = 0; j < cs.length; j++) {
        var sel = [cs[j]].concat(chain).join(' > ');
        if (unique(sel, e)) return sel;
      }
      chain.unshift(cs[cs.length - 1]);
      var p = n.parentElement;
      if (p && p.id && unique('#' + esc(p.id), p)) {
        var anchored = ['#' + esc(p.id)].concat(chain).join(' > ');
        if (unique(anchored, e)) return anchored;
      }
    }
    return chain.join(' > ');
  }
  function html(e) {
    var c = e.cloneNode(true);
    var inputs = [c].concat(Array.prototype.slice.call(
      c.querySelectorAll ? c.querySelectorAll('input') : []));
    for (var i = 0; i < inputs.length; i++) {
      var x = inputs[i];
      if (x.tagName === 'INPUT' &&
          String(x.getAttribute('type') || '').toLowerCase() === 'password') {
        x.removeAttribute('value');
      }
    }
    var h = c.outerHTML || '';
    return h.length > opts.maxHtml ? h.slice(0, opts.maxHtml) + '…' : h;
  }
  function styles(e) {
    var cs = w.getComputedStyle(e), out = {};
    for (var i = 0; i < opts.styles.length; i++) {
      var v = cs.getPropertyValue(opts.styles[i]);
      if (v) out[opts.styles[i]] = v;
    }
    return out;
  }
  var current = null;
  function show(e, marked) {
    var r = e.getBoundingClientRect();
    box.style.display = 'block';
    box.style.left = r.left + 'px';
    box.style.top = r.top + 'px';
    box.style.width = r.width + 'px';
    box.style.height = r.height + 'px';
    if (marked) box.style.background = 'transparent';
    label.style.display = 'block';
    label.style.left = r.left + 'px';
    label.style.top = Math.max(0, r.top - 20) + 'px';
    label.textContent = selectorFor(e) + ' · ' + Math.round(r.width) +
      ' × ' + Math.round(r.height);
  }
  function capture(e) {
    var r = e.getBoundingClientRect();
    var data = {
      selector: selectorFor(e),
      html: html(e),
      styles: styles(e),
      box: { x: r.left + w.scrollX, y: r.top + w.scrollY,
             width: r.width, height: r.height },
      viewport: { x: r.left, y: r.top, width: r.width, height: r.height },
      url: w.location.href,
      dpr: w.devicePixelRatio || 1
    };
    // The element's print goes clean; [mark] shows it for the page's.
    band.style.display = 'none';
    box.style.display = 'none';
    label.style.display = 'none';
    current = e;
    return data;
  }
  function swallow(ev) {
    ev.preventDefault();
    ev.stopPropagation();
    if (ev.stopImmediatePropagation) ev.stopImmediatePropagation();
  }
  function onMove(ev) {
    var t = ev.target;
    if (!t || t.nodeType !== 1 || isMine(t) || t === current) return;
    current = t;
    show(t, false);
  }
  // The press picks: pointerdown, because a disabled button gets no
  // click. The rest of that press (mouseup, click) is swallowed too.
  var done = false;
  function onPress(ev) {
    if (isMine(ev.target)) return;
    swallow(ev);
    if (done) {
      if (ev.type === 'click') off();
      return;
    }
    if (ev.type !== 'pointerdown' && ev.type !== 'mousedown' &&
        ev.type !== 'click') return;
    var t = ev.target;
    if (!t || t.nodeType !== 1) return;
    done = true;
    if (ev.type === 'click') off(); else w.setTimeout(off, 600);
    w[opts.binding](JSON.stringify(capture(t)));
  }
  function onKey(ev) {
    if (ev.key !== 'Escape') return;
    swallow(ev);
    api.stop();
    w[opts.binding](JSON.stringify({ cancel: true }));
  }
  var presses = ['pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click',
                 'dblclick', 'contextmenu', 'submit'];
  function off() {
    w.removeEventListener('mousemove', onMove, true);
    w.removeEventListener('keydown', onKey, true);
    for (var i = 0; i < presses.length; i++) {
      w.removeEventListener(presses[i], onPress, true);
    }
  }
  w.addEventListener('mousemove', onMove, true);
  w.addEventListener('keydown', onKey, true);
  for (var i = 0; i < presses.length; i++) {
    w.addEventListener(presses[i], onPress, true);
  }
  var api = {
    selectorFor: selectorFor,
    mark: function () {
      if (current) show(current, true);
      label.style.display = 'none';
      return 'marked';
    },
    stop: function () {
      off();
      for (var i = 0; i < mine.length; i++) {
        if (mine[i].parentNode) mine[i].parentNode.removeChild(mine[i]);
      }
      mine = [];
      if (w.__promptoriumPicker === api) delete w.__promptoriumPicker;
    }
  };
  w.__promptoriumPicker = api;
  return 'on';
}
''';

/// `Runtime.evaluate` expression that turns the picker on in the preview
/// page of [port].
String pickerExpression(int port) {
  final opts = jsonEncode({
    'port': port,
    'binding': pickerBinding,
    'maxHtml': pickerMaxHtml,
    'styles': pickerStyles,
  });
  return '($pickerSource)(window, document, $opts)';
}

/// Outlines the picked element for the print of the page.
const pickerMarkExpression =
    'window.__promptoriumPicker ? window.__promptoriumPicker.mark() : "off"';

/// Turns the picker off (Esc, a second "Apontar", after the screenshots).
const pickerStopExpression =
    'window.__promptoriumPicker ? (window.__promptoriumPicker.stop(), "off") '
    ': "off"';

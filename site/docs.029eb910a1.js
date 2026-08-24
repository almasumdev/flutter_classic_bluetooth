/* excel_plus docs. No dependencies. */
(function () {
  'use strict';

  /* ---------- mobile drawer ---------- */
  var sidebar = document.getElementById('sidebar');
  var toggle = document.querySelector('.menu');
  var scrim = document.querySelector('.scrim');

  function setDrawer(open) {
    if (!sidebar) return;
    sidebar.classList.toggle('open', open);
    if (scrim) scrim.classList.toggle('on', open);
    if (toggle) toggle.setAttribute('aria-expanded', open ? 'true' : 'false');
    document.body.style.overflow = open ? 'hidden' : '';
  }

  if (toggle) {
    toggle.addEventListener('click', function () {
      setDrawer(!sidebar.classList.contains('open'));
    });
  }
  if (scrim) scrim.addEventListener('click', function () { setDrawer(false); });
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape') setDrawer(false);
  });

  /* ---------- Dart syntax highlighting ----------
     Tokenises comments, strings, annotations, numbers, keywords and type
     names. Runs on textContent, so the source is already entity-decoded and
     the output is built with escaped text nodes only. */
  var KEYWORDS = ('abstract as assert async await break case catch class const continue covariant ' +
    'default deferred do dynamic else enum export extends extension external factory false final ' +
    'finally for get hide if implements import in interface is late library mixin new null on ' +
    'operator part required rethrow return sealed set show static super switch sync this throw ' +
    'true try typedef var void while with yield').split(' ');
  var KEYSET = Object.create(null);
  for (var i = 0; i < KEYWORDS.length; i++) KEYSET[KEYWORDS[i]] = true;

  function esc(s) {
    return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }

  function highlightDart(src) {
    var out = '';
    var n = src.length;
    var i = 0;
    while (i < n) {
      var c = src[i];

      // line comment
      if (c === '/' && src[i + 1] === '/') {
        var e = src.indexOf('\n', i);
        if (e === -1) e = n;
        out += '<span class="tok-com">' + esc(src.slice(i, e)) + '</span>';
        i = e;
        continue;
      }
      // block comment
      if (c === '/' && src[i + 1] === '*') {
        var b = src.indexOf('*/', i + 2);
        b = b === -1 ? n : b + 2;
        out += '<span class="tok-com">' + esc(src.slice(i, b)) + '</span>';
        i = b;
        continue;
      }
      // string, with optional r prefix
      if (c === "'" || c === '"' || ((c === 'r') && (src[i + 1] === "'" || src[i + 1] === '"'))) {
        var start = i;
        if (c === 'r') i++;
        var q = src[i];
        i++;
        while (i < n && src[i] !== q) {
          if (src[i] === '\\' && src[start] !== 'r') i++;
          if (src[i] === '\n') break;
          i++;
        }
        i = Math.min(i + 1, n);
        out += '<span class="tok-str">' + esc(src.slice(start, i)) + '</span>';
        continue;
      }
      // annotation
      if (c === '@' && /[A-Za-z_]/.test(src[i + 1] || '')) {
        var am = /^@[A-Za-z_$][\w$]*/.exec(src.slice(i))[0];
        out += '<span class="tok-ann">' + esc(am) + '</span>';
        i += am.length;
        continue;
      }
      // number
      if (/[0-9]/.test(c)) {
        var nm = /^(0x[0-9a-fA-F]+|[0-9]+\.?[0-9]*(e[+-]?[0-9]+)?)/.exec(src.slice(i))[0];
        out += '<span class="tok-num">' + esc(nm) + '</span>';
        i += nm.length;
        continue;
      }
      // identifier
      if (/[A-Za-z_$]/.test(c)) {
        var im = /^[A-Za-z_$][\w$]*/.exec(src.slice(i))[0];
        if (KEYSET[im]) out += '<span class="tok-key">' + esc(im) + '</span>';
        else if (/^[A-Z]/.test(im)) out += '<span class="tok-cls">' + esc(im) + '</span>';
        else out += esc(im);
        i += im.length;
        continue;
      }
      out += esc(c);
      i++;
    }
    return out;
  }

  var blocks = document.querySelectorAll('pre > code');
  for (var b = 0; b < blocks.length; b++) {
    var code = blocks[b];
    if (code.getAttribute('data-lang') === 'none') continue;
    code.innerHTML = highlightDart(code.textContent);
  }

  /* ---------- copy buttons ---------- */
  var pres = document.querySelectorAll('.codeblock');
  for (var p = 0; p < pres.length; p++) {
    (function (wrap) {
      var codeEl = wrap.querySelector('code');
      if (!codeEl) return;
      var btn = document.createElement('button');
      btn.className = 'copy';
      btn.type = 'button';
      btn.textContent = 'Copy';
      btn.setAttribute('aria-label', 'Copy code to clipboard');
      btn.addEventListener('click', function () {
        var text = codeEl.textContent;
        var done = function () {
          btn.textContent = 'Copied';
          btn.classList.add('done');
          setTimeout(function () {
            btn.textContent = 'Copy';
            btn.classList.remove('done');
          }, 1600);
        };
        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(text).then(done, function () { btn.textContent = 'Failed'; });
        } else {
          var ta = document.createElement('textarea');
          ta.value = text;
          ta.style.position = 'fixed';
          ta.style.opacity = '0';
          document.body.appendChild(ta);
          ta.select();
          try { document.execCommand('copy'); done(); } catch (err) { btn.textContent = 'Failed'; }
          document.body.removeChild(ta);
        }
      });
      wrap.appendChild(btn);
    })(pres[p]);
  }

  /* ---------- table of contents scrollspy ---------- */
  var links = document.querySelectorAll('.toc a');
  if (links.length && 'IntersectionObserver' in window) {
    var map = {};
    var targets = [];
    for (var l = 0; l < links.length; l++) {
      var id = links[l].getAttribute('href').slice(1);
      var el = document.getElementById(id);
      if (el) { map[id] = links[l]; targets.push(el); }
    }
    var visible = {};
    var obs = new IntersectionObserver(function (entries) {
      for (var e = 0; e < entries.length; e++) {
        visible[entries[e].target.id] = entries[e].isIntersecting;
      }
      var current = null;
      for (var t = 0; t < targets.length; t++) {
        if (visible[targets[t].id]) { current = targets[t].id; break; }
      }
      if (!current) {
        for (var u = targets.length - 1; u >= 0; u--) {
          if (targets[u].getBoundingClientRect().top < 120) { current = targets[u].id; break; }
        }
      }
      for (var k in map) map[k].classList.toggle('active', k === current);
    }, { rootMargin: '-80px 0px -70% 0px', threshold: 0 });
    for (var q = 0; q < targets.length; q++) obs.observe(targets[q]);
  }
})();

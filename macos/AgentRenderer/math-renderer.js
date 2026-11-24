/* LaTeX delimiters are parsed before rendering. Model text is never HTML. */
(function (root) {
  'use strict';
  const escapeHTML = text => text.replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  function escaped(text, at) {
    let count = 0;
    while (at > 0 && text[--at] === '\\') count++;
    return count % 2 === 1;
  }
  function closing(text, delimiter, from, inlineDollar = false) {
    let at = from;
    while ((at = text.indexOf(delimiter, at)) !== -1) {
      if (!escaped(text, at) && (!inlineDollar || (!/\s/.test(text[at - 1] || '') && !/\d/.test(text[at + 1] || '')))) return at;
      at += delimiter.length;
    }
    return -1;
  }
  function tokenize(text) {
    const tokens = []; let plain = '';
    function flush() { if (plain) { tokens.push({type:'text', text:plain}); plain = ''; } }
    for (let i = 0; i < text.length;) {
      if (text.startsWith('```', i)) {
        const line = text.indexOf('\n', i + 3), end = line < 0 ? -1 : text.indexOf('```', line + 1);
        if (line >= 0 && end >= 0) {
          flush(); const lang = text.slice(i + 3, line).trim().toLowerCase();
          const body = text.slice(line + 1, end).replace(/\n$/, '');
          tokens.push({type: /^(latex|tex|math)$/.test(lang) ? 'math' : 'blockCode', text:body, display:true, raw:text.slice(i, end + 3)});
          i = end + 3; continue;
        }
      }
      if (text[i] === '`') {
        const end = text.indexOf('`', i + 1);
        if (end > i + 1 && !text.slice(i, end).includes('\n')) {
          flush(); tokens.push({type:'code', text:text.slice(i + 1, end)}); i = end + 1; continue;
        }
      }
      if (text.startsWith('\\$', i)) { plain += '$'; i += 2; continue; }
      let left, right, display = false, keepDelimiters = false;
      if (text.startsWith('$$', i)) { left = right = '$$'; display = true; }
      else if (text.startsWith('\\[', i)) { left = '\\['; right = '\\]'; display = true; }
      else if (text.startsWith('\\(', i)) { left = '\\('; right = '\\)'; }
      else if (text[i] === '$' && !/\s/.test(text[i + 1] || ' ')) { left = right = '$'; }
      else {
        const environment = text.slice(i).match(/^\\begin\{(equation\*?|align\*?|alignat\*?|gather\*?)\}/);
        if (environment) { left = environment[0]; right = '\\end{' + environment[1] + '}'; display = true; keepDelimiters = true; }
      }
      if (left && !escaped(text, i)) {
        const end = closing(text, right, i + left.length, left === '$');
        if (end >= 0 && (left !== '$' || !text.slice(i, end).includes('\n'))) {
          flush(); const raw = text.slice(i, end + right.length);
          tokens.push({type:'math', text:keepDelimiters ? raw : text.slice(i + left.length, end), display, raw});
          i = end + right.length; continue;
        }
      }
      plain += text[i++];
    }
    flush(); return tokens;
  }
  function render(text) {
    return tokenize(text).map(token => {
      if (token.type === 'text') return escapeHTML(token.text);
      if (token.type === 'code') return '<code>' + escapeHTML(token.text) + '</code>';
      if (token.type === 'blockCode') return '<pre><code>' + escapeHTML(token.text) + '</code></pre>';
      try {
        return root.katex.renderToString(token.text, {displayMode:token.display, output:'htmlAndMathml',
          throwOnError:true, trust:false, strict:'ignore', maxExpand:500, maxSize:10, macros:{}});
      } catch (_) {
        return '<span class="formula-source" title="Formula could not be rendered">' + escapeHTML(token.raw) + '</span>';
      }
    }).join('');
  }
  root.PDFNanoMath = {tokenize, render, escapeHTML};
})(globalThis);

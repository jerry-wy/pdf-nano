/* Markdown owns document structure and code spans. Math consumes its source
   before Markdown can interpret TeX punctuation as escapes or emphasis. */
(function (root) {
  'use strict';
  const md = root.markdownit({html: false});
  md.disable('image');
  const escape = md.utils.escapeHtml;
  function formulaAt(text, start) {
    const first = text[start];
    if (first !== '$' && first !== '\\') return;
    let left, right, environment;
    if (text.startsWith('$$', start)) left = right = '$$';
    else if (first === '$' && !/\s/.test(text[start + 1] || ' ')) left = right = '$';
    else if (text.startsWith('\\[', start)) { left = '\\['; right = '\\]'; }
    else if (text.startsWith('\\(', start)) { left = '\\('; right = '\\)'; }
    else if (text.startsWith('\\begin{', start)) {
      environment = /^\\begin\{(equation\*?|align\*?|alignat\*?|gather\*?|aligned|gathered|cases|[bpvVB]?matrix)\}/.exec(text.slice(start));
      if (environment) { left = environment[0]; right = '\\end{' + environment[1] + '}'; }
    }
    if (!left) return;
    const body = start + left.length;
    for (let end = text.indexOf(right, body); end >= 0; end = text.indexOf(right, end + right.length)) {
      let p = end;
      while (p > body && text[p - 1] === '\\') p--;
      if ((end - p) % 2) continue;
      if (left === '$' && (/\s/.test(text[end - 1]) || /\d/.test(text[end + 1] || ''))) continue;
      const raw = text.slice(start, end + right.length);
      if (left === '$' && raw.includes('\n')) return;
      return {raw, tex: environment ? raw : text.slice(body, end), display: left !== '$' && left !== '\\('};
    }
  }
  function typeset({tex, raw, display}) {
    try {
      return root.katex.renderToString(tex, {displayMode:display, output:'htmlAndMathml',
        throwOnError:true, trust:false, strict:'ignore', maxExpand:500, maxSize:10, macros:{}});
    } catch (_) {
      return '<span class="formula-source" title="Formula could not be rendered">' + escape(raw) + '</span>';
    }
  }
  md.inline.ruler.before('escape', 'formula', (state, silent) => {
    const formula = formulaAt(state.src, state.pos);
    if (!formula || state.pos + formula.raw.length > state.posMax) return false;
    if (!silent) state.push('formula', '', 0).meta = formula;
    state.pos += formula.raw.length;
    return true;
  });
  md.renderer.rules.formula = (tokens, i) => typeset(tokens[i].meta);
  const codeFence = md.renderer.rules.fence;
  md.renderer.rules.fence = (tokens, i, ...args) => {
    const token = tokens[i];
    if (!/^(latex|tex|math)$/i.test(token.info.trim())) return codeFence(tokens, i, ...args);
    const raw = token.content.trim();
    const wrapped = formulaAt(raw, 0);
    return typeset({raw, tex: wrapped?.raw === raw ? wrapped.tex : raw, display:true});
  };
  root.PDFNanoMath = {render: text => md.render(text)};
})(globalThis);

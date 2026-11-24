import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import path from 'node:path';
import crypto from 'node:crypto';

const root = path.resolve('macos/AgentRenderer');
const context = vm.createContext({console});
vm.runInContext(fs.readFileSync(path.join(root, 'vendor/katex/katex.min.js'), 'utf8'), context);
vm.runInContext(fs.readFileSync(path.join(root, 'math-renderer.js'), 'utf8'), context);
const {render, tokenize} = context.PDFNanoMath;
const cases = [
  ['inline dollar', String.raw`The risk is $R(f)=\mathbb{E}[\ell(f(X),Y)]$.`, 1],
  ['inline parentheses', String.raw`设 \(x_i \in \mathbb{R}^d\)，则成立。`, 1],
  ['display fractions', String.raw`\[ \frac{1}{n}\sum_{i=1}^n x_i^2 \]`, 1],
  ['display dollars', String.raw`$$\int_0^1 \sqrt{x}\,dx=\frac{2}{3}$$`, 1],
  ['matrices', String.raw`$$\begin{bmatrix}a&b\\c&d\end{bmatrix}$$`, 1],
  ['aligned steps', String.raw`\begin{align} a&=b+c\\ &=d \end{align}`, 1],
  ['multiple formulas', String.raw`$a$ and \(b\), then \[a+b=c\]`, 3],
  ['math code fence', '```latex\n\\frac{a}{b}\n```', 1]
];
for (const [label, text, count] of cases) {
  const html = render(text);
  assert.equal((html.match(/class="katex"/g) || []).length, count, label);
  assert.ok(html.includes('<math'), `${label}: accessible MathML`);
  assert.ok(!html.includes('formula-source'), `${label}: rendered successfully`);
  console.log(`PASS: ${label}`);
}
assert.equal(tokenize(String.raw`Price is \$5 and \$10.`).filter(x => x.type === 'math').length, 0);
assert.equal(tokenize('Price is $5 and $10.').filter(x => x.type === 'math').length, 0);
assert.ok(!render('`$raw$`\n```python\nprint("$raw$")\n```').includes('class="katex"'));
assert.ok(render('`$raw$`').includes('<code>$raw$</code>'));
assert.ok(render(String.raw`Bad \[\frac{a\] remains readable.`).includes('formula-source'));
assert.ok(render('Unclosed $x + y').includes('$x + y'));
console.log('PASS: Currency, code, and malformed formulas stay readable');
const injection = '<img src="https://example.test/leak" onerror="alert(1)"><script>alert(2)</script>';
assert.ok(!render(injection).includes('<img'));
assert.ok(!render(injection).includes('<script>'));
assert.ok(render(injection).includes('&lt;script&gt;'));
assert.ok(!render(String.raw`$\href{javascript:alert(1)}{click}$`).includes('href="javascript:'));
assert.ok(!render(String.raw`$\includegraphics{https://example.test/leak}$`).includes('<img'));
assert.ok(render(String.raw`$\def\a{\a}\a$`).includes('formula-source'));
console.log('PASS: HTML stays text, unsafe math commands are disabled, macro expansion is bounded');
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'vendor/katex/SHA256.json')));
for (const [file, hash] of Object.entries(manifest)) {
  assert.equal(crypto.createHash('sha256').update(fs.readFileSync(path.join(root, 'vendor/katex', file))).digest('hex'), hash, file);
}
for (const file of ['index.html', 'reader.css', 'reader.js', 'math-renderer.js']) assert.ok(fs.existsSync(path.join(root, file)));
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
assert.ok(html.includes("connect-src 'none'"));
assert.ok(!/<(?:script|link)[^>]+(?:src|href)="https?:/i.test(html));
console.log('PASS: Pinned engine, fonts, and scripts are bundled; no CDN or network requests');

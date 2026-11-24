import { chromium } from 'playwright';
import assert from 'node:assert/strict';
import { pathToFileURL } from 'node:url';
import path from 'node:path';

const browser = await chromium.launch({executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', headless: true});
try {
  const page = await browser.newPage({viewport:{width:300,height:700}});
  const errors = [], remote = [];
  page.on('pageerror', e => errors.push(e.message));
  page.on('request', r => { if (/^https?:/.test(r.url())) remote.push(r.url()); });
  await page.addInitScript(() => { window.heights = []; window.webkit = {messageHandlers:{readerHeight:{postMessage: x => window.heights.push(x)}}}; });
  await page.goto(pathToFileURL(path.resolve('macos/AgentRenderer/index.html')).href);
  await page.evaluate(() => window.readerRender([
    {isUser:true, text:'Explain the equation.'},
    {isUser:false, text:String.raw`The empirical risk is \(R_n(f)\):
\[ R_n(f)=\frac{1}{n}\sum_{i=1}^{n}\ell(f(x_i),y_i) \]
A matrix example:
$$\begin{bmatrix}a&b\\c&d\end{bmatrix}$$
<script>alert('never execute')</script>`}
  ],{dark:false, ink:'#242424', muted:'#777', bubble:'rgba(127,127,127,.08)'},1));
  await page.waitForFunction(() => window.heights.some(x => x.revision === 1));
  await page.evaluate(() => document.fonts.ready);
  assert.equal(await page.locator('.katex').count(), 3);
  assert.equal(await page.locator('.body script').count(), 0);
  const wideHeight = await page.locator('#messages').evaluate(x => x.getBoundingClientRect().height);
  await page.setViewportSize({width:220,height:700});
  const narrowHeight = await page.locator('#messages').evaluate(x => x.getBoundingClientRect().height);
  assert.ok(narrowHeight >= wideHeight);
  assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
  assert.equal(remote.length, 0);
  assert.deepEqual(errors, []);
  await page.screenshot({path:'build/agent-math-preview.png',fullPage:true});
  console.log('PASS: Browser typesetting, responsive width, local fonts, height updates and escaped HTML');
} finally { await browser.close(); }

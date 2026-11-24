'use strict';
const messages = document.getElementById('messages');
let revision = 0, count = 0, queued = false;
function currentMetrics() {
  return {height: Math.max(24, Math.ceil(messages.getBoundingClientRect().height + 8)), revision, count};
}
function reportHeight() {
  if (queued) return;
  queued = true;
  setTimeout(() => {
    queued = false;
    window.webkit?.messageHandlers?.readerHeight?.postMessage(currentMetrics());
  });
}
window.readerRender = function (items, theme, version) {
  revision = version; count = items.length;
  document.documentElement.style.colorScheme = theme.dark ? 'dark' : 'light';
  document.documentElement.style.setProperty('--ink', theme.ink);
  document.documentElement.style.setProperty('--muted', theme.muted);
  document.documentElement.style.setProperty('--bubble', theme.bubble);
  const fragment = document.createDocumentFragment();
  for (const item of items) {
    const article = document.createElement('article');
    article.className = item.isUser ? 'message user' : 'message assistant';
    article.setAttribute('aria-label', item.isUser ? 'Your message' : 'Agent response');
    if (!item.isUser) {
      const caption = document.createElement('div'); caption.className = 'caption'; caption.textContent = 'Agent'; article.append(caption);
    }
    const body = document.createElement('div'); body.className = 'body';
    if (item.isUser) body.textContent = item.text;
    else body.innerHTML = PDFNanoMath.render(item.text);
    article.append(body); fragment.append(article);
  }
  messages.replaceChildren(fragment);
  reportHeight(); document.fonts.ready.then(reportHeight);
  // The host can show the first render immediately, without waiting for a
  // timer/ResizeObserver on a view that may still be covered or offscreen.
  return currentMetrics();
};
new ResizeObserver(reportHeight).observe(messages);

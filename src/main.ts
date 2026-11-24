import * as pdfjs from 'pdfjs-dist';
import workerUrl from 'pdfjs-dist/build/pdf.worker.min.mjs?url';
import { icon } from './icons';
import { makeDemo } from './demo';
import './style.css';
pdfjs.GlobalWorkerOptions.workerSrc = workerUrl;
type Point = {
    x: number;
    y: number;
};
type Mark = {
    id: string;
    page: number;
    type: 'highlight' | 'pen' | 'note';
    points: Point[];
    text?: string;
};
type DocumentEntry = {
    name: string;
    bytes: Uint8Array;
    pdf: pdfjs.PDFDocumentProxy;
    marks: Mark[];
    key: string;
    texts: string[];
    ocr: Record<number, string>;
};
let documents: DocumentEntry[] = [];
let doc: DocumentEntry;
let page = 1;
let zoom = 1;
let fit = true;
let mode = 'pointer';
let panel = 'pages';
let rendering = false;
let renderAgain = false;
let query = '';
let activeSearch = 0;
let hits: {
    page: number;
    text: string;
}[] = [];
let drawing: Mark | null = null;
let busy = false;
let ocrBusy = false;
let loadId = 0;
let thumbId = 0;
const $ = <T extends Element = HTMLElement>(s: string) => document.querySelector<T>(s)!;
const safe = (s: string) => s.replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]!));
const button = (id: string, i: string, label: string, extra = '') => `<button id="${id}" class="icon-button ${extra}" title="${label}" aria-label="${label}">${icon(i)}</button>`;
$('#app').innerHTML = `
<main>
 <header class="toolbar">
  <div class="toolbar-start">
   ${button('toggle-sidebar', 'grid', 'Toggle page sidebar')}
   ${button('open', 'plus', 'Open a PDF (⌘ O)')}
   <details class="document-menu"><summary title="Open documents"><span id="file-title">PDF Nano</span>${icon('chevron')}</summary><div class="menu-popover"><div id="documents"></div><span id="doc-count" hidden></span></div></details>
  </div>
  <div class="tool-group" aria-label="Annotation tools">${button('tool-pointer', 'pointer', 'Select text (V)', 'active')}${button('tool-highlight', 'highlight', 'Draw highlight (H)')}${button('tool-pen', 'pen', 'Draw with pen (D)')}${button('tool-note', 'note', 'Add note (N)')}<span class="divider"></span>${button('undo', 'undo', 'Undo annotation (⌘ Z)')}</div>
  <div class="toolbar-end">${button('search-toggle', 'search', 'Search document (⌘ F)')}
   <details class="more-menu"><summary aria-label="More tools" title="More tools">···</summary><div class="menu-popover"><button id="scan">${icon('scan')} Scan images to PDF</button><button id="ocr">${icon('spark')} Recognize page text</button><button id="about">${icon('info')} About PDF Nano</button></div></details>
   ${button('export', 'arrow', 'Export PDF')}
  </div>
 </header>
 <div class="reader-shell"><div class="reader-body">
  <aside class="page-panel sidebar" aria-label="Pages and notes"><div class="panel-tabs"><button id="tab-pages" class="active">Pages</button><button id="tab-notes">Notes <span id="note-count">0</span></button></div><div id="panel-content"></div><span id="page-total" hidden></span></aside>
  <section class="viewer-area" aria-label="PDF reader"><div id="search-bar" hidden><div class="search-input">${icon('search')}<input id="search-input" placeholder="Find in document" aria-label="Search this document"/><span id="search-count"></span>${button('search-prev', 'chevron', 'Previous result', 'reverse')}${button('search-next', 'chevron', 'Next result')}${button('search-close', 'close', 'Close search')}</div><div id="search-results"></div></div><div id="viewport"><div id="page-wrap"><canvas id="pdf-canvas"></canvas><div id="text-layer" class="textLayer"></div><svg id="annotation-layer" aria-label="Annotation canvas"></svg></div><div id="loading">Opening PDF…</div></div></section>
 </div></div>
 <footer><span class="footer-brand">pdf <strong>nano</strong></span><div class="page-controls">${button('prev-page', 'chevron', 'Previous page', 'reverse')}<input id="page-number" type="number" min="1" value="1" aria-label="Page number"/><span class="muted">/ <span id="pages">3</span></span>${button('next-page', 'chevron', 'Next page')}</div><div class="zoom-controls">${button('zoom-out', 'minus', 'Zoom out')}<button id="zoom-label" title="Reset to fit width">100%</button>${button('zoom-in', 'plus', 'Zoom in')}${button('fit', 'fit', 'Fit page width')}</div></footer>
 <div class="sr-only"><h1 id="heading">PDF Nano</h1><span id="document-info"></span><span id="save-status" role="status"></span><span id="tool-hint"></span></div>
</main>
<input id="file-input" type="file" accept="application/pdf,.pdf" multiple hidden/><input id="image-input" type="file" accept="image/jpeg,image/png,image/webp" multiple hidden/>
<dialog id="modal"><div id="modal-content"></div></dialog><div id="toast" role="status"></div><div id="drop-overlay">${icon('file')}<h2>Drop to open.</h2></div>`;
let toastTimer: ReturnType<typeof setTimeout>;
function toast(message: string) {
    $('#toast').textContent = message;
    $('#toast').classList.add('visible');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => $('#toast').classList.remove('visible'), 4000);
}
// Dialogs are assembled with safe text, never document-supplied HTML.
function showDialog(content: string) {
    $('#modal-content').innerHTML = `${button('modal-close', 'close', 'Close dialog')}${content}`;
    $('#modal-close').onclick = () => $('#modal') instanceof HTMLDialogElement && ($('#modal') as HTMLDialogElement).close();
    ($('#modal') as HTMLDialogElement).showModal();
}
function persist() {
    try {
        localStorage.setItem(doc.key, JSON.stringify(doc.marks));
        $('#save-status').textContent = 'All changes saved locally';
    }
    catch {
        $('#save-status').textContent = 'Storage full — export to save';
    }
    $('#note-count').textContent = String(doc.marks.length);
}
function renderDocuments() {
    $('#doc-count').textContent = String(documents.length);
    $('#documents').innerHTML = documents.map((d, i) => `<button class="document-item ${d === doc ? 'active' : ''}" data-doc="${i}">${icon('file')}<span>${safe(d.name)}<small>${d.pdf.numPages} pages · PDF</small></span>${d === doc ? '<span class="document-dot"></span>' : ''}</button>`).join('');
    document.querySelectorAll<HTMLButtonElement>('[data-doc]').forEach(b => b.onclick = () => activate(documents[Number(b.dataset.doc)]));
}
async function openBytes(bytes: Uint8Array, name: string) {
    const pdf = await pdfjs.getDocument({ data: bytes.slice(), cMapUrl: `${import.meta.env.BASE_URL}pdfjs/cmaps/`, cMapPacked: true, standardFontDataUrl: `${import.meta.env.BASE_URL}pdfjs/standard_fonts/`, wasmUrl: `${import.meta.env.BASE_URL}pdfjs/wasm/` }).promise;
    const key = `pdf-nano:${pdf.fingerprints[0]}`;
    let marks: Mark[] = [];
    try {
        const saved = JSON.parse(localStorage.getItem(key) || '[]');
        if (Array.isArray(saved))
            marks = saved.filter(m => m && typeof m.id === 'string' && Number.isInteger(m.page) && m.page >= 1 && m.page <= pdf.numPages && (m.text === undefined || typeof m.text === 'string') && ['highlight', 'pen', 'note'].includes(m.type) && Array.isArray(m.points) && m.points.length > 0 && m.points.every((p: Point) => Number.isFinite(p.x) && Number.isFinite(p.y)));
    }
    catch {
    }
    const entry = { name, bytes, pdf, marks, key, texts: [], ocr: {} };
    documents.push(entry);
    activate(entry);
    return entry;
}
function activate(entry: DocumentEntry) {
    loadId++;
    drawing = null;
    doc = entry;
    page = 1;
    query = '';
    hits = [];
    $<HTMLInputElement>('#search-input').value = '';
    $('#search-results').innerHTML = '';
    $('#search-count').textContent = '';
    $('#heading').textContent = doc.name.replace(/\.pdf$/i, '');
    $('#file-title').textContent = doc.name;
    $('#document-info').textContent = `${doc.pdf.numPages} pages`;
    $('#pages').textContent = String(doc.pdf.numPages);
    $('#page-total').textContent = `${doc.pdf.numPages} pages`;
    $('#page-number').setAttribute('max', String(doc.pdf.numPages));
    persist();
    renderDocuments();
    renderPanel();
    void renderPage();
}
async function openFiles(files: FileList | File[]) {
    for (const file of Array.from(files)) {
        if (!file.name.toLowerCase().endsWith('.pdf')) {
            toast('Please choose a PDF file.');
            continue;
        }
        try {
            await openBytes(new Uint8Array(await file.arrayBuffer()), file.name);
        }
        catch (e) {
            toast(`Could not open ${file.name}. It may be damaged or password protected.`);
            console.error(e);
        }
    }
}
async function renderPage() {
    if (!doc)
        return;
    if (rendering) {
        renderAgain = true;
        return;
    }
    rendering = true;
    const entry = doc;
    const number = page;
    $('#loading').hidden = false;
    try {
        const p = await entry.pdf.getPage(number);
        const base = p.getViewport({ scale: 1 });
        if (fit) {
            const padding = getComputedStyle($('#viewport'));
            const available = $('#viewport').clientWidth - parseFloat(padding.paddingLeft) - parseFloat(padding.paddingRight);
            zoom = Math.min(1.4, Math.max(.1, available / base.width));
        }
        const v = p.getViewport({ scale: zoom });
        const canvas = $<HTMLCanvasElement>('#pdf-canvas');
        const ratio = Math.min(window.devicePixelRatio || 1, 2, Math.sqrt(16000000 / (v.width * v.height)));
        canvas.width = Math.floor(v.width * ratio);
        canvas.height = Math.floor(v.height * ratio);
        canvas.style.width = `${v.width}px`;
        canvas.style.height = `${v.height}px`;
        $('#page-wrap').style.width = `${v.width}px`;
        $('#page-wrap').style.height = `${v.height}px`;
        $('#page-wrap').style.setProperty('--scale-factor', String(zoom));
        $('#page-wrap').style.setProperty('--total-scale-factor', String(v.scale * v.userUnit));
        await p.render({ canvas, canvasContext: canvas.getContext('2d')!, viewport: v, transform: [ratio, 0, 0, ratio, 0, 0] }).promise;
        $('#text-layer').innerHTML = '';
        const content = await p.getTextContent();
        await new pdfjs.TextLayer({ textContentSource: content, container: $('#text-layer'), viewport: v }).render();
        entry.texts[number - 1] = content.items.map(item => 'str' in item ? item.str : '').join(' ');
        $('#annotation-layer').setAttribute('viewBox', '0 0 1000 1000');
        $('#annotation-layer').setAttribute('preserveAspectRatio', 'none');
        $('#zoom-label').textContent = `${Math.round(zoom * 100)}%`;
        $<HTMLInputElement>('#page-number').value = String(page);
        $('#prev-page').toggleAttribute('disabled', page <= 1);
        $('#next-page').toggleAttribute('disabled', page >= doc.pdf.numPages);
        drawMarks();
        highlightSearch();
        document.querySelectorAll('[data-page]').forEach(b => b.classList.toggle('active', Number((b as HTMLElement).dataset.page) === page));
    }
    catch (e) {
        toast('This page could not be rendered. Try another document.');
        console.error(e);
    }
    finally {
        rendering = false;
        $('#loading').hidden = true;
        if (renderAgain) {
            renderAgain = false;
            void renderPage();
        }
    }
}
let thumbnailObserver: IntersectionObserver | undefined;
async function renderPanel() {
    if (!doc)
        return;
    const generation = ++thumbId;
    thumbnailObserver?.disconnect();
    if (panel === 'notes') {
        $('#panel-content').innerHTML = doc.marks.length ? doc.marks.map(m => `<div class="note-card"><button data-jump="${m.page}"><small>PAGE ${m.page} · ${m.type.toUpperCase()}</small><p>${safe(m.text || (m.type === 'pen' ? 'A handwritten mark' : 'A highlighted passage'))}</p></button><button class="delete-mark" data-delete="${safe(m.id)}" aria-label="Delete annotation">${icon('trash')}</button></div>`).join('') : `<div class="empty-notes">${icon('note')}<h3>Room for your thoughts.</h3><p>Highlight a passage, draw a mark, or leave a little note.</p></div>`;
        document.querySelectorAll<HTMLButtonElement>('[data-jump]').forEach(b => b.onclick = () => goPage(Number(b.dataset.jump)));
        document.querySelectorAll<HTMLButtonElement>('[data-delete]').forEach(b => b.onclick = () => {
            doc.marks = doc.marks.filter(m => m.id !== b.dataset.delete);
            changed();
        });
        return;
    }
    const entry = doc;
    $('#panel-content').innerHTML = '';
    thumbnailObserver = new IntersectionObserver(entries => {
        for (const item of entries) {
            if (!item.isIntersecting)
                continue;
            thumbnailObserver?.unobserve(item.target);
            const target = item.target as HTMLButtonElement;
            void (async () => {
                const p = await entry.pdf.getPage(Number(target.dataset.page));
                if (generation !== thumbId)
                    return;
                const v = p.getViewport({ scale: 110 / p.getViewport({ scale: 1 }).width });
                const c = target.querySelector('canvas')!;
                c.width = v.width;
                c.height = v.height;
                await p.render({ canvas: c, canvasContext: c.getContext('2d')!, viewport: v }).promise;
            })().catch(() => {
                target.title = 'Preview unavailable — click to open page';
            });
        }
    }, { root: $('#panel-content'), rootMargin: '200px' });
    for (let i = 1; i <= entry.pdf.numPages; i++) {
        const b = document.createElement('button');
        b.className = `thumbnail ${i === page ? 'active' : ''}`;
        b.dataset.page = String(i);
        b.setAttribute('aria-label', `Go to page ${i}`);
        b.innerHTML = `<div class="thumbnail-paper"><canvas width="110" height="146"></canvas></div><span>${String(i).padStart(2, '0')}</span>`;
        b.onclick = () => goPage(i);
        $('#panel-content').append(b);
        thumbnailObserver.observe(b);
    }
}
function goPage(n: number) {
    if (!doc)
        return;
    drawing = null;
    page = Math.min(doc.pdf.numPages, Math.max(1, Number.isFinite(n) ? Math.round(n) : 1));
    void renderPage();
    $('#viewport').scrollTop = 0;
}
function setMode(next: string) {
    mode = next;
    document.querySelectorAll('[id^="tool-"]').forEach(b => b.classList.toggle('active', b.id === `tool-${mode}`));
    $('#tool-hint').textContent = ({ pointer: 'Select & read', highlight: 'Drag to highlight', pen: 'Make your mark', note: 'Click to leave a note' } as Record<string, string>)[mode];
    $('#annotation-layer').style.pointerEvents = mode === 'pointer' ? 'none' : 'auto';
    $('#annotation-layer').style.cursor = mode === 'note' ? 'copy' : 'crosshair';
}
function drawMarks() {
    if (!doc)
        return;
    const marks = [...doc.marks.filter(m => m.page === page), ...(drawing ? [drawing] : [])];
    $('#annotation-layer').innerHTML = marks.map(m => {
        const a = m.points[0], b = m.points[m.points.length - 1];
        if (m.type === 'highlight')
            return `<rect x="${Math.min(a.x, b.x)}" y="${Math.min(a.y, b.y)}" width="${Math.max(3, Math.abs(a.x - b.x))}" height="${Math.max(10, Math.abs(a.y - b.y))}" fill="#e8c64b" opacity=".38"/>`;
        if (m.type === 'pen')
            return `<polyline points="${m.points.map(p => `${p.x},${p.y}`).join(' ')}" stroke="#345a49" stroke-width="2.4" fill="none" stroke-linecap="round" stroke-linejoin="round"/>`;
        return `<g><rect x="${a.x}" y="${a.y}" width="28" height="24" rx="4" fill="#ead78f"/><path d="M${a.x + 7} ${a.y + 8}h14m-14 5h10" stroke="#675a2e" stroke-width="2"/><title>${safe(m.text || '')}</title></g>`;
    }).join('');
}
function changed() {
    persist();
    drawMarks();
    if (panel === 'notes')
        void renderPanel();
}
const layer = $<SVGSVGElement>('#annotation-layer');
function point(e: PointerEvent): Point {
    const r = layer.getBoundingClientRect();
    return { x: Math.max(0, Math.min(1000, (e.clientX - r.left) / r.width * 1000)), y: Math.max(0, Math.min(1000, (e.clientY - r.top) / r.height * 1000)) };
}
layer.addEventListener('pointerdown', e => {
    if (!doc || mode === 'pointer' || rendering)
        return;
    const p = point(e);
    if (mode === 'note') {
        const entry = doc, n = page;
        showDialog('<div class="dialog-icon">' + icon('note') + '</div><h2>A thought worth keeping.</h2><p>Add a note to this page.</p><textarea id="note-text" placeholder="What’s on your mind?" maxlength="1500"></textarea><button id="save-note" class="primary">Save note</button>');
        $('#note-text').focus();
        $('#save-note').onclick = () => {
            const text = $<HTMLTextAreaElement>('#note-text').value.trim();
            if (!text)
                return;
            entry.marks.push({ id: crypto.randomUUID(), page: n, type: 'note', points: [p], text });
            ($('#modal') as HTMLDialogElement).close();
            changed();
            toast('Note added. Find it in the Notes tab.');
        };
        return;
    }
    drawing = { id: crypto.randomUUID(), page, type: mode as 'pen' | 'highlight', points: [p] };
    layer.setPointerCapture(e.pointerId);
});
layer.addEventListener('pointermove', e => {
    if (!drawing)
        return;
    if (drawing.type === 'highlight')
        drawing.points = [drawing.points[0], point(e)];
    else
        drawing.points.push(point(e));
    drawMarks();
});
layer.addEventListener('pointerup', () => {
    if (!drawing)
        return;
    if (drawing.points.length > 1)
        doc.marks.push(drawing);
    drawing = null;
    changed();
});
layer.addEventListener('pointercancel', () => {
    drawing = null;
    drawMarks();
});
async function search() {
    if (!doc)
        return;
    const id = ++loadId;
    const entry = doc;
    query = $<HTMLInputElement>('#search-input').value.trim().toLowerCase();
    hits = [];
    const matches: typeof hits = [];
    const term = query;
    activeSearch = 0;
    if (!query) {
        $('#search-count').textContent = '';
        $('#search-results').innerHTML = '';
        highlightSearch();
        return;
    }
    $('#search-count').textContent = 'Searching…';
    for (let i = 1; i <= entry.pdf.numPages; i++) {
        if (id !== loadId || entry !== doc)
            return;
        if (entry.texts[i - 1] === undefined) {
            const p = await entry.pdf.getPage(i);
            const t = await p.getTextContent();
            entry.texts[i - 1] = t.items.map(a => 'str' in a ? a.str : '').join(' ');
        }
        const text = entry.texts[i - 1] + ' ' + (entry.ocr[i] || '');
        const at = text.toLowerCase().indexOf(term);
        if (at !== -1)
            matches.push({ page: i, text: text.slice(Math.max(0, at - 30), at + 100) });
    }
    if (id !== loadId || entry !== doc)
        return;
    hits = matches;
    $('#search-count').textContent = hits.length ? `${hits.length} page${hits.length === 1 ? '' : 's'}` : 'No matches';
    $('#search-results').innerHTML = hits.map((h, i) => `<button data-hit="${i}"><span>PAGE ${h.page}</span>${safe(h.text)}</button>`).join('');
    document.querySelectorAll<HTMLButtonElement>('[data-hit]').forEach(b => b.onclick = () => {
        activeSearch = Number(b.dataset.hit);
        goPage(hits[activeSearch].page);
    });
    if (hits.length)
        goPage(hits[0].page);
    else
        highlightSearch();
}
function highlightSearch() {
    document.querySelectorAll<HTMLElement>('#text-layer span').forEach(s => s.classList.toggle('search-match', !!query && !!s.textContent?.toLowerCase().includes(query)));
}
function toggleSearch(show = true) {
    $('#search-bar').hidden = !show;
    if (show)
        $('#search-input').focus();
    else {
        loadId++;
        clearTimeout(searchTimer);
        query = '';
        highlightSearch();
    }
}
async function exportPdf() {
    if (!doc || busy)
        return;
    busy = true;
    const entry = doc;
    $('#export').setAttribute('disabled', '');
    toast('Preparing your PDF…');
    try {
        const { PDFDocument, StandardFonts, rgb } = await import('pdf-lib');
        const pdf = await PDFDocument.load(entry.bytes);
        const font = await pdf.embedFont(StandardFonts.Helvetica);
        const encode = (s: string) => Array.from(s).map(c => {
            try {
                font.encodeText(c);
                return c;
            }
            catch {
                return '?';
            }
        }).join('');
        for (const m of entry.marks) {
            const p = pdf.getPage(m.page - 1);
            const sourcePage = await entry.pdf.getPage(m.page);
            const viewport = sourcePage.getViewport({ scale: 1 });
            const w = viewport.width, h = viewport.height;
            const map = (v: Point) => {
                const [x, y] = viewport.convertToPdfPoint(v.x / 1000 * w, v.y / 1000 * h);
                return { x, y };
            };
            const a = map(m.points[0]);
            if (m.type === 'highlight') {
                const first = m.points[0], last = m.points[m.points.length - 1];
                const x = Math.min(first.x, last.x), y = Math.min(first.y, last.y);
                const start = map({x, y});
                const end = map({x: x + Math.max(3, Math.abs(first.x-last.x)), y: y + Math.max(10, Math.abs(first.y-last.y))});
                p.drawRectangle({x: Math.min(start.x,end.x), y: Math.min(start.y,end.y), width: Math.abs(end.x-start.x), height: Math.abs(end.y-start.y), color: rgb(.91,.78,.29), opacity: .38});
            }
            if (m.type === 'pen')
                for (let i = 1; i < m.points.length; i++)
                    p.drawLine({ start: map(m.points[i - 1]), end: map(m.points[i]), thickness: w * .0024, color: rgb(.2, .35, .29) });
            if (m.type === 'note') {
                p.drawRectangle({ x: a.x, y: a.y - 18, width: 22, height: 18, color: rgb(.92, .84, .56) });
                p.drawText('N', { x: a.x + 6, y: a.y - 13, size: 10, font, color: rgb(.3, .3, .2) });
            }
        }
        const notes = entry.marks.filter(m => m.type === 'note');
        if (notes.length) {
            let p = pdf.addPage();
            let y = p.getHeight() - 55;
            p.drawText('Notes from PDF Nano', { x: 45, y, size: 20, font });
            y -= 40;
            for (const n of notes) {
                const words = encode(`Page ${n.page}: ${n.text}`).split(/\s+/);
                let line = '';
                for (const word of words) {
                    const pieces = word.match(/.{1,70}/g) || [''];
                    for (const piece of pieces) {
                        if ((line + piece).length > 78) {
                            if (y < 55) {
                                p = pdf.addPage();
                                y = p.getHeight() - 55;
                            }
                            p.drawText(line, { x: 45, y, size: 11, font });
                            y -= 16;
                            line = '';
                        }
                        line += piece + ' ';
                    }
                }
                if (y < 55) {
                    p = pdf.addPage();
                    y = p.getHeight() - 55;
                }
                p.drawText(line, { x: 45, y, size: 11, font });
                y -= 32;
            }
        }
        download(await pdf.save(), entry.name.replace(/\.pdf$/i, '') + ' — annotated.pdf', 'application/pdf');
        toast('PDF exported with your annotations.');
    }
    catch (e) {
        toast('Export failed. This PDF may have restrictions or unsupported data.');
        console.error(e);
    }
    finally {
        busy = false;
        $('#export').removeAttribute('disabled');
    }
}
function download(bytes: Uint8Array | string, name: string, type: string) {
    const blob = new Blob([typeof bytes === 'string' ? bytes : new Uint8Array(bytes)], { type });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = name;
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 10000);
}
function showScan() {
    showDialog(`<div class="dialog-icon">${icon('scan')}</div><div class="eyebrow">PAPER, MEET PIXELS</div><h2>A fresh start for your paper.</h2><p>Turn photos of your pages into one tidy PDF. Add JPG, PNG, or WebP images in reading order.</p><button id="choose-images" class="scan-drop">${icon('upload')}<strong>Choose page images</strong><span>Or take a photo using your device’s file picker</span></button><div class="scan-tip">${icon('spark')} After importing, use <strong>Recognize text</strong> to search scanned pages.</div><p class="dialog-small">Images are processed on your device. Nothing is uploaded.</p>`);
    $('#choose-images').onclick = () => $('#image-input').click();
}
async function scanImages(files: File[]) {
    if (!files.length)
        return;
    ($('#modal') as HTMLDialogElement).close();
    toast('Turning your images into a PDF…');
    try {
        const { PDFDocument } = await import('pdf-lib');
        const pdf = await PDFDocument.create();
        for (const file of files) {
            const bitmap = await createImageBitmap(file);
            const scale = Math.min(1, 2200 / Math.max(bitmap.width, bitmap.height));
            const c = document.createElement('canvas');
            c.width = Math.round(bitmap.width * scale);
            c.height = Math.round(bitmap.height * scale);
            c.getContext('2d')!.fillStyle = 'white';
            c.getContext('2d')!.fillRect(0, 0, c.width, c.height);
            c.getContext('2d')!.drawImage(bitmap, 0, 0, c.width, c.height);
            bitmap.close();
            const jpg = await pdf.embedJpg(c.toDataURL('image/jpeg', .88));
            const p = pdf.addPage(c.width > c.height ? [842, 595] : [595, 842]);
            const margin = 24, s = Math.min((p.getWidth() - margin * 2) / jpg.width, (p.getHeight() - margin * 2) / jpg.height);
            p.drawImage(jpg, { x: (p.getWidth() - jpg.width * s) / 2, y: (p.getHeight() - jpg.height * s) / 2, width: jpg.width * s, height: jpg.height * s });
        }
        await openBytes(await pdf.save(), `Scan ${new Date().toISOString().slice(0, 10)}.pdf`);
        toast('Your scan is ready. Recognize text to make it searchable.');
    }
    catch (e) {
        toast('Could not scan these images. Try JPG, PNG, or WebP files.');
        console.error(e);
    }
}
async function recognize() {
    if (!doc || ocrBusy)
        return;
    ocrBusy = true;
    const entry = doc, n = page;
    $('#ocr').setAttribute('disabled', '');
    $('#ocr').textContent = 'Loading text recognition…';
    let worker: Awaited<ReturnType<typeof import('tesseract.js')['createWorker']>> | undefined;
    try {
        const { createWorker } = await import('tesseract.js');
        worker = await createWorker('eng', 1, { logger: m => {
                $('#ocr').textContent = m.status === 'recognizing text' ? `Reading text… ${Math.round(m.progress * 100)}%` : 'Loading text recognition…';
            } });
        const p = await entry.pdf.getPage(n);
        const v = p.getViewport({ scale: 2 });
        const c = document.createElement('canvas');
        c.width = v.width;
        c.height = v.height;
        await p.render({ canvas: c, canvasContext: c.getContext('2d')!, viewport: v }).promise;
        const result = await worker.recognize(c);
        entry.ocr[n] = result.data.text;
        if (entry !== doc) {
            toast(`Text recognized on page ${n} of ${entry.name}.`);
            return;
        }
        showDialog(`<div class="dialog-icon">${icon('scan')}</div><h2>A page, in words.</h2><p>Recognized text from page ${n}. This text is now searchable in this session. OCR is English-only; review it for accuracy.</p><textarea id="ocr-text" readonly>${safe(result.data.text)}</textarea><button class="primary" id="download-text">${icon('arrow')} Save as text</button><p class="dialog-small">OCR text is not embedded into the exported PDF.</p>`);
        $('#download-text').onclick = () => download(result.data.text, `${entry.name.replace(/\.pdf$/i, '')}-page-${n}.txt`, 'text/plain');
        if (query)
            void search();
    }
    catch (e) {
        toast('Text recognition could not load. Check your connection and try again.');
        console.error(e);
    }
    finally {
        await worker?.terminate();
        ocrBusy = false;
        $('#ocr').removeAttribute('disabled');
        $('#ocr').innerHTML = icon('scan') + ' Recognize text';
    }
}
$('#open').onclick = () => $('#file-input').click();
$('#file-input').onchange = e => {
    void openFiles((e.target as HTMLInputElement).files!);
    (e.target as HTMLInputElement).value = '';
};
$('#image-input').onchange = e => {
    void scanImages(Array.from((e.target as HTMLInputElement).files!));
    (e.target as HTMLInputElement).value = '';
};
$('#scan').onclick = showScan;
$('#export').onclick = () => void exportPdf();
$('#ocr').onclick = () => void recognize();
$('#prev-page').onclick = () => goPage(page - 1);
$('#next-page').onclick = () => goPage(page + 1);
$('#page-number').onchange = () => goPage(Number($<HTMLInputElement>('#page-number').value));
['pointer', 'highlight', 'pen', 'note'].forEach(t => $('#tool-' + t).onclick = () => setMode(t));
$('#undo').onclick = () => {
    doc?.marks.pop();
    if (doc)
        changed();
};
$('#zoom-in').onclick = () => {
    fit = false;
    zoom = Math.min(3, zoom + .15);
    void renderPage();
};
$('#zoom-out').onclick = () => {
    fit = false;
    zoom = Math.max(.3, zoom - .15);
    void renderPage();
};
$('#fit').onclick = $('#zoom-label').onclick = () => {
    fit = true;
    void renderPage();
};
$('#search-toggle').onclick = () => toggleSearch($('#search-bar').hidden);
$('#search-close').onclick = () => toggleSearch(false);
let searchTimer: ReturnType<typeof setTimeout>;
$('#search-input').oninput = () => {
    clearTimeout(searchTimer);
    searchTimer = setTimeout(() => void search().catch(() => toast('This document could not be searched.')), 200);
};
$('#search-next').onclick = () => {
    if (hits.length) {
        activeSearch = (activeSearch + 1) % hits.length;
        goPage(hits[activeSearch].page);
    }
};
$('#search-prev').onclick = () => {
    if (hits.length) {
        activeSearch = (activeSearch - 1 + hits.length) % hits.length;
        goPage(hits[activeSearch].page);
    }
};
['pages', 'notes'].forEach(t => $('#tab-' + t).onclick = () => {
    panel = t;
    $('#tab-pages').classList.toggle('active', t === 'pages');
    $('#tab-notes').classList.toggle('active', t === 'notes');
    void renderPanel();
});
$('#toggle-sidebar').onclick = () => {
    document.body.classList.toggle('sidebar-open');
    $('#toggle-sidebar').setAttribute('aria-expanded', String(document.body.classList.contains('sidebar-open')));
    if (fit) void renderPage();
};
document.addEventListener('click', e => {
    document.querySelectorAll<HTMLDetailsElement>('details[open]').forEach(menu => {
        if (!menu.contains(e.target as Node) || (e.target as HTMLElement).closest('button')) menu.open = false;
    });
});
$('#about').onclick = () => showDialog(`<div class="dialog-icon">${icon('book')}</div><h2>Small app. Room to think.</h2><p>PDF Nano is a quiet place to read, annotate, and collect your thoughts.</p><p>Documents stay in memory. Annotations are saved in this browser and restored when you reopen the same PDF. Export to keep a portable copy.</p><p>Text recognition downloads an English OCR model when first used. Your document is processed locally.</p><div class="about-shortcuts"><span>Open PDF <kbd>⌘ / Ctrl O</kbd></span><span>Find text <kbd>⌘ / Ctrl F</kbd></span><span>Undo annotation <kbd>⌘ / Ctrl Z</kbd></span></div>`);
document.addEventListener('keydown', e => {
    const typing = (e.target as HTMLElement).matches('input,textarea');
    if ((e.metaKey || e.ctrlKey) && ['o', 'f'].includes(e.key.toLowerCase())) {
        e.preventDefault();
        if (e.key.toLowerCase() === 'o')
            $('#file-input').click();
        else
            toggleSearch();
        return;
    }
    if (typing || $<HTMLDialogElement>('#modal').open)
        return;
    if ((e.metaKey || e.ctrlKey) && e.key === 'z') {
        e.preventDefault();
        $('#undo').click();
        return;
    }
    if (e.metaKey || e.ctrlKey || e.altKey)
        return;
    const shortcuts: Record<string, string> = { v: 'pointer', h: 'highlight', d: 'pen', n: 'note' };
    if (shortcuts[e.key])
        setMode(shortcuts[e.key]);
    if (e.key === 'ArrowRight')
        goPage(page + 1);
    if (e.key === 'ArrowLeft')
        goPage(page - 1);
    if (e.key === 'Escape') {
        toggleSearch(false);
        setMode('pointer');
    }
});
let dragDepth = 0;
document.addEventListener('dragenter', e => {
    if (e.dataTransfer?.types.includes('Files')) {
        e.preventDefault();
        dragDepth++;
        $('#drop-overlay').classList.add('visible');
    }
});
document.addEventListener('dragover', e => e.preventDefault());
document.addEventListener('dragleave', () => {
    if (--dragDepth <= 0)
        $('#drop-overlay').classList.remove('visible');
});
document.addEventListener('drop', e => {
    e.preventDefault();
    dragDepth = 0;
    $('#drop-overlay').classList.remove('visible');
    if (e.dataTransfer?.files)
        void openFiles(e.dataTransfer.files);
});
let resizeTimer: ReturnType<typeof setTimeout>;
window.addEventListener('resize', () => {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(() => {
        if (fit)
            void renderPage();
    }, 150);
});
void makeDemo().then(bytes => openBytes(bytes, 'The art of paying attention.pdf')).catch(e => {
    console.error(e);
    $('#loading').textContent = 'Could not load the example. Open a PDF to begin.';
});

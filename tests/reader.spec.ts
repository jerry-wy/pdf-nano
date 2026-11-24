import { test, expect } from '@playwright/test';
import { PDFDocument, StandardFonts } from 'pdf-lib';
import { readFile } from 'node:fs/promises';
test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await expect(page.locator('#text-layer')).toContainText('paying attention.');
    await expect(page.locator('#loading')).toBeHidden();
});
test('renders the example and navigates/searches across pages', async ({ page }) => {
    await expect(page.locator('#pages')).toHaveText('3');
    await page.getByRole('button', { name: 'Next page', exact: true }).click();
    await expect(page.locator('#text-layer')).toContainText('what matters.');
    await page.locator('#search-toggle').click();
    await page.getByRole('textbox', { name: 'Search this document' }).fill('destination');
    await expect(page.locator('#search-count')).toHaveText('1 page');
    await expect(page.locator('#page-number')).toHaveValue('3');
    await expect(page.locator('#text-layer .search-match').first()).toBeVisible();
});
test('saves a note locally, restores it, and exports its text into a notes page', async ({ page }) => {
    await page.locator('#tool-note').click();
    await page.locator('#annotation-layer').click({ position: { x: 100, y: 100 } });
    await page.locator('#note-text').fill('Keep this thought for later.');
    await page.getByRole('button', { name: 'Save note', exact: true }).click();
    await page.reload();
    await expect(page.locator('#note-count')).toHaveText('1');
    await page.locator('#toggle-sidebar').click();
    await page.locator('#tab-notes').click();
    await expect(page.locator('#panel-content')).toContainText('Keep this thought for later.');
    const pending = page.waitForEvent('download');
    await page.locator('#export').click();
    const download = await pending;
    const bytes = await readFile((await download.path())!);
    const pdf = await PDFDocument.load(bytes);
    expect(pdf.getPageCount()).toBe(4);
    await page.locator('#file-input').setInputFiles({ name: 'exported.pdf', mimeType: 'application/pdf', buffer: bytes });
    await expect(page.locator('#pages')).toHaveText('4');
    await page.locator('#page-number').fill('4');
    await page.locator('#page-number').press('Tab');
    await expect(page.locator('#text-layer')).toContainText('Keep this thought for later.');
});
test('opens a real uploaded PDF and clamps page input', async ({ page }) => {
    const pdf = await PDFDocument.create();
    const font = await pdf.embedFont(StandardFonts.Helvetica);
    pdf.addPage().drawText('A document of my own', { x: 50, y: 700, font });
    await page.locator('#file-input').setInputFiles({ name: 'my-document.pdf', mimeType: 'application/pdf', buffer: Buffer.from(await pdf.save()) });
    await expect(page.locator('#heading')).toHaveText('my-document');
    await expect(page.locator('#text-layer')).toContainText('A document of my own');
    await page.locator('#page-number').fill('99');
    await page.locator('#page-number').press('Tab');
    await expect(page.locator('#page-number')).toHaveValue('1');
    await expect(page.locator('#next-page')).toBeDisabled();
});
test('draws and undoes a highlight', async ({ page }) => {
    await page.locator('#tool-highlight').click();
    const box = (await page.locator('#annotation-layer').boundingBox())!;
    await page.mouse.move(box.x + 60, box.y + 100);
    await page.mouse.down();
    await page.mouse.move(box.x + 230, box.y + 120, { steps: 8 });
    await page.mouse.up();
    await expect(page.locator('#annotation-layer rect')).toHaveCount(1);
    await page.locator('#undo').click();
    await expect(page.locator('#annotation-layer rect')).toHaveCount(0);
});
test('turns an image into an exportable PDF', async ({ page }) => {
    // Generate a real image in-browser; the scan path must decode and embed it.
    const data = await page.evaluate(() => {
        const c = document.createElement('canvas');
        c.width = 320;
        c.height = 480;
        const ctx = c.getContext('2d')!;
        ctx.fillStyle = 'white';
        ctx.fillRect(0, 0, 320, 480);
        ctx.fillStyle = 'black';
        ctx.font = '24px sans-serif';
        ctx.fillText('Scanned page', 20, 60);
        return c.toDataURL('image/png').split(',')[1];
    });
    await page.locator('#image-input').setInputFiles({ name: 'page.png', mimeType: 'image/png', buffer: Buffer.from(data, 'base64') });
    await expect(page.locator('#heading')).toContainText('Scan ');
    await expect(page.locator('#pages')).toHaveText('1');
    const pending = page.waitForEvent('download');
    await page.locator('#export').click();
    const downloaded = await pending;
    const pdf = await PDFDocument.load(await readFile((await downloaded.path())!));
    expect(pdf.getPageCount()).toBe(1);
});
test('fits the narrow layout without horizontal overflow', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await expect(page.locator('#toggle-sidebar')).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(390);
    await page.locator('#toggle-sidebar').click();
    await expect(page.locator('.sidebar')).toBeInViewport();
});

 test('keeps the reader chrome minimal and exposes secondary tools on demand', async ({ page }) => {
  await expect(page.locator('.page-panel')).toBeHidden();
  await expect(page.locator('#scan')).toBeHidden();
  await page.locator('.more-menu summary').click();
  await expect(page.locator('#scan')).toBeVisible();
  await page.locator('#scan').click();
  await expect(page.locator('#modal')).toBeVisible();
  await expect(page.locator('.more-menu')).not.toHaveAttribute('open', '');
});

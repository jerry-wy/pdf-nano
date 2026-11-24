export async function makeDemo() {
    const { PDFDocument, StandardFonts, rgb } = await import('pdf-lib');
    const pdf = await PDFDocument.create();
    pdf.setCreationDate(new Date("2026-01-01T00:00:00Z"));
    pdf.setModificationDate(new Date("2026-01-01T00:00:00Z"));
    const regular = await pdf.embedFont(StandardFonts.Helvetica);
    const bold = await pdf.embedFont(StandardFonts.HelveticaBold);
    const serif = await pdf.embedFont(StandardFonts.TimesRoman);
    const ink = rgb(.18, .25, .21), muted = rgb(.43, .46, .42), green = rgb(.27, .40, .31);
    const sections = [['The art of paying attention', 'A field guide to a more considered everyday.'], ['Make room for what matters', 'Less noise. More possibility.'], ['A practice, not a destination', 'Small moments are where a meaningful life begins.']];
    sections.forEach(([title, sub], i) => {
        const p = pdf.addPage([595, 790]);
        const text = (s: string, x: number, y: number, size: number, font = regular, color = ink) => p.drawText(s, { x, y, size, font, color });
        text('FIELDNOTES', 55, 735, 10, bold);
        text('VOL. 01   /   THE SLOWER SERIES', 330, 735, 8, regular, muted);
        p.drawLine({ start: { x: 55, y: 718 }, end: { x: 540, y: 718 }, thickness: .7, color: rgb(.78, .8, .76) });
        text(`0${i + 1}   /   ${['ON ATTENTION', 'ON SIMPLICITY', 'ON PRACTICE'][i]}`, 55, 675, 9, bold, green);
        const titles = i === 0 ? ['The art of', 'paying attention.'] : i === 1 ? ['Make room for', 'what matters.'] : ['A practice, not', 'a destination.'];
        text(titles[0], 55, 613, 43, serif);
        text(titles[1], 55, 565, 43, serif);
        text(sub, 55, 529, 12, regular, muted);
        p.drawRectangle({ x: 55, y: 319, width: 485, height: 174, color: rgb(.89, .91, .85) });
        // Quiet, geometric landscape, entirely vector-based.
        p.drawCircle({ x: 434, y: 437, size: 28, color: rgb(.76, .79, .63) });
        p.drawSvgPath('M 0 110 Q 95 5 200 90 Q 310 160 485 30 L 485 174 L 0 174 Z', { x: 55, y: 493, color: rgb(.65, .72, .61) });
        p.drawSvgPath('M 0 140 Q 100 70 240 130 Q 390 185 485 90 L 485 174 L 0 174 Z', { x: 55, y: 493, color: rgb(.42, .55, .43) });
        text(['A quieter kind of clarity', 'The beauty of enough', 'Begin where you are'][i], 55, 282, 19, serif);
        const paragraphs = [
            ['We live in a world that asks us to look everywhere at once. Every', 'notification, every open tab, every passing thought competes for a', 'little piece of our attention. But what happens when we slow down?', '', 'Attention is a practice. It begins with noticing the ordinary: the light', 'across a desk, the texture of a page, an idea worth staying with.', 'When we give something our full attention, we begin to see it anew.'],
            ['Simplicity is less about having nothing and more about making room', 'for the things that deserve our care. A clear desk. An unhurried', 'conversation. A single page, read with intention.', '', 'Choose one thing to do today with a little more care. Let everything', 'else wait for a moment. Notice how space changes the way you think.', 'What would you keep if you could only keep what matters?'],
            ['There is no perfect way to begin. Open a book. Write a sentence.', 'Take a walk without a destination. The small things we return to', 'become the shape of our days.', '', 'Leave a note in the margin. Underline a thought you want to keep.', 'Make this page your own. Attention grows through practice, and', 'practice begins with a single, ordinary moment.']
        ][i];
        paragraphs.forEach((s, j) => text(s, 55, 253 - j * 17, 11, regular, muted));
        p.drawLine({ start: { x: 55, y: 76 }, end: { x: 540, y: 76 }, thickness: .7, color: rgb(.78, .8, .76) });
        text('A LITTLE SPACE FOR BIG IDEAS.', 55, 56, 8, regular, muted);
        text(`FIELDNOTES     /     0${i + 1}`, 425, 56, 8, regular, muted);
    });
    return pdf.save();
}

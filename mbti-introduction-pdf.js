(function (root) {
  'use strict';

  const pageWidth = 595.28;
  const pageHeight = 841.89;
  const scale = 2;
  const margin = 48;
  const font = '"Apple SD Gothic Neo", "Malgun Gothic", "Noto Sans CJK KR", sans-serif';

  function wrap(context, text) {
    const lines = [];
    const width = pageWidth - 2 * margin;
    for (const paragraph of text.split('\n')) {
      let line = '';
      for (const token of paragraph.match(/\s+|\S+/gu) || []) {
        if (context.measureText(line + token).width <= width) {
          line += token;
          continue;
        }
        if (line.trim()) lines.push(line.trimEnd());
        line = token.trimStart();
        if (context.measureText(line).width <= width) continue;
        line = '';
        for (const character of token) {
          if (context.measureText(line + character).width > width) {
            lines.push(line);
            line = '';
          }
          line += character;
        }
      }
      lines.push(line.trimEnd());
    }
    return lines;
  }

  function createPdf(document, title, paragraphs) {
    const canvas = document.createElement('canvas');
    canvas.width = Math.round(pageWidth * scale);
    canvas.height = Math.round(pageHeight * scale);
    const context = canvas.getContext('2d');
    if (!context) throw new Error('이 기기에서 PDF를 만들 수 없습니다.');

    context.scale(scale, scale);
    context.textBaseline = 'top';
    const pages = [];
    const bottom = pageHeight - 64;
    let y;

    function startPage() {
      context.fillStyle = '#fff';
      context.fillRect(0, 0, canvas.width / scale, canvas.height / scale);
      context.font = 'bold 10px ' + font;
      context.fillStyle = '#31524d';
      context.fillText('청라학원  |  나의 MBTI 학습법', margin, 34);
      y = 59;
    }

    function finishPage() {
      context.font = '10px ' + font;
      context.fillStyle = '#31524d';
      context.fillText(String(pages.length + 1), margin, pageHeight - 38);
      const jpeg = canvas.toDataURL('image/jpeg', 0.94).split(',')[1];
      pages.push(Uint8Array.from(root.atob(jpeg), character => character.charCodeAt(0)));
    }

    function write(text, size, leading, gap, bold, keepNext = false) {
      const face = (bold ? 'bold ' : '') + size + 'px ' + font;
      context.font = face;
      const lines = wrap(context, text);
      if (keepNext && y + lines.length * leading + gap + 19 > bottom) {
        finishPage();
        startPage();
      }
      for (const line of lines) {
        if (y + leading > bottom) {
          finishPage();
          startPage();
        }
        context.font = face;
        context.fillStyle = '#182525';
        context.fillText(line, margin, y);
        y += leading;
      }
      y += gap;
    }

    startPage();
    write(title, 23, 31, 15, true);
    for (const paragraph of paragraphs) {
      const heading = paragraph.tagName === 'H3';
      write(paragraph.textContent, heading ? 14 : 11, heading ? 21 : 17, heading ? 6 : 9, heading, heading);
    }
    finishPage();
    return imagePdf(pages, canvas.width, canvas.height);
  }

  function imagePdf(pages, width, height) {
    // The PDF embeds each rendered page as a JPEG to preserve Korean glyphs.
    const parts = [];
    const offsets = [0];
    const encoder = new TextEncoder();
    let length = 0;

    function append(part) {
      const bytes = typeof part === 'string' ? encoder.encode(part) : part;
      parts.push(bytes);
      length += bytes.length;
    }

    function object(id, body, stream) {
      offsets[id] = length;
      append(id + ' 0 obj\n' + body);
      if (stream) {
        append('\nstream\n');
        append(stream);
        append('\nendstream');
      }
      append('\nendobj\n');
    }

    append('%PDF-1.4\n');
    object(1, '<< /Type /Catalog /Pages 2 0 R >>');
    const children = pages.map((_, index) => (3 + index * 3) + ' 0 R').join(' ');
    object(2, '<< /Type /Pages /Count ' + pages.length + ' /Kids [' + children + '] >>');
    const paint = encoder.encode('q ' + pageWidth + ' 0 0 ' + pageHeight + ' 0 0 cm /PageImage Do Q');
    pages.forEach((image, index) => {
      const id = 3 + index * 3;
      object(id, '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ' + pageWidth + ' ' + pageHeight +
        '] /Resources << /XObject << /PageImage ' + (id + 1) + ' 0 R >> >> /Contents ' + (id + 2) + ' 0 R >>');
      object(id + 1, '<< /Type /XObject /Subtype /Image /Width ' + width + ' /Height ' + height +
        ' /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length ' + image.length + ' >>', image);
      object(id + 2, '<< /Length ' + paint.length + ' >>', paint);
    });

    const xref = length;
    append('xref\n0 ' + offsets.length + '\n0000000000 65535 f \n');
    for (const offset of offsets.slice(1)) append(String(offset).padStart(10, '0') + ' 00000 n \n');
    append('trailer\n<< /Size ' + offsets.length + ' /Root 1 0 R >>\nstartxref\n' + xref + '\n%%EOF\n');
    return new Blob(parts, { type: 'application/pdf' });
  }

  root.CheonglaMBTIIntroductionPDF = { create: createPdf };
})(globalThis);

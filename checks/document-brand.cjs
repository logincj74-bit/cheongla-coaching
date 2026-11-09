const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const PDFLib = require('../vendor/pdf-lib-1.17.1.min.js');
const read = file => fs.readFileSync(path.join(__dirname, '..', file));
const drawn = [];
const context = {
  fillRect() {}, drawImage(image) { drawn.push(image.src); },
  fillText(text) { drawn.push(text); }, scale() {},
  measureText(text) { return { width: text.length * 10 }; }
};
const logo = read('assets/cheongla-icon-180-v2.png');
const jpeg = 'data:image/jpeg;base64,/9j/2Q==';
const canvas = {
  getContext: () => context,
  toDataURL: format => format === 'image/jpeg' ? jpeg : 'data:image/png;base64,' + logo.toString('base64')
};
class Image {
  set src(url) { this.url = url; queueMicrotask(() => this.onload()); }
  get src() { return this.url; }
}
const document = {
  baseURI: 'https://example.test/cheongla/',
  createElement(tag) {
    assert.equal(tag, 'canvas');
    return canvas;
  }
};
const browser = vm.createContext({ document, PDFLib, URL, Image, Blob, TextEncoder, atob });
vm.runInContext(read('document-brand.js').toString(), browser);
vm.runInContext(read('mbti-introduction-pdf.js').toString(), browser);
const brand = browser.CheonglaDocumentBrand;

(async () => {
  const input = await PDFLib.PDFDocument.create();
  input.addPage([400, 500]).drawText('Original document');
  const pdf = await brand.coverPdf(await input.save(), '상담 자료.pdf');
  const output = await PDFLib.PDFDocument.load(await pdf.arrayBuffer());
  assert.equal(output.getPageCount(), 2);
  assert.equal(output.getPage(0).getWidth(), 595.28);
  assert.equal(output.getPage(1).getWidth(), 400);
  assert.deepEqual(drawn, [brand.logoUrl, '전주 독학재수 청라학원', '상담 자료']);
  drawn.length = 0;
  const paragraphs = Array.from({ length: 90 }, () => ({ tagName: 'P', textContent: '학습지도 본문' }));
  const mbti = await browser.CheonglaMBTIIntroductionPDF.create(document, '나의 MBTI 학습법', paragraphs);
  const mbtiPdf = await PDFLib.PDFDocument.load(await mbti.arrayBuffer());
  assert(mbtiPdf.getPageCount() > 1);
  assert.equal(drawn.filter(text => text === brand.logoUrl).length, mbtiPdf.getPageCount());
  assert.equal(drawn.filter(text => text === '전주 독학재수 청라학원').length, mbtiPdf.getPageCount());
  console.log('PASS branded PDF cover, original-page dimensions, and branding on each MBTI PDF page');
})().catch(error => { console.error(error); process.exitCode = 1; });

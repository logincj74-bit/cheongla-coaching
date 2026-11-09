/* Shared branding for app-generated documents and downloaded PDF copies. */
(function (root) {
  'use strict';

  const document = root.document;
  const name = '전주 독학재수 청라학원';
  const logoUrl = new URL('assets/cheongla-icon-180-v2.png', document.baseURI).href;
  const libraryUrl = new URL('vendor/pdf-lib-1.17.1.min.js', document.baseURI).href;
  let library;
  let logo;

  function loadLogo() {
    if (!logo) {
      logo = new Promise((resolve, reject) => {
        const image = new Image();
        image.onload = () => resolve(image);
        image.onerror = () => reject(new Error('청라 로고를 불러오지 못했습니다. 다시 시도해 주세요.'));
        image.src = logoUrl;
      }).catch(error => { logo = null; throw error; });
    }
    return logo;
  }

  function loadLibrary() {
    if (root.PDFLib) return Promise.resolve(root.PDFLib);
    if (!library) {
      library = new Promise((resolve, reject) => {
        const script = document.createElement('script');
        script.src = libraryUrl;
        script.onload = () => root.PDFLib ? resolve(root.PDFLib) : fail();
        script.onerror = fail;
        function fail() {
          script.remove();
          reject(new Error('PDF 문서 처리 기능을 불러오지 못했습니다. 다시 시도해 주세요.'));
        }
        document.head.append(script);
      }).catch(error => { library = null; throw error; });
    }
    return library;
  }

  async function coverPdf(bytes, filename) {
    const [{ PDFDocument }, image] = await Promise.all([loadLibrary(), loadLogo()]);
    const pdf = await PDFDocument.load(bytes, { updateMetadata: false });
    const canvas = document.createElement('canvas');
    canvas.width = 1500;
    canvas.height = 620;
    const context = canvas.getContext('2d');
    if (!context) throw new Error('PDF 표지를 만들 수 없습니다.');
    context.fillStyle = '#fff';
    context.fillRect(0, 0, canvas.width, canvas.height);
    context.drawImage(image, 625, 20, 250, 250);
    context.textAlign = 'center';
    context.fillStyle = '#203e42';
    context.font = 'bold 68px "Apple SD Gothic Neo", "Malgun Gothic", sans-serif';
    context.fillText(name, 750, 365);
    context.fillRect(580, 420, 340, 3);
    context.font = '40px "Apple SD Gothic Neo", "Malgun Gothic", sans-serif';
    context.fillText(filename.replace(/\.pdf$/i, ''), 750, 505, 1400);
    const banner = await pdf.embedPng(canvas.toDataURL('image/png'));
    const cover = pdf.insertPage(0);
    cover.setSize(595.28, 841.89);
    cover.drawImage(banner, { x: 48, y: 430, width: 499.28, height: 499.28 * 620 / 1500 });
    return new Blob([await pdf.save()], { type: 'application/pdf' });
  }

  function download(blob, filename) {
    const url = root.URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = filename;
    document.body.append(link);
    try {
      link.click();
    } finally {
      link.remove();
      setTimeout(() => root.URL.revokeObjectURL(url), 60000);
    }
  }

  async function downloadAttachment(storage, file) {
    const pdf = /\.pdf$/i.test(file.filename);
    const options = pdf ? undefined : { download: file.filename };
    const { data, error } = await storage.createSignedUrl(file.object_path, 120, options);
    if (error) throw error;
    const url = new URL(data.signedUrl);
    if (url.protocol !== 'https:') throw new Error('파일 주소를 확인해 주세요.');
    if (!pdf) {
      root.location.assign(url.href);
      return;
    }
    const response = await fetch(url.href);
    if (!response.ok) throw new Error('PDF 첨부파일을 불러오지 못했습니다.');
    download(await coverPdf(await response.arrayBuffer(), file.filename), file.filename);
  }

  root.CheonglaDocumentBrand = { name, logoUrl, loadLogo, coverPdf, download, downloadAttachment };
})(globalThis);

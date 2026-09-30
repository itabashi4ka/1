// web/ のファイルを1つのHTMLにまとめる → dist/installment-calculator.html
// 実行: npm run build
const fs = require('fs');
const path = require('path');

const WEB = path.join(__dirname, '..', 'web');
const OUT_DIR = path.join(__dirname, '..', 'dist');
const read = (p) => fs.readFileSync(path.join(WEB, p), 'utf8');
const dataURL = (p, type) => `data:${type};base64,${fs.readFileSync(path.join(WEB, p)).toString('base64')}`;
// </script> などがインライン化した中身に現れないようにする
const safeScript = (s) => s.replace(/<\/script/gi, '<\\/script');

let html = read('index.html');
const replaceOnce = (pattern, replacement) => {
  if (!pattern.test(html)) throw new Error('not found: ' + pattern);
  html = html.replace(pattern, () => replacement);
};

replaceOnce(/<link rel="stylesheet" href="css\/app\.css">/, `<style>\n${read('css/app.css')}</style>`);
replaceOnce(/<link rel="manifest"[^>]*>\n/, '');
replaceOnce(/<link rel="icon" href="icons\/icon\.svg"[^>]*>/, `<link rel="icon" href="${dataURL('icons/icon.svg', 'image/svg+xml')}" type="image/svg+xml">`);
replaceOnce(/<link rel="apple-touch-icon" href="icons\/icon-180\.png">/, `<link rel="apple-touch-icon" href="${dataURL('icons/icon-180.png', 'image/png')}">`);
for (const src of ['js/core.js', 'js/default-template.js', 'js/app.js']) {
  replaceOnce(new RegExp(`<script src="${src.replace('.', '\\.')}"></script>`), `<script>\n${safeScript(read(src))}</script>`);
}

fs.mkdirSync(OUT_DIR, { recursive: true });
const out = path.join(OUT_DIR, 'installment-calculator.html');
fs.writeFileSync(out, html);
console.log(`${path.relative(process.cwd(), out)} (${Math.round(html.length / 1024)} KB)`);

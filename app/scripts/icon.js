// App Symbol aus dem StageView Zeichen (engine/seite/icon.svg im Skill stagecraft-stageview), randlos, iOS rundet selbst ab.
// Aufruf im Ordner app/: node scripts/icon.js
const { chromium } = require('/Users/oletrappmann/.hermes/hermes-agent/node_modules/playwright');
const path = require('path');
const SVG = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="1024" height="1024"><defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#6A7B6D"/><stop offset="1" stop-color="#2A302C"/></linearGradient></defs><rect width="64" height="64" fill="url(#g)"/><path d="M20 15L49.5 32L20 49L20 27" fill="none" stroke="#F3F2EE" stroke-width="5.5" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1024, height: 1024 } });
  await p.setContent(`<html><body style="margin:0">${SVG}</body></html>`);
  await p.screenshot({ path: path.join(__dirname, '../StageView/Assets.xcassets/AppIcon.appiconset/icon.png'), omitBackground: false });
  await b.close();
  console.log('ok');
})();

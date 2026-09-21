const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require('playwright');

async function main() {
  const source = fs.readFileSync(path.join(__dirname, '..', 'WANsim2.sh'), 'utf8');
  const html = source.split('REACTUI_STAGE_TEMPLATE=r"""')[1].split('"""')[0];
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    let current = {
      topology: 'nat',
      l3: { segment: '10.254', links: [
        { wan: 'wan1', lan: 'lan1', vlans: 2, startVlan: 100, baseOctet: 10 },
        { wan: 'wan2', lan: 'lan2', vlans: 2, startVlan: 120, baseOctet: 20 },
      ] },
      telegram: { bots: [] },
    };
    let submitted;
    await page.route('http://wansim.test/**', async route => {
      const url = new URL(route.request().url());
      if (url.pathname === '/prebeta') {
        return route.fulfill({ contentType: 'text/html', body: html });
      }
      if (url.pathname === '/api/reactui/submit') {
        submitted = route.request().postDataJSON();
        current = submitted;
        return route.fulfill({ json: { ok: true, message: 'Parametros recibidos' } });
      }
      return route.fulfill({ json: {
        interfaces: ['wan1', 'lan1', 'wan2', 'lan2'].map(name => ({ name })),
        controlInterfaces: [], draft: current, daemons: [], leases: [],
      } });
    });
    await page.goto('http://wansim.test/prebeta');
    const modes = page.getByLabel('Modo del puerto LAN');
    await modes.first().waitFor({ timeout: 60000 });
    assert.equal(await modes.count(), 2);
    assert.equal(await page.getByText('ID VLAN inicial', { exact: true }).count(), 2);
    await modes.first().selectOption('access');
    assert.equal(await page.getByText('ID VLAN inicial', { exact: true }).count(), 1);
    assert.match(await page.locator('.diagram').innerText(), /Acceso sin etiqueta/);
    assert.match(await page.locator('.diagram').innerText(), /VLAN 120-121/);
    await page.getByRole('button', { name: 'Enviar parametros', exact: true }).click();
    await page.getByText('Parametros recibidos', { exact: true }).waitFor();
    assert.equal(submitted.l3.links[0].lanMode, 'access');
    assert.equal(submitted.l3.links[1].lanMode || 'vlan', 'vlan');
    await modes.nth(1).selectOption('access');
    assert.equal(await page.getByText('ID VLAN inicial', { exact: true }).count(), 0);
    await modes.first().selectOption('vlan');
    assert.equal(await page.getByText('ID VLAN inicial', { exact: true }).count(), 1);
    assert.match(await page.locator('.diagram').innerText(), /VLAN 100-101/);
    fs.mkdirSync('test-results', { recursive: true });
    await page.screenshot({ path: 'test-results/reactui-desktop.png', fullPage: true });
    await page.setViewportSize({ width: 390, height: 844 });
    await page.screenshot({ path: 'test-results/reactui-mobile.png', fullPage: true });
    assert.deepEqual(errors, []);
    console.log('ReactUI: mode controls, diagram and submit payload passed.');
  } finally {
    await browser.close();
  }
}

main().catch(error => { console.error(error); process.exitCode = 1; });

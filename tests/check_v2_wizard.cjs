const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require('playwright');

const dist = path.join(__dirname, '..', 'v2', 'frontend', 'dist');

async function main() {
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.addInitScript(() => window.sessionStorage.setItem('wansim-api-key', 'browser-test-key'));
    await page.route('http://wansim-v2.test/**', async route => {
      const request = route.request();
      const url = new URL(request.url());
      if (url.pathname === '/health') return route.fulfill({ json: { ok: true, version: '2.0.10-stable', execution_mode: 'host' } });
      if (url.pathname === '/api/v2/auth/me') return route.fulfill({ json: { id: 'legacy-api-key', username: 'legacy-api-key', role: 'admin', auth: 'api_key' } });
      if (url.pathname === '/api/v2/operations/overview') return route.fulfill({ json: {
        execution_mode: 'host', active_configuration: null, deployments: [], leases: [], services: [],
        interfaces: [
          { name: 'ens160', mac: '00:50:56:00:00:01', state: 'UP', ips: ['192.0.2.20'], rx_bytes: 1000, tx_bytes: 2000, is_management: true },
          { name: 'ens192', mac: '00:50:56:00:00:02', state: 'UP', ips: [], rx_bytes: 0, tx_bytes: 0, is_management: false },
          { name: 'ens224', mac: '00:50:56:00:00:03', state: 'DOWN', ips: [], rx_bytes: 0, tx_bytes: 0, is_management: false },
        ],
      } });
      if (url.pathname === '/api/v2/deployments') return route.fulfill({ json: [] });
      if (url.pathname === '/api/v2/telegram/bots') return route.fulfill({ json: [] });
      if (url.pathname === '/api/v2/configurations' && request.method() === 'POST') {
        const body = request.postDataJSON();
        return route.fulfill({ json: { id: 'cfg-browser-1', name: body.name, state: 'DRAFT', config: body.config, created_at: new Date().toISOString(), updated_at: new Date().toISOString() } });
      }
      if (url.pathname === '/api/v2/configurations/cfg-browser-1/plan') return route.fulfill({ json: {
        configuration_id: 'cfg-browser-1', execution_mode: 'host', management_confirmation_phrase: 'RIESGO ens160 cfg-browser-1',
        actions: [{ id: 'wan-up-1', phase: 'prepare', description: 'Activar WAN ens160', command: ['ip', 'link', 'set', 'ens160', 'up'] }],
        preflight: { ok: true, can_apply: true, mode: 'host', missing_interfaces: [], selected_interfaces: ['ens160', 'ens192'], management_interfaces: ['ens160'], protected_interfaces: ['ens160'], requires_management_confirmation: true, issues: [{ severity: 'warning', code: 'management_interface', title: 'ens160 transporta la administración', detail: 'Se activará recuperación automática.', interfaces: ['ens160'] }] },
        comparison: { current_name: 'Sin configuración activa', proposed_name: 'Topología WAN_SIM 2.0', current: ['Sin configuración activa'], proposed: ['Enlace 1: ens192 -> ens160'], changes: ['Agregar: Enlace 1: ens192 -> ens160'] },
      } });
      const localPath = url.pathname === '/' ? path.join(dist, 'index.html') : path.join(dist, url.pathname);
      if (fs.existsSync(localPath) && fs.statSync(localPath).isFile()) {
        const extension = path.extname(localPath);
        const contentType = extension === '.js' ? 'text/javascript' : extension === '.css' ? 'text/css' : 'text/html';
        return route.fulfill({ body: fs.readFileSync(localPath), contentType });
      }
      return route.fulfill({ status: 404, body: 'not found' });
    });

    await page.goto('http://wansim-v2.test/');
    await page.getByRole('button', { name: /Interfaces/ }).click();
    await page.getByText('3 interfaces detectadas').waitFor();
    assert.match(await page.locator('.interface-inventory').innerText(), /ens160.*Administración/s);
    await page.getByRole('button', { name: 'Usar recomendación' }).click();
    const selectors = page.locator('fieldset select');
    assert.equal(await selectors.nth(0).inputValue(), 'ens192');
    assert.equal(await selectors.nth(1).inputValue(), 'ens224');
    await selectors.nth(0).selectOption('ens160');
    await page.getByRole('button', { name: /Red/ }).click();
    await page.getByRole('button', { name: /Revisión/ }).click();
    await page.getByRole('button', { name: 'Revisar cambio' }).click();
    await page.getByText('ens160 transporta la administración').waitFor();
    assert.match(await page.locator('.comparison').innerText(), /ACTUAL.*PROPUESTA/s);
    await page.getByRole('button', { name: 'Desplegar cambio' }).click();
    await page.getByRole('heading', { name: 'Confirmar cambios reales' }).waitFor();
    assert.match(await page.locator('.modal-panel').innerText(), /RIESGO ens160 cfg-browser-1/);
    fs.mkdirSync('test-results', { recursive: true });
    await page.screenshot({ path: 'test-results/v2-wizard-desktop.png', fullPage: true });
    await page.setViewportSize({ width: 390, height: 844 });
    await page.screenshot({ path: 'test-results/v2-wizard-mobile.png', fullPage: true });
    assert.deepEqual(errors, []);
    console.log('ReactUI V2: wizard, preflight, comparison and management guard passed.');
  } finally {
    await browser.close();
  }
}

main().catch(error => { console.error(error); process.exitCode = 1; });

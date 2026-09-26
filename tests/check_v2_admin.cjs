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
    await page.route('http://wansim-admin.test/**', async route => {
      const request = route.request();
      const url = new URL(request.url());
      if (url.pathname === '/health') return route.fulfill({ json: { ok: true, version: '3.0.0-beta.1', execution_mode: 'dry-run' } });
      if (url.pathname === '/api/v2/auth/me') return route.fulfill({ json: { id: 'legacy-api-key', username: 'bootstrap-admin', role: 'admin', auth: 'api_key' } });
      if (url.pathname === '/api/v2/operations/overview') return route.fulfill({ json: { execution_mode: 'dry-run', active_configuration: null, deployments: [], leases: [], services: [], interfaces: [{ name: 'ens192', mac: '00:50:56:00:00:02', state: 'UP', ips: [], rx_bytes: 1000, tx_bytes: 2000, rx_mbps: 10.25, tx_mbps: 4.5, total_mbps: 14.75, is_management: false, netem: { active: true, delay_ms: 40, jitter_ms: 5, loss_percent: 1 } }] } });
      if (url.pathname === '/api/v2/deployments') return route.fulfill({ json: [] });
      if (url.pathname === '/api/v2/telegram/bots') return route.fulfill({ json: [] });
      if (url.pathname === '/api/v2/configurations') return route.fulfill({ json: [{ id: 'config-active', name: 'Laboratorio activo', state: 'ACTIVE', config: { topology: 'bridge', dhcpEnabled: false, l3: { segment: '10.254', links: [] }, bridge: { pairs: [{ input: 'ens160', output: 'ens192' }] } }, created_at: new Date().toISOString(), updated_at: new Date().toISOString() }] });
      if (url.pathname === '/api/v2/recovery/snapshots') return route.fulfill({ json: [{ id: 'snapshot-0001', configuration_id: 'config-0001', created_at: new Date().toISOString(), version: '2.0.12-rev1', checksum: 'abc123', integrity: true, topology: 'nat' }] });
      if (url.pathname === '/api/v2/recovery/backups') return route.fulfill({ json: [{ name: 'wansim-2.0.8-prestable.tar.gz', size: 3145728, created_at: new Date().toISOString(), checksum: 'def456', integrity: true }] });
      if (url.pathname === '/api/v2/operations/doctor') return route.fulfill({ json: { generated_at: new Date().toISOString(), status: 'warning', summary: { ok: 2, warning: 1, error: 0 }, checks: [{ component: 'database', status: 'ok', title: 'Integridad SQLite', detail: 'ok', remediation: '', restart_service: '' }, { component: 'telegram', status: 'warning', title: 'Bots de Telegram', detail: '1 sin webhook.', remediation: 'Sincroniza el bot.', restart_service: '' }] } });
      if (url.pathname === '/api/v2/audit/events') return route.fulfill({ json: [{ id: 'audit-1', actor: 'bootstrap-admin', role: 'admin', action: 'recovery.restore', target: 'snapshot-0001', detail: {}, created_at: new Date().toISOString() }] });
      if (url.pathname === '/api/v2/auth/users') return route.fulfill({ json: [{ id: 'user-1', username: 'bootstrap-admin', role: 'admin', enabled: true, created_at: new Date().toISOString(), updated_at: new Date().toISOString() }] });
      if (url.pathname === '/api/v2/system/releases') return route.fulfill({ json: { ok: true, current: '3.0.0-beta.1', latest: 'v3.0.0-beta.1', latest_stable: 'v2.0.13-stable', update_available: false, releases: ['v3.0.0-beta.1', 'v2.0.13-stable'] } });
      const localPath = url.pathname === '/' ? path.join(dist, 'index.html') : path.join(dist, url.pathname);
      if (fs.existsSync(localPath) && fs.statSync(localPath).isFile()) {
        const extension = path.extname(localPath);
        const contentType = extension === '.js' ? 'text/javascript' : extension === '.css' ? 'text/css' : 'text/html';
        return route.fulfill({ body: fs.readFileSync(localPath), contentType });
      }
      return route.fulfill({ status: 404, json: { detail: `not mocked: ${url.pathname}` } });
    });

    await page.goto('http://wansim-admin.test/');
    await page.getByRole('button', { name: /Recuperación/ }).click();
    await page.getByText('Snapshots verificados').waitFor();
    await page.getByText('Verificado', { exact: true }).waitFor();
    await page.getByText('SHA-256 válido', { exact: true }).waitFor();
    assert.match(await page.locator('.recovery-grid').innerText(), /Verificado/);
    assert.match(await page.locator('.recovery-grid').innerText(), /wansim-2\.0\.8-prestable\.tar\.gz/);
    await page.getByRole('button', { name: /Doctor/ }).click();
    await page.getByRole('heading', { name: 'Doctor' }).waitFor();
    await page.getByText('Integridad SQLite').waitFor();
    assert.match(await page.locator('.doctor-layout').innerText(), /Integridad SQLite/);
    await page.getByRole('button', { name: /Acceso/ }).click();
    await page.getByRole('heading', { name: 'Nuevo usuario' }).waitFor();
    await page.getByText('bootstrap-admin', { exact: true }).first().waitFor();
    await page.getByText('recovery.restore', { exact: true }).waitFor();
    assert.match(await page.locator('.access-grid').innerText(), /bootstrap-admin/);
    assert.match(await page.locator('.access-grid').innerText(), /recovery.restore/);
    await page.getByRole('button', { name: /Sistema/ }).click();
    await page.getByRole('heading', { name: 'Actualizaciones' }).waitFor();
    await page.getByRole('button', { name: 'Buscar versiones' }).click();
    await page.locator('.release-status dd').getByText('v2.0.13-stable', { exact: true }).waitFor();
    await page.getByText('Emilio Abundis', { exact: true }).waitFor();
    await page.getByRole('button', { name: /Operación/ }).click();
    await page.getByText('APPLIED', { exact: true }).waitFor();
    await page.getByText('14.75 Mbps actuales', { exact: true }).waitFor();
    await page.getByLabel('Acción para ens192').waitFor();
    await page.getByRole('button', { name: /Topología/ }).click();
    await page.getByRole('heading', { name: 'Configuración actual' }).waitFor();
    await page.getByText('Laboratorio activo', { exact: true }).first().waitFor();
    fs.mkdirSync('test-results', { recursive: true });
    await page.screenshot({ path: 'test-results/v2-admin-desktop.png', fullPage: true });
    await page.setViewportSize({ width: 390, height: 844 });
    await page.screenshot({ path: 'test-results/v2-admin-mobile.png', fullPage: true });
    assert.deepEqual(errors, []);
    console.log('ReactUI V3: recovery, Doctor, RBAC, updates and credits passed.');
  } finally {
    await browser.close();
  }
}

main().catch(error => { console.error(error); process.exitCode = 1; });

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
      if (url.pathname === '/health') return route.fulfill({ json: { ok: true, version: '2.0.12-rev2', execution_mode: 'dry-run' } });
      if (url.pathname === '/api/v2/auth/me') return route.fulfill({ json: { id: 'legacy-api-key', username: 'bootstrap-admin', role: 'admin', auth: 'api_key' } });
      if (url.pathname === '/api/v2/operations/overview') return route.fulfill({ json: { execution_mode: 'dry-run', active_configuration: null, deployments: [], leases: [], services: [], interfaces: [] } });
      if (url.pathname === '/api/v2/deployments') return route.fulfill({ json: [] });
      if (url.pathname === '/api/v2/telegram/bots') return route.fulfill({ json: [] });
      if (url.pathname === '/api/v2/recovery/snapshots') return route.fulfill({ json: [{ id: 'snapshot-0001', configuration_id: 'config-0001', created_at: new Date().toISOString(), version: '2.0.12-rev2', checksum: 'abc123', integrity: true, topology: 'nat' }] });
      if (url.pathname === '/api/v2/recovery/backups') return route.fulfill({ json: [{ name: 'wansim-2.0.8-prestable.tar.gz', size: 3145728, created_at: new Date().toISOString(), checksum: 'def456', integrity: true }] });
      if (url.pathname === '/api/v2/operations/doctor') return route.fulfill({ json: { generated_at: new Date().toISOString(), status: 'warning', summary: { ok: 2, warning: 1, error: 0 }, checks: [{ component: 'database', status: 'ok', title: 'Integridad SQLite', detail: 'ok', remediation: '', restart_service: '' }, { component: 'telegram', status: 'warning', title: 'Bots de Telegram', detail: '1 sin webhook.', remediation: 'Sincroniza el bot.', restart_service: '' }] } });
      if (url.pathname === '/api/v2/audit/events') return route.fulfill({ json: [{ id: 'audit-1', actor: 'bootstrap-admin', role: 'admin', action: 'recovery.restore', target: 'snapshot-0001', detail: {}, created_at: new Date().toISOString() }] });
      if (url.pathname === '/api/v2/auth/users') return route.fulfill({ json: [{ id: 'user-1', username: 'bootstrap-admin', role: 'admin', enabled: true, created_at: new Date().toISOString(), updated_at: new Date().toISOString() }] });
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
    fs.mkdirSync('test-results', { recursive: true });
    await page.screenshot({ path: 'test-results/v2-admin-desktop.png', fullPage: true });
    await page.setViewportSize({ width: 390, height: 844 });
    await page.screenshot({ path: 'test-results/v2-admin-mobile.png', fullPage: true });
    assert.deepEqual(errors, []);
    console.log('ReactUI V2: recovery, Doctor, RBAC and audit passed.');
  } finally {
    await browser.close();
  }
}

main().catch(error => { console.error(error); process.exitCode = 1; });

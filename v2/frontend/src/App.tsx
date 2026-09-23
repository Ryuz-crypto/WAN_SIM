import { useEffect, useMemo, useState, type SetStateAction } from 'react'
import {
  Bot, CheckCircle2, Clock3, Gauge, KeyRound, LayoutDashboard, LogOut,
  Play, RefreshCw, RotateCcw, Router, Save, ServerCog, ShieldCheck, SlidersHorizontal, Workflow,
} from 'lucide-react'
import { api, configureApiKey } from './api'
import { ConfigurationWizard } from './ConfigurationWizard'
import type { Config, Configuration, Deployment, L3Link, Overview, PlanReview, TelegramBot, TelegramPermission } from './types'

const emptyLink = (): L3Link => ({ wan: '', lan: '', lanMode: 'vlan', vlans: 1, startVlan: 100, baseOctet: 10, wanMode: 'dhcp', wanCidr: '', wanGateway: '' })
const initialConfig = (): Config => ({ topology: 'nat', dhcpEnabled: true, l3: { segment: '10.254', links: [emptyLink()] }, bridge: { pairs: [{ input: '', output: '' }] } })

function bytes(value: number) {
  if (!value) return '0 B'
  const units = ['B', 'KB', 'MB', 'GB', 'TB']
  const index = Math.min(Math.floor(Math.log(value) / Math.log(1024)), units.length - 1)
  return `${(value / 1024 ** index).toFixed(index ? 1 : 0)} ${units[index]}`
}

function App() {
  const [apiKey, setApiKey] = useState(() => window.sessionStorage.getItem('wansim-api-key') ?? '')
  const [apiKeyDraft, setApiKeyDraft] = useState('')
  const [tab, setTab] = useState<'configure' | 'operations' | 'telegram' | 'audit'>('configure')
  const [config, setConfig] = useState<Config>(initialConfig)
  const [name, setName] = useState('Topología WAN_SIM 2.0')
  const [configuration, setConfiguration] = useState<Configuration | null>(null)
  const [review, setReview] = useState<PlanReview | null>(null)
  const [overview, setOverview] = useState<Overview | null>(null)
  const [deployments, setDeployments] = useState<Deployment[]>([])
  const [health, setHealth] = useState<{ version: string; execution_mode: string } | null>(null)
  const [notice, setNotice] = useState('')
  const [busy, setBusy] = useState(false)
  const [netem, setNetem] = useState({ interface: '', delayMs: 0, jitterMs: 0, lossPercent: 0 })
  const [bots, setBots] = useState<TelegramBot[]>([])
  const [botForm, setBotForm] = useState({ name: '', token: '', chatIds: '', permission: 'operate' as TelegramPermission })
  const [telegramBaseUrl, setTelegramBaseUrl] = useState('')
  const [confirmDeployment, setConfirmDeployment] = useState(false)
  const [confirmationText, setConfirmationText] = useState('')
  const [managementConfirmationText, setManagementConfirmationText] = useState('')

  const interfaces = overview?.interfaces ?? []
  const interfaceNames = useMemo(() => interfaces.map(item => item.name), [interfaces])
  const refresh = async () => {
    try {
      const [nextOverview, nextDeployments, nextHealth, nextBots] = await Promise.all([api.overview(), api.deployments(), api.health(), api.bots()])
      setOverview(nextOverview); setDeployments(nextDeployments); setHealth(nextHealth); setBots(nextBots)
      if (!netem.interface && nextOverview.interfaces[0]) setNetem(value => ({ ...value, interface: nextOverview.interfaces[0].name }))
    } catch (error) { setNotice(error instanceof Error ? error.message : 'No se pudo consultar el plano de control.') }
  }
  useEffect(() => {
    if (!apiKey) return
    configureApiKey(apiKey)
    void refresh()
    const id = window.setInterval(() => void refresh(), 15000)
    return () => window.clearInterval(id)
  }, [apiKey])

  const authenticate = () => {
    const key = apiKeyDraft.trim()
    if (!key) { setNotice('Ingresa la clave de operador.'); return }
    window.sessionStorage.setItem('wansim-api-key', key)
    configureApiKey(key)
    setApiKey(key)
    setApiKeyDraft('')
  }
  const logout = () => {
    window.sessionStorage.removeItem('wansim-api-key')
    configureApiKey('')
    setApiKey('')
    setOverview(null); setDeployments([]); setBots([]); setNotice('')
  }

  const changeConfig = (next: SetStateAction<Config>) => {
    setConfig(current => typeof next === 'function' ? next(current) : next)
    setConfiguration(null); setReview(null)
  }
  const changeName = (value: string) => { setName(value); setConfiguration(null); setReview(null) }
  const resetConfig = () => { changeConfig(initialConfig()); setName('Topología WAN_SIM 2.0') }
  const createPlan = async () => {
    setBusy(true); setNotice('')
    try {
      const created = await api.createConfig(name, config)
      const response = await api.plan(created.id)
      setConfiguration(created); setReview(response)
      setNotice(response.preflight.can_apply ? 'Revisión completada. El cambio está listo para desplegar.' : 'La revisión encontró errores que deben corregirse.')
    } catch (error) { setNotice(error instanceof Error ? error.message : 'No se pudo validar la configuración.') }
    finally { setBusy(false) }
  }
  const deploy = async (confirmation?: string, managementConfirmation?: string) => {
    if (!configuration) return
    setBusy(true); setNotice('')
    let awaitingConnectivityConfirmation = false
    try {
      let result = await api.deploy(configuration.id, true, confirmation, managementConfirmation)
      if (result.status === 'AWAITING_CONFIRMATION') {
        awaitingConnectivityConfirmation = true
        await api.health()
        result = await api.confirmDeployment(result.id)
      }
      setDeployments(value => [result, ...value]); setNotice(result.status === 'APPLIED' ? 'Despliegue aplicado y conectividad confirmada.' : `Despliegue ${result.status.toLowerCase()}.`)
      setConfirmDeployment(false); setConfirmationText(''); setManagementConfirmationText(''); await refresh()
    }
    catch (error) {
      const detail = error instanceof Error ? error.message : 'error desconocido'
      setNotice(awaitingConnectivityConfirmation
        ? `No se confirmó la conectividad administrativa. El watchdog revertirá el cambio automáticamente: ${detail}`
        : detail)
    }
    finally { setBusy(false) }
  }
  const requestDeployment = () => {
    if (!configuration) return
    if (health?.execution_mode === 'host') { setConfirmationText(''); setManagementConfirmationText(''); setConfirmDeployment(true); return }
    void deploy()
  }
  const rollback = async (id: string) => {
    setBusy(true)
    try { const result = await api.rollback(id); setDeployments(value => value.map(item => item.id === id ? result : item)); setNotice('Rollback registrado.'); await refresh() }
    catch (error) { setNotice(error instanceof Error ? error.message : 'No se pudo ejecutar rollback.') }
    finally { setBusy(false) }
  }
  const applyNetem = async (reset = false) => {
    try { await api.netem(reset ? { ...netem, delayMs: 0, jitterMs: 0, lossPercent: 0 } : netem); setNotice(reset ? 'Perfil restablecido.' : 'Perfil de red aplicado.'); if (reset) setNetem(value => ({ ...value, delayMs: 0, jitterMs: 0, lossPercent: 0 })) }
    catch (error) { setNotice(error instanceof Error ? error.message : 'No se pudo actualizar netem.') }
  }
  const createBot = async () => {
    const allowed_chat_ids = botForm.chatIds.split(',').map(value => Number(value.trim())).filter(value => Number.isInteger(value))
    if (!botForm.name || !botForm.token || !allowed_chat_ids.length) { setNotice('Indica nombre, token y al menos un chat ID válido.'); return }
    setBusy(true)
    try { const created = await api.createBot({ name: botForm.name, token: botForm.token, allowed_chat_ids, permission: botForm.permission }); setBotForm({ name: '', token: '', chatIds: '', permission: 'operate' }); let message = `Bot creado. Guarda ahora el secreto de webhook: ${created.webhook_secret}`; if (telegramBaseUrl) { try { await api.syncBot(created.bot.id, telegramBaseUrl); message = `Bot y webhook sincronizados. Guarda ahora el secreto: ${created.webhook_secret}` } catch (error) { message = `${message}. No se sincronizó el webhook: ${error instanceof Error ? error.message : 'error desconocido'}` } } setNotice(message); await refresh() }
    catch (error) { setNotice(error instanceof Error ? error.message : 'No se pudo crear el bot.') }
    finally { setBusy(false) }
  }
  const updateBot = async (bot: TelegramBot, enabled: boolean) => {
    try { await api.updateBot(bot.id, { enabled }); setNotice(enabled ? 'Bot habilitado.' : 'Bot deshabilitado.'); await refresh() }
    catch (error) { setNotice(error instanceof Error ? error.message : 'No se pudo actualizar el bot.') }
  }
  const testBot = async (bot: TelegramBot) => {
    try { await api.testBot(bot.id, bot.allowed_chat_ids[0]); setNotice(`Prueba enviada a ${bot.name}.`) }
    catch (error) { setNotice(error instanceof Error ? error.message : 'No se pudo enviar la prueba.') }
  }
  const syncBot = async (bot: TelegramBot) => {
    if (!telegramBaseUrl) { setNotice('Indica la URL pública HTTPS del API para sincronizar el webhook.'); return }
    try { await api.syncBot(bot.id, telegramBaseUrl); setNotice(`Webhook sincronizado para ${bot.name}.`); await refresh() }
    catch (error) { setNotice(error instanceof Error ? error.message : 'No se pudo sincronizar el webhook.') }
  }

  return <main className="app-shell">
    <header className="topbar"><div className="brand"><Router size={28} /><div><strong>WAN_SIM</strong><span>Control Plane 2.0</span></div></div><div className="topbar-actions"><span className={`mode ${health?.execution_mode === 'host' ? 'host' : ''}`}><ShieldCheck size={15} />{apiKey ? health?.execution_mode ?? 'conectando' : 'protegido'}</span><span className="version">{health?.version ?? '2.0.8-prestable'}</span>{apiKey && <><button className="icon-button" onClick={() => void refresh()} title="Actualizar estado"><RefreshCw size={18} /></button><button className="icon-button" onClick={logout} title="Cerrar sesión"><LogOut size={18} /></button></>}</div></header>
    {!apiKey && <section className="workspace"><section className="panel auth-panel"><div className="panel-heading"><div><span className="eyebrow">Acceso de operador</span><h1>Plano de control protegido</h1></div><KeyRound size={23} /></div><label>Clave de API<input type="password" autoComplete="current-password" value={apiKeyDraft} onChange={event => setApiKeyDraft(event.target.value)} onKeyDown={event => { if (event.key === 'Enter') authenticate() }} /></label><div className="button-row"><button className="primary-button" onClick={authenticate}><KeyRound size={17} />Ingresar</button></div></section></section>}
    {apiKey && <>
    <nav className="nav-tabs" aria-label="Navegación principal">
      <button className={tab === 'configure' ? 'selected' : ''} onClick={() => setTab('configure')}><Workflow size={17} />Configurar</button>
      <button className={tab === 'operations' ? 'selected' : ''} onClick={() => setTab('operations')}><LayoutDashboard size={17} />Operación</button>
      <button className={tab === 'telegram' ? 'selected' : ''} onClick={() => setTab('telegram')}><Bot size={17} />Telegram</button>
      <button className={tab === 'audit' ? 'selected' : ''} onClick={() => setTab('audit')}><Clock3 size={17} />Cambios</button>
    </nav>
    {notice && <div className="notice">{notice}</div>}

    {tab === 'configure' && <ConfigurationWizard
      name={name} config={config} interfaces={interfaces} configuration={configuration} review={review} busy={busy}
      setName={changeName} setConfig={changeConfig} onReview={() => void createPlan()} onDeploy={requestDeployment} onReset={resetConfig}
    />}

    {tab === 'operations' && <section className="workspace operations-grid"><section className="metric-strip"><div><span>Interfaces</span><strong>{interfaces.length}</strong></div><div><span>Leases DHCP</span><strong>{overview?.leases.length ?? 0}</strong></div><div><span>Servicios activos</span><strong>{overview?.services.filter(item => item.active === 'active').length ?? 0}</strong></div><div><span>Configuración activa</span><strong>{overview?.active_configuration ? 'Sí' : 'No'}</strong></div></section><section className="panel full"><div className="panel-heading"><div><span className="eyebrow">Enlaces</span><h2>Interfaces y tráfico</h2></div><Gauge size={22} /></div><div className="table-wrap"><table><thead><tr><th>Interfaz</th><th>Estado</th><th>IPv4</th><th>MAC</th><th>Entrada</th><th>Salida</th></tr></thead><tbody>{interfaces.length ? interfaces.map(item => <tr key={item.name}><td><strong>{item.name}</strong></td><td><span className={`state ${item.state.toLowerCase()}`}>{item.state}</span></td><td>{item.ips.join(', ') || '-'}</td><td>{item.mac || '-'}</td><td>{bytes(item.rx_bytes)}</td><td>{bytes(item.tx_bytes)}</td></tr>) : <tr><td colSpan={6} className="empty">Sin interfaces disponibles desde el agente</td></tr>}</tbody></table></div></section><section className="panel"><div className="panel-heading"><div><span className="eyebrow">Degradación</span><h2>Netem</h2></div><SlidersHorizontal size={22} /></div><label>Interfaz<select value={netem.interface} onChange={event => setNetem(value => ({ ...value, interface: event.target.value }))}><option value="">Seleccionar</option>{interfaceNames.map(item => <option key={item}>{item}</option>)}</select></label><div className="field-grid"><label>Delay ms<input type="number" min="0" value={netem.delayMs} onChange={event => setNetem(value => ({ ...value, delayMs: Number(event.target.value) }))} /></label><label>Jitter ms<input type="number" min="0" value={netem.jitterMs} onChange={event => setNetem(value => ({ ...value, jitterMs: Number(event.target.value) }))} /></label><label>Pérdida %<input type="number" min="0" max="100" value={netem.lossPercent} onChange={event => setNetem(value => ({ ...value, lossPercent: Number(event.target.value) }))} /></label></div><div className="preset-row"><button onClick={() => setNetem(value => ({ ...value, delayMs: 40, jitterMs: 5, lossPercent: 0 }))}>Latencia</button><button onClick={() => setNetem(value => ({ ...value, delayMs: 0, jitterMs: 0, lossPercent: 2 }))}>Pérdida</button></div><div className="button-row"><button className="primary-button" disabled={!netem.interface} onClick={() => void applyNetem()}><Play size={17} />Aplicar</button><button className="secondary-button" disabled={!netem.interface} onClick={() => void applyNetem(true)}><RotateCcw size={17} />Reset</button></div></section><section className="panel"><div className="panel-heading"><div><span className="eyebrow">Servicios</span><h2>Daemons</h2></div><ServerCog size={22} /></div><div className="service-list">{overview?.services.map(item => <div key={item.name}><div><strong>{item.name}</strong><span className={item.active === 'active' ? 'good' : 'muted'}>{item.active} / {item.enabled}</span></div><button className="icon-button" title={`Reiniciar ${item.name}`} onClick={() => void api.restart(item.name).then(refresh).catch(error => setNotice(error.message))}><RefreshCw size={16} /></button></div>)}</div></section><section className="panel full"><div className="panel-heading"><div><span className="eyebrow">Asignaciones</span><h2>DHCP leases</h2></div><CheckCircle2 size={22} /></div><div className="table-wrap"><table><thead><tr><th>IP</th><th>Host</th><th>MAC</th><th>Estado</th></tr></thead><tbody>{overview?.leases.length ? overview.leases.map((item, index) => <tr key={`${item.ip}-${index}`}><td>{item.ip}</td><td>{item.host || '-'}</td><td>{item.mac || '-'}</td><td>{item.state || '-'}</td></tr>) : <tr><td colSpan={4} className="empty">Sin asignaciones DHCP</td></tr>}</tbody></table></div></section></section>}

    {tab === 'telegram' && <section className="workspace configure-grid"><section className="panel form-panel"><div className="panel-heading"><div><span className="eyebrow">Canal de operación</span><h1>Bots de Telegram</h1></div><Bot size={23} /></div><label>URL pública HTTPS del API<input value={telegramBaseUrl} placeholder="https://wansim.example.com" onChange={event => setTelegramBaseUrl(event.target.value)} /></label><label>Nombre<input value={botForm.name} placeholder="NOC principal" onChange={event => setBotForm(value => ({ ...value, name: event.target.value }))} /></label><label>Token del bot<input type="password" autoComplete="new-password" value={botForm.token} placeholder="123456:ABC..." onChange={event => setBotForm(value => ({ ...value, token: event.target.value }))} /></label><label>Chat IDs autorizados<input value={botForm.chatIds} placeholder="123456789, 987654321" onChange={event => setBotForm(value => ({ ...value, chatIds: event.target.value }))} /></label><label>Permiso<select value={botForm.permission} onChange={event => setBotForm(value => ({ ...value, permission: event.target.value as TelegramPermission }))}><option value="read">Solo lectura</option><option value="operate">Operación / netem</option><option value="admin">Administración</option></select></label><div className="button-row"><button className="primary-button" disabled={busy} onClick={() => void createBot()}><Save size={17} />Crear bot</button></div></section><section className="panel full"><div className="panel-heading"><div><span className="eyebrow">Acceso protegido</span><h2>Inventario de bots</h2></div><ShieldCheck size={22} /></div><div className="table-wrap"><table><thead><tr><th>Nombre</th><th>Token</th><th>Chats</th><th>Rol</th><th>Webhook</th><th>Estado</th><th></th></tr></thead><tbody>{bots.length ? bots.map(bot => <tr key={bot.id}><td><strong>{bot.name}</strong></td><td>{bot.token_hint}</td><td>{bot.allowed_chat_ids.join(', ')}</td><td>{bot.permission}</td><td>{bot.webhook_url ? 'sincronizado' : 'pendiente'}</td><td><span className={bot.enabled ? 'good' : 'muted'}>{bot.enabled ? 'habilitado' : 'deshabilitado'}</span></td><td><div className="button-row"><button className="secondary-button compact" onClick={() => void syncBot(bot)}>Sincronizar</button><button className="secondary-button compact" onClick={() => void testBot(bot)}>Probar</button><button className="secondary-button compact" onClick={() => void updateBot(bot, !bot.enabled)}>{bot.enabled ? 'Deshabilitar' : 'Habilitar'}</button></div></td></tr>) : <tr><td colSpan={7} className="empty">Sin bots configurados</td></tr>}</tbody></table></div></section></section>}

    {tab === 'audit' && <section className="workspace"><section className="panel full"><div className="panel-heading"><div><span className="eyebrow">Auditoría</span><h1>Despliegues</h1></div><Clock3 size={22} /></div><div className="table-wrap"><table><thead><tr><th>Hora</th><th>Estado</th><th>Acciones</th><th>Modo</th><th></th></tr></thead><tbody>{deployments.length ? deployments.map(item => <tr key={item.id}><td>{new Date(item.created_at).toLocaleString('es-MX')}</td><td><span className={`state ${item.status.toLowerCase()}`}>{item.status}</span></td><td>{item.plan.length}</td><td>{String(item.result.mode ?? '-')}</td><td><button className="secondary-button compact" disabled={!['APPLIED', 'AWAITING_CONFIRMATION'].includes(item.status) || busy} onClick={() => void rollback(item.id)}><RotateCcw size={15} />Rollback</button></td></tr>) : <tr><td colSpan={5} className="empty">Sin despliegues registrados</td></tr>}</tbody></table></div></section></section>}
    {confirmDeployment && configuration && <div className="modal-backdrop" role="dialog" aria-modal="true" aria-labelledby="deployment-confirm-title"><section className="modal-panel"><div className="panel-heading"><div><span className="eyebrow">Modo host</span><h2 id="deployment-confirm-title">Confirmar cambios reales</h2></div><ShieldCheck size={23} /></div><p>Se aplicarán las acciones revisadas al host.</p><code className="confirmation-code">APLICAR {configuration.id}</code><label>Confirmación del cambio<input autoFocus value={confirmationText} onChange={event => setConfirmationText(event.target.value)} /></label>{review?.management_confirmation_phrase && <div className="management-confirmation"><p>La selección incluye la ruta de administración. El sistema hará rollback si ReactUI no confirma conectividad después de aplicar.</p><code className="confirmation-code">{review.management_confirmation_phrase}</code><label>Confirmación de riesgo<input value={managementConfirmationText} onChange={event => setManagementConfirmationText(event.target.value)} /></label></div>}<div className="button-row"><button className="secondary-button" onClick={() => { setConfirmDeployment(false); setConfirmationText(''); setManagementConfirmationText('') }}>Cancelar</button><button className="primary-button" disabled={busy || confirmationText !== `APLICAR ${configuration.id}` || Boolean(review?.management_confirmation_phrase && managementConfirmationText !== review.management_confirmation_phrase)} onClick={() => void deploy(confirmationText, managementConfirmationText)}><Play size={17} />Aplicar cambios</button></div></section></div>}
    </>}
  </main>
}

export default App

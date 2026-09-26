import { useEffect, useMemo, useState } from 'react'
import { CheckCircle2, Gauge, Play, RefreshCw, RotateCcw, ServerCog, SlidersHorizontal } from 'lucide-react'
import { api } from './api'
import type { Overview } from './types'

type Props = { overview: Overview | null; canOperate: boolean; isAdmin: boolean; onNotice: (message: string) => void; onRefresh: () => Promise<void> }

function bytes(value: number) {
  if (!value) return '0 B'
  const units = ['B', 'KB', 'MB', 'GB', 'TB']
  const index = Math.min(Math.floor(Math.log(value) / Math.log(1024)), units.length - 1)
  return `${(value / 1024 ** index).toFixed(index ? 1 : 0)} ${units[index]}`
}

export function OperationsPanel({ overview, canOperate, isAdmin, onNotice, onRefresh }: Props) {
  const interfaces = overview?.interfaces ?? []
  const [netem, setNetem] = useState({ interface: interfaces[0]?.name ?? '', delayMs: 0, jitterMs: 0, lossPercent: 0 })
  const selected = useMemo(() => interfaces.find(item => item.name === netem.interface), [interfaces, netem.interface])
  useEffect(() => {
    if (!netem.interface && interfaces[0]) selectInterface(interfaces[0].name)
  }, [interfaces, netem.interface])
  const selectInterface = (name: string) => {
    const item = interfaces.find(value => value.name === name)
    setNetem({ interface: name, delayMs: item?.netem?.delay_ms ?? 0, jitterMs: item?.netem?.jitter_ms ?? 0, lossPercent: item?.netem?.loss_percent ?? 0 })
  }
  const applyNetem = async (reset = false) => {
    const payload = reset ? { ...netem, delayMs: 0, jitterMs: 0, lossPercent: 0 } : netem
    try { await api.netem(payload); setNetem(payload); onNotice(reset ? 'Perfil Netem restablecido.' : 'Perfil Netem aplicado.'); await onRefresh() }
    catch (error) { onNotice(error instanceof Error ? error.message : 'No se pudo actualizar Netem.') }
  }
  const interfaceAction = async (name: string, action: 'up' | 'down' | 'restart') => {
    if (!window.confirm(`${action === 'up' ? 'Activar' : action === 'down' ? 'Desactivar' : 'Reiniciar'} la interfaz ${name}?`)) return
    try { await api.interfaceAction(name, action); onNotice(`Interfaz ${name}: acción ${action} aplicada.`); await onRefresh() }
    catch (error) { onNotice(error instanceof Error ? error.message : 'No se pudo operar la interfaz.') }
  }
  return <section className="workspace operations-grid">
    <section className="metric-strip"><div><span>Interfaces</span><strong>{interfaces.length}</strong></div><div><span>Leases DHCP</span><strong>{overview?.leases.length ?? 0}</strong></div><div><span>Servicios activos</span><strong>{overview?.services.filter(item => item.active === 'active').length ?? 0}</strong></div><div><span>Configuración activa</span><strong>{overview?.active_configuration ? 'Sí' : 'No'}</strong></div></section>
    <section className="panel full"><div className="panel-heading"><div><span className="eyebrow">Enlaces</span><h2>Interfaces y tráfico</h2></div><Gauge size={22} /></div><div className="table-wrap"><table><thead><tr><th>Interfaz</th><th>Estado</th><th>IPv4</th><th>MAC</th><th>Entrada</th><th>Salida</th><th>BW actual</th><th>Acción</th></tr></thead><tbody>{interfaces.length ? interfaces.map(item => <tr key={item.name}><td><strong>{item.name}</strong>{item.is_management && <small className="table-note">Administración</small>}</td><td><span className={`state ${item.state.toLowerCase()}`}>{item.state}</span></td><td>{item.ips.join(', ') || '-'}</td><td>{item.mac || '-'}</td><td>{bytes(item.rx_bytes)}</td><td>{bytes(item.tx_bytes)}</td><td>{(item.total_mbps ?? 0).toFixed(2)} Mbps</td><td><select aria-label={`Acción para ${item.name}`} defaultValue="" disabled={!isAdmin} onChange={event => { const action = event.target.value as 'up' | 'down' | 'restart'; event.target.value = ''; if (action) void interfaceAction(item.name, action) }}><option value="">Elegir</option><option value="up">Up</option><option value="down" disabled={item.is_management}>Down</option><option value="restart" disabled={item.is_management}>Restart</option></select></td></tr>) : <tr><td colSpan={8} className="empty">Sin interfaces disponibles desde el agente</td></tr>}</tbody></table></div></section>
    <section className="panel"><div className="panel-heading"><div><span className="eyebrow">Degradación</span><h2>Netem</h2></div><SlidersHorizontal size={22} /></div><label>Interfaz<select value={netem.interface} onChange={event => selectInterface(event.target.value)}><option value="">Seleccionar</option>{interfaces.map(item => <option key={item.name}>{item.name}</option>)}</select></label><div className={`applied-profile ${selected?.netem?.active ? 'active' : ''}`}><span>{selected?.netem?.active ? 'APPLIED' : 'SIN DEGRADACIÓN'}</span><strong>{selected?.name ?? 'Selecciona interfaz'}</strong><p>{selected?.netem?.active ? `${selected.netem.delay_ms} ms latencia · ${selected.netem.jitter_ms} ms jitter · ${selected.netem.loss_percent}% pérdida` : 'No hay un perfil Netem activo.'}</p><b>{(selected?.total_mbps ?? 0).toFixed(2)} Mbps actuales</b></div><div className="field-grid"><label>Delay ms<input type="number" min="0" value={netem.delayMs} onChange={event => setNetem(value => ({ ...value, delayMs: Number(event.target.value) }))} /></label><label>Jitter ms<input type="number" min="0" value={netem.jitterMs} onChange={event => setNetem(value => ({ ...value, jitterMs: Number(event.target.value) }))} /></label><label>Pérdida %<input type="number" min="0" max="100" value={netem.lossPercent} onChange={event => setNetem(value => ({ ...value, lossPercent: Number(event.target.value) }))} /></label></div><div className="preset-row"><button disabled={!canOperate} onClick={() => setNetem(value => ({ ...value, delayMs: 40, jitterMs: 5, lossPercent: 0 }))}>Latencia</button><button disabled={!canOperate} onClick={() => setNetem(value => ({ ...value, delayMs: 0, jitterMs: 0, lossPercent: 2 }))}>Pérdida</button></div><div className="button-row"><button className="primary-button" disabled={!canOperate || !netem.interface} onClick={() => void applyNetem()}><Play size={17} />Aplicar</button><button className="secondary-button" disabled={!canOperate || !netem.interface} onClick={() => void applyNetem(true)}><RotateCcw size={17} />Reset</button></div></section>
    <section className="panel"><div className="panel-heading"><div><span className="eyebrow">Servicios</span><h2>Daemons</h2></div><ServerCog size={22} /></div><div className="service-list">{overview?.services.map(item => <div key={item.name}><div><strong>{item.name}</strong><span className={item.active === 'active' ? 'good' : 'muted'}>{item.active} / {item.enabled}</span></div>{isAdmin && <button className="icon-button light" title={`Reiniciar ${item.name}`} onClick={() => void api.restart(item.name).then(onRefresh).catch(error => onNotice(error.message))}><RefreshCw size={16} /></button>}</div>)}</div></section>
    <section className="panel full"><div className="panel-heading"><div><span className="eyebrow">Asignaciones</span><h2>DHCP leases</h2></div><CheckCircle2 size={22} /></div><div className="table-wrap"><table><thead><tr><th>IP</th><th>Host</th><th>MAC</th><th>Estado</th></tr></thead><tbody>{overview?.leases.length ? overview.leases.map((item, index) => <tr key={`${item.ip}-${index}`}><td>{item.ip}</td><td>{item.host || '-'}</td><td>{item.mac || '-'}</td><td>{item.state || '-'}</td></tr>) : <tr><td colSpan={4} className="empty">Sin asignaciones DHCP</td></tr>}</tbody></table></div></section>
  </section>
}

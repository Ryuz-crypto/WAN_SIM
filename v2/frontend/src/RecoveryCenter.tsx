import { useEffect, useState } from 'react'
import { ArchiveRestore, CheckCircle2, RefreshCw, RotateCcw, ShieldAlert } from 'lucide-react'
import { api } from './api'
import type { HostBackup, RecoverySnapshot, UserRole } from './types'

type Props = { role: UserRole; onNotice: (message: string) => void; onChanged: () => void }

export function RecoveryCenter({ role, onNotice, onChanged }: Props) {
  const [snapshots, setSnapshots] = useState<RecoverySnapshot[]>([])
  const [backups, setBackups] = useState<HostBackup[]>([])
  const [selected, setSelected] = useState<RecoverySnapshot | null>(null)
  const [selectedBackup, setSelectedBackup] = useState<HostBackup | null>(null)
  const [lastKnownGood, setLastKnownGood] = useState(false)
  const [confirmation, setConfirmation] = useState('')
  const [busy, setBusy] = useState(false)

  const refresh = async () => {
    try {
      const [snapshotItems, backupItems] = await Promise.all([api.snapshots(), api.backups()])
      setSnapshots(snapshotItems); setBackups(backupItems)
    } catch (error) { onNotice(error instanceof Error ? error.message : 'No se pudieron consultar los puntos de recuperación.') }
  }
  useEffect(() => { void refresh() }, [])

  const expected = selectedBackup
    ? `RESTAURAR BACKUP ${selectedBackup.name}`
    : lastKnownGood ? 'RECUPERAR ULTIMA FUNCIONAL' : selected ? `RESTAURAR ${selected.id}` : ''
  const restore = async () => {
    if (!expected || confirmation !== expected) return
    setBusy(true)
    try {
      if (selectedBackup) {
        const result = await api.restoreBackup(selectedBackup.name, confirmation)
        onNotice(`Restauración programada en ${result.unit}. La interfaz puede reconectarse.`)
      } else {
        const result = lastKnownGood
          ? await api.restoreLastKnownGood(confirmation)
          : await api.restoreSnapshot(selected!.id, confirmation)
        onNotice(`Recuperación finalizada con estado ${result.status}.`)
      }
      setSelected(null); setSelectedBackup(null); setLastKnownGood(false); setConfirmation('')
      await refresh(); onChanged()
    } catch (error) { onNotice(error instanceof Error ? error.message : 'No se pudo restaurar el punto de recuperación.') }
    finally { setBusy(false) }
  }

  return <section className="workspace recovery-grid">
    <section className="panel full"><div className="panel-heading"><div><span className="eyebrow">Recuperación transaccional</span><h1>Snapshots verificados</h1></div><ArchiveRestore size={23} /></div>
      <div className="section-toolbar"><div><strong>{snapshots.length} puntos disponibles</strong><span>El checksum se comprueba nuevamente antes de restaurar.</span></div><div className="button-row inline"><button className="icon-button light" title="Actualizar recuperación" onClick={() => void refresh()}><RefreshCw size={16} /></button>{role === 'admin' && <button className="primary-button" disabled={!snapshots.some(item => item.integrity)} onClick={() => { setLastKnownGood(true); setSelected(null); setSelectedBackup(null); setConfirmation('') }}><RotateCcw size={16} />Última funcional</button>}</div></div>
      <div className="table-wrap"><table><thead><tr><th>Fecha</th><th>Versión</th><th>Topología</th><th>Integridad</th><th>Configuración</th><th></th></tr></thead><tbody>{snapshots.length ? snapshots.map(item => <tr key={item.id}><td>{new Date(item.created_at).toLocaleString('es-MX')}</td><td>{item.version}</td><td>{item.topology}</td><td><span className={`state ${item.integrity ? 'active' : 'rejected'}`}>{item.integrity ? 'Verificado' : 'Alterado'}</span></td><td><code>{item.configuration_id ? item.configuration_id.slice(0, 12) : 'Estado inicial'}</code></td><td>{role === 'admin' && <button className="secondary-button compact" disabled={!item.integrity} onClick={() => { setSelected(item); setLastKnownGood(false); setConfirmation('') }}><ArchiveRestore size={14} />Restaurar</button>}</td></tr>) : <tr><td className="empty" colSpan={6}>Todavía no existen snapshots. Se crean antes de cada despliegue real.</td></tr>}</tbody></table></div>
    </section>
    <section className="panel full"><div className="panel-heading"><div><span className="eyebrow">Respaldo del host</span><h2>Versiones instaladas</h2></div><ArchiveRestore size={21} /></div>
      <div className="section-toolbar"><div><strong>{backups.length} respaldos del sistema</strong><span>Incluyen configuración, datos y entorno previos a una actualización.</span></div></div>
      <div className="table-wrap"><table><thead><tr><th>Fecha</th><th>Archivo</th><th>Tamaño</th><th>Integridad</th><th></th></tr></thead><tbody>{backups.length ? backups.map(item => <tr key={item.name}><td>{item.created_at ? new Date(item.created_at).toLocaleString('es-MX') : 'No disponible'}</td><td><code>{item.name}</code></td><td>{(item.size / 1024 / 1024).toFixed(1)} MB</td><td><span className={`state ${item.integrity ? 'active' : 'rejected'}`}>{item.integrity ? 'SHA-256 válido' : 'Alterado'}</span></td><td>{role === 'admin' && <button className="secondary-button compact" disabled={!item.integrity} onClick={() => { setSelectedBackup(item); setSelected(null); setLastKnownGood(false); setConfirmation('') }}><ArchiveRestore size={14} />Restaurar host</button>}</td></tr>) : <tr><td className="empty" colSpan={5}>No hay respaldos del instalador en este host.</td></tr>}</tbody></table></div>
    </section>
    {(selected || selectedBackup || lastKnownGood) && <div className="modal-backdrop" role="dialog" aria-modal="true"><section className="modal-panel"><div className="panel-heading"><div><span className="eyebrow">Acción administrativa</span><h2>Confirmar recuperación</h2></div><ShieldAlert size={23} /></div><p>{selectedBackup ? 'Se programará la restauración completa del host. ReactUI puede desconectarse mientras reinician los servicios.' : 'La topología actual será sustituida por un estado previamente verificado.'}</p><code className="confirmation-code">{expected}</code><label>Confirmación exacta<input autoFocus value={confirmation} onChange={event => setConfirmation(event.target.value)} /></label><div className="integrity-note"><CheckCircle2 size={16} />La API validará checksum e integridad antes de modificar el sistema.</div><div className="button-row"><button className="secondary-button" onClick={() => { setSelected(null); setSelectedBackup(null); setLastKnownGood(false); setConfirmation('') }}>Cancelar</button><button className="primary-button" disabled={busy || confirmation !== expected} onClick={() => void restore()}><ArchiveRestore size={16} />Restaurar</button></div></section></div>}
  </section>
}

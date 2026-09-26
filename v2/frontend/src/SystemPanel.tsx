import { useState } from 'react'
import { CircleDollarSign, Download, ExternalLink, GitBranch, Heart, RefreshCw } from 'lucide-react'
import { api } from './api'
import type { ReleaseStatus } from './types'

type Props = { isAdmin: boolean; onNotice: (message: string) => void }

export function SystemPanel({ isAdmin, onNotice }: Props) {
  const [status, setStatus] = useState<ReleaseStatus | null>(null)
  const [selected, setSelected] = useState('')
  const [confirmation, setConfirmation] = useState('')
  const [busy, setBusy] = useState(false)
  const check = async () => {
    setBusy(true)
    try { const result = await api.releases(); setStatus(result); setSelected(result.latest ?? ''); onNotice(result.update_available ? `Nueva versión disponible: ${result.latest}` : 'La instalación está al día.') }
    catch (error) { onNotice(error instanceof Error ? error.message : 'No se pudo consultar GitHub.') }
    finally { setBusy(false) }
  }
  const update = async () => {
    if (!selected) return
    setBusy(true)
    try { const result = await api.updateSystem(selected, confirmation); onNotice(`Actualización programada en ${result.unit}. ReactUI se reiniciará durante el proceso.`); setConfirmation('') }
    catch (error) { onNotice(error instanceof Error ? error.message : 'No se pudo programar la actualización.') }
    finally { setBusy(false) }
  }
  return <section className="workspace system-grid">
    <section className="panel"><div className="panel-heading"><div><span className="eyebrow">Canal oficial</span><h1>Actualizaciones</h1></div><GitBranch size={23} /></div><p>Consulta las etiquetas publicadas en GitHub. La actualización crea un respaldo y utiliza el instalador transaccional del host.</p><button className="secondary-button" disabled={!isAdmin || busy} onClick={() => void check()}><RefreshCw size={16} />Buscar versiones</button>{status && <div className="release-status"><dl><div><dt>Instalada</dt><dd>{status.current}</dd></div><div><dt>Última pública</dt><dd>{status.latest || '-'}</dd></div><div><dt>Última estable</dt><dd>{status.latest_stable || '-'}</dd></div></dl><label>Versión a instalar<select value={selected} onChange={event => { setSelected(event.target.value); setConfirmation('') }}>{status.releases.map(release => <option key={release}>{release}</option>)}</select></label><code className="confirmation-code">ACTUALIZAR {selected}</code><label>Confirmación<input value={confirmation} onChange={event => setConfirmation(event.target.value)} /></label><button className="primary-button" disabled={busy || confirmation !== `ACTUALIZAR ${selected}`} onClick={() => void update()}><Download size={16} />Aplicar actualización</button></div>}</section>
    <section className="panel"><div className="panel-heading"><div><span className="eyebrow">Proyecto</span><h2>Créditos</h2></div><Heart size={22} /></div><div className="credits"><strong>Emilio Abundis</strong><a href="mailto:decameru@outlook.com">decameru@outlook.com</a><a href="https://github.com/Ryuz-crypto/WAN_SIM" target="_blank" rel="noreferrer">Repositorio oficial <ExternalLink size={14} /></a></div><div className="donation"><CircleDollarSign size={24} /><div><strong>Apoya WAN_SIM</strong><p>Para patrocinios o donaciones, contacta al autor indicando “Donación WAN_SIM”.</p></div><a className="secondary-button compact" href="mailto:decameru@outlook.com?subject=Donaci%C3%B3n%20WAN_SIM">Contactar</a></div></section>
  </section>
}

import { useEffect, useState } from 'react'
import { CheckCircle2, CircleAlert, Download, RefreshCw, Stethoscope } from 'lucide-react'
import { api } from './api'
import type { DoctorReport, UserRole } from './types'

type Props = { role: UserRole; onNotice: (message: string) => void; onChanged: () => void }

export function DoctorPanel({ role, onNotice, onChanged }: Props) {
  const [report, setReport] = useState<DoctorReport | null>(null)
  const [busyService, setBusyService] = useState('')
  const refresh = async () => {
    try { setReport(await api.doctor()) }
    catch (error) { onNotice(error instanceof Error ? error.message : 'No se pudo ejecutar Doctor.') }
  }
  useEffect(() => { void refresh() }, [])
  const restart = async (service: string) => {
    setBusyService(service)
    try { await api.restart(service); onNotice(`${service} recibió la orden de reinicio.`); await refresh(); onChanged() }
    catch (error) { onNotice(error instanceof Error ? error.message : `No se pudo reiniciar ${service}.`) }
    finally { setBusyService('') }
  }
  const download = () => {
    if (!report) return
    const url = URL.createObjectURL(new Blob([JSON.stringify(report, null, 2)], { type: 'application/json' }))
    const link = document.createElement('a'); link.href = url; link.download = `wansim-doctor-${Date.now()}.json`; link.click(); URL.revokeObjectURL(url)
  }
  return <section className="workspace doctor-layout">
    <section className="metric-strip doctor-summary"><div><span>Correctos</span><strong>{report?.summary.ok ?? 0}</strong></div><div><span>Advertencias</span><strong>{report?.summary.warning ?? 0}</strong></div><div><span>Errores</span><strong>{report?.summary.error ?? 0}</strong></div><div><span>Estado</span><strong className={report?.status === 'error' ? 'bad' : report?.status === 'warning' ? 'warn' : 'good'}>{report?.status ?? '...'}</strong></div></section>
    <section className="panel full"><div className="panel-heading"><div><span className="eyebrow">Diagnóstico estructurado</span><h1>Doctor</h1></div><Stethoscope size={23} /></div><div className="button-row"><button className="primary-button" onClick={() => void refresh()}><RefreshCw size={16} />Ejecutar nuevamente</button><button className="secondary-button" disabled={!report} onClick={download}><Download size={16} />Exportar soporte</button></div>
      <div className="doctor-list">{report?.checks.map((item, index) => <article key={`${item.component}-${item.title}-${index}`} className={`doctor-check ${item.status}`}>{item.status === 'ok' ? <CheckCircle2 size={20} /> : <CircleAlert size={20} />}<div><span>{item.component}</span><strong>{item.title}</strong><p>{item.detail}</p>{item.remediation && item.status !== 'ok' && <small>{item.remediation}</small>}</div>{role === 'admin' && item.restart_service && <button className="secondary-button compact" disabled={busyService === item.restart_service} onClick={() => void restart(item.restart_service)}><RefreshCw size={14} />Reiniciar</button>}</article>) ?? <div className="empty">Ejecutando diagnóstico...</div>}</div>
    </section>
  </section>
}

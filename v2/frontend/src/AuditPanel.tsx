import { useEffect, useState } from 'react'
import { ChevronDown, Clock3, RotateCcw } from 'lucide-react'
import { api } from './api'
import type { AuditEvent, Deployment } from './types'

type Props = { deployments: Deployment[]; canOperate: boolean; busy: boolean; onRollback: (id: string) => void; onNotice: (message: string) => void }

function humanEvent(event: AuditEvent) {
  const detail = event.detail
  const messages: Record<string, string> = {
    'auth.login': 'Inició sesión', 'auth.login_failed': 'Intentó entrar con usuario o contraseña incorrectos', 'auth.logout': 'Cerró sesión',
    'user.create': `Creó el usuario ${String(detail.username ?? event.target)}`, 'user.update': 'Modificó permisos o estado de un usuario',
    'user.delete': `Eliminó el usuario ${String(detail.username ?? event.target)}`, 'user.password_rotate': 'Cambió su contraseña',
    'netem.apply': `Actualizó la degradación de ${event.target}: ${Number(detail.delay_ms ?? 0)} ms de latencia, ${Number(detail.jitter_ms ?? 0)} ms de jitter y ${Number(detail.loss_percent ?? 0)}% de pérdida`,
    'configuration.create': `Guardó la configuración ${String(detail.name ?? event.target)}`, 'deployment.apply': 'Aplicó una configuración de red',
    'deployment.rollback': 'Revirtió un despliegue', 'deployment.confirm': 'Confirmó la conectividad administrativa',
    'recovery.restore': 'Restauró un snapshot de red', 'recovery.last_known_good': 'Recuperó la última configuración funcional',
    'recovery.backup_restore': 'Programó la restauración de un respaldo completo',
    'service.restart': `Reinició ${event.target}`, 'interface.up': `Activó la interfaz ${event.target}`,
    'interface.down': `Desactivó la interfaz ${event.target}`, 'interface.restart': `Reinició la interfaz ${event.target}`,
    'system.update': `Programó la actualización a ${event.target}`,
  }
  return messages[event.action] ?? event.action.replaceAll('.', ' ')
}

export function AuditPanel({ deployments, canOperate, busy, onRollback, onNotice }: Props) {
  const [events, setEvents] = useState<AuditEvent[]>([])
  useEffect(() => { void api.auditEvents().then(setEvents).catch(error => onNotice(error instanceof Error ? error.message : 'No se pudo cargar la auditoría.')) }, [])
  return <section className="workspace audit-layout">
    <section className="panel full"><div className="panel-heading"><div><span className="eyebrow">Auditoría</span><h1>Despliegues</h1></div><Clock3 size={22} /></div><div className="deployment-list">{deployments.length ? deployments.map(item => <details key={item.id}><summary><div><span className={`state ${item.status.toLowerCase()}`}>{item.status}</span><strong>{new Date(item.created_at).toLocaleString('es-MX')}</strong><small>{item.plan.length} acciones · {String(item.result.mode ?? '-')}</small></div><ChevronDown size={18} /></summary><div className="deployment-detail"><p>{item.status === 'APPLIED' ? 'La configuración se aplicó correctamente.' : item.status === 'ROLLED_BACK' ? 'Los cambios se revirtieron y se recuperó el estado anterior.' : `El despliegue terminó como ${item.status}.`}</p><ul>{item.plan.map(action => <li key={action.id}>{action.description}</li>)}</ul><button className="secondary-button compact" disabled={!canOperate || !['APPLIED', 'AWAITING_CONFIRMATION'].includes(item.status) || busy} onClick={() => onRollback(item.id)}><RotateCcw size={15} />Rollback</button></div></details>) : <p className="empty">Sin despliegues registrados</p>}</div></section>
    <section className="panel full"><div className="panel-heading"><div><span className="eyebrow">Actividad humana</span><h2>Eventos del sistema</h2></div></div><div className="event-list">{events.map(event => <details key={event.id}><summary><div><strong>{humanEvent(event)}</strong><span>{event.actor} · {new Date(event.created_at).toLocaleString('es-MX')}</span></div><ChevronDown size={17} /></summary><div><code>{event.action}</code><p>Destino: {event.target}</p>{Object.keys(event.detail).length > 0 && <pre>{JSON.stringify(event.detail, null, 2)}</pre>}</div></details>)}</div></section>
  </section>
}

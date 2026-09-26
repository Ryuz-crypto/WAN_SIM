import { Edit3, Network } from 'lucide-react'
import type { Configuration } from './types'

type Props = { configurations: Configuration[]; onEdit: (configuration: Configuration) => void }

function summary(item: Configuration) {
  if (item.config.topology === 'bridge') {
    return (item.config.bridge?.pairs ?? []).map((pair, index) => `Bridge ${index + 1}: ${pair.input} ↔ ${pair.output}`)
  }
  return (item.config.l3?.links ?? []).map((link, index) => {
    const lan = link.lanMode === 'access' ? 'acceso sin etiqueta' : `${link.vlans} VLAN desde ${link.startVlan}`
    const wan = link.wanMode === 'dhcp' ? 'WAN por DHCP' : `${link.wanCidr} vía ${link.wanGateway}`
    return `Enlace ${index + 1}: ${link.lan} (${lan}) → ${link.wan} (${wan})`
  })
}

export function CurrentConfiguration({ configurations, onEdit }: Props) {
  const active = configurations.find(item => item.state === 'ACTIVE')
  return <section className="workspace">
    <section className="panel full"><div className="panel-heading"><div><span className="eyebrow">Estado efectivo</span><h1>Configuración actual</h1></div><Network size={23} /></div>
      {active ? <div className="current-config"><div><span className="state active">Activa</span><h2>{active.name}</h2><p>{active.config.topology === 'nat' ? 'L3 / NAT' : 'Bridge L2'} · actualizada {new Date(active.updated_at).toLocaleString('es-MX')}</p></div><div className="config-lines">{summary(active).map(line => <p key={line}>{line}</p>)}</div><button className="primary-button" onClick={() => onEdit(active)}><Edit3 size={16} />Modificar esta configuración</button></div> : <p className="empty">Todavía no existe una configuración activa.</p>}
    </section>
    <section className="panel full"><div className="panel-heading"><div><span className="eyebrow">Historial reutilizable</span><h2>Configuraciones guardadas</h2></div></div><div className="configuration-list">{configurations.map(item => <article key={item.id}><div><span className={`state ${item.state.toLowerCase()}`}>{item.state}</span><strong>{item.name}</strong><small>{item.config.topology === 'nat' ? 'L3 / NAT' : 'Bridge L2'} · {new Date(item.updated_at).toLocaleString('es-MX')}</small></div><div className="config-lines">{summary(item).map(line => <p key={line}>{line}</p>)}</div><button className="secondary-button compact" onClick={() => onEdit(item)}><Edit3 size={15} />Usar como borrador</button></article>)}</div></section>
  </section>
}

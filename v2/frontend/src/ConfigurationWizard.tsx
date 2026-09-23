import { useState, type Dispatch, type SetStateAction } from 'react'
import {
  AlertTriangle, Cable, CheckCircle2, ChevronLeft, ChevronRight, GitCompareArrows, Network,
  Play, RefreshCw, RotateCcw, Save, ShieldAlert, WandSparkles, X,
} from 'lucide-react'
import type { Config, Configuration, L3Link, NetworkInterface, PlanReview } from './types'

type Props = {
  name: string
  config: Config
  interfaces: NetworkInterface[]
  configuration: Configuration | null
  review: PlanReview | null
  busy: boolean
  setName: (value: string) => void
  setConfig: Dispatch<SetStateAction<Config>>
  onReview: () => void
  onDeploy: () => void
  onReset: () => void
}

const emptyLink = (): L3Link => ({ wan: '', lan: '', lanMode: 'vlan', vlans: 1, startVlan: 100, baseOctet: 10, wanMode: 'dhcp', wanCidr: '', wanGateway: '' })
const steps = ['Objetivo', 'Interfaces', 'Red', 'Revisión']

function interfaceLabel(item: NetworkInterface) {
  const address = item.ips[0] ?? 'sin IPv4'
  return `${item.name} · ${address}${item.is_management ? ' · administración' : ''}`
}

function InterfaceSelect({ value, interfaces, onChange }: { value: string; interfaces: NetworkInterface[]; onChange: (value: string) => void }) {
  return <select value={value} onChange={event => onChange(event.target.value)}>
    <option value="">Seleccionar interfaz</option>
    {interfaces.map(item => <option key={item.name} value={item.name}>{interfaceLabel(item)}</option>)}
  </select>
}

function Diagram({ config }: { config: Config }) {
  if (config.topology === 'bridge') return <div className="diagram">{config.bridge.pairs.map((pair, index) => <div className="flow" key={index}><span>{pair.input || 'Entrada'}</span><i /><b>Bridge {index + 1}</b><i /><span>{pair.output || 'Salida'}</span></div>)}</div>
  return <div className="diagram">{config.l3.links.map((link, index) => <div className="flow" key={index}><span>{link.lan || 'LAN'}</span><i /><b>{link.lanMode === 'access' ? 'Acceso' : `VLAN ${link.startVlan}-${link.startVlan + link.vlans - 1}`}</b><i /><span>{link.wan || 'WAN'}</span></div>)}</div>
}

export function ConfigurationWizard(props: Props) {
  const [step, setStep] = useState(0)
  const { config, interfaces, review } = props
  const updateLink = (index: number, patch: Partial<L3Link>) => props.setConfig(value => ({ ...value, l3: { ...value.l3, links: value.l3.links.map((link, position) => position === index ? { ...link, ...patch } : link) } }))
  const updateBridge = (index: number, patch: Partial<Config['bridge']['pairs'][number]>) => props.setConfig(value => ({ ...value, bridge: { pairs: value.bridge.pairs.map((pair, position) => position === index ? { ...pair, ...patch } : pair) } }))
  const recommend = () => {
    const management = interfaces.find(item => item.is_management)
    const available = interfaces.filter(item => item.name !== management?.name)
    if (config.topology === 'nat') {
      const preserveManagement = available.length >= 2
      const wan = preserveManagement ? available[0] : management ?? available[0]
      const lan = preserveManagement ? available[1] : available[0] ?? interfaces.find(item => item.name !== wan?.name)
      props.setConfig(value => ({ ...value, l3: { ...value.l3, links: [{ ...value.l3.links[0], wan: wan?.name ?? '', lan: lan?.name ?? '' }] } }))
    } else {
      props.setConfig(value => ({ ...value, bridge: { pairs: [{ input: available[0]?.name ?? '', output: available[1]?.name ?? '' }] } }))
    }
  }

  const errors = review?.preflight.issues.filter(item => item.severity === 'error').length ?? 0
  const warnings = review?.preflight.issues.filter(item => item.severity === 'warning').length ?? 0

  return <section className="workspace configure-grid wizard-layout">
    <section className="panel form-panel">
      <div className="panel-heading"><div><span className="eyebrow">Asistente de topología</span><h1>{steps[step]}</h1></div><Network size={23} /></div>
      <ol className="wizard-steps">{steps.map((label, index) => <li key={label} className={index === step ? 'current' : index < step ? 'done' : ''}><button onClick={() => setStep(index)}><span>{index < step ? <CheckCircle2 size={16} /> : index + 1}</span>{label}</button></li>)}</ol>

      {step === 0 && <div className="wizard-body">
        <label>Nombre del cambio<input value={props.name} onChange={event => props.setName(event.target.value)} /></label>
        <span className="field-title">Tipo de topología</span>
        <div className="choice-grid">
          <button className={config.topology === 'nat' ? 'selected' : ''} onClick={() => props.setConfig(value => ({ ...value, topology: 'nat' }))}><Network size={20} /><strong>L3 / NAT</strong><span>WAN y LAN con enrutamiento</span></button>
          <button className={config.topology === 'bridge' ? 'selected' : ''} onClick={() => props.setConfig(value => ({ ...value, topology: 'bridge' }))}><Cable size={20} /><strong>Bridge L2</strong><span>Enlace transparente entre puertos</span></button>
        </div>
      </div>}

      {step === 1 && <div className="wizard-body">
        <div className="section-toolbar"><div><strong>{interfaces.length} interfaces detectadas</strong><span>{interfaces.filter(item => item.is_management).map(item => `${item.name} es la ruta principal`).join(', ') || 'Ruta principal no identificada'}</span></div><button className="secondary-button compact" disabled={interfaces.length < 2} onClick={recommend}><WandSparkles size={15} />Usar recomendación</button></div>
        <div className="interface-inventory">{interfaces.map(item => <div key={item.name} className={item.is_management ? 'management' : ''}><div><strong>{item.name}</strong>{item.is_management && <span className="risk-badge"><ShieldAlert size={12} />Administración</span>}</div><span>{item.ips.join(', ') || 'Sin IPv4'} · {item.mac || 'Sin MAC'} · {item.state}</span></div>)}</div>
        {config.topology === 'nat' ? config.l3.links.map((link, index) => <fieldset key={index}><legend>Enlace {index + 1}</legend>{config.l3.links.length > 1 && <button className="remove-button" title={`Eliminar enlace ${index + 1}`} onClick={() => props.setConfig(value => ({ ...value, l3: { ...value.l3, links: value.l3.links.filter((_, position) => position !== index) } }))}><X size={15} /></button>}<div className="field-grid"><label>Salida WAN<InterfaceSelect value={link.wan} interfaces={interfaces} onChange={wan => updateLink(index, { wan })} /></label><label>Puerto LAN<InterfaceSelect value={link.lan} interfaces={interfaces} onChange={lan => updateLink(index, { lan })} /></label></div></fieldset>) : config.bridge.pairs.map((pair, index) => <fieldset key={index}><legend>Bridge {index + 1}</legend>{config.bridge.pairs.length > 1 && <button className="remove-button" title={`Eliminar Bridge ${index + 1}`} onClick={() => props.setConfig(value => ({ ...value, bridge: { pairs: value.bridge.pairs.filter((_, position) => position !== index) } }))}><X size={15} /></button>}<div className="field-grid"><label>Entrada<InterfaceSelect value={pair.input} interfaces={interfaces} onChange={input => updateBridge(index, { input })} /></label><label>Salida<InterfaceSelect value={pair.output} interfaces={interfaces} onChange={output => updateBridge(index, { output })} /></label></div></fieldset>)}
        {config.topology === 'nat' ? <button className="secondary-button" disabled={config.l3.links.length >= 2} onClick={() => props.setConfig(value => ({ ...value, l3: { ...value.l3, links: [...value.l3.links, { ...emptyLink(), startVlan: 200, baseOctet: 20 }] } }))}><Cable size={16} />Agregar enlace</button> : <button className="secondary-button" disabled={config.bridge.pairs.length >= 3} onClick={() => props.setConfig(value => ({ ...value, bridge: { pairs: [...value.bridge.pairs, { input: '', output: '' }] } }))}><Cable size={16} />Agregar Bridge</button>}
      </div>}

      {step === 2 && <div className="wizard-body">
        {config.topology === 'nat' ? <>
          <div className="segmented"><button className={config.dhcpEnabled ? 'selected' : ''} onClick={() => props.setConfig(value => ({ ...value, dhcpEnabled: true }))}>DHCP LAN activo</button><button className={!config.dhcpEnabled ? 'selected' : ''} onClick={() => props.setConfig(value => ({ ...value, dhcpEnabled: false }))}>DHCP LAN inactivo</button></div>
          <label>Familia de subred LAN<select value={config.l3.segment} onChange={event => props.setConfig(value => ({ ...value, l3: { ...value.l3, segment: event.target.value as Config['l3']['segment'] } }))}><option value="10.254">10.254.X.0/24</option><option value="172.16">172.16.X.0/24</option><option value="192.168">192.168.X.0/24</option></select></label>
          {config.l3.links.map((link, index) => <fieldset key={index}><legend>{link.lan || 'LAN'} → {link.wan || 'WAN'}</legend><div className="field-grid"><label>Modo del puerto LAN<select value={link.lanMode} onChange={event => updateLink(index, { lanMode: event.target.value as L3Link['lanMode'] })}><option value="vlan">VLAN etiquetada</option><option value="access">Acceso sin etiqueta</option></select></label><label>Dirección WAN<select value={link.wanMode} onChange={event => updateLink(index, { wanMode: event.target.value as L3Link['wanMode'] })}><option value="dhcp">Automática por DHCP</option><option value="manual">IP manual</option></select></label></div>{link.wanMode === 'manual' && <div className="field-grid"><label>IP WAN con CIDR<input placeholder="192.168.1.2/24" value={link.wanCidr} onChange={event => updateLink(index, { wanCidr: event.target.value })} /></label><label>Gateway WAN<input placeholder="192.168.1.1" value={link.wanGateway} onChange={event => updateLink(index, { wanGateway: event.target.value })} /></label></div>}<div className="field-grid">{link.lanMode === 'vlan' && <><label>Cantidad de VLANs<input type="number" min="1" max="254" value={link.vlans} onChange={event => updateLink(index, { vlans: Number(event.target.value) })} /></label><label>Primera VLAN<input type="number" min="1" max="4094" value={link.startVlan} onChange={event => updateLink(index, { startVlan: Number(event.target.value) })} /></label></>}<label>Tercer octeto inicial<input type="number" min="1" max="254" value={link.baseOctet} onChange={event => updateLink(index, { baseOctet: Number(event.target.value) })} /></label></div></fieldset>)}
        </> : <div className="bridge-summary"><Cable size={28} /><strong>Bridge L2 transparente</strong><span>{config.bridge.pairs.length} par(es), sin direccionamiento ni DHCP administrado.</span></div>}
      </div>}

      {step === 3 && <div className="wizard-body">
        <Diagram config={config} />
        <div className="button-row"><button className="primary-button" disabled={props.busy} onClick={props.onReview}><RefreshCw size={17} />Revisar cambio</button><button className="secondary-button" onClick={props.onReset}><RotateCcw size={17} />Restablecer</button></div>
        {review && <>
          <div className="preflight-summary"><span className={errors ? 'bad' : 'good'}>{errors} errores</span><span className={warnings ? 'warn' : 'good'}>{warnings} advertencias</span><span>{review.actions.length} acciones</span></div>
          <div className="issue-list">{review.preflight.issues.map((issue, index) => <div key={`${issue.code}-${index}`} className={`issue ${issue.severity}`}>{issue.severity === 'error' ? <X size={17} /> : issue.severity === 'warning' ? <AlertTriangle size={17} /> : <CheckCircle2 size={17} />}<div><strong>{issue.title}</strong><span>{issue.detail}</span></div></div>)}</div>
          <div className="comparison"><div><span>Actual</span>{review.comparison.current.map(item => <p key={item}>{item}</p>)}</div><div><span>Propuesta</span>{review.comparison.proposed.map(item => <p key={item}>{item}</p>)}</div></div>
          <div className="change-list"><strong>Cambios</strong>{review.comparison.changes.map(item => <p key={item}>{item}</p>)}</div>
          <details className="technical-plan"><summary><Save size={15} />Plan técnico ({review.actions.length})</summary><ol className="action-list">{review.actions.map(action => <li key={action.id}><span className={`phase ${action.phase}`}>{action.phase}</span><div><strong>{action.description}</strong><code>{action.command.join(' ')}</code></div></li>)}</ol></details>
          <div className="button-row"><button className="primary-button" disabled={!props.configuration || !review.preflight.can_apply || props.busy} onClick={props.onDeploy}><Play size={17} />Desplegar cambio</button></div>
        </>}
      </div>}

      <div className="wizard-navigation"><button className="secondary-button" disabled={step === 0} onClick={() => setStep(value => value - 1)}><ChevronLeft size={17} />Anterior</button><span>{step + 1} de {steps.length}</span><button className="primary-button" disabled={step === steps.length - 1} onClick={() => setStep(value => value + 1)}>Siguiente<ChevronRight size={17} /></button></div>
    </section>

    <section className="right-stack">
      <section className="panel topology-preview"><div className="panel-heading"><div><span className="eyebrow">Vista conceptual</span><h2>Topología propuesta</h2></div><GitCompareArrows size={22} /></div><Diagram config={config} /></section>
      <section className="panel selection-summary"><div className="panel-heading"><div><span className="eyebrow">Selección</span><h2>Resumen</h2></div><CheckCircle2 size={22} /></div><dl><div><dt>Modo</dt><dd>{config.topology === 'nat' ? 'L3 / NAT' : 'Bridge L2'}</dd></div><div><dt>Pares</dt><dd>{config.topology === 'nat' ? config.l3.links.length : config.bridge.pairs.length}</dd></div><div><dt>DHCP LAN</dt><dd>{config.topology === 'nat' && config.dhcpEnabled ? 'Activo' : 'Inactivo'}</dd></div><div><dt>Ruta principal</dt><dd>{interfaces.filter(item => item.is_management).map(item => item.name).join(', ') || 'No detectada'}</dd></div></dl></section>
    </section>
  </section>
}

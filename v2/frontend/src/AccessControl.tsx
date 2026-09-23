import { useEffect, useState } from 'react'
import { KeyRound, Plus, RefreshCw, ShieldCheck, UserCog } from 'lucide-react'
import { api } from './api'
import type { AuditEvent, Identity, User, UserRole } from './types'

type Props = { identity: Identity; onNotice: (message: string) => void; onLogout: () => void }

export function AccessControl({ identity, onNotice, onLogout }: Props) {
  const [users, setUsers] = useState<User[]>([])
  const [events, setEvents] = useState<AuditEvent[]>([])
  const [form, setForm] = useState({ username: '', password: '', role: 'viewer' as UserRole })
  const [passwords, setPasswords] = useState({ current: '', next: '' })
  const refresh = async () => {
    try {
      const [nextEvents, nextUsers] = await Promise.all([api.auditEvents(), identity.role === 'admin' ? api.users() : Promise.resolve([])])
      setEvents(nextEvents); setUsers(nextUsers)
    } catch (error) { onNotice(error instanceof Error ? error.message : 'No se pudo consultar control de acceso.') }
  }
  useEffect(() => { void refresh() }, [identity.role])
  const create = async () => {
    try { await api.createUser(form); setForm({ username: '', password: '', role: 'viewer' }); onNotice('Usuario creado.'); await refresh() }
    catch (error) { onNotice(error instanceof Error ? error.message : 'No se pudo crear el usuario.') }
  }
  const update = async (user: User, patch: { role?: UserRole; enabled?: boolean }) => {
    try { await api.updateUser(user.id, patch); onNotice('Usuario actualizado.'); await refresh() }
    catch (error) { onNotice(error instanceof Error ? error.message : 'No se pudo actualizar el usuario.') }
  }
  const rotate = async () => {
    try { await api.changePassword(passwords.current, passwords.next); onNotice('Contraseña actualizada. Inicia sesión nuevamente.'); onLogout() }
    catch (error) { onNotice(error instanceof Error ? error.message : 'No se pudo actualizar la contraseña.') }
  }
  return <section className="workspace access-grid">
    {identity.role === 'admin' && <><section className="panel"><div className="panel-heading"><div><span className="eyebrow">RBAC</span><h1>Nuevo usuario</h1></div><UserCog size={23} /></div><label>Usuario<input value={form.username} onChange={event => setForm(value => ({ ...value, username: event.target.value }))} /></label><label>Contraseña inicial<input type="password" autoComplete="new-password" value={form.password} onChange={event => setForm(value => ({ ...value, password: event.target.value }))} /></label><label>Rol<select value={form.role} onChange={event => setForm(value => ({ ...value, role: event.target.value as UserRole }))}><option value="viewer">Viewer</option><option value="operator">Operator</option><option value="admin">Admin</option></select></label><div className="button-row"><button className="primary-button" disabled={!form.username || form.password.length < 12} onClick={() => void create()}><Plus size={16} />Crear usuario</button></div></section>
    <section className="panel"><div className="panel-heading"><div><span className="eyebrow">Sesiones</span><h2>Usuarios</h2></div><ShieldCheck size={22} /></div><div className="user-list">{users.map(user => <div key={user.id}><div><strong>{user.username}</strong><span>{user.enabled ? 'Habilitado' : 'Deshabilitado'}</span></div><select aria-label={`Rol de ${user.username}`} value={user.role} onChange={event => void update(user, { role: event.target.value as UserRole })}><option value="viewer">viewer</option><option value="operator">operator</option><option value="admin">admin</option></select><button className="secondary-button compact" onClick={() => void update(user, { enabled: !user.enabled })}>{user.enabled ? 'Deshabilitar' : 'Habilitar'}</button></div>)}</div></section></>}
    {identity.auth === 'session' && <section className="panel"><div className="panel-heading"><div><span className="eyebrow">Credencial personal</span><h2>Cambiar contraseña</h2></div><KeyRound size={22} /></div><label>Contraseña actual<input type="password" autoComplete="current-password" value={passwords.current} onChange={event => setPasswords(value => ({ ...value, current: event.target.value }))} /></label><label>Nueva contraseña<input type="password" autoComplete="new-password" value={passwords.next} onChange={event => setPasswords(value => ({ ...value, next: event.target.value }))} /></label><div className="button-row"><button className="primary-button" disabled={passwords.current.length < 12 || passwords.next.length < 12} onClick={() => void rotate()}><RefreshCw size={16} />Rotar credencial</button></div></section>}
    <section className="panel full"><div className="panel-heading"><div><span className="eyebrow">Trazabilidad</span><h2>Auditoría de acciones</h2></div><ShieldCheck size={22} /></div><div className="table-wrap"><table><thead><tr><th>Fecha</th><th>Actor</th><th>Rol</th><th>Acción</th><th>Destino</th></tr></thead><tbody>{events.length ? events.map(event => <tr key={event.id}><td>{new Date(event.created_at).toLocaleString('es-MX')}</td><td>{event.actor}</td><td>{event.role}</td><td><code>{event.action}</code></td><td>{event.target}</td></tr>) : <tr><td className="empty" colSpan={5}>Sin eventos de auditoría.</td></tr>}</tbody></table></div></section>
  </section>
}

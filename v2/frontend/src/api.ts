import type {
  AuditEvent, Config, Configuration, Deployment, DoctorReport, Identity, Overview, PlanReview,
  HostBackup, RecoverySnapshot, TelegramBot, TelegramBotCreated, TelegramPermission, User, UserRole,
} from './types'

let operatorKey = ''
let sessionToken = ''

export function configureApiKey(value: string) {
  operatorKey = value
  if (value) sessionToken = ''
}

export function configureSessionToken(value: string) {
  sessionToken = value
  if (value) operatorKey = ''
}

async function request<T>(url: string, init?: RequestInit): Promise<T> {
  const response = await fetch(url, { headers: {
    'Content-Type': 'application/json',
    ...(operatorKey ? { 'X-WAN-SIM-API-Key': operatorKey } : {}),
    ...(sessionToken ? { Authorization: `Bearer ${sessionToken}` } : {}),
  }, ...init })
  if (!response.ok) {
    const payload = await response.json().catch(() => ({})) as { detail?: string | Array<{ msg?: string; loc?: Array<string | number> }> }
    const detail = Array.isArray(payload.detail)
      ? payload.detail.map(item => `${item.loc?.slice(1).join('.') ?? 'configuración'}: ${item.msg ?? 'valor inválido'}`).join(' · ')
      : payload.detail
    throw new Error(detail ?? `HTTP ${response.status}`)
  }
  return response.json() as Promise<T>
}

export const api = {
  health: () => request<{ ok: boolean; version: string; execution_mode: string; users_configured: boolean }>('/health'),
  login: (username: string, password: string) => request<{ token: string; expires_at: string; user: User }>('/api/v2/auth/login', { method: 'POST', body: JSON.stringify({ username, password }) }),
  logout: () => request<{ ok: boolean }>('/api/v2/auth/logout', { method: 'POST' }),
  me: () => request<Identity>('/api/v2/auth/me'),
  users: () => request<User[]>('/api/v2/auth/users'),
  createUser: (payload: { username: string; password: string; role: UserRole }) => request<User>('/api/v2/auth/users', { method: 'POST', body: JSON.stringify(payload) }),
  updateUser: (id: string, payload: { role?: UserRole; enabled?: boolean; password?: string }) => request<User>(`/api/v2/auth/users/${id}`, { method: 'PATCH', body: JSON.stringify(payload) }),
  changePassword: (currentPassword: string, newPassword: string) => request<{ ok: boolean; reauthenticate: boolean }>('/api/v2/auth/password', { method: 'POST', body: JSON.stringify({ currentPassword, newPassword }) }),
  overview: () => request<Overview>('/api/v2/operations/overview'),
  doctor: () => request<DoctorReport>('/api/v2/operations/doctor'),
  createConfig: (name: string, config: Config) => request<Configuration>('/api/v2/configurations', { method: 'POST', body: JSON.stringify({ name, config }) }),
  plan: (id: string) => request<PlanReview>(`/api/v2/configurations/${id}/plan`, { method: 'POST' }),
  deploy: (id: string, apply: boolean, confirmation?: string, managementConfirmation?: string) => request<Deployment>(`/api/v2/configurations/${id}/deploy`, { method: 'POST', body: JSON.stringify({ apply, confirmation, managementConfirmation }) }),
  confirmDeployment: (id: string) => request<Deployment>(`/api/v2/deployments/${id}/confirm`, { method: 'POST' }),
  deployments: () => request<Deployment[]>('/api/v2/deployments'),
  rollback: (id: string) => request<Deployment>(`/api/v2/deployments/${id}/rollback`, { method: 'POST' }),
  snapshots: () => request<RecoverySnapshot[]>('/api/v2/recovery/snapshots'),
  backups: () => request<HostBackup[]>('/api/v2/recovery/backups'),
  restoreSnapshot: (id: string, confirmation: string) => request<Deployment>(`/api/v2/recovery/snapshots/${id}/restore`, { method: 'POST', body: JSON.stringify({ confirmation }) }),
  restoreBackup: (name: string, confirmation: string) => request<{ ok: boolean; unit: string; backup: string }>(`/api/v2/recovery/backups/${encodeURIComponent(name)}/restore`, { method: 'POST', body: JSON.stringify({ confirmation }) }),
  restoreLastKnownGood: (confirmation: string) => request<Deployment>('/api/v2/recovery/last-known-good', { method: 'POST', body: JSON.stringify({ confirmation }) }),
  auditEvents: () => request<AuditEvent[]>('/api/v2/audit/events'),
  netem: (payload: { interface: string; delayMs: number; jitterMs: number; lossPercent: number }) => request('/api/v2/operations/netem', { method: 'POST', body: JSON.stringify(payload) }),
  restart: (service: string) => request('/api/v2/operations/services/restart', { method: 'POST', body: JSON.stringify({ service }) }),
  bots: () => request<TelegramBot[]>('/api/v2/telegram/bots'),
  createBot: (payload: { name: string; token: string; allowed_chat_ids: number[]; permission: TelegramPermission }) => request<TelegramBotCreated>('/api/v2/telegram/bots', { method: 'POST', body: JSON.stringify(payload) }),
  updateBot: (id: string, payload: { enabled?: boolean; permission?: TelegramPermission; allowed_chat_ids?: number[] }) => request<TelegramBot>(`/api/v2/telegram/bots/${id}`, { method: 'PATCH', body: JSON.stringify(payload) }),
  testBot: (id: string, chatId: number) => request(`/api/v2/telegram/bots/${id}/test`, { method: 'POST', body: JSON.stringify({ chat_id: chatId }) }),
  syncBot: (id: string, publicBaseUrl: string) => request<{ ok: boolean; webhook_url: string }>(`/api/v2/telegram/bots/${id}/sync`, { method: 'POST', body: JSON.stringify({ publicBaseUrl }) }),
}

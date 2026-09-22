import type { Config, Configuration, Deployment, Overview, TelegramBot, TelegramBotCreated, TelegramPermission } from './types'

async function request<T>(url: string, init?: RequestInit): Promise<T> {
  const response = await fetch(url, { headers: { 'Content-Type': 'application/json' }, ...init })
  if (!response.ok) {
    const payload = await response.json().catch(() => ({})) as { detail?: string }
    throw new Error(payload.detail ?? `HTTP ${response.status}`)
  }
  return response.json() as Promise<T>
}

export const api = {
  health: () => request<{ ok: boolean; version: string; execution_mode: string }>('/health'),
  overview: () => request<Overview>('/api/v2/operations/overview'),
  createConfig: (name: string, config: Config) => request<Configuration>('/api/v2/configurations', { method: 'POST', body: JSON.stringify({ name, config }) }),
  plan: (id: string) => request<{ configuration_id: string; execution_mode: string; actions: Deployment['plan'] }>(`/api/v2/configurations/${id}/plan`, { method: 'POST' }),
  deploy: (id: string, apply: boolean) => request<Deployment>(`/api/v2/configurations/${id}/deploy`, { method: 'POST', body: JSON.stringify({ apply }) }),
  deployments: () => request<Deployment[]>('/api/v2/deployments'),
  rollback: (id: string) => request<Deployment>(`/api/v2/deployments/${id}/rollback`, { method: 'POST' }),
  netem: (payload: { interface: string; delayMs: number; jitterMs: number; lossPercent: number }) => request('/api/v2/operations/netem', { method: 'POST', body: JSON.stringify(payload) }),
  restart: (service: string) => request('/api/v2/operations/services/restart', { method: 'POST', body: JSON.stringify({ service }) }),
  bots: () => request<TelegramBot[]>('/api/v2/telegram/bots'),
  createBot: (payload: { name: string; token: string; allowed_chat_ids: number[]; permission: TelegramPermission }) => request<TelegramBotCreated>('/api/v2/telegram/bots', { method: 'POST', body: JSON.stringify(payload) }),
  updateBot: (id: string, payload: { enabled?: boolean; permission?: TelegramPermission; allowed_chat_ids?: number[] }) => request<TelegramBot>(`/api/v2/telegram/bots/${id}`, { method: 'PATCH', body: JSON.stringify(payload) }),
  testBot: (id: string, chatId: number) => request(`/api/v2/telegram/bots/${id}/test`, { method: 'POST', body: JSON.stringify({ chat_id: chatId }) }),
  syncBot: (id: string, publicBaseUrl: string) => request<{ ok: boolean; webhook_url: string }>(`/api/v2/telegram/bots/${id}/sync`, { method: 'POST', body: JSON.stringify({ publicBaseUrl }) }),
}

export type Topology = 'nat' | 'bridge'
export type LanMode = 'vlan' | 'access'

export type L3Link = {
  wan: string; lan: string; lanMode: LanMode; vlans: number; startVlan: number; baseOctet: number
  wanMode: 'dhcp' | 'manual'; wanCidr?: string; wanGateway?: string
}
export type Config = {
  topology: Topology; dhcpEnabled: boolean
  l3: { segment: '10.254' | '172.16' | '192.168'; links: L3Link[] }
  bridge: { pairs: { input: string; output: string }[] }
}
export type Configuration = { id: string; name: string; state: string; config: Config; created_at: string; updated_at: string }
export type Action = { id: string; phase: string; description: string; command: string[]; undo?: string[] }
export type Deployment = { id: string; configuration_id: string; status: string; plan: Action[]; result: Record<string, unknown>; created_at: string; updated_at: string }
export type NetworkInterface = { name: string; mac: string; state: string; ips: string[]; rx_bytes: number; tx_bytes: number; is_management?: boolean }
export type Service = { name: string; active: string; enabled: string }
export type Lease = { ip: string; mac: string; host: string; state: string }
export type Overview = { execution_mode: string; interfaces: NetworkInterface[]; services: Service[]; leases: Lease[]; active_configuration: Configuration | null; deployments: Deployment[] }
export type TelegramPermission = 'read' | 'operate' | 'admin'
export type TelegramBot = { id: string; name: string; token_hint: string; allowed_chat_ids: number[]; permission: TelegramPermission; enabled: boolean; webhook_url?: string; created_at: string; updated_at: string }
export type TelegramBotCreated = { bot: TelegramBot; webhook_secret: string }
export type PreflightIssue = { severity: 'error' | 'warning' | 'recommendation'; code: string; title: string; detail: string; interfaces: string[] }
export type PreflightReport = {
  ok: boolean; can_apply: boolean; mode: string; missing_interfaces: string[]; selected_interfaces: string[]
  management_interfaces: string[]; protected_interfaces: string[]; requires_management_confirmation: boolean
  issues: PreflightIssue[]
}
export type ConfigurationComparison = {
  current_name: string; proposed_name: string; current: string[]; proposed: string[]; changes: string[]
}
export type PlanReview = {
  configuration_id: string; execution_mode: string; actions: Action[]; preflight: PreflightReport
  comparison: ConfigurationComparison; management_confirmation_phrase: string
}
export type UserRole = 'viewer' | 'operator' | 'admin'
export type Identity = { id: string; username: string; role: UserRole; auth: 'session' | 'api_key'; expires_at?: string }
export type User = { id: string; username: string; role: UserRole; enabled: boolean; created_at: string; updated_at: string }
export type RecoverySnapshot = {
  id: string; configuration_id: string; created_at: string; version: string; checksum: string
  integrity: boolean; topology: string
}
export type HostBackup = {
  name: string; size: number; created_at: string; checksum: string; integrity: boolean
}
export type DoctorCheck = {
  component: string; status: 'ok' | 'warning' | 'error'; title: string; detail: string
  remediation: string; restart_service: string
}
export type DoctorReport = {
  generated_at: string; status: 'ok' | 'warning' | 'error'
  summary: { ok: number; warning: number; error: number }; checks: DoctorCheck[]
}
export type AuditEvent = {
  id: string; actor: string; role: string; action: string; target: string
  detail: Record<string, unknown>; created_at: string
}

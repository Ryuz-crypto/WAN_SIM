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
export type NetworkInterface = { name: string; mac: string; state: string; ips: string[]; rx_bytes: number; tx_bytes: number }
export type Service = { name: string; active: string; enabled: string }
export type Lease = { ip: string; mac: string; host: string; state: string }
export type Overview = { execution_mode: string; interfaces: NetworkInterface[]; services: Service[]; leases: Lease[]; active_configuration: Configuration | null; deployments: Deployment[] }
export type TelegramPermission = 'read' | 'operate' | 'admin'
export type TelegramBot = { id: string; name: string; token_hint: string; allowed_chat_ids: number[]; permission: TelegramPermission; enabled: boolean; webhook_url?: string; created_at: string; updated_at: string }
export type TelegramBotCreated = { bot: TelegramBot; webhook_secret: string }

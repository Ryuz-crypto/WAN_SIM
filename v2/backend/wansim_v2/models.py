from __future__ import annotations

from enum import Enum
from ipaddress import IPv4Address, IPv4Network, ip_interface
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator


class Topology(str, Enum):
    NAT = "nat"
    BRIDGE = "bridge"


class LanMode(str, Enum):
    VLAN = "vlan"
    ACCESS = "access"


class WanAddressing(str, Enum):
    DHCP = "dhcp"
    MANUAL = "manual"


class L3Link(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    wan: str = Field(min_length=1, max_length=15, pattern=r"^[a-zA-Z0-9_.-]+$")
    lan: str = Field(min_length=1, max_length=15, pattern=r"^[a-zA-Z0-9_.-]+$")
    lan_mode: LanMode = Field(default=LanMode.VLAN, alias="lanMode")
    vlans: int = Field(default=1, ge=1, le=254)
    start_vlan: int = Field(default=100, ge=1, le=4094, alias="startVlan")
    base_octet: int = Field(default=10, ge=1, le=254, alias="baseOctet")
    wan_mode: WanAddressing = Field(default=WanAddressing.DHCP, alias="wanMode")
    wan_cidr: str | None = Field(default=None, alias="wanCidr")
    wan_gateway: str | None = Field(default=None, alias="wanGateway")

    @model_validator(mode="after")
    def validate_link(self) -> "L3Link":
        if self.wan == self.lan:
            raise ValueError("WAN y LAN no pueden ser la misma interfaz.")
        if self.lan_mode == LanMode.ACCESS:
            self.vlans = 1
        if self.base_octet + self.vlans - 1 > 254:
            raise ValueError("El rango de subredes LAN excede el tercer octeto 254.")
        if self.lan_mode == LanMode.VLAN and self.start_vlan + self.vlans - 1 > 4094:
            raise ValueError("El rango de VLAN excede el ID 4094.")
        if self.wan_mode == WanAddressing.MANUAL:
            if not self.wan_cidr or not self.wan_gateway:
                raise ValueError("WAN manual requiere CIDR y gateway.")
            wan_interface = ip_interface(self.wan_cidr)
            gateway = IPv4Address(self.wan_gateway)
            if gateway not in wan_interface.network:
                raise ValueError("El gateway WAN debe pertenecer a la red indicada por el CIDR.")
        return self


class L3Config(BaseModel):
    segment: Literal["10.254", "172.16", "192.168"] = "10.254"
    links: list[L3Link] = Field(min_length=1, max_length=2)

    @model_validator(mode="after")
    def validate_ranges(self) -> "L3Config":
        used_interfaces: set[str] = set()
        vlan_ranges: list[range] = []
        networks: list[IPv4Network] = []
        for link in self.links:
            for interface in (link.wan, link.lan):
                if interface in used_interfaces:
                    raise ValueError(f"La interfaz {interface} se repite entre pares L3.")
                used_interfaces.add(interface)
            if link.lan_mode == LanMode.VLAN:
                current = range(link.start_vlan, link.start_vlan + link.vlans)
                if any(set(current).intersection(existing) for existing in vlan_ranges):
                    raise ValueError("Los ID de VLAN se solapan entre pares L3.")
                vlan_ranges.append(current)
            for offset in range(link.vlans):
                network = IPv4Network(f"{self.segment}.{link.base_octet + offset}.0/24")
                if network in networks:
                    raise ValueError(f"La subred LAN {network} se repite.")
                networks.append(network)
                if link.wan_mode == WanAddressing.MANUAL and network.overlaps(ip_interface(link.wan_cidr).network):
                    raise ValueError(f"La WAN manual se solapa con la LAN {network}.")
        return self


class BridgePair(BaseModel):
    input: str = Field(min_length=1, max_length=15, pattern=r"^[a-zA-Z0-9_.-]+$")
    output: str = Field(min_length=1, max_length=15, pattern=r"^[a-zA-Z0-9_.-]+$")

    @model_validator(mode="after")
    def different_interfaces(self) -> "BridgePair":
        if self.input == self.output:
            raise ValueError("Entrada y salida Bridge deben ser interfaces diferentes.")
        return self


class BridgeConfig(BaseModel):
    pairs: list[BridgePair] = Field(min_length=1, max_length=3)

    @model_validator(mode="after")
    def unique_interfaces(self) -> "BridgeConfig":
        interfaces = [interface for pair in self.pairs for interface in (pair.input, pair.output)]
        if len(interfaces) != len(set(interfaces)):
            raise ValueError("Una interfaz sólo puede pertenecer a un par Bridge.")
        return self


class TopologyConfig(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    topology: Topology
    l3: L3Config | None = None
    bridge: BridgeConfig | None = None
    dhcp_enabled: bool = Field(default=True, alias="dhcpEnabled")

    @model_validator(mode="before")
    @classmethod
    def discard_inactive_section(cls, data: object) -> object:
        if not isinstance(data, dict):
            return data
        payload = dict(data)
        topology = payload.get("topology")
        if topology in (Topology.NAT, Topology.NAT.value):
            payload.pop("bridge", None)
        elif topology in (Topology.BRIDGE, Topology.BRIDGE.value):
            payload.pop("l3", None)
        return payload

    @model_validator(mode="after")
    def selected_topology(self) -> "TopologyConfig":
        if self.topology == Topology.NAT and self.l3 is None:
            raise ValueError("La topología NAT requiere configuración L3.")
        if self.topology == Topology.BRIDGE and self.bridge is None:
            raise ValueError("La topología Bridge requiere pares L2.")
        return self


class ConfigurationCreate(BaseModel):
    name: str = Field(default="Borrador WAN_SIM", min_length=1, max_length=80)
    config: TopologyConfig


class DeploymentRequest(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    apply: bool = False
    confirmation: str | None = Field(default=None, max_length=80)
    management_confirmation: str | None = Field(default=None, max_length=160, alias="managementConfirmation")


class NetemRequest(BaseModel):
    interface: str = Field(min_length=1, max_length=15, pattern=r"^[a-zA-Z0-9_.-]+$")
    delay_ms: float = Field(default=0, ge=0, le=60_000, alias="delayMs")
    jitter_ms: float = Field(default=0, ge=0, le=60_000, alias="jitterMs")
    loss_percent: float = Field(default=0, ge=0, le=100, alias="lossPercent")


class ServiceRestartRequest(BaseModel):
    service: str = Field(min_length=1, max_length=80, pattern=r"^[a-zA-Z0-9_.@-]+$")


class InterfaceActionRequest(BaseModel):
    interface: str = Field(min_length=1, max_length=15, pattern=r"^[a-zA-Z0-9_.-]+$")
    action: Literal["up", "down", "restart"]


class UpdateApplyRequest(BaseModel):
    version: str = Field(pattern=r"^v[23]\.[0-9]+\.[0-9]+-(stable|prestable|beta\.[0-9]+|rc\.[0-9]+)$")
    confirmation: str = Field(min_length=8, max_length=160)


class TelegramPermission(str, Enum):
    READ = "read"
    OPERATE = "operate"
    ADMIN = "admin"


class UserRole(str, Enum):
    VIEWER = "viewer"
    OPERATOR = "operator"
    ADMIN = "admin"


class LoginRequest(BaseModel):
    username: str = Field(min_length=3, max_length=64, pattern=r"^[a-zA-Z0-9_.-]+$")
    password: str = Field(min_length=12, max_length=256)


class UserCreate(BaseModel):
    username: str = Field(min_length=3, max_length=64, pattern=r"^[a-zA-Z0-9_.-]+$")
    password: str = Field(min_length=12, max_length=256)
    role: UserRole = UserRole.VIEWER


class UserUpdate(BaseModel):
    role: UserRole | None = None
    enabled: bool | None = None
    password: str | None = Field(default=None, min_length=12, max_length=256)


class PasswordChange(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    current_password: str = Field(min_length=12, max_length=256, alias="currentPassword")
    new_password: str = Field(min_length=12, max_length=256, alias="newPassword")


class RecoveryRequest(BaseModel):
    confirmation: str = Field(min_length=8, max_length=160)


class TelegramBotCreate(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    name: str = Field(min_length=1, max_length=80)
    token: str = Field(min_length=20, max_length=200)
    allowed_chat_ids: list[int] = Field(min_length=1, max_length=50, alias="allowedChatIds")
    permission: TelegramPermission = TelegramPermission.READ
    webhook_secret: str | None = Field(default=None, min_length=16, max_length=128, alias="webhookSecret")


class TelegramBotUpdate(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    enabled: bool | None = None
    allowed_chat_ids: list[int] | None = Field(default=None, min_length=1, max_length=50, alias="allowedChatIds")
    permission: TelegramPermission | None = None


class TelegramWebhookSyncRequest(BaseModel):
    public_base_url: str = Field(min_length=12, max_length=240, alias="publicBaseUrl")


class TelegramBotRecord(BaseModel):
    id: str
    name: str
    token_hint: str
    allowed_chat_ids: list[int]
    permission: TelegramPermission
    enabled: bool
    webhook_url: str | None = None
    created_at: str
    updated_at: str


class TelegramBotCreated(BaseModel):
    bot: TelegramBotRecord
    webhook_secret: str


class TelegramDeliveryRequest(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    chat_id: int = Field(alias="chatId")


class ConfigurationRecord(BaseModel):
    id: str
    name: str
    state: str
    config: TopologyConfig
    created_at: str
    updated_at: str


class CommandAction(BaseModel):
    id: str
    phase: Literal["prepare", "apply", "verify", "rollback"]
    description: str
    command: list[str]
    undo: list[str] | None = None


class DeploymentRecord(BaseModel):
    id: str
    configuration_id: str
    status: str
    plan: list[CommandAction]
    result: dict = Field(default_factory=dict)
    created_at: str
    updated_at: str

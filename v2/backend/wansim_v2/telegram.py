from __future__ import annotations

import json
import secrets
import urllib.error
import urllib.request
from dataclasses import dataclass
from hmac import compare_digest
from typing import Any

from .models import TelegramPermission
from .operations import OperationsService
from .repository import ConfigRepository


class TelegramGateway:
    """Small Bot API client kept behind an interface for deterministic tests."""

    def send_message(self, token: str, chat_id: int, text: str, keyboard: list[list[dict[str, str]]] | None = None) -> dict:
        payload: dict[str, Any] = {"chat_id": chat_id, "text": text}
        if keyboard:
            payload["reply_markup"] = {"inline_keyboard": keyboard}
        request = urllib.request.Request(
            f"https://api.telegram.org/bot{token}/sendMessage",
            data=json.dumps(payload).encode(),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=10) as response:
                return {"ok": True, "response": json.loads(response.read().decode())}
        except (OSError, urllib.error.URLError, urllib.error.HTTPError, json.JSONDecodeError) as error:
            return {"ok": False, "error": str(error)}

    def set_webhook(self, token: str, url: str, secret: str) -> dict:
        request = urllib.request.Request(
            f"https://api.telegram.org/bot{token}/setWebhook",
            data=json.dumps({"url": url, "secret_token": secret, "allowed_updates": ["message", "callback_query"]}).encode(),
            headers={"Content-Type": "application/json"}, method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=10) as response:
                payload = json.loads(response.read().decode())
                return {"ok": bool(payload.get("ok")), "response": payload}
        except (OSError, urllib.error.URLError, urllib.error.HTTPError, json.JSONDecodeError) as error:
            return {"ok": False, "error": str(error)}


@dataclass
class TelegramService:
    repository: ConfigRepository
    operations: OperationsService
    gateway: TelegramGateway

    def create(self, name: str, token: str, allowed_chat_ids: list[int], permission: TelegramPermission, webhook_secret: str | None) -> dict:
        secret = webhook_secret or secrets.token_urlsafe(32)
        record = self.repository.create_telegram_bot(name, token, secret, allowed_chat_ids, permission.value)
        return {"bot": record, "webhook_secret": secret}

    def test_delivery(self, bot_id: str, chat_id: int) -> dict:
        bot = self.repository.get_telegram_bot_secret(bot_id)
        if not bot:
            raise LookupError("Bot no encontrado.")
        if chat_id not in bot["allowed_chat_ids"]:
            raise PermissionError("El chat no está autorizado para este bot.")
        return self.gateway.send_message(bot["token"], chat_id, "WAN_SIM 2.0: conexión Telegram validada.")

    def synchronize(self, bot_id: str, public_base_url: str) -> dict:
        bot = self.repository.get_telegram_bot_secret(bot_id)
        if not bot:
            raise LookupError("Bot no encontrado.")
        base = public_base_url.rstrip("/")
        if not base.startswith("https://"):
            raise ValueError("La URL pública de Telegram debe usar HTTPS.")
        webhook_url = f"{base}/api/v2/telegram/bots/{bot_id}/webhook"
        result = self.gateway.set_webhook(bot["token"], webhook_url, bot["webhook_secret"])
        if not result.get("ok"):
            raise RuntimeError(result.get("error", "Telegram rechazó el webhook."))
        self.repository.set_telegram_webhook(bot_id, webhook_url)
        return {"ok": True, "webhook_url": webhook_url}

    def process_update(self, bot_id: str, provided_secret: str | None, update: dict) -> dict:
        bot = self.repository.get_telegram_bot_secret(bot_id)
        if not bot or not bot["enabled"]:
            raise LookupError("Bot no disponible.")
        if not provided_secret or not compare_digest(bot["webhook_secret"], provided_secret):
            raise PermissionError("Secreto de webhook inválido.")

        callback = update.get("callback_query") or {}
        message = callback.get("message") or update.get("message") or {}
        chat_id = ((message.get("chat") or {}).get("id"))
        if not isinstance(chat_id, int) or chat_id not in bot["allowed_chat_ids"]:
            raise PermissionError("Chat no autorizado.")
        data = callback.get("data") or ((message.get("text") or "").strip())
        result = self._dispatch(bot["permission"], data)
        delivery = self.gateway.send_message(bot["token"], chat_id, result["text"], result.get("keyboard"))
        return {"ok": True, "action": result["action"], "delivery": delivery}

    def _dispatch(self, permission: str, data: str) -> dict:
        if data in ("/start", "/status", "status"):
            overview = self.operations.overview()
            interfaces = overview["interfaces"][:4]
            buttons = [[{"text": f"Estado {item['name']}", "callback_data": "status"}] for item in interfaces]
            if permission in (TelegramPermission.OPERATE.value, TelegramPermission.ADMIN.value):
                buttons.extend([[{"text": f"40 ms {item['name']}", "callback_data": f"netem|{item['name']}|40|5|0"}] for item in interfaces])
            return {
                "action": "status",
                "text": f"WAN_SIM: {len(overview['interfaces'])} interfaces, {len(overview['leases'])} leases DHCP, modo {overview['execution_mode']}.",
                "keyboard": buttons,
            }
        if data.startswith("netem|"):
            self._require(permission, TelegramPermission.OPERATE)
            _, interface, delay, jitter, loss = data.split("|", 4)
            result = self.operations.netem(interface, float(delay), float(jitter), float(loss))
            if not result.get("ok"):
                raise RuntimeError(result.get("error", result.get("output", "No se pudo aplicar netem.")))
            return {"action": "netem", "text": f"Perfil aplicado en {interface}: {delay} ms, jitter {jitter} ms, pérdida {loss}%."}
        if data.startswith("restart|"):
            self._require(permission, TelegramPermission.ADMIN)
            service = data.split("|", 1)[1]
            result = self.operations.restart(service)
            if not result.get("ok"):
                raise RuntimeError(result.get("error", result.get("output", "No se pudo reiniciar servicio.")))
            return {"action": "restart", "text": f"Reinicio solicitado para {service}."}
        raise ValueError("Acción Telegram no admitida.")

    @staticmethod
    def _require(permission: str, minimum: TelegramPermission) -> None:
        levels = {TelegramPermission.READ.value: 0, TelegramPermission.OPERATE.value: 1, TelegramPermission.ADMIN.value: 2}
        if levels.get(permission, -1) < levels[minimum.value]:
            raise PermissionError("El bot no tiene permiso para esta operación.")

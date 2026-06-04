# =====================================================================
# 🛡️ AI DEVELOPER GUARDRAIL: REGRESSION PREVENTION DIRECTIVE
# - SYSTEM ATTRIBUTES: AMD-GAIA LOW-LEVEL ENV BOOTSTRAP HOOK.
# - CRITICAL: Perform a strict line-by-line regression audit before editing.
# =====================================================================

import os
import sys
import time
import threading
import importlib.util
from pathlib import Path

# 🔐 INFRASTRUCTURE LOCK: Hard-override system variables to reject upstream update requests
os.environ["GAIA_AUTO_UPDATE"] = "false"
os.environ["GAIA_CHECK_UPDATES"] = "false"
os.environ["GAIA_DISABLE_UPDATE_CHECK"] = "true"

PENDING_TICKETS = {}
TICKET_LOCK = threading.Lock()

try:
    import gaia.ui.sse_handler as sse_mod
    from fastapi import APIRouter, FastAPI
    from pydantic import BaseModel


    class ElectronPayload(BaseModel):
        confirm_id: str
        approved: bool


    OrigConfirmExecution = sse_mod.SSEOutputHandler.confirm_tool_execution
    OrigResolveConfirmation = sse_mod.SSEOutputHandler.resolve_tool_confirmation

    def hotload_user_agents():
        """
        Scans user-space configurations and bridges them straight into GAIA's
        native discovery directories to force formal UI registration hooks.
        """
        # 📂 Secure user-space sources
        base_dir = Path(os.environ.get("SNAP_USER_DATA", "~/snap/amd-gaia/current")) / ".gaia"
        user_src_dir = base_dir / "sideloaded_agents"
        user_src_dir.mkdir(parents=True, exist_ok=True)

        # 🎯 Target native discovery directory
        gaia_native_dir = base_dir / "agents"
        gaia_native_dir.mkdir(parents=True, exist_ok=True)

        for py_file in user_src_dir.glob("*.py"):
            if py_file.name == "__init__.py":
                continue

            agent_name = py_file.stem
            target_agent_folder = gaia_native_dir / agent_name
            target_agent_folder.mkdir(parents=True, exist_ok=True)

            # Formally mirror the agent script as the primary entry point
            target_script = target_agent_folder / "agent.py"
            if not target_script.exists():
                try:
                    # Establish a clean link boundary across the user space
                    target_script.symlink_to(py_file)
                    print(f"🛰️ Dynamic Hotload Matrix: Linked [{agent_name}] to GAIA registry workspace.", flush=True)
                except Exception as link_err:
                    # Fallback to a standard copy operation if symlink creation is constrained
                    import shutil
                    shutil.copystr(str(py_file), str(target_script))

    def patched_confirm_tool_execution(self, tool_name, tool_args, timeout=60):
        if self.background_mode:
            return OrigConfirmExecution(self, tool_name, tool_args, timeout)

        confirm_id = ""
        try:
            frame = sys._getframe(1)
            while frame:
                if 'confirm_id' in frame.f_locals:
                    confirm_id = str(frame.f_locals['confirm_id'])
                    break
                frame = frame.f_back
        except Exception:
            pass

        if not confirm_id:
            import uuid
            confirm_id = str(uuid.uuid4())

        self._confirm_id = confirm_id

        event_signal = threading.Event()
        with TICKET_LOCK:
            PENDING_TICKETS[confirm_id] = {"signal": event_signal, "status": "pending"}

        self._emit({
            "type": "permission_request",
            "tool": tool_name,
            "args": tool_args,
            "confirm_id": confirm_id,
            "timeout_seconds": timeout,
        })

        print(f"🛰️ Sandbox API Matrix: Monitoring memory register for token: [{confirm_id}]", flush=True)

        success = event_signal.wait(timeout=timeout)

        with TICKET_LOCK:
            ticket_data = PENDING_TICKETS.pop(confirm_id, None)

        if success and ticket_data:
            print(f"🛰️ Sandbox API Matrix matched memory signal! continuing task -> [{ticket_data['status']}]",
                  flush=True)
            return ticket_data["status"] == "approved"

        return False


    sse_mod.SSEOutputHandler.confirm_tool_execution = patched_confirm_tool_execution
    print("🛰️ Global Sandbox Concurrency Bootstrap Hooks Refactored to Memory Store.", flush=True)


    # 🛰️ CUSTOM ROUTE INJECTOR
    def inject_custom_api_route(app: FastAPI):
        custom_router = APIRouter(prefix="/api/sandbox")

        @custom_router.post("/resolve")
        async def resolve_sandbox_ticket(payload: ElectronPayload):
            print(f"🛰️ Custom API Route intercepted click event: {payload.confirm_id} -> approved={payload.approved}",
                  flush=True)
            with TICKET_LOCK:
                if payload.confirm_id in PENDING_TICKETS:
                    PENDING_TICKETS[payload.confirm_id]["status"] = "approved" if payload.approved else "denied"
                    PENDING_TICKETS[payload.confirm_id]["signal"].set()
                    return {"status": "success", "message": "Memory address signaled cleanly"}
            return {"status": "error", "message": "Token transaction missing or expired"}

        app.include_router(custom_router)
        print("🛰️ Custom Writable Sandbox API Route forcefully appended to FastAPI ledger matrix.", flush=True)


    import fastapi.applications

    orig_init = fastapi.applications.FastAPI.__init__


    def patched_fastapi_init(self, *args, **kwargs):
        orig_init(self, *args, **kwargs)
        inject_custom_api_route(self)


    fastapi.applications.FastAPI.__init__ = patched_fastapi_init

except Exception as bootstrap_err:
    print(f"⚠️ Sandbox Bootstrap Hook initialization deferred: {str(bootstrap_err)}", flush=True)

# =====================================================================
# 🛰️ DYNAMIC APPLICATION UPDATE SILENCER MATRIX
# =====================================================================
try:
    # Hunt the core configuration manager inside active system memory namespaces
    config_mod = sys.modules.get('gaia.config') or sys.modules.get('gaia.core.config')
    if not config_mod:
        import gaia.config as config_mod

    if hasattr(config_mod, 'get_config'):
        orig_get_config = config_mod.get_config


        def patched_get_config(*args, **kwargs):
            cfg = orig_get_config(*args, **kwargs)
            # Force-strip update parameters entirely from the application profile layout
            if hasattr(cfg, 'auto_update'): cfg.auto_update = False
            if hasattr(cfg, 'check_for_updates'): cfg.check_for_updates = False
            if hasattr(cfg, 'update_notifications'): cfg.update_notifications = False
            return cfg


        config_mod.get_config = patched_get_config
        print("🛰️ Deep Sandbox Security: Native engine auto-updates successfully suppressed.", flush=True)

except Exception as update_patch_err:
    print(f"🛰️ Update suppression hook deferred cleanly: {str(update_patch_err)}", flush=True)

# =====================================================================
# 🌟 EXECUTION GATEWAY: Fire hotloader at the absolute baseline
# =====================================================================
try:
    if 'hotload_user_agents' in locals():
        hotload_user_agents()
except Exception as gateway_err:
    print(f"⚠️ Hotload runner halted by execution gateway: {str(gateway_err)}", flush=True)

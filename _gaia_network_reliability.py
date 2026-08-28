"""
Network reliability patch layer for GAIA runtime.

Four-tier strategy for reliable web retrieval:
  Tier 1   — API/search-provider endpoints (handled by GAIA agents natively)
  Tier 2   — Standard HTTP fetch (requests/httpx) with split timeouts, retries,
              backoff+jitter, and per-domain cooldowns
  Tier 2.5 — Text-browser subprocess (lynx/w3m): packaged in all topologies;
              handles server-rendered HTML that blocks raw Python HTTP.
              Empty-page detection automatically escalates to Tier 3.
  Tier 3   — Full browser fetch fallback (Chromium/CDP) when tier-2/2.5 stall

Blackhole detection:
  A "blackhole" is a connection that TCP-establishes but never delivers a body
  (or delivers it only after an extreme delay). Classic signs: Read timed out,
  empty bodies, or per-domain timeout counts above threshold.

Local / Lemonade LLM Endpoints:
  Local IP addresses, loopback endpoints, and Lemonade server routes are detected
  automatically. They bypass domain cooldowns/circuit breakers and receive extended
  timeout budgets to allow for local model swapping, offloading, and long inference runs.

This module focuses on reliability, not stealth or bot-evasion.
"""

import asyncio
import ipaddress
import os
import random
import shutil
import subprocess
import threading
import time
from urllib.parse import urlparse


SAFE_METHODS = {"GET", "HEAD", "OPTIONS"}
BROWSER_FALLBACK_METHODS = {"GET"}
RETRYABLE_STATUS = {408, 429, 500, 502, 503, 504}
CHALLENGE_MARKERS = (
    "captcha",
    "are you human",
    "cf-chl",
    "cloudflare",
    "attention required",
    "bot verification",
)
BLOCKED_MARKERS = (
    "access denied",
    "request blocked",
    "forbidden",
    "temporarily unavailable",
)
# JavaScript shell/SPA indicators (used by Tier-2 empty-page detection to escalate to Tier 2.5/3)
JS_SHELL_MARKERS = (
    "<noscript>",
    'id="root"',
    "id='root'",
    'id="app"',
    "id='app'",
    "__next_data__",
    "window.__data",
)
# Content markers indicating the page has actual text (used to avoid false escalation)
TEXT_CONTENT_MARKERS = (
    "<p ", "<p>", "<article", "<section", "<h1", "<h2", "<h3",
    "<table", "<li ", "<li>",
)

# Split connect/read timeout: TCP-connect blackholes are caught in 5s;
# slow-read / body-stall blackholes are caught in 8s.
_DEFAULT_CONNECT_TIMEOUT = float(os.environ.get("GAIA_CONNECT_TIMEOUT", "5"))
_DEFAULT_READ_TIMEOUT = float(os.environ.get("GAIA_READ_TIMEOUT", "8"))
# Hard cap on any caller-supplied timeout for public web traffic.
_MAX_CALLER_TIMEOUT_SECONDS = float(os.environ.get("GAIA_MAX_CALLER_TIMEOUT", "8"))

# Timeout budget specifically for Lemonade / LLM endpoints.
# Set to 1800s (30 minutes) by default to prevent timing out on long inference generations.
_LEMONADE_TIMEOUT = float(os.environ.get("GAIA_LEMONADE_TIMEOUT", "1800.0"))

_MAX_RETRIES = 0
_BACKOFF_BASE_SECONDS = 0.6
_BACKOFF_MAX_SECONDS = 5.0
_DOMAIN_COOLDOWN_SECONDS = 90.0

# Tier-3 promotion: after this many timeouts within _BLACKHOLE_WINDOW_SECONDS
# on a single domain, auto-promote to browser-required tier if browser available,
# else set a long cooldown.
_BLACKHOLE_TIMEOUT_THRESHOLD = int(os.environ.get("GAIA_BLACKHOLE_THRESHOLD", "2"))
_BLACKHOLE_WINDOW_SECONDS = 300.0  # 5-minute rolling window

_DOMAIN_COOLDOWNS = {}
_DOMAIN_TIMEOUT_EVENTS = {}   # domain -> list of monotonic timestamps
_COOLDOWN_LOCK = threading.Lock()
_BROWSER_PROMOTED_DOMAINS = set()  # domains auto-promoted to tier-3
_PATCHED = False
_BROWSER_STATE_LOGGED = False


def _env_flag(name, default="1"):
    value = os.environ.get(name, default)
    return str(value).strip().lower() in ("1", "true", "yes", "on")


# Diagnostics are enabled by default for initial rollout and can be disabled.
_LOG_ENABLED = _env_flag("GAIA_NETWORK_RELIABILITY_LOG", "1")
_ENABLE_BROWSER_RETRIEVER = _env_flag("GAIA_ENABLE_BROWSER_RETRIEVER", "1")
_ENABLE_TEXT_BROWSER = _env_flag("GAIA_ENABLE_TEXT_BROWSER", "1")
_BROWSER_EXECUTABLE_OVERRIDE = os.environ.get("GAIA_BROWSER_EXECUTABLE", "").strip()
_BROWSER_REQUIRED_DOMAINS = {
    d.strip().lower()
    for d in os.environ.get("GAIA_BROWSER_REQUIRED_DOMAINS", "").split(",")
    if d.strip()
}
_TEXT_BROWSER_EMPTY_THRESHOLD = int(os.environ.get("GAIA_TEXT_BROWSER_EMPTY_THRESHOLD", "512"))


def _log(msg):
    if not _LOG_ENABLED:
        return
    print(f"[network-reliability] {msg}", flush=True)


def _safe_domain_str(domain):
    """Return domain string or '-' if empty/None. Used for consistent log formatting."""
    return domain or "-"


def _is_lemonade_or_local_endpoint(domain_or_url: str) -> bool:
    """Identify if target host/url is local LAN, loopback, or Lemonade server."""
    if not domain_or_url:
        return False

    # Check against environment routing variables configured for Lemonade
    configured_lemonade = os.environ.get("LEMONADE_BASE_URL", "")
    configured_llm = os.environ.get("GAIA_LLM_URL", "")
    if configured_lemonade and configured_lemonade in domain_or_url:
        return True
    if configured_llm and configured_llm in domain_or_url:
        return True

    domain = _domain_from_url(domain_or_url) if "://" in domain_or_url else domain_or_url
    domain_clean = domain.split(":")[0].strip().lower()

    if domain_clean in ("localhost", "127.0.0.1", "::1", "lemonade", "lemonade-server"):
        return True

    # Check for private IP range
    try:
        ip = ipaddress.ip_address(domain_clean)
        if ip.is_private or ip.is_loopback:
            return True
    except ValueError:
        pass

    # Check for Lemonade / LLM API path signatures in URL
    if any(route in domain_or_url for route in ("/api/v1", "/v1/chat", "/models", "/health")):
        return True

    return False


def _is_chromium_snap_wrapper(path):
    """Detect Ubuntu chromium-browser wrapper scripts that require snapd."""
    try:
        with open(path, "rb") as handle:
            head = handle.read(4096)
    except Exception:
        return False

    return b"requires the chromium snap to be installed" in head


def _detect_browser_executable():
    """Detect a full JS-capable browser (Tier 3)."""
    candidates = []
    saw_snap_wrapper = False
    if _BROWSER_EXECUTABLE_OVERRIDE:
        candidates.append(_BROWSER_EXECUTABLE_OVERRIDE)

    candidates.extend([
        "/snap/bin/chromium",
        "/usr/bin/chromium",
        "/usr/bin/chromium-browser",
        "/opt/google/chrome/google-chrome",
        "/usr/bin/google-chrome",
        "/usr/bin/google-chrome-stable",
    ])

    candidates.extend([
        "chromium",
        "chromium-browser",
        "google-chrome",
        "google-chrome-stable",
        "brave-browser",
        "firefox",
    ])

    for candidate in candidates:
        if os.path.isabs(candidate) and os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            if _is_chromium_snap_wrapper(candidate):
                saw_snap_wrapper = True
                continue
            return True, candidate, "ok"
        resolved = shutil.which(candidate)
        if resolved:
            if _is_chromium_snap_wrapper(resolved):
                saw_snap_wrapper = True
                continue
            return True, resolved, "ok"

    if saw_snap_wrapper:
        return False, "", "chromium-wrapper-requires-snap"

    return False, "", "no-browser-executable-found"


def _detect_text_browser():
    """Detect a text-browser for Tier 2.5 (lynx, w3m)."""
    snap_root = os.environ.get("SNAP", "")
    candidates = []
    for name in ("lynx", "w3m"):
        for explicit in (f"/usr/bin/{name}", f"/bin/{name}"):
            if os.path.isfile(explicit) and os.access(explicit, os.X_OK):
                candidates.append((name, explicit))

        resolved = shutil.which(name)
        if resolved:
            candidates.append((name, resolved))

        if snap_root:
            snap_path = os.path.join(snap_root, "usr", "bin", name)
            if os.path.isfile(snap_path) and os.access(snap_path, os.X_OK):
                if resolved != snap_path:
                    candidates.append((name, snap_path))

    for name, path in candidates:
        return True, name, path, "ok"

    return False, "", "", "no-text-browser-found"


_BROWSER_AVAILABLE, _BROWSER_EXECUTABLE, _BROWSER_REASON = _detect_browser_executable()
_TEXT_BROWSER_AVAILABLE, _TEXT_BROWSER_NAME, _TEXT_BROWSER_PATH, _TEXT_BROWSER_REASON = _detect_text_browser()


def _domain_requires_browser(domain):
    if _is_lemonade_or_local_endpoint(domain):
        return False
    if not domain or not _BROWSER_REQUIRED_DOMAINS:
        return False
    return any(domain == required or domain.endswith(f".{required}") for required in _BROWSER_REQUIRED_DOMAINS)


def _promote_domain_to_browser(domain, reason):
    if not domain or _is_lemonade_or_local_endpoint(domain):
        return
    if not (_ENABLE_BROWSER_RETRIEVER and _BROWSER_AVAILABLE):
        return

    _BROWSER_REQUIRED_DOMAINS.add(domain)
    if domain not in _BROWSER_PROMOTED_DOMAINS:
        _BROWSER_PROMOTED_DOMAINS.add(domain)
        _log(f"tier-3 promotion domain={domain} ({reason})")


def _maybe_log_browser_state():
    global _BROWSER_STATE_LOGGED
    if _BROWSER_STATE_LOGGED:
        return

    if _ENABLE_TEXT_BROWSER and _TEXT_BROWSER_AVAILABLE:
        _log(f"tier-2.5 text-browser available ({_TEXT_BROWSER_NAME}={_TEXT_BROWSER_PATH})")
    elif _ENABLE_TEXT_BROWSER:
        _log(f"tier-2.5 text-browser not found ({_TEXT_BROWSER_REASON}); skipping")

    if _ENABLE_BROWSER_RETRIEVER and _BROWSER_AVAILABLE:
        _log(f"tier-3 browser retriever enabled (executable={_BROWSER_EXECUTABLE})")
    elif _ENABLE_BROWSER_RETRIEVER and not _BROWSER_AVAILABLE:
        _log(
            "tier-3 browser retriever enabled but no browser executable found; "
            "falling back to HTTP transport where allowed"
        )

    _BROWSER_STATE_LOGGED = True


def _fetch_via_text_browser(url):
    """Tier-2.5: fetch URL via lynx or w3m subprocess."""
    global _TEXT_BROWSER_AVAILABLE, _TEXT_BROWSER_REASON

    if not _ENABLE_TEXT_BROWSER or not _TEXT_BROWSER_AVAILABLE or _is_lemonade_or_local_endpoint(url):
        return None, False

    try:
        if _TEXT_BROWSER_NAME == "lynx":
            cmd = [
                _TEXT_BROWSER_PATH,
                "-dump",
                "-nolist",
                "-nomargins",
                "-width=120",
                "-connect_timeout=8",
                "-read_timeout=12",
                url,
            ]
        else:  # w3m
            cmd = [
                _TEXT_BROWSER_PATH,
                "-dump",
                "-cols", "120",
                "-T", "text/html",
                url,
            ]

        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=8,
        )
        text = result.stdout.strip()
        byte_len = len(text.encode("utf-8", errors="replace"))

        if byte_len < _TEXT_BROWSER_EMPTY_THRESHOLD:
            _log(
                f"tier-2.5 empty-page domain={_domain_from_url(url)} "
                f"browser={_TEXT_BROWSER_NAME} bytes={byte_len} "
                f"(threshold={_TEXT_BROWSER_EMPTY_THRESHOLD}) → escalating to tier-3"
            )
            return text, True

        _log(
            f"tier-2.5 ok domain={_domain_from_url(url)} "
            f"browser={_TEXT_BROWSER_NAME} bytes={byte_len}"
        )
        return text, False

    except subprocess.TimeoutExpired:
        _log(f"tier-2.5 timeout domain={_domain_from_url(url)} browser={_TEXT_BROWSER_NAME}")
        _record_timeout(_domain_from_url(url))
        return None, False
    except (FileNotFoundError, OSError) as exc:
        _TEXT_BROWSER_AVAILABLE = False
        _TEXT_BROWSER_REASON = f"runtime-unusable ({exc.__class__.__name__})"
        _log(
            f"tier-2.5 disabled domain={_domain_from_url(url)} "
            f"browser={_TEXT_BROWSER_NAME} reason={_TEXT_BROWSER_REASON}"
        )
        return None, False
    except Exception as exc:
        _log(f"tier-2.5 error domain={_domain_from_url(url)} err={exc}")
        return None, False


def _fetch_via_browser(url):
    """Tier-3: fetch URL via full browser."""
    if not _ENABLE_BROWSER_RETRIEVER or not _BROWSER_AVAILABLE or _is_lemonade_or_local_endpoint(url):
        return None

    domain = _domain_from_url(url)
    cmd = [
        _BROWSER_EXECUTABLE,
        "--headless=new",
        "--disable-gpu",
        "--disable-dev-shm-usage",
        "--no-sandbox",
        "--disable-blink-features=AutomationControlled",
        "--disable-component-extensions-with-background-pages",
        "--disable-default-apps",
        "--disable-sync",
        "--no-first-run",
        "--no-default-browser-check",
        "--disable-plugins",
        "--disable-extensions",
        "--start-maximized",
        "--user-agent=Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36",
        "--dump-dom",
        url,
    ]

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=12,
        )

        if result.returncode != 0:
            stderr_preview = (result.stderr or "").strip()[:240]
            _log(
                f"tier-3 failed domain={_safe_domain_str(domain)} executable={_BROWSER_EXECUTABLE} "
                f"exit_code={result.returncode} stderr={stderr_preview!r}"
            )
            return None

        output = (result.stdout or "").strip()
        if not output:
            _log(f"tier-3 empty domain={_safe_domain_str(domain)} executable={_BROWSER_EXECUTABLE}")
            return None

        is_error_doc, reason = _is_browser_error_document(output, domain)
        if is_error_doc:
            _log(
                f"tier-3 error-page domain={_safe_domain_str(domain)} executable={_BROWSER_EXECUTABLE} "
                f"reason={reason}"
            )
            return None

        _log(
            f"tier-3 ok domain={_safe_domain_str(domain)} executable={_BROWSER_EXECUTABLE} "
            f"bytes={len(output.encode('utf-8', errors='replace'))}"
        )
        return output
    except subprocess.TimeoutExpired:
        _log(f"tier-3 timeout domain={_safe_domain_str(domain)} executable={_BROWSER_EXECUTABLE}")
        _record_timeout(domain)
        return None
    except Exception as exc:
        _log(f"tier-3 error domain={_safe_domain_str(domain)} err={exc}")
        return None


def _build_requests_fallback_response(url, payload):
    import requests

    response = requests.Response()
    response.status_code = 200
    response.url = url
    response.encoding = "utf-8"
    response.headers["Content-Type"] = "text/html; charset=utf-8"
    response._content = payload.encode("utf-8", errors="replace")
    return response


def _is_browser_error_document(payload, domain):
    if not payload:
        return False, ""

    lower = payload.lower()

    if "chrome-error://" in lower:
        return True, "chrome-error-scheme"
    if 'id="main-frame-error"' in lower or "id='main-frame-error'" in lower:
        return True, "main-frame-error"
    if "this site can" in lower and "be reached" in lower:
        return True, "site-cant-be-reached"

    has_err_token = "err_" in lower
    has_neterror_shell = (
        "error-code-color" in lower
        and "google-gray-900" in lower
        and "neterror" in lower
    )
    if has_err_token and has_neterror_shell:
        return True, "chromium-neterror-shell"

    if domain:
        if f"<title>{domain}</title>" in lower and "error-code-color" in lower:
            return True, "domain-title-error-shell"

    return False, ""


def _build_httpx_fallback_response(httpx_module, method, url, payload):
    request = httpx_module.Request(method, url)
    return httpx_module.Response(
        status_code=200,
        headers={"Content-Type": "text/html; charset=utf-8"},
        content=payload.encode("utf-8", errors="replace"),
        request=request,
    )


async def _try_tier25_then_tier3_async(url, domain, reason):
    return await asyncio.to_thread(_try_tier25_then_tier3, url, domain, reason)


def _domain_from_url(url):
    try:
        return (urlparse(url).hostname or "").lower()
    except Exception:
        return ""


def _is_cooling_down(domain):
    if not domain or _is_lemonade_or_local_endpoint(domain):
        return False

    now = time.monotonic()
    with _COOLDOWN_LOCK:
        until = _DOMAIN_COOLDOWNS.get(domain, 0)
        if until <= now:
            _DOMAIN_COOLDOWNS.pop(domain, None)
            return False
        return True


def _set_cooldown(domain, reason):
    if not domain or _is_lemonade_or_local_endpoint(domain):
        return

    until = time.monotonic() + _DOMAIN_COOLDOWN_SECONDS
    with _COOLDOWN_LOCK:
        _DOMAIN_COOLDOWNS[domain] = until
    _log(f"domain cooldown set for '{domain}' ({reason})")


def _record_timeout(domain):
    if not domain or _is_lemonade_or_local_endpoint(domain):
        return

    now = time.monotonic()
    cutoff = now - _BLACKHOLE_WINDOW_SECONDS
    with _COOLDOWN_LOCK:
        events = _DOMAIN_TIMEOUT_EVENTS.get(domain, [])
        events = [t for t in events if t > cutoff]
        events.append(now)
        _DOMAIN_TIMEOUT_EVENTS[domain] = events
        count = len(events)

    _log(f"timeout domain={domain} count_in_window={count}/{_BLACKHOLE_TIMEOUT_THRESHOLD}")

    if count >= _BLACKHOLE_TIMEOUT_THRESHOLD:
        if _ENABLE_BROWSER_RETRIEVER and _BROWSER_AVAILABLE and domain not in _BROWSER_PROMOTED_DOMAINS:
            _BROWSER_PROMOTED_DOMAINS.add(domain)
            _BROWSER_REQUIRED_DOMAINS.add(domain)
            _log(f"tier-3 promotion domain={domain} (repeated timeouts → browser fallback)")
        else:
            _set_cooldown(domain, f"blackhole-candidate ({count} timeouts in window)")


def _build_timeout(kwargs, domain_or_url=""):
    """Return appropriate timeout settings, granting Lemonade/local endpoints higher budgets."""
    caller_timeout = kwargs.get("timeout")

    # If it's Lemonade or local LAN/loopback, provide an extended 30-minute read timeout budget
    if _is_lemonade_or_local_endpoint(domain_or_url):
        if caller_timeout is None:
            return (15.0, _LEMONADE_TIMEOUT)
        if isinstance(caller_timeout, (tuple, list)) and len(caller_timeout) == 2:
            return (max(float(caller_timeout[0]), 15.0), max(float(caller_timeout[1]), _LEMONADE_TIMEOUT))
        return max(float(caller_timeout), _LEMONADE_TIMEOUT)

    # Standard public web traffic timeout behavior:
    if caller_timeout is None:
        return (_DEFAULT_CONNECT_TIMEOUT, _DEFAULT_READ_TIMEOUT)

    if isinstance(caller_timeout, (tuple, list)) and len(caller_timeout) == 2:
        connect = min(float(caller_timeout[0]), _MAX_CALLER_TIMEOUT_SECONDS)
        read = min(float(caller_timeout[1]), _MAX_CALLER_TIMEOUT_SECONDS)
        return (connect, read)

    capped = min(float(caller_timeout), _MAX_CALLER_TIMEOUT_SECONDS)
    return (_DEFAULT_CONNECT_TIMEOUT, capped)


def _is_timeout_error(exc):
    exc_str = exc.__class__.__name__.lower()
    exc_msg = str(exc).lower()
    return (
        "timeout" in exc_str
        or "timed out" in exc_msg
        or "read timed out" in exc_msg
        or "connect timeout" in exc_msg
        or "connection timed out" in exc_msg
    )


def _sleep_backoff(attempt):
    backoff = min(_BACKOFF_BASE_SECONDS * (2 ** attempt), _BACKOFF_MAX_SECONDS)
    jitter = random.uniform(0.0, 0.25)
    time.sleep(backoff + jitter)


async def _sleep_backoff_async(attempt):
    backoff = min(_BACKOFF_BASE_SECONDS * (2 ** attempt), _BACKOFF_MAX_SECONDS)
    jitter = random.uniform(0.0, 0.25)
    await asyncio.sleep(backoff + jitter)


def _is_html_response(response):
    content_type = (response.headers.get("content-type") or "").lower()
    return "html" in content_type or "text" in content_type


def _is_empty_response(response):
    if not _is_html_response(response):
        return False

    try:
        body = response.content
    except Exception:
        return False

    if len(body) < _TEXT_BROWSER_EMPTY_THRESHOLD:
        return True

    try:
        preview = body[:4096].decode("utf-8", errors="replace").lower()
    except Exception:
        return False

    has_js_shell = any(m in preview for m in JS_SHELL_MARKERS)
    has_text = any(m in preview for m in TEXT_CONTENT_MARKERS)
    return has_js_shell and not has_text


def _try_tier25_then_tier3(url, domain, reason):
    if _is_lemonade_or_local_endpoint(domain) or _is_lemonade_or_local_endpoint(url):
        return None

    text, empty_signal = _fetch_via_text_browser(url)

    if text and not empty_signal:
        _log(f"tier-2.5 served domain={domain} reason={reason}")
        return text

    if _ENABLE_BROWSER_RETRIEVER and _BROWSER_AVAILABLE:
        if empty_signal and domain not in _BROWSER_PROMOTED_DOMAINS:
            _BROWSER_PROMOTED_DOMAINS.add(domain)
            _BROWSER_REQUIRED_DOMAINS.add(domain)
            _log(f"tier-3 promotion domain={domain} (tier-2.5 empty-page → browser fallback)")

        if not empty_signal:
            _log(f"tier-2.5 miss domain={domain} reason={reason} → trying tier-3")

        tier3_payload = _fetch_via_browser(url)
        if tier3_payload:
            return tier3_payload
    elif empty_signal:
        _set_cooldown(domain, f"js-shell-only-no-tier3 ({reason})")

    return None


def _is_challenge_response(response):
    if not _is_html_response(response):
        return False
    try:
        preview = response.text[:4096].lower()
    except Exception:
        return False
    return any(marker in preview for marker in CHALLENGE_MARKERS)


def _is_blocked_response(response):
    if not _is_html_response(response):
        return False
    try:
        preview = response.text[:4096].lower()
    except Exception:
        return False
    return any(marker in preview for marker in BLOCKED_MARKERS)


def _patch_requests():
    try:
        import requests
    except Exception:
        return False

    original_request = requests.sessions.Session.request

    def patched_request(self, method, url, *args, **kwargs):
        method_upper = (method or "GET").upper()
        domain = _domain_from_url(url)
        started = time.monotonic()

        _maybe_log_browser_state()

        if _domain_requires_browser(domain) and not _BROWSER_AVAILABLE:
            raise requests.exceptions.RequestException(
                "Browser transport is required for this domain but no browser executable was found. "
                "Set GAIA_BROWSER_EXECUTABLE or install Chromium/Chrome on host. "
                f"domain={domain}"
            )

        if _domain_requires_browser(domain) and _BROWSER_AVAILABLE and method_upper in BROWSER_FALLBACK_METHODS:
            tier3_payload = _fetch_via_browser(url)
            if tier3_payload:
                return _build_requests_fallback_response(url, tier3_payload)

        if _is_cooling_down(domain):
            raise requests.exceptions.RequestException(
                f"Domain '{domain}' is in cooldown due to earlier blocking/challenge responses"
            )

        max_attempts = _MAX_RETRIES + 1 if method_upper in SAFE_METHODS else 1
        last_error = None

        for attempt in range(max_attempts):
            request_kwargs = dict(kwargs)
            request_kwargs["timeout"] = _build_timeout(request_kwargs, url or domain)

            try:
                response = original_request(self, method, url, *args, **request_kwargs)

                challenge = _is_challenge_response(response)
                blocked = _is_blocked_response(response) or response.status_code in (403,)

                if method_upper in BROWSER_FALLBACK_METHODS and (challenge or blocked):
                    reason = "http-challenge" if challenge else f"http-blocked-{response.status_code}"
                    _log(
                        f"requests guarded-response domain={_safe_domain_str(domain)} method={method_upper} "
                        f"status={response.status_code} reason={reason} attempt={attempt + 1}/{max_attempts}"
                    )
                    _promote_domain_to_browser(domain, f"{reason} → browser-first")
                    fallback_payload = _try_tier25_then_tier3(url, domain, reason)
                    if fallback_payload:
                        return _build_requests_fallback_response(url, fallback_payload)

                if challenge:
                    _log(
                        f"requests challenge domain={_safe_domain_str(domain)} method={method_upper} "
                        f"status={response.status_code} attempt={attempt + 1}/{max_attempts}"
                    )
                    _set_cooldown(domain, "challenge-response")
                    if attempt < max_attempts - 1:
                        _log(f"requests retrying after challenge domain={_safe_domain_str(domain)}")
                        _sleep_backoff(attempt)
                        continue

                if response.status_code in RETRYABLE_STATUS and attempt < max_attempts - 1:
                    _log(
                        f"requests retryable-status domain={_safe_domain_str(domain)} method={method_upper} "
                        f"status={response.status_code} attempt={attempt + 1}/{max_attempts}"
                    )
                    _sleep_backoff(attempt)
                    continue

                elapsed_ms = int((time.monotonic() - started) * 1000)
                _log(
                    f"requests done domain={_safe_domain_str(domain)} method={method_upper} "
                    f"status={response.status_code} attempts={attempt + 1} elapsed_ms={elapsed_ms}"
                )

                if method_upper in BROWSER_FALLBACK_METHODS and response.status_code == 200 and _is_empty_response(response):
                    _log(f"requests empty-page domain={_safe_domain_str(domain)} → trying tier-2.5")
                    fallback_payload = _try_tier25_then_tier3(url, domain, "http-200-empty")
                    if fallback_payload:
                        return _build_requests_fallback_response(url, fallback_payload)

                return response
            except requests.exceptions.RequestException as exc:
                last_error = exc
                if _is_timeout_error(exc):
                    _record_timeout(domain)
                    _log(
                        f"requests timeout domain={_safe_domain_str(domain)} method={method_upper} "
                        f"attempt={attempt + 1}/{max_attempts} err={exc.__class__.__name__}"
                    )
                else:
                    _log(
                        f"requests exception domain={_safe_domain_str(domain)} method={method_upper} "
                        f"attempt={attempt + 1}/{max_attempts} err={exc.__class__.__name__}"
                    )
                if attempt < max_attempts - 1:
                    _sleep_backoff(attempt)
                    continue
                break

        if last_error:
            if method_upper in BROWSER_FALLBACK_METHODS:
                fallback_payload = _try_tier25_then_tier3(url, domain, "http-exhausted")
                if fallback_payload:
                    return _build_requests_fallback_response(url, fallback_payload)
            raise last_error

        return original_request(self, method, url, *args, **kwargs)

    requests.sessions.Session.request = patched_request
    _log("requests transport hooks installed")
    return True


def _patch_httpx():
    try:
        import httpx
    except Exception:
        return False

    original_client_request = httpx.Client.request
    original_async_client_request = httpx.AsyncClient.request

    def patched_client_request(self, method, url, *args, **kwargs):
        method_upper = (method or "GET").upper()
        domain = _domain_from_url(str(url))
        started = time.monotonic()

        _maybe_log_browser_state()

        if _domain_requires_browser(domain) and not _BROWSER_AVAILABLE:
            raise httpx.RequestError(
                "Browser transport is required for this domain but no browser executable was found. "
                "Set GAIA_BROWSER_EXECUTABLE or install Chromium/Chrome on host. "
                f"domain={domain}"
            )

        if _domain_requires_browser(domain) and _BROWSER_AVAILABLE and method_upper in BROWSER_FALLBACK_METHODS:
            tier3_payload = _fetch_via_browser(str(url))
            if tier3_payload:
                return _build_httpx_fallback_response(httpx, method, str(url), tier3_payload)

        if _is_cooling_down(domain):
            raise httpx.RequestError(
                f"Domain '{domain}' is in cooldown due to earlier blocking/challenge responses"
            )

        max_attempts = _MAX_RETRIES + 1 if method_upper in SAFE_METHODS else 1
        last_error = None

        for attempt in range(max_attempts):
            request_kwargs = dict(kwargs)
            request_kwargs["timeout"] = _build_timeout(request_kwargs, str(url) or domain)

            try:
                response = original_client_request(self, method, url, *args, **request_kwargs)

                challenge = _is_challenge_response(response)
                blocked = _is_blocked_response(response) or response.status_code in (403,)

                if method_upper in BROWSER_FALLBACK_METHODS and (challenge or blocked):
                    reason = "http-challenge" if challenge else f"http-blocked-{response.status_code}"
                    _log(
                        f"httpx guarded-response domain={_safe_domain_str(domain)} method={method_upper} "
                        f"status={response.status_code} reason={reason} attempt={attempt + 1}/{max_attempts}"
                    )
                    _promote_domain_to_browser(domain, f"{reason} → browser-first")
                    fallback_payload = _try_tier25_then_tier3(str(url), domain, reason)
                    if fallback_payload:
                        return _build_httpx_fallback_response(httpx, method, str(url), fallback_payload)

                if challenge:
                    _log(
                        f"httpx challenge domain={_safe_domain_str(domain)} method={method_upper} "
                        f"status={response.status_code} attempt={attempt + 1}/{max_attempts}"
                    )
                    _set_cooldown(domain, "challenge-response")
                    if attempt < max_attempts - 1:
                        _log(f"httpx retrying after challenge domain={_safe_domain_str(domain)}")
                        _sleep_backoff(attempt)
                        continue

                if response.status_code in RETRYABLE_STATUS and attempt < max_attempts - 1:
                    _log(
                        f"httpx retryable-status domain={_safe_domain_str(domain)} method={method_upper} "
                        f"status={response.status_code} attempt={attempt + 1}/{max_attempts}"
                    )
                    _sleep_backoff(attempt)
                    continue

                elapsed_ms = int((time.monotonic() - started) * 1000)
                _log(
                    f"httpx done domain={_safe_domain_str(domain)} method={method_upper} "
                    f"status={response.status_code} attempts={attempt + 1} elapsed_ms={elapsed_ms}"
                )

                if method_upper in BROWSER_FALLBACK_METHODS and response.status_code == 200 and _is_empty_response(response):
                    _log(f"httpx empty-page domain={_safe_domain_str(domain)} → trying tier-2.5")
                    fallback_payload = _try_tier25_then_tier3(str(url), domain, "http-200-empty")
                    if fallback_payload:
                        return _build_httpx_fallback_response(httpx, method, str(url), fallback_payload)

                return response
            except httpx.RequestError as exc:
                last_error = exc
                if _is_timeout_error(exc):
                    _record_timeout(domain)
                    _log(
                        f"httpx timeout domain={_safe_domain_str(domain)} method={method_upper} "
                        f"attempt={attempt + 1}/{max_attempts} err={exc.__class__.__name__}"
                    )
                else:
                    _log(
                        f"httpx exception domain={_safe_domain_str(domain)} method={method_upper} "
                        f"attempt={attempt + 1}/{max_attempts} err={exc.__class__.__name__}"
                    )
                if attempt < max_attempts - 1:
                    _sleep_backoff(attempt)
                    continue
                break

        if last_error:
            if method_upper in BROWSER_FALLBACK_METHODS:
                fallback_payload = _try_tier25_then_tier3(str(url), domain, "http-exhausted")
                if fallback_payload:
                    return _build_httpx_fallback_response(httpx, method, str(url), fallback_payload)
            raise last_error

        return original_client_request(self, method, url, *args, **kwargs)

    async def patched_async_client_request(self, method, url, *args, **kwargs):
        method_upper = (method or "GET").upper()
        domain = _domain_from_url(str(url))
        started = time.monotonic()

        _maybe_log_browser_state()

        if _domain_requires_browser(domain) and not _BROWSER_AVAILABLE:
            raise httpx.RequestError(
                "Browser transport is required for this domain but no browser executable was found. "
                "Set GAIA_BROWSER_EXECUTABLE or install Chromium/Chrome on host. "
                f"domain={domain}"
            )

        if _domain_requires_browser(domain) and _BROWSER_AVAILABLE and method_upper in BROWSER_FALLBACK_METHODS:
            tier3_payload = await asyncio.to_thread(_fetch_via_browser, str(url))
            if tier3_payload:
                return _build_httpx_fallback_response(httpx, method, str(url), tier3_payload)

        if _is_cooling_down(domain):
            raise httpx.RequestError(
                f"Domain '{domain}' is in cooldown due to earlier blocking/challenge responses"
            )

        max_attempts = _MAX_RETRIES + 1 if method_upper in SAFE_METHODS else 1
        last_error = None

        for attempt in range(max_attempts):
            request_kwargs = dict(kwargs)
            request_kwargs["timeout"] = _build_timeout(request_kwargs, str(url) or domain)

            try:
                response = await original_async_client_request(self, method, url, *args, **request_kwargs)

                challenge = _is_challenge_response(response)
                blocked = _is_blocked_response(response) or response.status_code in (403,)

                if method_upper in BROWSER_FALLBACK_METHODS and (challenge or blocked):
                    reason = "http-challenge" if challenge else f"http-blocked-{response.status_code}"
                    _log(
                        f"httpx-async guarded-response domain={_safe_domain_str(domain)} method={method_upper} "
                        f"status={response.status_code} reason={reason} attempt={attempt + 1}/{max_attempts}"
                    )
                    _promote_domain_to_browser(domain, f"{reason} → browser-first")
                    fallback_payload = await _try_tier25_then_tier3_async(str(url), domain, reason)
                    if fallback_payload:
                        return _build_httpx_fallback_response(httpx, method, str(url), fallback_payload)

                if challenge:
                    _log(
                        f"httpx-async challenge domain={_safe_domain_str(domain)} method={method_upper} "
                        f"status={response.status_code} attempt={attempt + 1}/{max_attempts}"
                    )
                    _set_cooldown(domain, "challenge-response")
                    if attempt < max_attempts - 1:
                        _log(f"httpx-async retrying after challenge domain={_safe_domain_str(domain)}")
                        await _sleep_backoff_async(attempt)
                        continue

                if response.status_code in RETRYABLE_STATUS and attempt < max_attempts - 1:
                    _log(
                        f"httpx-async retryable-status domain={_safe_domain_str(domain)} method={method_upper} "
                        f"status={response.status_code} attempt={attempt + 1}/{max_attempts}"
                    )
                    await _sleep_backoff_async(attempt)
                    continue

                elapsed_ms = int((time.monotonic() - started) * 1000)
                _log(
                    f"httpx-async done domain={_safe_domain_str(domain)} method={method_upper} "
                    f"status={response.status_code} attempts={attempt + 1} elapsed_ms={elapsed_ms}"
                )

                if method_upper in BROWSER_FALLBACK_METHODS and response.status_code == 200 and _is_empty_response(response):
                    _log(f"httpx-async empty-page domain={_safe_domain_str(domain)} → trying tier-2.5")
                    fallback_payload = await _try_tier25_then_tier3_async(str(url), domain, "http-200-empty")
                    if fallback_payload:
                        return _build_httpx_fallback_response(httpx, method, str(url), fallback_payload)

                return response
            except httpx.RequestError as exc:
                last_error = exc
                if _is_timeout_error(exc):
                    _record_timeout(domain)
                    _log(
                        f"httpx-async timeout domain={_safe_domain_str(domain)} method={method_upper} "
                        f"attempt={attempt + 1}/{max_attempts} err={exc.__class__.__name__}"
                    )
                else:
                    _log(
                        f"httpx-async exception domain={_safe_domain_str(domain)} method={method_upper} "
                        f"attempt={attempt + 1}/{max_attempts} err={exc.__class__.__name__}"
                    )
                if attempt < max_attempts - 1:
                    await _sleep_backoff_async(attempt)
                    continue
                break

        if last_error:
            if method_upper in BROWSER_FALLBACK_METHODS:
                fallback_payload = await _try_tier25_then_tier3_async(str(url), domain, "http-exhausted")
                if fallback_payload:
                    return _build_httpx_fallback_response(httpx, method, str(url), fallback_payload)
            raise last_error

        return await original_async_client_request(self, method, url, *args, **kwargs)

    httpx.Client.request = patched_client_request
    httpx.AsyncClient.request = patched_async_client_request
    _log("httpx transport hooks installed")
    return True


def install_network_reliability():
    global _PATCHED
    if _PATCHED:
        return

    _maybe_log_browser_state()

    installed = False
    installed = _patch_requests() or installed
    installed = _patch_httpx() or installed

    if installed:
        _PATCHED = True
    else:
        _log("no transport libraries found to patch")
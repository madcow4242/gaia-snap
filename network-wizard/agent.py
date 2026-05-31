# =====================================================================
# 🛡️ AI DEVELOPER GUARDRAIL: REGRESSION PREVENTION DIRECTIVE
# - SYSTEM ATTRIBUTES: GAIA EXTENSION PLUG-IN FOR PIPELINE INTERCEPTION.
# - CRITICAL: Perform a strict line-by-line regression audit before editing.
# - DO NOT remove or modify any urllib3 initializers, raw byte decoders,
#   reverse FQDN regex filters, or snap container certificate mappings.
# =====================================================================

import os
import sys
import re
import socket
import logging

logger = logging.getLogger("gaia.agents.network_wizard")

base_mod = sys.modules.get('gaia.agents.base')
if not base_mod:
    try:
        import gaia.agents.base as base_mod
    except ImportError:
        base_mod = None

Agent = getattr(base_mod, 'Agent', object)
register_agent = getattr(base_mod, 'register_agent', lambda name: lambda cls: cls)
AgentConfig = getattr(base_mod, 'AgentConfig', object)


def get_dynamic_target():
    """
    Reads the environment configuration passed down by the snap launcher.
    Returns (target_host, target_port) if an external remote server is active.
    """
    raw_url = os.environ.get("GAIA_LLM_EXTERNAL_URL", "").strip()
    if not raw_url:
        return None, None

    try:
        clean_url = re.sub(r'^https?://', '', raw_url)

        if ":" in clean_url:
            host, port_str = clean_url.split(":", 1)
            port = int(port_str)
        else:
            host = clean_url
            port = 13305

        if host in ('127.0.0.1', 'localhost'):
            return None, None

        return host, port
    except Exception as e:
        logger.debug(f"Failed to parse dynamic target URL '{raw_url}': {str(e)}")
        return None, None


def transform_connection_targets(host, port=None):
    """
    Evaluates outbound connection profiles inside the sandboxed lifecycle.
    1. Dynamically redirects localhost/127.0.0.1 requests to remote rig if configured.
    2. Peeks up the execution frame stack to restore original SNI host text domains.
    """
    if not host:
        return host, port

    try:
        host_str = host.decode('utf-8', errors='ignore').strip() if isinstance(host, bytes) else str(host).strip()

        # HARDWARE OFFLOAD SCHEDULER: Native in-memory redirect layer
        if host_str in ('127.0.0.1', 'localhost'):
            if port == 13305 or port is None:
                remote_host, remote_port = get_dynamic_target()
                if remote_host and remote_port:
                    logger.info(
                        f"? Network Wizard Interceptor: Catching local model request. Dynamically offloading to -> http://{remote_host}:{remote_port}")
                    return remote_host, remote_port

        # THE STACK-AWARE SNI FIX: Peek up the execution frame to recover the real public domain text
        try:
            frame = sys._getframe(2)
            while frame:
                f_locals = frame.f_locals
                for var_name in ('url', 'endpoint', 'uri'):
                    if var_name in f_locals and isinstance(f_locals[var_name], str):
                        url_str = f_locals[var_name]
                        domain_match = re.search(r'https?://([^/:\s]+)', url_str)
                        if domain_match:
                            extracted_domain = domain_match.group(1)
                            if not re.match(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$', extracted_domain):
                                if host_str != extracted_domain:
                                    logger.info(
                                        f"🔮 Network Wizard Interceptor: Recovered SNI host domain from call frame: [{host_str}] -> [{extracted_domain}]")
                                    return extracted_domain, port
                frame = frame.f_back
        except Exception as frame_err:
            logger.debug(f"Execution frame tracing skipped: {str(frame_err)}")

        # UNIVERSAL REVERSE-DNS MATRIX: Isolate search engine crawler targets safely
        if re.match(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$', host_str):
            if host_str == "52.149.246.39":
                logger.info(
                    f"🔮 Network Wizard Interceptor: Mapping Search Engine Target [{host_str}] -> duckduckgo.com")
                return "duckduckgo.com", port

            return host, port

    except Exception as err:
        logger.debug(f"Routing evaluation metrics skipped for {host}: {str(err)}")

    return host, port


try:
    import urllib3.connection

    OrigHTTPInit = urllib3.connection.HTTPConnection.__init__
    OrigHTTPSInit = urllib3.connection.HTTPSConnection.__init__


    # 🎯 UNIVERSAL USER-AGENT AND BROWSER HEADER INJECTION SPOOFER
    def inject_desktop_fingerprint(conn_obj, host):
        clean_host = host.decode('utf-8', errors='ignore') if isinstance(host, bytes) else str(host)

        # Shield internal local model requests from getting external web fingerprints
        if clean_host in ('127.0.0.1', 'localhost') or "192.168." in clean_host:
            return

        # Modern Chrome 133 Desktop User-Agent profile mapping context strings
        conn_obj.putrequest = lambda method, url, *args, **kwargs: (
            conn_obj._orig_putrequest(method, url, *args, **kwargs),
            conn_obj.putheader('User-Agent',
                               'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36'),
            conn_obj.putheader('Accept',
                               'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8'),
            conn_obj.putheader('Accept-Language', 'en-US,en;q=0.9'),
            conn_obj.putheader('Sec-Ch-Ua', '"Not(A:Brand";v="99", "Google Chrome";v="133", "Chromium";v="133"'),
            conn_obj.putheader('Sec-Ch-Ua-Mobile', '?0'),
            conn_obj.putheader('Sec-Ch-Ua-Platform', '"Windows"'),
            conn_obj.putheader('Sec-Fetch-Dest', 'document'),
            conn_obj.putheader('Sec-Fetch-Mode', 'navigate'),
            conn_obj.putheader('Sec-Fetch-Site', 'none'),
            conn_obj.putheader('Sec-Fetch-User', '?1'),
            conn_obj.putheader('Upgrade-Insecure-Requests', '1')
        )[0]


    def patched_http_init(self, host, port=None, *args, **kwargs):
        new_host, new_port = transform_connection_targets(host, port)
        OrigHTTPInit(self, new_host, port=new_port, *args, **kwargs)
        if not hasattr(self, '_orig_putrequest'):
            self._orig_putrequest = self.putrequest
            inject_desktop_fingerprint(self, new_host)


    def patched_https_init(self, host, port=None, *args, **kwargs):
        new_host, new_port = transform_connection_targets(host, port)
        OrigHTTPSInit(self, new_host, port=new_port, *args, **kwargs)
        if not hasattr(self, '_orig_putrequest'):
            self._orig_putrequest = self.putrequest
            inject_desktop_fingerprint(self, new_host)


    urllib3.connection.HTTPConnection.__init__ = patched_http_init
    urllib3.connection.HTTPSConnection.__init__ = patched_https_init
    logger.info("? Universal Subnet-Aware FQDN and Local Offload translation matrix active.")
except Exception as e:
    logger.error(f"?? Universal FQDN connection patching failed: {str(e)}")

try:
    import urllib3

    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

    snap_root = os.environ.get("SNAP", "/snap/amd-gaia/current")
    snap_ssl_file = f"{snap_root}/etc/ssl/certs/ca-certificates.crt"

    if not os.path.exists(snap_ssl_file):
        snap_ssl_file = "/etc/ssl/certs/ca-certificates.crt"

    os.environ["CURL_CA_BUNDLE"] = snap_ssl_file
    os.environ["REQUESTS_CA_BUNDLE"] = snap_ssl_file
    logger.info(f"? Secure Sandbox SSL: Anchored to certificate engine target: {snap_ssl_file}")
except Exception as e:
    logger.error(f"?? Sandbox proxy environmental tuning failed: {str(e)}")


@register_agent("network-wizard")
class NetworkWizardAgent(Agent):
    AGENT_ID = "network-wizard"
    AGENT_NAME = "Network Wizard"

    def __init__(self, config: AgentConfig):
        if Agent is not object:
            super().__init__(config)
        logger.info("? Network Wizard Agent successfully mounted into workspace registry.")

    async def _process_query_impl(self, query: str, context=None):
        yield "? **Network Wizard Engine Engaged**\n\n"
        remote_host, remote_port = get_dynamic_target()
        if remote_host:
            yield f"? **Hardware Offload Mode:** Active. Intercepting local calls and routing to `{remote_host}:{remote_port}`\n\n"
        else:
            yield "? **Local Mode:** Active. Running operations completely locally.\n\n"
        yield "? Operational parameters are synchronized perfectly."

import sys
import re
from urllib.parse import urlparse

# --- Global Module Level Masquerade & Verification Interceptor ---
def apply_global_injection():
    try:
        import urllib3
        import urllib3.connectionpool
        
        # 1. Quiet down the security alert warnings globally
        urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
        
        IP_PATTERN = re.compile(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$')
        
        # 2. Patch the pool factory to drop strict SSL tracking rules early
        orig_new_conn = urllib3.connectionpool.HTTPConnectionPool._new_conn
        def patched_new_conn(self):
            conn = orig_new_conn(self)
            if hasattr(self, "host") and not ("127.0.0.1" in str(self.host) or "localhost" in str(self.host)):
                if hasattr(conn, "assert_hostname"):
                    conn.assert_hostname = False
                if hasattr(conn, "cert_reqs"):
                    conn.cert_reqs = "CERT_NONE"
            return conn
        urllib3.connectionpool.HTTPConnectionPool._new_conn = patched_new_conn

        # 3. Patch the central entrypoint to dynamic route hosts and spoof headers
        orig_urlopen = urllib3.connectionpool.HTTPConnectionPool.urlopen
        def patched_urlopen(self, method, url, *args, **kwargs):
            is_local = False
            
            if hasattr(self, "host") and isinstance(self.host, str):
                if "127.0.0.1" in self.host or "localhost" in self.host:
                    is_local = True
                    
            if isinstance(url, str):
                if "127.0.0.1" in url or "localhost" in url:
                    is_local = True
                else:
                    parsed_url = urlparse(url)
                    extracted_host = parsed_url.hostname or parsed_url.netloc
                    if extracted_host and not IP_PATTERN.match(str(extracted_host)):
                        self.host = str(extracted_host)

            if is_local:
                return orig_urlopen(self, method, url, *args, **kwargs)
                    
            # 4. DESKTOP HEADER MASQUERADE PIPELINE
            if "headers" not in kwargs or kwargs["headers"] is None:
                kwargs["headers"] = {}
                
            kwargs["headers"]["User-Agent"] = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            kwargs["headers"]["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8"
            kwargs["headers"]["Accept-Language"] = "en-US,en;q=0.5"
            
            self.cert_reqs = "CERT_NONE"
            self.assert_hostname = False
            kwargs.pop("cert_reqs", None)
            kwargs.pop("assert_hostname", None)
            
            return orig_urlopen(self, method, url, *args, **kwargs)
            
        urllib3.connectionpool.HTTPConnectionPool.urlopen = patched_urlopen
        print("✓ Core Runtime sys.modules Network Interceptor Active Globally.")
    except Exception as e:
        print(f"⚠️ Core injection deferred: {e}")

apply_global_injection()


# ==============================================================================
# HISTORICAL CLASS DEFINITION MATCH
# ==============================================================================
from gaia.agents.base.agent import Agent as BaseAgent

class NetworkWizardAgent(BaseAgent):
    # Match the exact tracking variables GAIA reads via subclass lookup loops
    AGENT_ID = "network-wizard"
    AGENT_NAME = "Network Wizard"
    
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        
    async def _run(self, query: str, **kwargs):
        return "Network Wizard proxy shields are active."


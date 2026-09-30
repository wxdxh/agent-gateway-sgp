# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import os
import ssl
import urllib3
import requests

# Disable insecure request warnings
urllib3.disable_warnings()

# Ensure Google APIs route through standard endpoints rather than mTLS when behind Agent Gateway
os.environ["GOOGLE_API_USE_MTLS_ENDPOINT"] = "never"
os.environ["GOOGLE_API_USE_CLIENT_CERTIFICATE"] = "false"

# Configure SSL context and HTTP clients to bypass TLS inspection validation errors
try:
    _orig_create_default_context = ssl.create_default_context
    def _custom_create_default_context(*args, **kwargs):
        ctx = _orig_create_default_context(*args, **kwargs)
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        return ctx
    ssl.create_default_context = _custom_create_default_context
    ssl._create_default_https_context = _custom_create_default_context
except Exception:
    pass

try:
    _orig_request = requests.Session.request
    def _custom_request(self, *args, **kwargs):
        kwargs["verify"] = False
        return _orig_request(self, *args, **kwargs)
    requests.Session.request = _custom_request
except Exception:
    pass

try:
    import httpx
    _orig_httpx_init = httpx.Client.__init__
    def _custom_httpx_init(self, *args, **kwargs):
        kwargs["verify"] = False
        _orig_httpx_init(self, *args, **kwargs)
    httpx.Client.__init__ = _custom_httpx_init

    _orig_async_httpx_init = httpx.AsyncClient.__init__
    def _custom_async_httpx_init(self, *args, **kwargs):
        kwargs["verify"] = False
        _orig_async_httpx_init(self, *args, **kwargs)
    httpx.AsyncClient.__init__ = _custom_async_httpx_init
except Exception:
    pass

from .agent import app

__all__ = ["app"]

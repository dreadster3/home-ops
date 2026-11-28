"""Strip X-DashScope-Async from DashScope/QwenCloud video poll requests.

LiteLLM (v1.110.4) hardcodes X-DashScope-Async: enable in
DashScopeVideoConfig.validate_environment, but the Qwen Cloud token-plan host
rejects that header on the task-query route (GET /api/v1/tasks/{id}) with 403
AccessDenied "current user api does not support asynchronous calls". Task
creation still requires the header, so only status/content calls are stripped.

Why not extra_headers / a pre-call hook: the video status/content handlers pass
the caller's extra_headers dict *itself* into validate_environment
(`headers=extra_headers or {}`), which mutates it in place
(`headers.update(auth_headers)`) and returns the same object. The handler's
follow-up `if extra_headers: headers.update(extra_headers)` is then a self-update
no-op, so a hook-set "disable" is clobbered straight back to "enable". Instead we
remove the header inside the poll-specific transform methods, which receive the
exact headers dict that is sent on the wire.
"""

import functools

from litellm.integrations.custom_logger import CustomLogger
from litellm.llms.dashscope.videos.transformation import DashScopeVideoConfig

_ASYNC_HEADER = "x-dashscope-async"


def _strip_async_header(method):
    @functools.wraps(method)
    def wrapper(self, *args, **kwargs):
        # Litellm calls these with keyword args; fall back to the 4th positional
        # (video_id, api_base, litellm_params, headers[, variant]).
        headers = kwargs.get("headers")
        if headers is None and len(args) >= 4:
            headers = args[3]
        if isinstance(headers, dict):
            for key in [k for k in headers if k.lower() == _ASYNC_HEADER]:
                del headers[key]
        return method(self, *args, **kwargs)

    return wrapper


# QwenCloudVideoConfig (and qwen_ai_platform) inherit both methods from
# DashScopeVideoConfig, so patching the base class covers every family provider.
# These two transforms run only for status/content retrieval, never for create,
# so task creation keeps the required X-DashScope-Async: enable.
DashScopeVideoConfig.transform_video_status_retrieve_request = _strip_async_header(
    DashScopeVideoConfig.transform_video_status_retrieve_request
)
DashScopeVideoConfig.transform_video_content_request = _strip_async_header(
    DashScopeVideoConfig.transform_video_content_request
)


class VideoPollHeaders(CustomLogger):
    """Kept so litellm_settings.callbacks can resolve video_poll_headers.video_poll_headers.

    The header fix happens at import time above, not in a call hook.
    """


video_poll_headers = VideoPollHeaders()

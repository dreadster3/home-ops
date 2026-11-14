"""Override the async header on DashScope video poll requests.

LiteLLM (through v1.109.0) hardcodes X-DashScope-Async: enable on every
video request, but the Qwen Cloud token-plan host rejects that header on
the task-query route (GET /api/v1/tasks/{id}) with 403 AccessDenied
"current user api does not support asynchronous calls". Task creation
still requires the header, so only status/content calls are overridden.
"""

from litellm.integrations.custom_logger import CustomLogger

_POLL_CALL_TYPES = frozenset(
    {
        "avideo_status",
        "video_status",
        "avideo_retrieve",
        "video_retrieve",
        "avideo_content",
        "video_content",
    }
)


class VideoPollHeaders(CustomLogger):
    async def async_pre_call_hook(self, user_api_key_dict, cache, data, call_type):
        if call_type in _POLL_CALL_TYPES:
            headers = dict(data.get("extra_headers") or {})
            headers["X-DashScope-Async"] = "disable"
            data["extra_headers"] = headers
        return data


video_poll_headers = VideoPollHeaders()

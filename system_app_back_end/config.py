import os


def _load_dotenv() -> None:
    path = os.path.join(os.path.dirname(__file__), ".env")
    if not os.path.isfile(path):
        return
    with open(path, encoding="utf-8") as env_file:
        for line in env_file:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            key = key.strip()
            if key.lower().startswith("export "):
                key = key[7:].strip()
            value = value.strip().strip('"').strip("'")
            if not key or not value:
                continue
            os.environ.setdefault(key, value)


_load_dotenv()

DATABASE_URL = os.environ.get(
    "DATABASE_URL",
    "postgresql://tsoof_meow:fEvshaefJ94L4VpNtTckNwbDAdyxxU94@dpg-d8jafem7r5hc73dmip10-a/system_app_db_9a0q",
)

if DATABASE_URL.startswith("postgres://"):
    DATABASE_URL = DATABASE_URL.replace("postgres://", "postgresql://", 1)

_BASE_DIR = os.path.dirname(os.path.abspath(__file__))


def resolve_upload_folder() -> str:
    """Pick a writable uploads directory (Render disk, env override, or local ./uploads)."""
    configured = os.environ.get("UPLOAD_FOLDER")
    if configured:
        return os.path.abspath(configured)
    if os.path.isdir("/var/data"):
        return "/var/data/uploads"
    return os.path.join(_BASE_DIR, "uploads")


UPLOAD_FOLDER = resolve_upload_folder()


def openai_api_key():
    """Live env lookup — import-time snapshots miss vars Render injects later.

    Dashboard env vars are preferred. A Secret File named OPENAI_API_KEY is
    also accepted; those are files, not `os.environ` entries.
    """
    raw = (os.environ.get("OPENAI_API_KEY") or "").strip().strip('"').strip("'")
    if raw:
        return raw
    file_path = (os.environ.get("OPENAI_API_KEY_FILE") or "").strip()
    if not file_path:
        for candidate in (
            "/etc/secrets/OPENAI_API_KEY",
            "/etc/secrets/openai_api_key",
        ):
            if os.path.isfile(candidate):
                file_path = candidate
                break
    if file_path and os.path.isfile(file_path):
        with open(file_path, encoding="utf-8") as handle:
            raw = handle.read().strip().strip('"').strip("'")
        if raw:
            return raw
    return None


OPENAI_API_KEY = openai_api_key()
OPENAI_MODEL = os.environ.get("OPENAI_MODEL", "gpt-5.6")
# How hard the agent thinks between tool calls. "low" is the documented setting
# for tool use and planning that still has to feel interactive.
OPENAI_REASONING_EFFORT = os.environ.get("OPENAI_REASONING_EFFORT", "low")
OPENAI_IMAGE_MODEL = os.environ.get("OPENAI_IMAGE_MODEL", "gpt-image-2")
OPENAI_PROCESS_UPDATE_TEMPERATURE = float(
    os.environ.get("OPENAI_PROCESS_UPDATE_TEMPERATURE", "0.5")
)

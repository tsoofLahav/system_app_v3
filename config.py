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
            value = value.strip().strip('"').strip("'")
            os.environ.setdefault(key, value)


_load_dotenv()

DATABASE_URL = os.environ.get(
    "DATABASE_URL",
    "postgresql://tsoof_meow:fEvshaefJ94L4VpNtTckNwbDAdyxxU94@dpg-d8jafem7r5hc73dmip10-a/system_app_db_9a0q",
)

if DATABASE_URL.startswith("postgres://"):
    DATABASE_URL = DATABASE_URL.replace("postgres://", "postgresql://", 1)

UPLOAD_FOLDER = os.environ.get("UPLOAD_FOLDER", "/var/data/uploads")

OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY")
OPENAI_MODEL = os.environ.get("OPENAI_MODEL", "gpt-4o")
OPENAI_IMAGE_MODEL = os.environ.get("OPENAI_IMAGE_MODEL", "dall-e-3")
OPENAI_PROCESS_UPDATE_TEMPERATURE = float(
    os.environ.get("OPENAI_PROCESS_UPDATE_TEMPERATURE", "0.5")
)

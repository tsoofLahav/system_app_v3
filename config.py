import os

DATABASE_URL = os.environ.get(
    "DATABASE_URL",
    "postgresql://tsoof_meow:fEvshaefJ94L4VpNtTckNwbDAdyxxU94@dpg-d8jafem7r5hc73dmip10-a/system_app_db_9a0q",
)

if DATABASE_URL.startswith("postgres://"):
    DATABASE_URL = DATABASE_URL.replace("postgres://", "postgresql://", 1)

UPLOAD_FOLDER = os.environ.get("UPLOAD_FOLDER", "/var/data/uploads")

from models import File, FileVersion, db


def save_file_version(file: File, *, source: str) -> FileVersion:
    version = FileVersion(
        file_id=file.id,
        body=file.body or "",
        source=source,
    )
    db.session.add(version)
    return version

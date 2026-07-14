"""Default blocks inserted below a part header per file type."""

PART_PLACEMENT_FILE_TYPES = frozenset({"plan", "execution", "tasks", "log"})


def part_default_block_specs(file_type: str) -> list[tuple[str, dict]]:
    if file_type == "plan":
        return [
            (
                "list",
                {
                    "items": [{"text": ""}],
                    "list_style": "bullet",
                },
            ),
        ]
    if file_type == "execution":
        return [
            ("text", {"text": ""}),
            (
                "list",
                {
                    "items": [{"text": ""}],
                    "list_style": "bullet",
                },
            ),
        ]
    if file_type == "tasks":
        return []
    if file_type == "log":
        return [("text", {"text": ""})]
    return []

"""Prepare an additive social schema alongside an exported private-store schema."""

import argparse
import re
from pathlib import Path


def prepare(existing: str, social: str) -> str:
    if not re.search(r"\bDEFINE\s+SCHEMA\b", existing):
        raise ValueError("The existing schema must be an unmodified CloudKit schema export.")
    if re.search(r"\bRECORD\s+TYPE\s+WW\w+", existing) or re.search(r"\bCREATE\s+ROLE\s+Moderator\b", existing):
        raise ValueError("Social types or the Moderator role already exist. Review the exported schema and changes manually.")
    if re.search(r'GRANT\s+(?:WRITE|CREATE)(?:\s*,\s*\w+)*\s+TO\s+"_world"', social, re.IGNORECASE):
        raise ValueError("World write/create permissions are not permitted.")
    types = set(re.findall(r"RECORD\s+TYPE\s+(\w+)", social))
    if types != {"WWProfile", "WWList", "WWFollow", "WWLike", "WWReport"}:
        raise ValueError("The social fragment has unexpected record types.")
    body = re.sub(r"^\s*DEFINE\s+SCHEMA\s*", "", social, count=1)
    # Preserve the complete export, including private SwiftData types, fields, roles, and indexes.
    return existing.rstrip() + "\n\n" + body.rstrip() + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("existing", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    if args.existing.resolve() == args.output.resolve():
        parser.error("Keep the existing export intact; choose a different output path.")
    fragment = Path(__file__).with_name("social.ckdb").read_text()
    try:
        merged = prepare(args.existing.read_text(), fragment)
        if args.output.exists() and args.output.read_text() != merged:
            raise ValueError("The output already exists with different contents. Choose a new review file.")
        args.output.write_text(merged)
    except (OSError, ValueError) as error:
        parser.error(str(error))
    print(f"Prepared {args.output}. Validate and review it before importing. No remote schema was changed.")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Append a DataSuite audit row to Google Sheets through OAuth.

This script uses only Python stdlib and Google Sheets REST endpoints. It does
not automate Chrome or Google Sheets UI.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from typing import Any


DEFAULT_COLUMNS = [
    "timestamp",
    "action",
    "asset_id",
    "asset_name",
    "sql",
    "execution_id",
    "task_id",
    "adhoc_code",
    "status",
    "row_count",
    "result_preview",
    "datasuite_log_url",
    "presto_history_url",
    "note",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Append one audit row to a Google Sheet using OAuth."
    )
    parser.add_argument("--spreadsheet-id", default=os.getenv("GSHEET_SPREADSHEET_ID"))
    parser.add_argument("--spreadsheet-url", default=os.getenv("GSHEET_SPREADSHEET_URL"))
    parser.add_argument("--sheet-name", default=os.getenv("GSHEET_SHEET_NAME", "ds_studio_log"))
    parser.add_argument("--oauth-json", default=os.getenv("GSHEET_OAUTH_JSON"))
    parser.add_argument("--access-token", default=os.getenv("GSHEET_ACCESS_TOKEN"))
    parser.add_argument("--row-json", help="Audit row as a JSON object.")
    parser.add_argument("--row-json-file", help="Path to a JSON object containing the audit row.")
    parser.add_argument("--row-tsv", help="Audit row as one TSV line using the standard columns.")
    parser.add_argument("--row-tsv-file", help="Path to a one-line TSV row.")
    parser.add_argument(
        "--columns",
        default=os.getenv("GSHEET_AUDIT_COLUMNS"),
        help="Optional comma-separated column order. Defaults to the standard DataSuite audit columns.",
    )
    parser.add_argument("--dry-run", action="store_true", help="Print the row payload without calling Sheets.")
    parser.add_argument(
        "--no-create-sheet",
        action="store_true",
        help="Fail if the target sheet tab does not exist instead of creating it.",
    )
    return parser.parse_args()


def die(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(1)


def extract_spreadsheet_id(url_or_id: str | None) -> str | None:
    if not url_or_id:
        return None
    match = re.search(r"/spreadsheets/d/([a-zA-Z0-9-_]+)", url_or_id)
    if match:
        return match.group(1)
    if re.fullmatch(r"[a-zA-Z0-9-_]+", url_or_id):
        return url_or_id
    return None


def api_request(
    method: str,
    url: str,
    access_token: str,
    body: dict[str, Any] | None = None,
) -> dict[str, Any]:
    headers = {"Authorization": f"Bearer {access_token}"}
    data = None
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            text = resp.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        details = exc.read().decode("utf-8", errors="replace")
        die(f"Google API {method} failed with HTTP {exc.code}: {details}")
    if not text:
        return {}
    return json.loads(text)


def oauth_token_request(body: dict[str, str]) -> dict[str, Any]:
    data = urllib.parse.urlencode(body).encode("utf-8")
    req = urllib.request.Request(
        "https://oauth2.googleapis.com/token",
        data=data,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        details = exc.read().decode("utf-8", errors="replace")
        die(f"OAuth token refresh failed with HTTP {exc.code}: {details}")


def load_access_token(args: argparse.Namespace) -> str:
    if args.access_token:
        return args.access_token
    if not args.oauth_json:
        die("provide --oauth-json or GSHEET_OAUTH_JSON, or --access-token / GSHEET_ACCESS_TOKEN")

    with open(args.oauth_json, "r", encoding="utf-8") as fh:
        cred = json.load(fh)

    if cred.get("type") == "authorized_user":
        required = ["client_id", "client_secret", "refresh_token"]
        missing = [key for key in required if not cred.get(key)]
        if missing:
            die(f"authorized_user OAuth JSON missing: {', '.join(missing)}")
        token = oauth_token_request(
            {
                "client_id": cred["client_id"],
                "client_secret": cred["client_secret"],
                "refresh_token": cred["refresh_token"],
                "grant_type": "refresh_token",
            }
        )
        if not token.get("access_token"):
            die("OAuth refresh response did not contain access_token")
        return token["access_token"]

    if cred.get("access_token"):
        return cred["access_token"]

    die("unsupported OAuth JSON; expected authorized_user JSON or JSON with access_token")


def ensure_sheet_tab(spreadsheet_id: str, sheet_name: str, access_token: str, create: bool) -> None:
    url = (
        f"https://sheets.googleapis.com/v4/spreadsheets/{spreadsheet_id}?"
        + urllib.parse.urlencode({"fields": "sheets.properties.title"})
    )
    meta = api_request("GET", url, access_token)
    titles = [s.get("properties", {}).get("title") for s in meta.get("sheets", [])]
    if sheet_name in titles:
        return
    if not create:
        die(f"sheet tab does not exist: {sheet_name}")
    batch_url = f"https://sheets.googleapis.com/v4/spreadsheets/{spreadsheet_id}:batchUpdate"
    api_request(
        "POST",
        batch_url,
        access_token,
        {"requests": [{"addSheet": {"properties": {"title": sheet_name}}}]},
    )


def quote_sheet_name(name: str) -> str:
    return "'" + name.replace("'", "''") + "'"


def col_letter(index: int) -> str:
    if index < 1:
        die("column index must be >= 1")
    out = ""
    while index:
        index, rem = divmod(index - 1, 26)
        out = chr(ord("A") + rem) + out
    return out


def load_row(args: argparse.Namespace, columns: list[str]) -> dict[str, Any]:
    sources = [
        bool(args.row_json),
        bool(args.row_json_file),
        bool(args.row_tsv),
        bool(args.row_tsv_file),
    ]
    if sum(sources) != 1:
        die("provide exactly one of --row-json, --row-json-file, --row-tsv, --row-tsv-file")

    if args.row_json:
        row = json.loads(args.row_json)
    elif args.row_json_file:
        with open(args.row_json_file, "r", encoding="utf-8") as fh:
            row = json.load(fh)
    else:
        if args.row_tsv_file:
            with open(args.row_tsv_file, "r", encoding="utf-8", newline="") as fh:
                line = fh.readline().rstrip("\n")
        else:
            line = args.row_tsv
        values = next(csv.reader([line], delimiter="\t"))
        row = {col: values[idx] if idx < len(values) else "" for idx, col in enumerate(columns)}

    if not isinstance(row, dict):
        die("row payload must be a JSON object or one TSV row")
    row.setdefault("timestamp", dt.datetime.now(dt.timezone.utc).astimezone().isoformat(timespec="seconds"))
    return row


def main() -> None:
    args = parse_args()
    spreadsheet_id = args.spreadsheet_id or extract_spreadsheet_id(args.spreadsheet_url)
    if not spreadsheet_id:
        die("provide --spreadsheet-id / GSHEET_SPREADSHEET_ID or --spreadsheet-url / GSHEET_SPREADSHEET_URL")

    columns = [c.strip() for c in args.columns.split(",")] if args.columns else DEFAULT_COLUMNS
    columns = [c for c in columns if c]
    row = load_row(args, columns)
    values = [[str(row.get(col, "")) for col in columns]]

    if args.dry_run:
        print(
            json.dumps(
                {
                    "spreadsheetId": spreadsheet_id,
                    "sheetName": args.sheet_name,
                    "columns": columns,
                    "values": values,
                },
                ensure_ascii=False,
                indent=2,
            )
        )
        return

    token = load_access_token(args)
    ensure_sheet_tab(spreadsheet_id, args.sheet_name, token, create=not args.no_create_sheet)
    base = f"https://sheets.googleapis.com/v4/spreadsheets/{spreadsheet_id}/values"
    sheet = quote_sheet_name(args.sheet_name)
    last_col = col_letter(len(columns))

    header_range = urllib.parse.quote(f"{sheet}!A1:{last_col}1", safe="")
    header_url = f"{base}/{header_range}"
    header = api_request("GET", header_url, token)
    existing = header.get("values", [])
    if not existing:
        api_request(
            "PUT",
            header_url + "?valueInputOption=RAW",
            token,
            {"majorDimension": "ROWS", "values": [columns]},
        )

    append_range = urllib.parse.quote(f"{sheet}!A:{last_col}", safe="")
    append_url = (
        f"{base}/{append_range}:append?"
        + urllib.parse.urlencode({"valueInputOption": "RAW", "insertDataOption": "INSERT_ROWS"})
    )
    result = api_request(
        "POST",
        append_url,
        token,
        {"majorDimension": "ROWS", "values": values},
    )
    print(json.dumps({"ok": True, "updates": result.get("updates", result)}, ensure_ascii=False))


if __name__ == "__main__":
    main()

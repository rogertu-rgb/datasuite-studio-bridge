# Google Sheets Audit Append

Use `scripts/append_gsheet_audit.py` when a DataSuite operation should be recorded in a Google Sheet through OAuth and the Google Sheets API.

## Required Inputs

- Spreadsheet ID or URL:
  - `GSHEET_SPREADSHEET_ID`
  - `GSHEET_SPREADSHEET_URL`
  - `--spreadsheet-id`
  - `--spreadsheet-url`
- Sheet tab name:
  - `GSHEET_SHEET_NAME`
  - `--sheet-name`
  - default: `ds_studio_log`
- OAuth credential:
  - `GSHEET_OAUTH_JSON` / `--oauth-json`
  - or `GSHEET_ACCESS_TOKEN` / `--access-token`

The OAuth JSON should be an authorized-user JSON with:

```json
{
  "type": "authorized_user",
  "client_id": "...",
  "client_secret": "...",
  "refresh_token": "..."
}
```

Do not paste OAuth token values into chat. Keep them in a local file or environment variable.

## Standard Columns

```text
timestamp
action
asset_id
asset_name
sql
execution_id
task_id
adhoc_code
status
row_count
result_preview
datasuite_log_url
presto_history_url
note
```

## Dry Run

```bash
./datasuite-studio-bridge/scripts/append_gsheet_audit.py \
  --spreadsheet-id dummy \
  --sheet-name ds_studio_log \
  --row-json '{"action":"run_sql","asset_id":"11872628","sql":"select 3;"}' \
  --dry-run
```

## Real Append

```bash
GSHEET_OAUTH_JSON=/path/to/oauth.json \
GSHEET_SPREADSHEET_URL='https://docs.google.com/spreadsheets/d/<id>/edit' \
GSHEET_SHEET_NAME=ds_studio_log \
./datasuite-studio-bridge/scripts/append_gsheet_audit.py \
  --row-json-file /path/to/audit-row.json
```

The script calls:

- `POST https://oauth2.googleapis.com/token`
- `GET https://sheets.googleapis.com/v4/spreadsheets/{spreadsheetId}`
- `POST https://sheets.googleapis.com/v4/spreadsheets/{spreadsheetId}:batchUpdate` when the target tab is missing
- `GET/PUT/POST https://sheets.googleapis.com/v4/spreadsheets/{spreadsheetId}/values/...`

It does not automate Chrome or Google Sheets UI.

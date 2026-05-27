---
name: datasuite-studio-bridge
description: "Fast DataSuite-style Data Studio automation through the authenticated Chrome page and Data Studio APIs. Use when Codex needs to control datasuite.example.com/studio without slow Computer Use mouse actions: create temp query tabs, save SQL to Data Studio tasks, run adhoc SQL, stop executions, find Studio tasks, enter Scheduler for manual/scheduled/workflow tasks, check/open Backfill for scheduled/workflow tasks, configure Data Output Setting or Properties Setting, fetch logs/results/links, or keep an audit trail of Data Studio actions."
---

# DataSuite Studio Bridge

## Overview

Use the authenticated Chrome Data Studio tab as a bridge for Data Studio actions. Prefer direct Data Studio APIs for save/run/log/result/stop, and use bridge-clicks for UI-only actions such as pressing the `+` temp-query button, entering Scheduler, and editing output/property settings when exact APIs have not yet been captured.

Do not use Computer Use for Data Studio page control unless the bridge/API path is blocked and the user accepts a fallback.

## Core Rules

- Use the existing Chrome tab at `https://datasuite.example.com/studio`; do not paste DataSuite URLs into the address bar.
- Run JavaScript with the existing bridge script:
  `./scripts/chrome-js-bridge.sh`
- Prefer `--tab-index <window.tab>` after listing tabs; fall back to `--url-contains datasuite.example.com/studio`.
- For write APIs, include headers copied from the page convention:
  `Content-Type: application/json`, `studio-project-code: example_project`, `hadoop-account: example.user`, and `X-CSRF-TOKEN` from the `CSRF-TOKEN` cookie.
- Treat run, stop, save, submit-to-scheduler, trigger, rerun, kill, and release actions as state-changing. Keep scope explicit and log what was done.
- Treat output creation, output status toggle, output deletion, marker parsing/deletion, property saves, and scheduler submission as state-changing. Require explicit user intent, use `DS_CONFIRM=1` for script commands that change UI state, and audit the final action.
- Never claim that front-end editor display proves execution. Use Data Studio history/log/result APIs as source of truth.

## Standard SQL Workflow

1. Find or create a temp query tab.
2. Save the SQL into the tab using `/datastudio/api/v1/file/save`.
3. Run the same SQL using `/datastudio/api/v1/execution/adhoc/submit`.
4. Poll `/datastudio/api/v1/execution/adhoc/log`.
5. Fetch `/datastudio/api/v1/execution/adhoc/result/v2`.
6. Report `assetId`, `executionId`, `taskId`, `adhocCode`, status, row count, result preview, and links.
7. Append an audit record when running a real user task.

Use `scripts/ds_studio_bridge.sh` for repeatable actions.

```bash
SKILL=./datasuite-studio-bridge

# Save SQL text to a Data Studio asset.
printf 'select 3;' > /tmp/query.sql
$SKILL/scripts/ds_studio_bridge.sh save-sql 11872628 /tmp/query.sql

# Run SQL and get an executionId.
$SKILL/scripts/ds_studio_bridge.sh run-sql 11872628 /tmp/query.sql

# Fetch log/result by executionId.
$SKILL/scripts/ds_studio_bridge.sh log 71887183
$SKILL/scripts/ds_studio_bridge.sh result 71887183
```

For Scheduler/output/property controls, inspect visible controls before acting:

```bash
$SKILL/scripts/ds_studio_bridge.sh inspect-ui output
$SKILL/scripts/ds_studio_bridge.sh open-settings output
$SKILL/scripts/ds_studio_bridge.sh open-settings properties
```

## Creating A Temp Query

To create a new adhoc query tab, click the Data Studio `+` button through the bridge rather than using mouse automation:

```bash
$SKILL/scripts/ds_studio_bridge.sh create-temp
```

Then list temp tabs and use the newest `assetId`:

```bash
$SKILL/scripts/ds_studio_bridge.sh temp-tabs
```

Validated behavior: creating `Temp_Query_3` produced `assetId=11872628`.

## Saving SQL

Saving via API is more stable than typing into Monaco. Use `/file/detail` to read the current task payload, then POST `/file/save` with:

- `content: <sql>`
- `parameter: detail.parameters.user || []`
- omit `parameters`

This persists the page/file state. Verify with `/file/detail` and check `data.content`.

Important: Directly setting a textarea can update the visible text without updating Monaco's model or Data Studio's saved `content`. Prefer API save for automation.

## Running SQL

Submit with `/execution/adhoc/submit` using a payload like:

```json
{
  "assetId": 11872628,
  "codeContent": "select 3;",
  "selectedCode": "select 3;",
  "selectedRange": null,
  "parameter": [],
  "needLimit": true,
  "limit": 2000,
  "idcRegion": "SG",
  "executionEngineType": 23,
  "sparkSQLConfig": {},
  "preTaskCommand": [],
  "postTaskCommand": []
}
```

Optionally call `/execution/adhoc/cr/needRuleCheck` first. It should return `data:false` when no rule validation is needed.

Validated run examples:

- `select 1;` on `Temp_Query_3` returned `_col0=1`, `executionId=71885346`.
- `select 3;` on `Temp_Query_3` returned `_col0=3`, `executionId=71887183`.

## Execution Log And Result

Fetch execution logs with:

```text
GET /datastudio/api/v1/execution/adhoc/log?offset=0&sqlIndex=0&executionId=<executionId>
```

Useful fields:

- `data.status`: `20` means success in observed adhoc runs.
- `data.hasResult`: result availability.
- `data.logEnd`: whether the log has reached `<exec-log-eof>`.
- `data.readLogLength`: next offset when incremental polling is needed.
- `data.adhocCode`: build the DataSuite adhoc log URL.
- `data.logContent`: contains Presto query id, history server URL, row count, and execution summary.

Fetch result data with:

```text
GET /datastudio/api/v1/execution/adhoc/result/v2?executionId=<executionId>&limit=2000&sqlIndex=0
```

Useful fields:

- `data.header`
- `data.columnTypes`
- `data.body`
- `data.count`
- `data.taskId`
- `data.sql`
- `data.adhocCode`
- `data.idcRegion`

Construct links:

```text
DataSuite adhoc log:
https://datasuite.example.com/scheduler/dev/adhoc/<adhocCode>/log

Presto history:
Extract the "Presto History Server URL" from logContent.
```

When reporting to the user, include:

```text
executionId
taskId
adhocCode
status
row count
short result preview
DataSuite log link
Presto history link if present
```

## Stopping SQL

Stop only execution IDs started by the current task unless the user explicitly allows broader action.

```text
POST /datastudio/api/v1/batchKill
body: {"executionIds":[<executionId>]}
```

Validated behavior: stopping test execution `71884758` returned success and changed log status to `15`.

## Finding Tasks

Read task trees and filter locally:

```text
Scheduled Tasks:
GET /datastudio/api/v1/asset/trees?projectCode=example_project&rootTypes=2

Manual Tasks:
GET /datastudio/api/v1/asset/trees?projectCode=example_project&rootTypes=3
```

For `example_manual_task`, observed result:

```text
assetId: 9877176
assetName: example_manual_task
assetType: 23
owner: example.user
path: Manual Tasks/example.user/path/to/example_task
scheduleTaskCode: example_project.studio_9877176
submittedToProduction: true
```

## Scheduler Entry

Scheduler entry depends on asset type:

- Adhoc/temp query tabs do not have Scheduler pages.
- Manual tasks, scheduled tasks, and workflow tasks can enter Scheduler.
- Default environment is `prod`; use `staging` or `dev` only when the user explicitly asks.

To enter Scheduler from the active Data Studio task tab, compute the Scheduler URL and open it through the Chrome bridge.

```bash
$SKILL/scripts/ds_studio_bridge.sh scheduler-url
$SKILL/scripts/ds_studio_bridge.sh enter-scheduler
```

If a task code or asset ID is already known, navigate directly to Scheduler. The optional environment is `prod`, `staging`, or `dev`; use `prod` unless the user explicitly asks otherwise.

```bash
$SKILL/scripts/ds_studio_bridge.sh enter-scheduler example_project.studio_9877176 manual
$SKILL/scripts/ds_studio_bridge.sh enter-scheduler 9877176 manual
$SKILL/scripts/ds_studio_bridge.sh enter-scheduler example_project.studio_5383431 scheduled prod
$SKILL/scripts/ds_studio_bridge.sh enter-scheduler example_project_5936046 workflow prod
$SKILL/scripts/ds_studio_bridge.sh enter-scheduler example_project.studio_5383431 scheduled staging
$SKILL/scripts/ds_studio_bridge.sh enter-scheduler example_project.studio_5383431 scheduled dev
```

Observed environment URL prefixes:

```text
prod:    /scheduler
staging: /scheduler/uat
dev:     /scheduler/dev
```

Observed task URL patterns:

```text
Scheduled task:
https://datasuite.example.com/scheduler[/env-prefix]/task/<taskCode>/matrix?project_code=example_project

Manual task:
https://datasuite.example.com/scheduler[/env-prefix]/task/manual/<taskCode>/matrix?project_code=example_project

Workflow:
https://datasuite.example.com/scheduler[/env-prefix]/workflow/<workflowCode>/matrix?project_code=example_project
```

After opening Scheduler, point generic bridge commands at the Scheduler tab:

```bash
export DS_URL_CONTAINS='datasuite.example.com/scheduler'
$SKILL/scripts/ds_studio_bridge.sh inspect-ui 'Output Config'
$SKILL/scripts/ds_studio_bridge.sh click-text 'Output Config' '.ant-tabs-tab'
$SKILL/scripts/ds_studio_bridge.sh inspect-ui 'Operate'
```

Backfill rule:

- Scheduled task Scheduler pages can have Backfill.
- Workflow Scheduler pages can have Backfill.
- Manual task Scheduler pages do not have Backfill.

Check or open Backfill on a Scheduler page:

```bash
export DS_URL_CONTAINS='datasuite.example.com/scheduler'
$SKILL/scripts/ds_studio_bridge.sh scheduler-backfill check
$SKILL/scripts/ds_studio_bridge.sh scheduler-backfill open
```

Validated example: active Data Studio task `example_scheduled_task` resolved to PROD Scheduler URL:

```text
https://datasuite.example.com/scheduler/task/example_project.studio_5383431/matrix?project_code=example_project
```

## Output Settings

Use the Data Output Setting panel for adding/editing output tasks such as Google Sheet or CSV outputs.

Start with inspection:

```bash
$SKILL/scripts/ds_studio_bridge.sh open-settings output
$SKILL/scripts/ds_studio_bridge.sh inspect-ui output
```

Add a draft output config:

```bash
DS_CONFIRM=1 $SKILL/scripts/ds_studio_bridge.sh output-new gsheet
DS_CONFIRM=1 $SKILL/scripts/ds_studio_bridge.sh output-new csv
```

After the output config form opens, inspect it and fill fields by label:

```bash
$SKILL/scripts/ds_studio_bridge.sh inspect-ui
$SKILL/scripts/ds_studio_bridge.sh set-field-by-label 'Output name' 'seller_review_output'
$SKILL/scripts/ds_studio_bridge.sh set-field-by-label 'Google Sheet URL' 'https://docs.google.com/spreadsheets/d/.../edit'
```

For existing output tasks, select the output row/checkbox first, then toggle or delete:

```bash
DS_CONFIRM=1 $SKILL/scripts/ds_studio_bridge.sh output-action turn-off
DS_CONFIRM=1 $SKILL/scripts/ds_studio_bridge.sh output-action turn-on
DS_CONFIRM=1 $SKILL/scripts/ds_studio_bridge.sh output-action delete
```

Observed Add New Output modal: destination options are `Google Sheet` and `CSV`; radio values observed in the DOM were Google Sheet=`3` and CSV=`1`.

## Property Settings

Use the Properties Setting panel for output markers, input markers, frequency, run time, and repetition.

```bash
$SKILL/scripts/ds_studio_bridge.sh open-settings properties
$SKILL/scripts/ds_studio_bridge.sh inspect-ui frequency
```

Common bridge actions:

```bash
$SKILL/scripts/ds_studio_bridge.sh select-by-label 'Frequency' 'DAILY'
$SKILL/scripts/ds_studio_bridge.sh set-field-by-label 'Run at' '00:01'
$SKILL/scripts/ds_studio_bridge.sh set-field-by-label 'Repeat On' 'Everyday'
DS_CONFIRM=1 $SKILL/scripts/ds_studio_bridge.sh click-text 'Auto Parse'
DS_CONFIRM=1 $SKILL/scripts/ds_studio_bridge.sh click-text 'Delete Markers'
DS_CONFIRM=1 $SKILL/scripts/ds_studio_bridge.sh click-text 'Add Partitions'
```

Known sections include Task Information, Schedule, Dependencies & Input Marker, Output Markers, Execution Settings, Alarm and Time Out Settings, Email Upon Successful Completion, and Data Quality Check.

Before saving/submitting property changes, inspect the final page state and summarize the exact fields changed.

## Audit Log

For non-trivial runs, write a local TSV audit log under the workspace, for example:

```text
ds_audit/ds_studio_bridge_log.tsv
```

Include:

```text
timestamp	action	asset_id	asset_name	sql	execution_id	task_id	adhoc_code	status	row_count	result_preview	datasuite_log_url	presto_history_url	note
```

If the user configures Google Sheets OAuth, also append the same row to Google Sheets through the Sheets API. Do not use Chrome, clipboard, Computer Use, or the old Google Sheets UI paste script for this.

Use `scripts/append_gsheet_audit.py`:

```bash
SKILL=./datasuite-studio-bridge

export GSHEET_OAUTH_JSON=/path/to/oauth_authorized_user.json
export GSHEET_SPREADSHEET_ID=your_spreadsheet_id
export GSHEET_SHEET_NAME=ds_studio_log

$SKILL/scripts/append_gsheet_audit.py \
  --row-json '{"action":"run_sql","asset_id":"11872628","sql":"select 3;","execution_id":"71887183","status":"20","row_count":"1","result_preview":"_col0=3"}'
```

Supported auth inputs:

- `GSHEET_OAUTH_JSON` / `--oauth-json`: authorized-user OAuth JSON with `client_id`, `client_secret`, and `refresh_token`.
- `GSHEET_ACCESS_TOKEN` / `--access-token`: already refreshed OAuth bearer token.

The script creates the target sheet tab if missing, checks whether the header row exists and creates it when the tab is empty, then appends one row with `valueInputOption=RAW`.

Summarize the audit record in the final answer so the user knows exactly what was done in DS.

## Reference

Read `references/api-notes.md` when modifying API payloads, troubleshooting authentication, or adding new commands to the script.

Read `references/google-sheets-audit.md` when configuring or troubleshooting Google Sheets OAuth audit logging.

Read `references/scheduler-output-property.md` when entering Scheduler or configuring Data Output Setting / Properties Setting.

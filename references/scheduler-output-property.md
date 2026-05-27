# Scheduler, Output, And Property Settings

Use these notes when controlling Data Studio Scheduler, Data Output Setting, or Properties Setting through the Chrome JavaScript bridge. Prefer direct Data Studio/Scheduler APIs only after capturing the exact endpoint and payload. Until then, use the bridge UI commands in `scripts/ds_studio_bridge.sh`.

## Bridge Commands

```bash
SKILL=./datasuite-studio-bridge

# Inspect visible controls, optionally filtered by keyword.
$SKILL/scripts/ds_studio_bridge.sh inspect-ui
$SKILL/scripts/ds_studio_bridge.sh inspect-ui output
$SKILL/scripts/ds_studio_bridge.sh inspect-ui frequency

# Click a visible button/tab/menu item by text.
$SKILL/scripts/ds_studio_bridge.sh click-text 'Data Output Setting'

# Open right-side settings panels.
$SKILL/scripts/ds_studio_bridge.sh open-settings properties
$SKILL/scripts/ds_studio_bridge.sh open-settings output

# Fill or select controls near a visible label.
$SKILL/scripts/ds_studio_bridge.sh set-field-by-label 'Output name' 'my_output'
$SKILL/scripts/ds_studio_bridge.sh set-field-by-label 'Google Sheet URL' 'https://docs.google.com/spreadsheets/d/.../edit'
$SKILL/scripts/ds_studio_bridge.sh select-by-label 'Frequency' 'DAILY'
$SKILL/scripts/ds_studio_bridge.sh toggle-by-label 'Auto Retry' on
```

State-changing UI clicks require explicit confirmation:

```bash
DS_CONFIRM=1 $SKILL/scripts/ds_studio_bridge.sh output-new gsheet
DS_CONFIRM=1 $SKILL/scripts/ds_studio_bridge.sh output-action turn-off
DS_CONFIRM=1 $SKILL/scripts/ds_studio_bridge.sh output-action turn-on
DS_CONFIRM=1 $SKILL/scripts/ds_studio_bridge.sh output-action delete
DS_CONFIRM=1 $SKILL/scripts/ds_studio_bridge.sh click-text 'Auto Parse'
DS_CONFIRM=1 $SKILL/scripts/ds_studio_bridge.sh click-text 'Delete Markers'
```

## Enter Scheduler

From an open Data Studio task tab, compute the Scheduler URL or open it in a new Chrome tab. `prod` is the default environment.

Scheduler entry rules:

- Adhoc/temp query tabs do not have Scheduler pages.
- Manual tasks, scheduled tasks, and workflow tasks can enter Scheduler.
- Backfill exists only for scheduled task and workflow Scheduler pages, not manual task pages.

```bash
$SKILL/scripts/ds_studio_bridge.sh scheduler-url
$SKILL/scripts/ds_studio_bridge.sh enter-scheduler
```

When a Scheduler task code or asset ID is already known, navigate directly:

```bash
$SKILL/scripts/ds_studio_bridge.sh enter-scheduler example_project.studio_9877176 manual
$SKILL/scripts/ds_studio_bridge.sh enter-scheduler 9877176 manual
$SKILL/scripts/ds_studio_bridge.sh enter-scheduler example_project.studio_5383431 scheduled prod
$SKILL/scripts/ds_studio_bridge.sh enter-scheduler example_project_5936046 workflow prod
```

Environment URL prefixes captured from the Data Studio frontend:

```text
prod    -> /scheduler
staging -> /scheduler/uat
dev     -> /scheduler/dev
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

Observed example:

```text
https://datasuite.example.com/scheduler/task/manual/example_project.studio_9877176/matrix?project_code=example_project
```

If the Data Studio active-tab API cannot find the active tab, the script falls back to reading the visible `Task Code` from the page body and infers scheduled/manual from the visible schedule text.

For Backfill:

```bash
DS_URL_CONTAINS='scheduler/task/example_project.studio_5383431' \
  $SKILL/scripts/ds_studio_bridge.sh scheduler-backfill check

DS_URL_CONTAINS='scheduler/task/example_project.studio_5383431' \
  $SKILL/scripts/ds_studio_bridge.sh scheduler-backfill open
```

Expected results:

- `kind=scheduled` or `kind=workflow`, `available=true`: Backfill tab is available.
- `kind=manual`, `available=false`, `reason=manual_scheduler_has_no_backfill`: do not try Backfill actions.

After Scheduler is open, target the Scheduler tab for generic inspection/click commands:

```bash
DS_URL_CONTAINS='scheduler/task/example_project.studio_5383431' \
  $SKILL/scripts/ds_studio_bridge.sh inspect-ui 'Output Config'

DS_URL_CONTAINS='scheduler/task/example_project.studio_5383431' \
  $SKILL/scripts/ds_studio_bridge.sh click-text 'Output Config' '.ant-tabs-tab'
```

Validated Scheduler page signal:

```text
Prod
Scheduled Tasks/Task View
Task Code: example_project.studio_5383431
Tabs: Matrix View, List View, Lineage, Gantt Chart, Runtime Trend, Details, Code, Output Config, Operation Log, Privilege, Alarm, Backfill, SLA & DR
```

## Data Output Setting

Workflow:

1. Open a valid Data Studio SQL task tab.
2. Open output settings:
   ```bash
   $SKILL/scripts/ds_studio_bridge.sh open-settings output
   $SKILL/scripts/ds_studio_bridge.sh inspect-ui output
   ```
3. Add a draft output config:
   ```bash
   DS_CONFIRM=1 $SKILL/scripts/ds_studio_bridge.sh output-new gsheet
   ```
4. Inspect the modal/drawer fields:
   ```bash
   $SKILL/scripts/ds_studio_bridge.sh inspect-ui
   ```
5. Fill fields by visible labels, for example:
   ```bash
   $SKILL/scripts/ds_studio_bridge.sh set-field-by-label 'Output name' 'seller_review_output'
   $SKILL/scripts/ds_studio_bridge.sh set-field-by-label 'Google Sheet URL' 'https://docs.google.com/spreadsheets/d/.../edit'
   ```
6. Change output config with the same label-based setters and selectors, then inspect before saving.
7. For an existing output row, select its row/checkbox first, then:
   ```bash
   DS_CONFIRM=1 $SKILL/scripts/ds_studio_bridge.sh output-action turn-off
   DS_CONFIRM=1 $SKILL/scripts/ds_studio_bridge.sh output-action turn-on
   DS_CONFIRM=1 $SKILL/scripts/ds_studio_bridge.sh output-action delete
   ```

Observed Add New Output modal:

- Title: `New Output`
- Destination options: `Google Sheet`, `CSV`
- Radio values observed: Google Sheet=`3`, CSV=`1`
- Buttons: `Cancel`, `Add`

If Data Studio says the current task is not compatible for data output, use a task with a valid single `SELECT` statement.

## Properties Setting

Workflow:

1. Open properties:
   ```bash
   $SKILL/scripts/ds_studio_bridge.sh open-settings properties
   $SKILL/scripts/ds_studio_bridge.sh inspect-ui frequency
   ```
2. Configure schedule fields:
   ```bash
   $SKILL/scripts/ds_studio_bridge.sh select-by-label 'Frequency' 'DAILY'
   $SKILL/scripts/ds_studio_bridge.sh set-field-by-label 'Run at' '00:01'
   $SKILL/scripts/ds_studio_bridge.sh set-field-by-label 'Repeat On' 'Everyday'
   ```
3. Configure input markers and output markers:
   ```bash
   DS_CONFIRM=1 $SKILL/scripts/ds_studio_bridge.sh click-text 'Auto Parse'
   DS_CONFIRM=1 $SKILL/scripts/ds_studio_bridge.sh click-text 'Delete Markers'
   DS_CONFIRM=1 $SKILL/scripts/ds_studio_bridge.sh click-text 'Add Partitions'
   ```
4. Configure switches:
   ```bash
   $SKILL/scripts/ds_studio_bridge.sh toggle-by-label 'Auto Retry' on
   $SKILL/scripts/ds_studio_bridge.sh toggle-by-label 'Latest Only' off
   $SKILL/scripts/ds_studio_bridge.sh toggle-by-label 'Email Upon Successful Completion' off
   ```
5. Inspect the final page state and only then click Save/Submit with `DS_CONFIRM=1`.

Observed Properties Setting sections:

- Task Information
- Schedule: `Frequency`, `Run at`, `Repeat On`, `Cron Expression`
- Dependencies & Input Marker
- Output Markers
- Execution Settings: `Auto Retry`, `Retry Attempt`, `Retry Interval`, `Latest Only`
- Alarm and Time Out Settings
- Email Upon Successful Completion
- Data Quality Check

## Safety

- Treat output creation, output status toggles, output deletion, marker parsing/deletion, scheduler submission, and property saves as state-changing.
- Always run `inspect-ui` before and after changing settings.
- Record changed fields, final task code/asset ID, and any confirmation dialogs in the audit log.

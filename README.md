# datasuite-studio-bridge

Codex skill for fast browser-bridge automation of a DataSuite-style Data Studio and Scheduler web app.

The public version is sanitized: company domains, project codes, user accounts, and task IDs are examples. Configure your own environment before use.

## Configure

```bash
export DS_PROJECT_CODE=your_project_code
export DS_HADOOP_ACCOUNT=your_account
export DS_STUDIO_URL_CONTAINS='datasuite.example.com/studio'
```

For Scheduler tabs:

```bash
export DS_URL_CONTAINS='datasuite.example.com/scheduler'
```

## Examples

```bash
SKILL=/path/to/datasuite-studio-bridge

$SKILL/scripts/ds_studio_bridge.sh temp-tabs
$SKILL/scripts/ds_studio_bridge.sh save-sql 123456 /tmp/query.sql
$SKILL/scripts/ds_studio_bridge.sh run-sql 123456 /tmp/query.sql
$SKILL/scripts/ds_studio_bridge.sh scheduler-url your_project_code.studio_123456 scheduled prod
$SKILL/scripts/ds_studio_bridge.sh scheduler-backfill check
```

See [SKILL.md](SKILL.md) for the full workflow.

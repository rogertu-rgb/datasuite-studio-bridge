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

bash "$SKILL/scripts/ds_studio_bridge.sh" temp-tabs
bash "$SKILL/scripts/ds_studio_bridge.sh" save-sql 123456 /tmp/query.sql
bash "$SKILL/scripts/ds_studio_bridge.sh" run-sql 123456 /tmp/query.sql
bash "$SKILL/scripts/ds_studio_bridge.sh" scheduler-url your_project_code.studio_123456 scheduled prod
bash "$SKILL/scripts/ds_studio_bridge.sh" scheduler-backfill check
```

## Known Behavior

This bridge is intentionally optimized for authenticated browser/API actions, not for visual UI playback.

- A successful action may not visibly update the current Data Studio page. For example, saving SQL into an asset, submitting an adhoc run, or stopping an execution can complete through the authenticated page context while the editor tab still looks unchanged.
- Treat the command output and audit log as the source of truth for what Codex did. Do not rely only on the visible browser state.
- SQL execution results are usually retrieved through execution history, result APIs, or the log/result page link. The result table may not appear in the currently open editor tab.
- Log links are often more reliable than the foreground UI for debugging. Keep the returned execution ID, adhoc code, task URL, Presto/history URL, and DataSuite log URL with each action record.
- Scheduler actions can open the correct task page without proving that the current page layout has refreshed. Re-run `inspect-ui`, `scheduler-backfill check`, or fetch execution history when you need confirmation.
- State-changing actions such as output creation, output toggles, deletion, backfill, submit, stop, or property edits should be recorded in an external audit sink such as a TSV or Google Sheet.

See [SKILL.md](SKILL.md) for the full workflow.

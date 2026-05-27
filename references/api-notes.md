# DataSuite Studio Bridge API Notes

## Authenticated Request Pattern

Requests run inside the logged-in Data Studio Chrome page. For state-changing requests, use:

```javascript
function cookie(name) {
  const parts = (`; ${document.cookie}`).split(`; ${name}=`);
  return parts.length === 2 ? decodeURIComponent(parts.pop().split(";").shift()) : "";
}

function req(method, path, body) {
  const xhr = new XMLHttpRequest();
  xhr.open(method, path, false);
  xhr.withCredentials = true;
  xhr.setRequestHeader("Content-Type", "application/json");
  xhr.setRequestHeader("studio-project-code", "example_project");
  xhr.setRequestHeader("hadoop-account", "example.user");
  xhr.setRequestHeader("X-CSRF-TOKEN", cookie("CSRF-TOKEN"));
  xhr.send(body ? JSON.stringify(body) : null);
  return { status: xhr.status, text: xhr.responseText };
}
```

Common failure modes:

- `401/403` on write APIs usually means missing `X-CSRF-TOKEN`, `studio-project-code`, `hadoop-account`, or `withCredentials`.
- `parameter can not be null` on `/file/save` means include `parameter: detail.parameters.user || []` and omit the original `parameters` object.
- Empty editor UI does not mean no execution. Check `/execution/adhoc/history/list`, `/log`, and `/result/v2`.

## Save SQL Payload

Read detail:

```text
GET /datastudio/api/v1/file/detail?projectCode=example_project&assetId=<assetId>&tabOrderUpdate=false
```

Save:

```javascript
const saveBody = {
  ...detail,
  content: sql,
  parameter: detail.parameters?.user || [],
  parameters: undefined
};
req("POST", "/datastudio/api/v1/file/save", saveBody);
```

Verify with `file/detail.data.content`.

## Run SQL Payload

Use:

```javascript
{
  assetId,
  codeContent: sql,
  selectedCode: sql,
  selectedRange: null,
  parameter: [],
  needLimit: true,
  limit: 2000,
  idcRegion: "SG",
  executionEngineType: 23,
  sparkSQLConfig: {},
  preTaskCommand: [],
  postTaskCommand: []
}
```

Call:

```text
POST /datastudio/api/v1/execution/adhoc/cr/needRuleCheck
POST /datastudio/api/v1/execution/adhoc/submit
```

## History, Log, Result, Stop

History:

```text
GET /datastudio/api/v1/execution/adhoc/history/list?startTime=<YYYY-MM-DD HH:mm:ss>&endTime=<YYYY-MM-DD HH:mm:ss>&assetId=<assetId>&pageSize=20&pageNum=1
```

Log:

```text
GET /datastudio/api/v1/execution/adhoc/log?offset=<offset>&sqlIndex=0&executionId=<executionId>
```

Result:

```text
GET /datastudio/api/v1/execution/adhoc/result/v2?executionId=<executionId>&limit=2000&sqlIndex=0
```

Stop:

```text
POST /datastudio/api/v1/batchKill
{"executionIds":[<executionId>]}
```

## Link Construction

DataSuite adhoc log:

```text
https://datasuite.example.com/scheduler/dev/adhoc/<adhocCode>/log
```

Presto history:

Extract from log text:

```text
Presto History Server URL: https://historyserver.example.com/query.html?<queryId>
```

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DS_PROJECT_CODE="${DS_PROJECT_CODE:-example_project}"
DS_HADOOP_ACCOUNT="${DS_HADOOP_ACCOUNT:-example.user}"
DS_STUDIO_URL_CONTAINS="${DS_STUDIO_URL_CONTAINS:-datasuite.example.com/studio}"

BRIDGE="${DS_CHROME_BRIDGE:-$SCRIPT_DIR/chrome-js-bridge.sh}"
TAB_ARG=()
if [[ -n "${DS_TAB_INDEX:-}" ]]; then
  TAB_ARG=(--tab-index "$DS_TAB_INDEX")
else
  TAB_ARG=(--url-contains "${DS_URL_CONTAINS:-$DS_STUDIO_URL_CONTAINS}")
fi

usage() {
  cat <<'EOF'
Usage:
  ds_studio_bridge.sh create-temp
  ds_studio_bridge.sh temp-tabs
  ds_studio_bridge.sh save-sql <assetId> <sql-file>
  ds_studio_bridge.sh run-sql <assetId> <sql-file>
  ds_studio_bridge.sh log <executionId> [offset]
  ds_studio_bridge.sh result <executionId> [limit]
  ds_studio_bridge.sh stop <executionId>
  ds_studio_bridge.sh find-task <manual|scheduled|workflow> <keyword>
  ds_studio_bridge.sh inspect-ui [keyword]
  ds_studio_bridge.sh click-text <text> [selector]
  ds_studio_bridge.sh set-field-by-label <label> <value>
  ds_studio_bridge.sh select-by-label <label> <option>
  ds_studio_bridge.sh toggle-by-label <label> <on|off>
  ds_studio_bridge.sh scheduler-url [taskCode|assetId] [manual|scheduled|workflow] [prod|staging|dev]
  ds_studio_bridge.sh enter-scheduler [taskCode|assetId] [manual|scheduled|workflow] [prod|staging|dev]
  ds_studio_bridge.sh scheduler-backfill <check|open>
  ds_studio_bridge.sh open-settings <properties|parameters|version|output>
  ds_studio_bridge.sh output-new <gsheet|csv>
  ds_studio_bridge.sh output-action <turn-on|turn-off|delete>

Environment:
  DS_PROJECT_CODE        Data Studio project code. Default: example_project.
  DS_HADOOP_ACCOUNT      Hadoop/account header value. Default: example.user.
  DS_STUDIO_URL_CONTAINS URL match for Data Studio tab. Default: datasuite.example.com/studio.
  DS_TAB_INDEX           Chrome tab index such as 2.1. If unset, targets DS_STUDIO_URL_CONTAINS.
  DS_URL_CONTAINS        Override URL matching when DS_TAB_INDEX is unset, e.g. datasuite.example.com/scheduler.
  DS_CHROME_BRIDGE       Override chrome-js-bridge.sh path.
  DS_CONFIRM             Set to 1 for state-changing UI clicks such as output-new, turn-on/off, or delete.
EOF
}

json_string() {
  python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
}

run_js() {
  local js_file="$1"
  "$BRIDGE" "${TAB_ARG[@]}" --js-file "$js_file"
}

open_chrome_url() {
  local url="$1"
  osascript - "$url" <<'OSA'
on run argv
  set targetUrl to item 1 of argv
  tell application "Google Chrome"
    if (count of windows) is 0 then make new window
    set w to window 1
    set t to make new tab at end of tabs of w
    set URL of t to targetUrl
    set active tab index of w to count of tabs of w
  end tell
end run
OSA
}

make_tmp_js() {
  local dir="${TMPDIR:-/tmp}"
  mktemp "$dir/ds-studio-bridge.XXXXXX"
}

common_js='
function cookie(name) {
  const parts = (`; ${document.cookie}`).split(`; ${name}=`);
  return parts.length === 2 ? decodeURIComponent(parts.pop().split(";").shift()) : "";
}
function req(method, path, body) {
  const xhr = new XMLHttpRequest();
  xhr.open(method, path, false);
  xhr.withCredentials = true;
  xhr.setRequestHeader("Content-Type", "application/json");
  xhr.setRequestHeader("studio-project-code", "${DS_PROJECT_CODE}");
  xhr.setRequestHeader("hadoop-account", "${DS_HADOOP_ACCOUNT}");
  xhr.setRequestHeader("X-CSRF-TOKEN", cookie("CSRF-TOKEN"));
  xhr.send(body ? JSON.stringify(body) : null);
  return { status: xhr.status, text: xhr.responseText };
}
'
common_js="${common_js//\$\{DS_PROJECT_CODE\}/$DS_PROJECT_CODE}"
common_js="${common_js//\$\{DS_HADOOP_ACCOUNT\}/$DS_HADOOP_ACCOUNT}"

cmd="${1:-}"
case "$cmd" in
  create-temp)
    tmp="$(make_tmp_js)"
    trap 'rm -f "$tmp"' EXIT
    cat > "$tmp" <<JS
(() => {
  const btn = Array.from(document.querySelectorAll("button")).find(
    b => String(b.className).includes("btn-create-temp-query") &&
      !!(b.offsetWidth || b.offsetHeight || b.getClientRects().length) &&
      !b.disabled
  );
  if (!btn) return JSON.stringify({ ok: false, reason: "create temp query button not found" });
  btn.click();
  return JSON.stringify({ ok: true, action: "clicked_create_temp_query" });
})()
JS
    run_js "$tmp"
    ;;

  temp-tabs)
    tmp="$(make_tmp_js)"
    trap 'rm -f "$tmp"' EXIT
    cat > "$tmp" <<JS
(() => {
  const r = req("GET", "/datastudio/api/v1/tab/currentlyOpenV2?projectCode=${DS_PROJECT_CODE}");
  const o = JSON.parse(r.text);
  const tabs = (o.data || []).filter(t => t.assetRoot === 7 || /Temp_Query/i.test(t.assetName || ""));
  return JSON.stringify({ status: r.status, tabs });
})()
JS
    python3 - "$tmp" "$common_js" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
p.write_text(p.read_text().replace("const r = req", sys.argv[2] + "\n  const r = req"))
PY
    run_js "$tmp"
    ;;

  save-sql)
    [[ $# -eq 3 ]] || { usage >&2; exit 2; }
    asset_id="$2"
    sql_json="$(json_string < "$3")"
    tmp="$(make_tmp_js)"
    trap 'rm -f "$tmp"' EXIT
    cat > "$tmp" <<JS
(() => {
$common_js
  const assetId = $asset_id;
  const sql = $sql_json;
  const detailPath = "/datastudio/api/v1/file/detail?projectCode=${DS_PROJECT_CODE}&assetId=" + assetId + "&tabOrderUpdate=false";
  const detail = JSON.parse(req("GET", detailPath).text).data;
  const body = { ...detail, content: sql, parameter: detail.parameters?.user || [], parameters: undefined };
  const save = req("POST", "/datastudio/api/v1/file/save", body);
  const verify = JSON.parse(req("GET", detailPath).text).data;
  return JSON.stringify({ save: { status: save.status, text: save.text }, verify: { assetId, assetName: verify.assetName, content: verify.content, currentVersion: verify.currentVersion } });
})()
JS
    run_js "$tmp"
    ;;

  run-sql)
    [[ $# -eq 3 ]] || { usage >&2; exit 2; }
    asset_id="$2"
    sql_json="$(json_string < "$3")"
    tmp="$(make_tmp_js)"
    trap 'rm -f "$tmp"' EXIT
    cat > "$tmp" <<JS
(() => {
$common_js
  const sql = $sql_json;
  const body = {
    assetId: $asset_id,
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
  };
  const needRuleCheck = req("POST", "/datastudio/api/v1/execution/adhoc/cr/needRuleCheck", body);
  const submit = req("POST", "/datastudio/api/v1/execution/adhoc/submit", body);
  let executionId = null;
  try { executionId = JSON.parse(submit.text).data?.executionId || null; } catch (e) {}
  return JSON.stringify({ needRuleCheck: { status: needRuleCheck.status, text: needRuleCheck.text }, submit: { status: submit.status, text: submit.text }, executionId });
})()
JS
    run_js "$tmp"
    ;;

  log)
    [[ $# -ge 2 && $# -le 3 ]] || { usage >&2; exit 2; }
    execution_id="$2"
    offset="${3:-0}"
    tmp="$(make_tmp_js)"
    trap 'rm -f "$tmp"' EXIT
    cat > "$tmp" <<JS
(() => {
  const xhr = new XMLHttpRequest();
  xhr.open("GET", "/datastudio/api/v1/execution/adhoc/log?offset=$offset&sqlIndex=0&executionId=$execution_id", false);
  xhr.send(null);
  return xhr.responseText;
})()
JS
    run_js "$tmp"
    ;;

  result)
    [[ $# -ge 2 && $# -le 3 ]] || { usage >&2; exit 2; }
    execution_id="$2"
    limit="${3:-2000}"
    tmp="$(make_tmp_js)"
    trap 'rm -f "$tmp"' EXIT
    cat > "$tmp" <<JS
(() => {
  const xhr = new XMLHttpRequest();
  xhr.open("GET", "/datastudio/api/v1/execution/adhoc/result/v2?executionId=$execution_id&limit=$limit&sqlIndex=0", false);
  xhr.send(null);
  return xhr.responseText;
})()
JS
    run_js "$tmp"
    ;;

  stop)
    [[ $# -eq 2 ]] || { usage >&2; exit 2; }
    execution_id="$2"
    tmp="$(make_tmp_js)"
    trap 'rm -f "$tmp"' EXIT
    cat > "$tmp" <<JS
(() => {
$common_js
  const stop = req("POST", "/datastudio/api/v1/batchKill", { executionIds: [$execution_id] });
  return JSON.stringify({ stop: { status: stop.status, text: stop.text } });
})()
JS
    run_js "$tmp"
    ;;

  find-task)
    [[ $# -eq 3 ]] || { usage >&2; exit 2; }
    root="$2"
    keyword_json="$(printf '%s' "$3" | json_string)"
    case "$root" in
      scheduled) root_type=2 ;;
      manual) root_type=3 ;;
      workflow) root_type=1 ;;
      *) echo "root must be manual, scheduled, or workflow" >&2; exit 2 ;;
    esac
    tmp="$(make_tmp_js)"
    trap 'rm -f "$tmp"' EXIT
    cat > "$tmp" <<JS
(() => {
  const keyword = $keyword_json.toLowerCase();
  const xhr = new XMLHttpRequest();
  xhr.open("GET", "/datastudio/api/v1/asset/trees?projectCode=${DS_PROJECT_CODE}&rootTypes=$root_type", false);
  xhr.send(null);
  const o = JSON.parse(xhr.responseText);
  const hits = [];
  function walk(node, path) {
    const name = node.assetName || node.rootName || "";
    const next = [...path, name].filter(Boolean);
    if (name.toLowerCase().includes(keyword) || String(node.assetId || "").includes(keyword)) {
      hits.push({ assetId: node.assetId, assetName: node.assetName, assetType: node.assetType, assetStatus: node.assetStatus, userRole: node.userRole, assetOwner: node.assetOwner, path: next.join("/"), updateTime: node.updateTime });
    }
    (node.assets || []).forEach(child => walk(child, next));
  }
  (o.data || []).forEach(root => (root.assets || []).forEach(node => walk(node, ["$root"])));
  return JSON.stringify({ status: xhr.status, count: hits.length, hits: hits.slice(0, 50) });
})()
JS
    run_js "$tmp"
    ;;

  inspect-ui)
    [[ $# -le 2 ]] || { usage >&2; exit 2; }
    keyword_json="$(printf '%s' "${2:-}" | json_string)"
    tmp="$(make_tmp_js)"
    trap 'rm -f "$tmp"' EXIT
    cat > "$tmp" <<JS
(() => {
  const keyword = $keyword_json.toLowerCase();
  const visible = e => !!(e.offsetWidth || e.offsetHeight || e.getClientRects().length);
  const txt = e => (e.innerText || e.getAttribute("aria-label") || e.getAttribute("placeholder") || e.title || e.value || "").trim();
  const controls = Array.from(document.querySelectorAll("button,a,[role=button],li,[role=tab],input,textarea,.ant-select-selector,.ant-switch"))
    .filter(visible)
    .map((e, i) => ({ i, tag: e.tagName, text: txt(e).slice(0, 160), cls: String(e.className).slice(0, 160), value: e.value || "", checked: e.getAttribute("aria-checked") || e.checked || "", href: e.href || "" }))
    .filter(x => !keyword || JSON.stringify(x).toLowerCase().includes(keyword));
  const modal = Array.from(document.querySelectorAll(".ant-modal,.ant-drawer")).filter(visible).map(e => txt(e).slice(0, 3000));
  return JSON.stringify({ href: location.href, title: document.title, keyword, modal, controls: controls.slice(0, 240) });
})()
JS
    run_js "$tmp"
    ;;

  click-text)
    [[ $# -ge 2 && $# -le 3 ]] || { usage >&2; exit 2; }
    text_json="$(printf '%s' "$2" | json_string)"
    selector_json="$(printf '%s' "${3:-button,a,[role=button],li,[role=tab],.ant-tabs-tab,.ant-menu-item}" | json_string)"
    if [[ "${DS_CONFIRM:-}" != "1" && "$2" =~ ^(Add|Add New Output|Delete|Delete\ Markers|Turn-on|Turn-off|Save|Submit|Confirm|OK|Auto\ Parse|Add\ Partitions)$ ]]; then
      echo "Refusing state-changing click without DS_CONFIRM=1: $2" >&2
      exit 3
    fi
    tmp="$(make_tmp_js)"
    trap 'rm -f "$tmp"' EXIT
    cat > "$tmp" <<JS
(() => {
  const target = $text_json;
  const selector = $selector_json;
  const norm = s => String(s || "").replace(/\\s+/g, " ").trim();
  const visible = e => !!(e.offsetWidth || e.offsetHeight || e.getClientRects().length);
  const text = e => norm(e.innerText || e.getAttribute("aria-label") || e.title || e.value || "");
  const candidates = Array.from(document.querySelectorAll(selector)).filter(visible);
  const exact = candidates.find(e => text(e) === target);
  const partial = candidates.find(e => text(e).includes(target));
  const el = exact || partial;
  if (!el) return JSON.stringify({ ok: false, reason: "text not found", target, selector, seen: candidates.map(text).filter(Boolean).slice(0, 80) });
  el.scrollIntoView({ block: "center", inline: "center" });
  el.click();
  return JSON.stringify({ ok: true, clicked: text(el), tag: el.tagName, cls: String(el.className).slice(0, 160), href: location.href });
})()
JS
    run_js "$tmp"
    ;;

  set-field-by-label)
    [[ $# -eq 3 ]] || { usage >&2; exit 2; }
    label_json="$(printf '%s' "$2" | json_string)"
    value_json="$(printf '%s' "$3" | json_string)"
    tmp="$(make_tmp_js)"
    trap 'rm -f "$tmp"' EXIT
    cat > "$tmp" <<JS
(() => {
  const label = $label_json;
  const value = $value_json;
  const norm = s => String(s || "").replace(/\\s+/g, " ").trim();
  const visible = e => !!(e.offsetWidth || e.offsetHeight || e.getClientRects().length);
  function setNativeValue(el, val) {
    const proto = el.tagName === "TEXTAREA" ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
    const desc = Object.getOwnPropertyDescriptor(proto, "value");
    desc.set.call(el, val);
    el.dispatchEvent(new Event("input", { bubbles: true }));
    el.dispatchEvent(new Event("change", { bubbles: true }));
  }
  const labelEl = Array.from(document.querySelectorAll("label,.ant-form-item-label,div,span"))
    .filter(visible)
    .find(e => norm(e.innerText || e.textContent) === label || norm(e.innerText || e.textContent).startsWith(label));
  if (!labelEl) return JSON.stringify({ ok: false, reason: "label not found", label });
  const item = labelEl.closest(".ant-form-item,.ant-row,.ant-modal,.ant-drawer") || labelEl.parentElement;
  const input = item && Array.from(item.querySelectorAll("input:not([type=hidden]),textarea")).find(visible);
  if (!input) return JSON.stringify({ ok: false, reason: "input not found near label", label, context: norm(item?.innerText).slice(0, 500) });
  input.focus();
  setNativeValue(input, value);
  return JSON.stringify({ ok: true, label, value, tag: input.tagName, placeholder: input.getAttribute("placeholder") || "" });
})()
JS
    run_js "$tmp"
    ;;

  select-by-label)
    [[ $# -eq 3 ]] || { usage >&2; exit 2; }
    label_json="$(printf '%s' "$2" | json_string)"
    option_json="$(printf '%s' "$3" | json_string)"
    tmp="$(make_tmp_js)"
    trap 'rm -f "$tmp"' EXIT
    cat > "$tmp" <<JS
(() => {
  const label = $label_json;
  const option = $option_json;
  const norm = s => String(s || "").replace(/\\s+/g, " ").trim();
  const visible = e => !!(e.offsetWidth || e.offsetHeight || e.getClientRects().length);
  const labelEl = Array.from(document.querySelectorAll("label,.ant-form-item-label,div,span"))
    .filter(visible)
    .find(e => norm(e.innerText || e.textContent) === label || norm(e.innerText || e.textContent).startsWith(label));
  if (!labelEl) return JSON.stringify({ ok: false, reason: "label not found", label });
  const item = labelEl.closest(".ant-form-item,.ant-row,.ant-modal,.ant-drawer") || labelEl.parentElement;
  const selector = item && Array.from(item.querySelectorAll(".ant-select-selector")).find(visible);
  if (!selector) return JSON.stringify({ ok: false, reason: "select not found near label", label, context: norm(item?.innerText).slice(0, 500) });
  selector.click();
  setTimeout(() => {
    const opts = Array.from(document.querySelectorAll(".ant-select-item-option,.ant-dropdown-menu-item,[role=option]")).filter(visible);
    const opt = opts.find(e => norm(e.innerText || e.textContent) === option) || opts.find(e => norm(e.innerText || e.textContent).includes(option));
    if (opt) opt.click();
  }, 100);
  return JSON.stringify({ ok: true, label, option, action: "selector_clicked_then_option_scheduled" });
})()
JS
    run_js "$tmp"
    ;;

  toggle-by-label)
    [[ $# -eq 3 ]] || { usage >&2; exit 2; }
    label_json="$(printf '%s' "$2" | json_string)"
    desired_json="$(printf '%s' "$3" | json_string)"
    tmp="$(make_tmp_js)"
    trap 'rm -f "$tmp"' EXIT
    cat > "$tmp" <<JS
(() => {
  const label = $label_json;
  const desired = String($desired_json).toLowerCase();
  const wantOn = ["on", "true", "1", "yes"].includes(desired);
  const norm = s => String(s || "").replace(/\\s+/g, " ").trim();
  const visible = e => !!(e.offsetWidth || e.offsetHeight || e.getClientRects().length);
  const labelEl = Array.from(document.querySelectorAll("label,.ant-form-item-label,div,span"))
    .filter(visible)
    .find(e => norm(e.innerText || e.textContent) === label || norm(e.innerText || e.textContent).startsWith(label));
  if (!labelEl) return JSON.stringify({ ok: false, reason: "label not found", label });
  const item = labelEl.closest(".ant-form-item,.ant-row,.ant-modal,.ant-drawer") || labelEl.parentElement;
  const sw = item && Array.from(item.querySelectorAll(".ant-switch,button[role=switch]")).find(visible);
  if (!sw) return JSON.stringify({ ok: false, reason: "switch not found near label", label, context: norm(item?.innerText).slice(0, 500) });
  const isOn = sw.className.includes("ant-switch-checked") || sw.getAttribute("aria-checked") === "true" || norm(sw.innerText) === "On";
  if (isOn !== wantOn) sw.click();
  return JSON.stringify({ ok: true, label, before: isOn ? "on" : "off", desired: wantOn ? "on" : "off", clicked: isOn !== wantOn });
})()
JS
    run_js "$tmp"
    ;;

  scheduler-url|enter-scheduler)
    [[ $# -le 4 ]] || { usage >&2; exit 2; }
    action="$cmd"
    target="${2:-}"
    kind="${3:-manual}"
    kind_provided=0
    [[ $# -ge 3 ]] && kind_provided=1
    env="${4:-prod}"
    case "$env" in
      prod) env_prefix="" ;;
      staging) env_prefix="/uat" ;;
      dev) env_prefix="/dev" ;;
      *) echo "env must be prod, staging, or dev" >&2; exit 2 ;;
    esac
    if [[ "$action" == "enter-scheduler" ]]; then
      json="$("$0" scheduler-url "${@:2}")"
      url="$(printf '%s' "$json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["url"])')"
      open_chrome_url "$url"
      printf '%s' "$json" | python3 -c 'import json,sys; o=json.load(sys.stdin); o["opened"]=True; print(json.dumps(o, ensure_ascii=False))'
      exit 0
    fi
    tmp="$(make_tmp_js)"
    trap 'rm -f "$tmp"' EXIT
    if [[ -n "$target" ]]; then
      case "$kind" in
        manual)
          if [[ "$target" =~ ^[0-9]+$ ]]; then task_code="${DS_PROJECT_CODE}.studio_$target"; else task_code="$target"; fi
          task_path="task/manual/$task_code"
          ;;
        scheduled)
          if [[ "$target" =~ ^[0-9]+$ ]]; then task_code="${DS_PROJECT_CODE}.studio_$target"; else task_code="$target"; fi
          task_path="task/$task_code"
          ;;
        workflow)
          if [[ "$target" =~ ^[0-9]+$ ]]; then task_code="${DS_PROJECT_CODE}_$target"; else task_code="$target"; fi
          task_path="workflow/$task_code"
          ;;
        adhoc|temp|temp-query)
          echo "Adhoc/temp query does not have a Scheduler task page." >&2
          exit 4
          ;;
        *) echo "kind must be manual, scheduled, workflow, or adhoc" >&2; exit 2 ;;
      esac
      path="/scheduler$env_prefix/$task_path/matrix?project_code=${DS_PROJECT_CODE}"
      path_json="$(printf '%s' "$path" | json_string)"
      cat > "$tmp" <<JS
(() => {
  const path = $path_json;
  const url = new URL(path, location.origin).toString();
  if ("$action" === "scheduler-url") return JSON.stringify({ ok: true, env: "$env", kind: "$kind", taskCode: "$task_code", url });
  location.assign(path);
  return JSON.stringify({ ok: true, action: "navigate_scheduler", env: "$env", kind: "$kind", taskCode: "$task_code", url, href: location.href });
})()
JS
    else
      cat > "$tmp" <<JS
(() => {
  $common_js
  const env = "$env";
  const envPrefix = "$env_prefix";
  const norm = s => String(s || "").replace(/\\s+/g, " ").trim();
  const activeTabName = norm(document.querySelector(".ant-tabs-tab-active .ant-tabs-tab-btn, .ant-tabs-tab-active")?.innerText || "");
  const tabsResp = req("GET", "/datastudio/api/v1/tab/currentlyOpenV2?projectCode=${DS_PROJECT_CODE}");
  const tabs = JSON.parse(tabsResp.text).data || [];
  const isTempName = /^(\\*\\s*)?Temp_Query/i.test(activeTabName);
  const activeTab = tabs.find(t => norm(t.assetName) === activeTabName) || tabs.find(t => String(t.id) === String(activeTabName)) || null;
  if (!activeTab) {
    const bodyText = document.body.innerText || "";
    const bodyTaskCode = (bodyText.match(/Task Code\\s+([a-z0-9_]+\\.studio_\\d+)/i) || [])[1];
    if (isTempName) return JSON.stringify({ ok: false, reason: "adhoc_temp_query_has_no_scheduler", activeTabName });
    if (!bodyTaskCode) return JSON.stringify({ ok: false, reason: "active Data Studio tab not found", activeTabName, tabs: tabs.map(t => ({ id: t.id, assetName: t.assetName, assetRoot: t.assetRoot, assetType: t.assetType })).slice(0, 30) });
    const fallbackKind = $kind_provided ? "$kind" : (/\\bFrequency\\b|\\bCron Expression\\b|\\bSchedule\\b/.test(bodyText) ? "scheduled" : "manual");
    if (["adhoc", "temp", "temp-query"].includes(fallbackKind)) return JSON.stringify({ ok: false, reason: "adhoc_temp_query_has_no_scheduler", activeTabName });
    if (fallbackKind === "workflow") {
      const workflowCode = bodyTaskCode.replace(/\\.studio_/, "_");
      const url = location.origin + "/scheduler" + envPrefix + "/workflow/" + encodeURIComponent(workflowCode) + "/matrix?project_code=${DS_PROJECT_CODE}";
      if ("$action" === "scheduler-url") return JSON.stringify({ ok: true, env, kind: "workflow", taskCode: workflowCode, source: "body_text_fallback", activeTabName, url });
      location.assign(url);
      return JSON.stringify({ ok: true, action: "navigate_scheduler", env, kind: "workflow", taskCode: workflowCode, source: "body_text_fallback", activeTabName, url, href: location.href });
    }
    const taskPath = "task/" + (fallbackKind === "manual" ? "manual/" : "") + encodeURIComponent(bodyTaskCode);
    const url = location.origin + "/scheduler" + envPrefix + "/" + taskPath + "/matrix?project_code=${DS_PROJECT_CODE}";
    if ("$action" === "scheduler-url") return JSON.stringify({ ok: true, env, kind: fallbackKind, taskCode: bodyTaskCode, source: "body_text_fallback", activeTabName, url });
    location.assign(url);
    return JSON.stringify({ ok: true, action: "navigate_scheduler", env, kind: fallbackKind, taskCode: bodyTaskCode, source: "body_text_fallback", activeTabName, url, href: location.href });
  }
  const detailResp = req("GET", "/datastudio/api/v1/file/detail?projectCode=${DS_PROJECT_CODE}&assetId=" + activeTab.id + "&tabOrderUpdate=false");
  const detail = JSON.parse(detailResp.text).data || {};
  const taskCode = detail.scheduleTaskCode || ("${DS_PROJECT_CODE}.studio_" + activeTab.id);
  const rootType = detail.assetRoot || activeTab.assetRoot;
  const assetType = detail.assetType || activeTab.assetType;
  if (Number(rootType) === 7 || Number(assetType) === 61 || /Temp_Query/i.test(activeTab.assetName || "")) return JSON.stringify({ ok: false, reason: "adhoc_temp_query_has_no_scheduler", assetId: activeTab.id, assetName: activeTab.assetName, rootType, assetType });
  const inferredKind = Number(rootType) === 1 || Number(assetType) === 2 ? "workflow" : Number(rootType) === 3 ? "manual" : "scheduled";
  const schedulerCode = inferredKind === "workflow" ? ("${DS_PROJECT_CODE}_" + activeTab.id) : taskCode;
  const taskPath = inferredKind === "workflow" ? ("workflow/" + encodeURIComponent(schedulerCode)) : ("task/" + (inferredKind === "manual" ? "manual/" : "") + encodeURIComponent(taskCode));
  const url = location.origin + "/scheduler" + envPrefix + "/" + taskPath + "/matrix?project_code=${DS_PROJECT_CODE}";
  if ("$action" === "scheduler-url") return JSON.stringify({ ok: true, env, kind: inferredKind, taskCode: schedulerCode, assetId: activeTab.id, assetName: activeTab.assetName, rootType, assetType, url });
  location.assign(url);
  return JSON.stringify({ ok: true, action: "navigate_scheduler", env, kind: inferredKind, taskCode: schedulerCode, assetId: activeTab.id, assetName: activeTab.assetName, rootType, assetType, url, href: location.href });
})()
JS
    fi
    run_js "$tmp"
    ;;

  scheduler-backfill)
    [[ $# -eq 2 ]] || { usage >&2; exit 2; }
    mode="$2"
    case "$mode" in
      check|open) ;;
      *) echo "scheduler-backfill mode must be check or open" >&2; exit 2 ;;
    esac
    tmp="$(make_tmp_js)"
    trap 'rm -f "$tmp"' EXIT
    cat > "$tmp" <<JS
(() => {
  const mode = "$mode";
  const norm = s => String(s || "").replace(/\\s+/g, " ").trim();
  const visible = e => !!(e.offsetWidth || e.offsetHeight || e.getClientRects().length);
  const href = location.href;
  const kind = /\\/workflow\\//.test(href) ? "workflow" : /\\/task\\/manual\\//.test(href) ? "manual" : /\\/task\\//.test(href) ? "scheduled" : "unknown";
  const backfillTab = Array.from(document.querySelectorAll(".ant-tabs-tab,[role=tab],button,a")).filter(visible).find(e => norm(e.innerText || e.textContent) === "Backfill");
  const available = (kind === "scheduled" || kind === "workflow") && !!backfillTab;
  if (mode === "open" && available) backfillTab.click();
  return JSON.stringify({ ok: true, mode, kind, available, opened: mode === "open" && available, reason: available ? "" : (kind === "manual" ? "manual_scheduler_has_no_backfill" : "backfill_not_found_or_wrong_page"), href });
})()
JS
    run_js "$tmp"
    ;;

  open-settings)
    [[ $# -eq 2 ]] || { usage >&2; exit 2; }
    case "$2" in
      properties) label="Properties Setting" ;;
      parameters) label="Parameters Setting" ;;
      version) label="Version History" ;;
      output) label="Data Output Setting" ;;
      *) echo "settings must be properties, parameters, version, or output" >&2; exit 2 ;;
    esac
    "$0" click-text "$label" "li,[role=tab],.ant-tabs-tab,.ant-menu-item"
    ;;

  output-new)
    [[ $# -eq 2 ]] || { usage >&2; exit 2; }
    [[ "${DS_CONFIRM:-}" == "1" ]] || { echo "Refusing output-new without DS_CONFIRM=1" >&2; exit 3; }
    case "$2" in
      gsheet|google-sheet|google_sheets) dest="Google Sheet"; value="3" ;;
      csv) dest="CSV"; value="1" ;;
      *) echo "destination must be gsheet or csv" >&2; exit 2 ;;
    esac
    dest_json="$(printf '%s' "$dest" | json_string)"
    value_json="$(printf '%s' "$value" | json_string)"
    tmp="$(make_tmp_js)"
    trap 'rm -f "$tmp"' EXIT
    cat > "$tmp" <<JS
(() => {
  const dest = $dest_json;
  const value = $value_json;
  const norm = s => String(s || "").replace(/\\s+/g, " ").trim();
  const visible = e => !!(e.offsetWidth || e.offsetHeight || e.getClientRects().length);
  const clickText = text => {
    const el = Array.from(document.querySelectorAll("button,li,[role=tab],.ant-tabs-tab")).filter(visible).find(e => norm(e.innerText || e.textContent) === text);
    if (!el) return false;
    el.scrollIntoView({ block: "center", inline: "center" });
    el.click();
    return true;
  };
  if (!clickText("Data Output Setting")) return JSON.stringify({ ok: false, step: "open_output_tab", reason: "Data Output Setting not found" });
  const add = Array.from(document.querySelectorAll("button")).filter(visible).find(e => norm(e.innerText) === "Add New Output");
  if (!add) return JSON.stringify({ ok: false, step: "add_new_output", reason: "Add New Output not found" });
  add.click();
  const radio = Array.from(document.querySelectorAll(".ant-modal input[type=radio],.ant-modal .ant-radio-button-input")).find(e => e.value === value);
  if (!radio) return JSON.stringify({ ok: false, step: "select_destination", reason: "destination radio not found", dest });
  radio.click();
  const addBtn = Array.from(document.querySelectorAll(".ant-modal button")).filter(visible).find(e => norm(e.innerText) === "Add");
  if (!addBtn) return JSON.stringify({ ok: false, step: "modal_add", reason: "Add button not found" });
  addBtn.click();
  return JSON.stringify({ ok: true, action: "output_new_draft", destination: dest });
})()
JS
    run_js "$tmp"
    ;;

  output-action)
    [[ $# -eq 2 ]] || { usage >&2; exit 2; }
    [[ "${DS_CONFIRM:-}" == "1" ]] || { echo "Refusing output-action without DS_CONFIRM=1" >&2; exit 3; }
    case "$2" in
      turn-on) label="Turn-on" ;;
      turn-off) label="Turn-off" ;;
      delete) label="Delete" ;;
      *) echo "action must be turn-on, turn-off, or delete" >&2; exit 2 ;;
    esac
    DS_CONFIRM=1 "$0" click-text "$label" "button"
    ;;

  -h|--help|"")
    usage
    ;;

  *)
    echo "Unknown command: $cmd" >&2
    usage >&2
    exit 2
    ;;
esac

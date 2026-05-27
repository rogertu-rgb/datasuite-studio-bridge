#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  chrome-js-bridge.sh --url-contains datasuite.example.com --expr '(() => document.title)()'
  chrome-js-bridge.sh --tab-index 2 --js-file /tmp/read-instance.js
  chrome-js-bridge.sh --url-contains docs.google.com/spreadsheets/d/ --open-url https://docs.google.com/spreadsheets/d/.../edit --expr '(() => document.title)()'
  chrome-js-bridge.sh --list-tabs

Runs JavaScript inside a Google Chrome tab through AppleScript and prints the result.
Use this for DataSuite pages instead of Computer Use.
EOF
}

url_contains=""
tab_index=""
expr=""
js_file=""
list_tabs=0
open_url=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --list-tabs)
      list_tabs=1
      shift
      ;;
    --url-contains)
      url_contains="${2:-}"
      shift 2
      ;;
    --tab-index)
      tab_index="${2:-}"
      shift 2
      ;;
    --open-url)
      open_url="${2:-}"
      shift 2
      ;;
    --expr)
      expr="${2:-}"
      shift 2
      ;;
    --js-file)
      js_file="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$list_tabs" == "1" ]]; then
  osascript <<'OSA'
tell application "Google Chrome"
  set out to ""
  repeat with wi from 1 to count of windows
    set w to window wi
    repeat with ti from 1 to count of tabs of w
      set t to tab ti of w
      set out to out & wi & "." & ti & " | " & (title of t as text) & " | " & (URL of t as text) & linefeed
    end repeat
  end repeat
  return out
end tell
OSA
  exit 0
fi

if [[ -n "$expr" && -n "$js_file" ]]; then
  echo "Pass either --expr or --js-file, not both." >&2
  exit 2
fi

if [[ -z "$expr" && -z "$js_file" ]]; then
  echo "Pass --expr or --js-file." >&2
  exit 2
fi

tmp=""
cleanup() {
  [[ -n "$tmp" && -f "$tmp" ]] && rm -f "$tmp"
}
trap cleanup EXIT

if [[ -n "$js_file" ]]; then
  if [[ ! -f "$js_file" ]]; then
    echo "JS file not found: $js_file" >&2
    exit 2
  fi
  tmp="$js_file"
else
  tmp="$(mktemp)"
  printf '%s' "$expr" > "$tmp"
fi

osascript - "$url_contains" "$tab_index" "$tmp" "$open_url" <<'OSA'
on waitForReady(theTab)
  repeat with n from 1 to 80
    try
      tell application "Google Chrome" to tell theTab to set stateText to execute javascript "document.readyState"
      if stateText is "complete" or stateText is "interactive" then exit repeat
    end try
    delay 0.25
  end repeat
end waitForReady

on executeInTab(theTab, jsSource)
  my waitForReady(theTab)
  with timeout of 10 seconds
    tell application "Google Chrome" to tell theTab to return execute javascript jsSource
  end timeout
end executeInTab

on run argv
  set urlContains to item 1 of argv
  set tabIndexText to item 2 of argv
  set jsPath to item 3 of argv
  set openUrl to item 4 of argv
  set jsSource to read (POSIX file jsPath) as «class utf8»

  tell application "Google Chrome"
    if tabIndexText is not "" then
      if tabIndexText contains "." then
        set oldDelims to AppleScript's text item delimiters
        set AppleScript's text item delimiters to "."
        set parts to text items of tabIndexText
        set AppleScript's text item delimiters to oldDelims
        set w to window ((item 1 of parts) as integer)
        set t to tab ((item 2 of parts) as integer) of w
      else
        set w to front window
        set t to tab (tabIndexText as integer) of w
      end if
      return my executeInTab(t, jsSource)
    end if

    repeat with wi from 1 to count of windows
      set w to window wi
      repeat with ti from 1 to count of tabs of w
        set t to tab ti of w
        set u to URL of t as text
        if urlContains is "" or u contains urlContains then
          return my executeInTab(t, jsSource)
        end if
      end repeat
    end repeat

    if openUrl is not "" then
      if (count of windows) is 0 then
        make new window
      end if
      set w to window 1
      set t to make new tab at end of tabs of w with properties {URL:openUrl}
      set active tab index of w to count of tabs of w
      return my executeInTab(t, jsSource)
    end if
  end tell

  error "No matching Chrome tab found"
end run
OSA

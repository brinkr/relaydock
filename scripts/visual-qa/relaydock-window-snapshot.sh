#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUTPUT_DIR="${ROOT_DIR}/artifacts/visual-qa"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BUILD_BINARY="${ROOT_DIR}/.build/debug/relaydock"
BRIDGE_BINARY="${ROOT_DIR}/target/debug/relaydock-bridge"
APP_BUNDLE_ID="dev.relaydock.visualqa"
APP_BUNDLE_DIR="${OUTPUT_DIR}/RelayDock-${TIMESTAMP}.app"
APP_EXECUTABLE="${APP_BUNDLE_DIR}/Contents/MacOS/relaydock"
APP_RESOURCES_DIR="${APP_BUNDLE_DIR}/Contents/Resources"
INFO_PLIST="${APP_BUNDLE_DIR}/Contents/Info.plist"
APP_LAUNCH_TIMEOUT_SECONDS="10"
WINDOW_LOOKUP_TIMEOUT_SECONDS="5"
WINDOW_LOOKUP_DELAY_SECONDS="0.25"
KEEP_OPEN="${RELAYDOCK_VISUAL_QA_KEEP_OPEN:-0}"
VISUAL_QA_FIXTURE="${RELAYDOCK_VISUAL_QA_FIXTURE:-prototype-density}"
APP_PID=""
LAST_WINDOW_RECT=""
LAST_WINDOW_ID=""
GENERATED_SCREENSHOTS=()
SHELL_PAGES=(
  "run-recovery|运行与恢复"
  "registry|资源登记"
  "logs-diagnostics|日志与诊断"
  "preferences|偏好设置"
)

mkdir -p "${OUTPUT_DIR}"

fail() {
  echo "Error: $*" >&2
  exit 1
}

fail_with_context() {
  local message="$1"
  local window_rect="${2:-${LAST_WINDOW_RECT}}"

  print_visual_qa_context "${window_rect}"
  fail "${message}"
}

print_visual_qa_context() {
  local window_rect="${1:-${LAST_WINDOW_RECT}}"

  {
    echo "RelayDock visual QA context:"
    echo "  app bundle: ${APP_BUNDLE_DIR}"
    echo "  bundle id: ${APP_BUNDLE_ID}"
    if [[ -n "${APP_PID}" ]]; then
      echo "  pid: ${APP_PID}"
    else
      echo "  pid: unknown"
    fi
    if [[ -n "${window_rect}" ]]; then
      echo "  window rect: ${window_rect}"
    else
      echo "  window rect: unknown"
    fi
    if [[ -n "${LAST_WINDOW_ID}" ]]; then
      echo "  window id: ${LAST_WINDOW_ID}"
    else
      echo "  window id: unknown"
    fi
    echo "Keep-open rerun hint: RELAYDOCK_VISUAL_QA_KEEP_OPEN=1 scripts/visual-qa/relaydock-window-snapshot.sh"
  } >&2
}

warn_accessibility_fallback() {
  local detail="$1"

  {
    echo "Warning: Accessibility permission is blocked for osascript window queries via System Events."
    echo "Trying CoreGraphics window lookup instead; the script will still fail if the RelayDock window rectangle cannot be read."
    echo "Page navigation still requires Accessibility. Grant it to the terminal or automation host running this script in System Settings > Privacy & Security > Accessibility."
    echo "Command output: ${detail}"
  } >&2
}

fail_screen_recording() {
  local command_text="$1"
  local detail="$2"
  local window_rect="${3:-}"

  {
    echo "Screen Recording permission is required for macOS screenshots in this environment."
    echo "Failed command: ${command_text}"
    echo "Grant Screen Recording to the terminal or automation host running this script in System Settings > Privacy & Security > Screen Recording, then rerun."
    echo "Command output: ${detail}"
  } >&2
  print_visual_qa_context "${window_rect}"

  exit 1
}

is_visual_qa_command() {
  local command_line="$1"
  [[ "${command_line}" == *"${OUTPUT_DIR}/RelayDock"*".app/Contents/MacOS/relaydock"* ]]
}

terminate_pid_if_matches() {
  local pid="$1"
  local command_line=""

  [[ -n "${pid}" ]] || return 0
  kill -0 "${pid}" >/dev/null 2>&1 || return 0

  command_line="$(ps -p "${pid}" -o command= 2>/dev/null || true)"
  [[ -n "${command_line}" ]] || return 0

  if [[ "${command_line}" != *"${APP_EXECUTABLE}"* ]] && ! is_visual_qa_command "${command_line}"; then
    return 0
  fi

  kill "${pid}" >/dev/null 2>&1 || true

  for _ in {1..20}; do
    kill -0 "${pid}" >/dev/null 2>&1 || break
    sleep 0.25
  done

  if kill -0 "${pid}" >/dev/null 2>&1; then
    kill -9 "${pid}" >/dev/null 2>&1 || true
  fi

  [[ "${pid}" == "${APP_PID}" ]] && wait "${pid}" >/dev/null 2>&1 || true
}

cleanup_stale_processes() {
  local candidate_pids=""
  local candidate_pid=""

  candidate_pids="$(pgrep -f "relaydock" || true)"
  [[ -n "${candidate_pids}" ]] || return 0

  while IFS= read -r candidate_pid; do
    [[ -n "${candidate_pid}" ]] || continue
    terminate_pid_if_matches "${candidate_pid}"
  done <<<"${candidate_pids}"
}

prepare_app_bundle() {
  mkdir -p "${APP_BUNDLE_DIR}/Contents/MacOS"
  mkdir -p "${APP_RESOURCES_DIR}"
  cp "${BUILD_BINARY}" "${APP_EXECUTABLE}"
  cp "${BRIDGE_BINARY}" "${APP_RESOURCES_DIR}/relaydock-bridge"
  chmod +x "${APP_EXECUTABLE}"
  chmod +x "${APP_RESOURCES_DIR}/relaydock-bridge"

  cat >"${INFO_PLIST}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>RelayDock</string>
  <key>CFBundleExecutable</key>
  <string>relaydock</string>
  <key>CFBundleIdentifier</key>
  <string>${APP_BUNDLE_ID}</string>
  <key>CFBundleName</key>
  <string>RelayDock</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>${TIMESTAMP}</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
EOF
}

find_app_pid() {
  local candidate_pids=""
  local candidate_pid=""
  local command_line=""

  candidate_pids="$(pgrep -f "relaydock" || true)"
  [[ -n "${candidate_pids}" ]] || return 1

  while IFS= read -r candidate_pid; do
    [[ -n "${candidate_pid}" ]] || continue
    command_line="$(ps -p "${candidate_pid}" -o command= 2>/dev/null || true)"

    if [[ "${command_line}" == *"${APP_EXECUTABLE}"* ]]; then
      printf '%s\n' "${candidate_pid}"
      return 0
    fi
  done <<<"${candidate_pids}"

  return 1
}

launch_app_bundle() {
  open -n --env "RELAYDOCK_VISUAL_QA_FIXTURE=${VISUAL_QA_FIXTURE}" "${APP_BUNDLE_DIR}" >/dev/null

  local launch_started_at="${SECONDS}"
  while (( SECONDS - launch_started_at < APP_LAUNCH_TIMEOUT_SECONDS )); do
    if APP_PID="$(find_app_pid)"; then
      export APP_PID
      return 0
    fi

    sleep 0.25
  done

  fail "Failed to detect RelayDock process launched from ${APP_BUNDLE_DIR}."
}

activate_app_bundle() {
  osascript -e "tell application id \"${APP_BUNDLE_ID}\" to activate" >/dev/null 2>&1 || true
}

read_window_rect() {
  local query_output=""
  local query_status="0"

  set +e
  query_output="$(
    python3 - "${APP_PID}" <<'PYTHON' 2>&1
import subprocess
import sys

app_pid = sys.argv[1]
script = r'''
on run argv
  set appPid to (item 1 of argv) as integer

  tell application "System Events"
    set matchedProcesses to every process whose unix id is appPid
    if (count of matchedProcesses) is 0 then return ""

    tell item 1 of matchedProcesses
      if (count of windows) is 0 then return ""

      set {xPos, yPos} to position of window 1
      set {windowWidth, windowHeight} to size of window 1
      return (xPos as integer as text) & "," & (yPos as integer as text) & "," & (windowWidth as integer as text) & "," & (windowHeight as integer as text)
    end tell
  end tell
end run
'''

try:
    result = subprocess.run(
        ["osascript", "-", app_pid],
        input=script,
        capture_output=True,
        text=True,
        timeout=3,
        check=False,
    )
except subprocess.TimeoutExpired as error:
    output = ""
    if error.stdout:
        output += error.stdout
    if error.stderr:
        output += error.stderr
    print(f"QUERY_TIMEOUT:{output.strip()}", end="")
    sys.exit(0)

output = (result.stdout or "") + (result.stderr or "")
print(output.strip(), end="")
sys.exit(result.returncode)
PYTHON
  )"
  query_status="$?"
  set -e

  if [[ "${query_output}" == QUERY_TIMEOUT:* ]]; then
    printf '%s\n' "${query_output}"
    return 0
  fi

  if [[ "${query_status}" != "0" ]]; then
    if [[ "${query_output}" == *"not allowed assistive access"* ]] || [[ "${query_output}" == *"(-25211)"* ]]; then
      printf 'ACCESSIBILITY_DENIED:%s\n' "${query_output}"
      return 0
    fi

    printf 'QUERY_FAILED:%s\n' "${query_output}"
    return 0
  fi

  printf '%s\n' "${query_output}"
}

read_window_info_with_coregraphics() {
  swift - "${APP_PID}" <<'SWIFT'
import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 2,
      let appPid = Int(CommandLine.arguments[1]) else {
    exit(1)
}

let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []

for window in windows {
    guard window[kCGWindowOwnerPID as String] as? Int == appPid else {
        continue
    }

    guard (window[kCGWindowLayer as String] as? Int ?? 0) == 0 else {
        continue
    }

    guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
          let windowNumber = window[kCGWindowNumber as String] as? Int,
          let width = bounds["Width"] as? Int,
          let height = bounds["Height"] as? Int,
          width > 0,
          height > 0 else {
        continue
    }

    let xPosition = bounds["X"] as? Int ?? 0
    let yPosition = bounds["Y"] as? Int ?? 0
    print("\(xPosition),\(yPosition),\(width),\(height),\(windowNumber)")
    exit(0)
}

exit(1)
SWIFT
}

is_black_screenshot() {
  local screenshot_path="$1"

  python3 - "${screenshot_path}" <<'PYTHON'
import sys
from pathlib import Path
from PIL import Image, ImageStat

image_path = Path(sys.argv[1])
if not image_path.exists() or image_path.stat().st_size == 0:
    sys.exit(0)

image = Image.open(image_path).convert("RGB")
stat = ImageStat.Stat(image)
if max(stat.extrema[0][1], stat.extrema[1][1], stat.extrema[2][1]) < 3:
    sys.exit(0)

sys.exit(1)
PYTHON
}

assert_no_topbar_hard_separator() {
  local screenshot_path="$1"
  local page_slug="$2"
  local separator_output=""
  local separator_status="0"

  set +e
  separator_output="$(
    python3 - "${screenshot_path}" <<'PYTHON' 2>&1
import sys
from pathlib import Path
from PIL import Image

image_path = Path(sys.argv[1])
image = Image.open(image_path).convert("RGB")
width, height = image.size
pixels = image.load()

left = width
right = 0
top = height
bottom = 0

for y in range(height):
    for x in range(width):
        if max(pixels[x, y]) > 10:
            left = min(left, x)
            right = max(right, x)
            top = min(top, y)
            bottom = max(bottom, y)

if right <= left or bottom <= top:
    print("WINDOW_CONTENT_NOT_FOUND")
    sys.exit(2)

content_width = right - left + 1
scale = content_width / 1120.0
content_left = left + round(220 * scale)
content_right = right - round(8 * scale)
scan_top = top + round(24 * scale)
scan_bottom = min(top + round(56 * scale), bottom)

if content_right <= content_left or scan_bottom <= scan_top:
    print("SCAN_REGION_INVALID")
    sys.exit(2)

for y in range(scan_top, scan_bottom + 1):
    sample_count = 0
    separator_count = 0

    for x in range(content_left, content_right + 1, 4):
        red, green, blue = pixels[x, y]
        average = (red + green + blue) / 3
        sample_count += 1

        if abs(red - green) <= 3 and abs(green - blue) <= 3 and 225 <= average <= 245:
            separator_count += 1

    ratio = separator_count / max(sample_count, 1)
    if ratio >= 0.50:
        print(f"TOPBAR_SEPARATOR_DETECTED:y={y}:ratio={ratio:.2f}")
        sys.exit(1)

sys.exit(0)
PYTHON
  )"
  separator_status="$?"
  set -e

  if [[ "${separator_status}" != "0" ]]; then
    fail_with_context "Topbar visual QA failed for '${page_slug}': ${separator_output}. Hide AppKit titlebar separators and avoid drawing a visible ShellTopBar divider."
  fi
}

select_shell_page() {
  local page_slug="$1"
  local page_title="$2"
  local select_output=""
  local select_status="0"

  activate_app_bundle

  set +e
  select_output="$(
    swift - "${APP_PID}" "${page_title}" <<'SWIFT' 2>&1
import ApplicationServices
import Foundation

guard CommandLine.arguments.count == 3,
      let appPid = pid_t(CommandLine.arguments[1]) else {
    print("Invalid arguments.")
    exit(1)
}

let pageTitle = CommandLine.arguments[2]
let appElement = AXUIElementCreateApplication(appPid)
let selectedValue = "已选择" as CFString
let maxDepth = 8

func attributeValue(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
    var value: AnyObject?
    let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    return error == .success ? value : nil
}

func attributeString(_ element: AXUIElement, _ attribute: String) -> String? {
    guard let value = attributeValue(element, attribute) else {
        return nil
    }

    if let stringValue = value as? String {
        return stringValue
    }

    return String(describing: value)
}

func childElements(_ element: AXUIElement) -> [AXUIElement] {
    var result: [AXUIElement] = []

    for attribute in [kAXWindowsAttribute, kAXChildrenAttribute, kAXVisibleChildrenAttribute] {
        if let children = attributeValue(element, attribute) as? [AXUIElement] {
            result.append(contentsOf: children)
        }
    }

    return result
}

func actionNames(_ element: AXUIElement) -> [String] {
    var actions: CFArray?
    let error = AXUIElementCopyActionNames(element, &actions)
    guard error == .success,
          let actionList = actions as? [String] else {
        return []
    }

    return actionList
}

func isSidebarButton(_ element: AXUIElement, selectedOnly: Bool) -> Bool {
    guard attributeString(element, kAXRoleAttribute) == kAXButtonRole,
          attributeString(element, kAXDescriptionAttribute) == pageTitle,
          actionNames(element).contains(kAXPressAction) else {
        return false
    }

    return !selectedOnly || attributeString(element, kAXValueAttribute) == selectedValue as String
}

func findSidebarButton(in element: AXUIElement, depth: Int = 0, selectedOnly: Bool = false) -> AXUIElement? {
    if depth > maxDepth {
        return nil
    }

    if isSidebarButton(element, selectedOnly: selectedOnly) {
        return element
    }

    for child in childElements(element) {
        if let found = findSidebarButton(in: child, depth: depth + 1, selectedOnly: selectedOnly) {
            return found
        }
    }

    return nil
}

if !AXIsProcessTrusted() {
    print("ACCESSIBILITY_DENIED:macOS Accessibility permission is required to select RelayDock page '\(pageTitle)'.")
    exit(2)
}

guard let pageElement = findSidebarButton(in: appElement) else {
    print("PAGE_NOT_FOUND:No AXButton with AXDescription '\(pageTitle)' and AXPress action was found.")
    exit(3)
}

let pressError = AXUIElementPerformAction(pageElement, kAXPressAction as CFString)
guard pressError == .success else {
    print("PAGE_PRESS_FAILED:AXPress returned \(pressError.rawValue) for '\(pageTitle)'.")
    exit(4)
}

let deadline = Date().addingTimeInterval(2.0)
repeat {
    if findSidebarButton(in: appElement, selectedOnly: true) != nil {
        print("selected:\(pageTitle)")
        exit(0)
    }

    Thread.sleep(forTimeInterval: 0.1)
} while Date() < deadline

print("PAGE_SELECT_UNVERIFIED:Pressed '\(pageTitle)' but did not observe selected accessibility value '\(selectedValue)'.")
exit(5)
SWIFT
  )"
  select_status="$?"
  set -e

  if [[ "${select_status}" != "0" ]]; then
    fail_with_context "Failed to select RelayDock page '${page_title}' (${page_slug}). ${select_output}"
  fi
}

capture_window_lookup_fallback() {
  local reason="$1"
  local detail="$2"

  {
    echo "Window lookup failed: ${reason}"
    if [[ -n "${detail}" ]]; then
      echo "Window query output: ${detail}"
    fi
  } >&2
  print_visual_qa_context
  echo "Visual QA requires a RelayDock window rectangle; refusing to fall back to a full-screen screenshot." >&2
  exit 1
}

locate_window_rect() {
  local window_rect=""
  local window_info=""
  local accessibility_denied_detail=""
  local lookup_started_at="${SECONDS}"
  local query_result=""

  while (( SECONDS - lookup_started_at < WINDOW_LOOKUP_TIMEOUT_SECONDS )); do
    query_result="$(read_window_rect)"

    if [[ "${query_result}" == ACCESSIBILITY_DENIED:* ]]; then
      accessibility_denied_detail="${query_result#ACCESSIBILITY_DENIED:}"
      break
    fi

    if [[ "${query_result}" == QUERY_FAILED:* ]]; then
      capture_window_lookup_fallback "Window query failed via osascript." "${query_result#QUERY_FAILED:}"
    fi

    if [[ "${query_result}" == QUERY_TIMEOUT:* ]]; then
      capture_window_lookup_fallback "Window query timed out via osascript." "${query_result#QUERY_TIMEOUT:}"
    fi

    if [[ "${query_result}" =~ ^-?[0-9]+,-?[0-9]+,[0-9]+,[0-9]+$ ]]; then
      window_rect="${query_result}"
      break
    fi

    sleep "${WINDOW_LOOKUP_DELAY_SECONDS}"
  done

  if [[ -n "${accessibility_denied_detail}" ]]; then
    warn_accessibility_fallback "${accessibility_denied_detail}"
    window_info="$(read_window_info_with_coregraphics || true)"
    if [[ -z "${window_info}" ]]; then
      capture_window_lookup_fallback "Accessibility permission blocked the RelayDock window rectangle query." "${accessibility_denied_detail}"
    fi
  fi

  if [[ -z "${window_info}" ]]; then
    window_info="$(read_window_info_with_coregraphics || true)"
  fi

  if [[ "${window_info}" =~ ^-?[0-9]+,-?[0-9]+,[0-9]+,[0-9]+,[0-9]+$ ]]; then
    LAST_WINDOW_RECT="${window_info%,*}"
    LAST_WINDOW_ID="${window_info##*,}"
    printf '%s\n' "${LAST_WINDOW_RECT}"
    return 0
  fi

  if [[ -n "${window_rect}" ]]; then
    LAST_WINDOW_RECT="${window_rect}"
    LAST_WINDOW_ID=""
    printf '%s\n' "${window_rect}"
    return 0
  fi

  if [[ -z "${window_info}" ]]; then
    capture_window_lookup_fallback "Failed to locate a RelayDock window via osascript or CoreGraphics within ${WINDOW_LOOKUP_TIMEOUT_SECONDS}s." ""
  fi

  capture_window_lookup_fallback "Failed to parse RelayDock CoreGraphics window info." "${window_info}"
}

capture_window_screenshot() {
  local window_rect="$1"
  local output_path="$2"
  local capture_output=""
  local capture_status="0"
  local capture_command=""
  LAST_WINDOW_RECT="${window_rect}"

  if [[ -z "${LAST_WINDOW_ID}" ]]; then
    print_visual_qa_context "${window_rect}"
    fail "Visual QA requires a CoreGraphics RelayDock window id; refusing rectangle capture because Retina coordinate conversion can capture the wrong app."
  fi

  capture_command="screencapture -x -l${LAST_WINDOW_ID} ${output_path}"

  set +e
  capture_output="$(screencapture -x -l"${LAST_WINDOW_ID}" "${output_path}" 2>&1)"
  capture_status="$?"
  set -e

  if [[ "${capture_status}" != "0" ]]; then
    if [[ "${capture_output}" == *"could not create image from display"* ]] || [[ "${capture_output}" == *"could not create image from rect"* ]]; then
      fail_screen_recording "${capture_command}" "${capture_output}" "${window_rect}"
    fi

    fail "Failed command: ${capture_command}
Command output: ${capture_output}"
  fi

  if is_black_screenshot "${output_path}"; then
    print_visual_qa_context "${window_rect}"
    fail "Captured screenshot is all black; visual QA cannot verify the RelayDock window. Check Screen Recording permission and display/window placement."
  fi
}

cleanup() {
  if [[ "${KEEP_OPEN}" == "1" ]]; then
    echo "Keeping RelayDock visual QA app open at ${APP_BUNDLE_DIR} with pid ${APP_PID}." >&2
    return 0
  fi

  osascript -e "tell application id \"${APP_BUNDLE_ID}\" to quit" >/dev/null 2>&1 || true
  terminate_pid_if_matches "${APP_PID}"
  cleanup_stale_processes
  rm -rf "${APP_BUNDLE_DIR}"
}
trap cleanup EXIT

cd "${ROOT_DIR}"
swift build >/dev/null
cargo build -p relaydock-core --bin relaydock-bridge >/dev/null

[[ -x "${BUILD_BINARY}" ]] || fail "Expected built binary at ${BUILD_BINARY}."
[[ -x "${BRIDGE_BINARY}" ]] || fail "Expected built bridge sidecar at ${BRIDGE_BINARY}."

cleanup_stale_processes
prepare_app_bundle
launch_app_bundle
activate_app_bundle
locate_window_rect >/dev/null
WINDOW_RECT="${LAST_WINDOW_RECT}"

for page_entry in "${SHELL_PAGES[@]}"; do
  IFS="|" read -r PAGE_SLUG PAGE_TITLE <<<"${page_entry}"
  OUTPUT_PATH="${OUTPUT_DIR}/relaydock-window-${TIMESTAMP}-${PAGE_SLUG}.png"

  select_shell_page "${PAGE_SLUG}" "${PAGE_TITLE}"
  locate_window_rect >/dev/null
  WINDOW_RECT="${LAST_WINDOW_RECT}"
  capture_window_screenshot "${WINDOW_RECT}" "${OUTPUT_PATH}"
  assert_no_topbar_hard_separator "${OUTPUT_PATH}" "${PAGE_SLUG}"
  GENERATED_SCREENSHOTS+=("${OUTPUT_PATH}")
done

printf '%s\n' "${GENERATED_SCREENSHOTS[@]}"

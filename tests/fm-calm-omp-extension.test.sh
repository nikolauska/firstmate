#!/usr/bin/env bash
# Focused OMP Calm command, preference, lifecycle, and public-UI seam checks.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-calm-omp-extension)
EXT="$ROOT/.omp/extensions/fm-calm.ts"

run_omp_calm_fixture() {
  local home=$1 root=$2 config_override=$3 expanded=$4
  FM_HOME="$home" FM_ROOT_OVERRIDE="$root" FM_CONFIG_OVERRIDE="$config_override" \
    EXT="$EXT" INITIAL_EXPANDED="$expanded" node --input-type=module <<'JS'
import { readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

const handlers = new Map();
const commands = new Map();
const transportCalls = [];
const executionCalls = [];
const sessionCalls = [];
const uiCalls = [];
let expanded = process.env.INITIAL_EXPANDED === "true";
const api = {
  on(name, handler) {
    handlers.set(name, handler);
  },
  registerCommand(name, command) {
    commands.set(name, command);
  },
  registerTool(...args) {
    executionCalls.push(["registerTool", args]);
  },
  sendMessage(...args) {
    transportCalls.push(["sendMessage", args]);
  },
  sendUserMessage(...args) {
    transportCalls.push(["sendUserMessage", args]);
  },
  appendEntry(...args) {
    sessionCalls.push(["appendEntry", args]);
  },
};
const extension = await import(`${pathToFileURL(process.env.EXT).href}?fixture=${Date.now()}-${Math.random()}`);
extension.default(api);
for (const required of ["session_start", "session_switch", "agent_start", "agent_end", "session_shutdown"]) {
  if (!handlers.has(required)) throw new Error(`missing OMP lifecycle handler ${required}`);
}
if (!commands.has("calm")) throw new Error("OMP /calm command was not registered");
const ctx = {
  ui: {
    getToolsExpanded() {
      uiCalls.push(["getToolsExpanded"]);
      return expanded;
    },
    setToolsExpanded(value) {
      uiCalls.push(["setToolsExpanded", value]);
      expanded = value;
    },
    setWorkingMessage(value) {
      uiCalls.push(["setWorkingMessage", value]);
    },
  },
  sendUserMessage(...args) {
    transportCalls.push(["context.sendUserMessage", args]);
  },
  sessionManager: {},
};
const eventContext = { ui: ctx.ui };
const calmCommand = commands.get("calm");

await handlers.get("session_start")({ type: "session_start" }, eventContext);
if (uiCalls.length !== 0) throw new Error(`default-off Calm changed presentation: ${JSON.stringify(uiCalls)}`);
if (transportCalls.length !== 0) throw new Error("default-off Calm touched transport state");

await calmCommand.handler("", ctx);
const preferencePath = `${process.env.FM_CONFIG_OVERRIDE || process.env.FM_HOME + "/config"}/calm`;
if (readFileSync(preferencePath, "utf8") !== "on\n") throw new Error("/calm did not persist on");
if ((statSync(preferencePath).mode & 0o777) !== 0o600) throw new Error("Calm preference is not private");
if (!uiCalls.some((call) => call[0] === "setToolsExpanded" && call[1] === false)) {
  throw new Error(`Calm did not collapse OMP tool output: ${JSON.stringify(uiCalls)}`);
}
if (expanded !== false) throw new Error("Calm did not change the supported OMP expansion presentation");

await handlers.get("agent_start")({ type: "agent_start" }, eventContext);
if (!uiCalls.some((call) => call[0] === "setWorkingMessage" && call[1] === "Working")) {
  throw new Error("Calm did not use OMP's supported working-message presentation");
}
const beforeContinue = uiCalls.length;
await handlers.get("agent_end")({ type: "agent_end", willContinue: true }, eventContext);
if (uiCalls.length !== beforeContinue) throw new Error("Calm hid working activity during an automatic continuation");
await handlers.get("agent_end")({ type: "agent_end", willContinue: false }, eventContext);
if (!uiCalls.some((call) => call[0] === "setWorkingMessage" && call[1] === undefined)) {
  throw new Error("Calm did not restore the stock working presentation");
}

await calmCommand.handler("", ctx);
if (readFileSync(preferencePath, "utf8") !== "off\n") throw new Error("/calm did not persist off");
if (expanded !== true) throw new Error("Calm off did not restore the user's expansion state");
if (transportCalls.length !== 0) throw new Error("Calm changed model or message transport state");
if (executionCalls.length !== 0) throw new Error("Calm changed tool execution registration");
if (sessionCalls.length !== 0) throw new Error("Calm changed session data");
if (readdirSync(preferencePath.replace(/\/calm$/, "")).some((name) => name.endsWith(".tmp"))) {
  throw new Error("Calm left an atomic-write temporary file behind");
}

writeFileSync(preferencePath, "on\n");
expanded = true;
await handlers.get("session_switch")({ type: "session_switch", reason: "new" }, eventContext);
if (expanded !== false) throw new Error("Calm did not reload on across an OMP session switch");
writeFileSync(preferencePath, "off\n");
await handlers.get("session_switch")({ type: "session_switch", reason: "resume" }, eventContext);
if (expanded !== true) throw new Error("Calm did not restore the expansion state when preference changed off");
await handlers.get("session_shutdown")({ type: "session_shutdown" }, eventContext);
if (transportCalls.length !== 0 || executionCalls.length !== 0 || sessionCalls.length !== 0) {
  throw new Error("Calm lifecycle handlers changed model, execution, or session state");
}
console.log(JSON.stringify({ preferencePath, uiCalls, transportCalls, executionCalls, sessionCalls }));
JS
}

test_omp_calm_command_lifecycle() {
  local home="$TMP_ROOT/home" root="$TMP_ROOT/root" config="$TMP_ROOT/config" out
  mkdir -p "$home/config" "$root/config" "$config"
  printf '%s\n' 'not-a-calm-value' > "$home/config/calm"
  out=$(run_omp_calm_fixture "$home" "$root" "$config" true) || fail "OMP Calm fixture failed: $out"
  assert_contains "$out" '"transportCalls":[]' "OMP Calm changed model or session transport state"
  assert_contains "$out" '"executionCalls":[]' "OMP Calm changed tool execution registration"
  assert_contains "$out" '"sessionCalls":[]' "OMP Calm changed session data"
  assert_contains "$out" '"setToolsExpanded",false' "OMP Calm did not exercise its supported tool-output presentation seam"
  pass "OMP Calm persists /calm, reloads it across session lifecycle, and restores supported presentation state"
}

test_omp_calm_home_resolution() {
  local home="$TMP_ROOT/resolution-home" root="$TMP_ROOT/resolution-root" config="$TMP_ROOT/resolution-config" out
  mkdir -p "$home/config" "$root/config" "$config"
  out=$(run_omp_calm_fixture "$home" "$root" "$config" true) || fail "OMP Calm override fixture failed: $out"
  [ -f "$config/calm" ] || fail "OMP Calm ignored FM_CONFIG_OVERRIDE"
  [ ! -e "$home/config/calm" ] || fail "OMP Calm wrote beside FM_CONFIG_OVERRIDE"
  rm -f "$config/calm"
  out=$(env -u FM_HOME FM_CONFIG_OVERRIDE= FM_ROOT_OVERRIDE="$root" EXT="$EXT" INITIAL_EXPANDED=true \
    node --input-type=module <<'JS'
import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";
const commands = new Map();
const api = { on() {}, registerCommand(name, command) { commands.set(name, command); } };
const extension = await import(`${pathToFileURL(process.env.EXT).href}?root=${Date.now()}`);
extension.default(api);
const ui = { getToolsExpanded: () => true, setToolsExpanded() {}, setWorkingMessage() {} };
await commands.get("calm").handler("", { ui });
if (readFileSync(`${process.env.FM_ROOT_OVERRIDE}/config/calm`, "utf8") !== "on\n") {
  throw new Error("OMP Calm ignored FM_ROOT_OVERRIDE when FM_HOME was unset");
}
JS
  ) || fail "OMP Calm root-resolution fixture failed: $out"
  [ ! -e "$ROOT/config/calm" ] || fail "OMP Calm wrote under the repository root"
  pass "OMP Calm resolves its preference from the effective Firstmate home, not OMP's launch directory"
}

test_omp_calm_command_lifecycle
test_omp_calm_home_resolution

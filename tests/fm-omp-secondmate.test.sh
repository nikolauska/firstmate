#!/usr/bin/env bash
# tests/fm-omp-secondmate.test.sh - persistent OMP secondmate launch, exact
# durable-session selection, duplicate-safe recovery, and abort preservation.
# shellcheck disable=SC2119,SC2120  # optional env arguments are fixture controls
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

BASE_PATH=${FM_TEST_BASE_PATH:-$PATH}
TMP_ROOT=$(fm_test_tmproot fm-omp-secondmate)
TASK_ID="omp-sm-$$"
WINDOW_NAME="fm-$TASK_ID"
PIDS=()
cleanup() {
  local pid
  for pid in "${PIDS[@]}"; do kill "$pid" 2>/dev/null || true; done
  rm -rf "$TMP_ROOT" "/tmp/fm-$TASK_ID"
}
trap cleanup EXIT

setup_case() { # <name>
  rm -rf "/tmp/fm-$TASK_ID"
  CASE="$TMP_ROOT/$1"
  MAIN_STATE="$CASE/main-state"
  MAIN_DATA="$CASE/main-data"
  MAIN_CONFIG="$CASE/main-config"
  MAIN_PROJECTS="$CASE/main-projects"
  HOME_DIR="$CASE/secondmate-home"
  FAKEBIN="$CASE/fakebin"
  TMUX_LOG="$CASE/tmux.log"
  HERDR_LOG="$CASE/herdr.log"
  LAUNCH_LOG="$CASE/launch"
  WINDOW_FLAG="$CASE/window"
  RETIRED_FLAG="$CASE/retired"
  mkdir -p "$MAIN_STATE" "$MAIN_DATA/$TASK_ID" "$MAIN_CONFIG" "$MAIN_PROJECTS" \
    "$HOME_DIR/.omp/extensions" "$HOME_DIR/state" "$HOME_DIR/config" "$HOME_DIR/data" "$HOME_DIR/projects" "$FAKEBIN" "$CASE/tmp"
  : > "$HERDR_LOG"
  cp "$ROOT/.omp/extensions/fm-primary-omp.ts" "$HOME_DIR/.omp/extensions/fm-primary-omp.ts"
  cp "$ROOT/AGENTS.md" "$HOME_DIR/AGENTS.md"
  ln -s "$ROOT/bin" "$HOME_DIR/bin"
  printf '%s\n' "$TASK_ID" > "$HOME_DIR/.fm-secondmate-home"
  printf 'OMP secondmate test charter.\n' > "$MAIN_DATA/$TASK_ID/brief.md"
  printf 'omp test/model low\n' > "$MAIN_CONFIG/secondmate-harness"
  printf 'pi\n' > "$MAIN_CONFIG/crew-harness"
  git -C "$HOME_DIR" init -q
  git -C "$HOME_DIR" config user.name fmtest
  git -C "$HOME_DIR" config user.email fmtest@example.com
  printf 'home\n' > "$HOME_DIR/README.md"
  git -C "$HOME_DIR" add README.md .omp/extensions/fm-primary-omp.ts
  git -C "$HOME_DIR" commit -qm init

  cat > "$FAKEBIN/omp" <<'JS'
#!/usr/bin/env bun
if (process.argv.includes("--hold")) {
  setInterval(() => {}, 60_000);
} else console.log(`OMP 17.1.8
--model=provider/id
--thinking=level
--auto-approve
--approval-mode=mode
--extension=path
--session-dir=path
--resume=path`);
JS
  chmod +x "$FAKEBIN/omp"
  TEST_OMP_BIN=$(fm_test_realpath "$FAKEBIN/omp")
  # A Node symlink supplies the fixture's Bun launch boundary without making
  # the portable deterministic lane depend on a host OMP/Bun installation.
  TEST_OMP_BUN=$(fm_test_realpath "$(command -v node)")
  ln -sf "$TEST_OMP_BUN" "$FAKEBIN/bun"
  "$TEST_OMP_BUN" "$TEST_OMP_BIN" --hold &
  AGENT_PID=$!
  PIDS+=("$AGENT_PID")

  cat > "$FAKEBIN/ps" <<'SH'
#!/usr/bin/env bash
case "$*" in
  *"tpgid="*"$FM_TEST_AGENT_PID"*) printf '%s\n' "$FM_TEST_AGENT_PID" ;;
  *"args="*"$FM_TEST_AGENT_PID"*) printf '%s %s --auto-approve\n' "$FM_TEST_OMP_BUN" "$FM_TEST_OMP_BIN" ;;
  *) exec /usr/bin/ps "$@" ;;
esac
SH
  chmod +x "$FAKEBIN/ps"

  cat > "$FAKEBIN/tmux" <<'SH'
#!/usr/bin/env bash
set -u
printf '%q ' "$@" >> "$FM_TEST_TMUX_LOG"
printf '\n' >> "$FM_TEST_TMUX_LOG"
cmd=${1:-}
shift || true
case "$cmd" in
  has-session|new-session|set-window-option|select-window) exit 0 ;;
  list-windows)
    if [ "${FM_TEST_STATE_MODE:-}" = unreadable ]; then
      printf 'permission denied\n' >&2
      exit 1
    fi
    [ -f "$FM_TEST_WINDOW_FLAG" ] && printf '%s\n' "$FM_TEST_WINDOW_NAME"
    ;;
  new-window)
    : > "$FM_TEST_WINDOW_FLAG"
    printf '@1\n'
    ;;
  display-message)
    case "$*" in
      *pane_current_command*)
        case "${FM_TEST_STATE_MODE:-live}" in
          ambiguous) printf 'node\n' ;;
          dead) [ -f "$FM_TEST_RETIRED_FLAG" ] && printf 'omp\n' || printf 'bash\n' ;;
          *) printf 'omp\n' ;;
        esac
        ;;
      *pane_pid*) printf '%s\n' "$FM_TEST_AGENT_PID" ;;
      *pane_current_path*) printf '%s\n' "$FM_TEST_HOME" ;;
      *'#S'*) printf 'firstmate\n' ;;
      *) printf '%%1\n' ;;
    esac
    ;;
  send-keys)
    args=("$@")
    for ((i=0; i<${#args[@]}; i++)); do
      if [ "${args[$i]}" = -l ] && [ $((i + 1)) -lt ${#args[@]} ]; then
        printf '%s\n' "${args[$((i + 1))]}" > "$FM_TEST_LAUNCH_LOG"
      fi
    done
    if [ "${args[${#args[@]}-1]:-}" = Enter ] && [ -s "$FM_TEST_LAUNCH_LOG" ] && [ "${FM_TEST_SKIP_ACK:-0}" != 1 ]; then
      mkdir -p "$FM_TEST_HOME/state/omp-sessions"
      session="$FM_TEST_HOME/state/omp-sessions/${FM_TEST_ACK_SESSION:-selected.jsonl}"
      printf '{"type":"session"}\n' > "$session"
      printf '%s\n' "$session" > "$FM_TEST_HOME/state/.omp-session"
      version=$(node -e 'const {createHash}=require("node:crypto"),{readFileSync}=require("node:fs");process.stdout.write("sha256:"+createHash("sha256").update(readFileSync(process.argv[1])).digest("hex"))' "$FM_TEST_HOME/.omp/extensions/fm-primary-omp.ts")
      printf '%s\n%s\n%s\n%s\n' "$version" "$FM_TEST_AGENT_PID" "$FM_TEST_OMP_BUN" "$FM_TEST_OMP_BIN" > "$FM_TEST_HOME/state/.omp-primary-extension-loaded"
      printf '%s\n' "$FM_TEST_AGENT_PID" > "$FM_TEST_HOME/state/.lock"
    fi
    ;;
  kill-window)
    rm -f "$FM_TEST_WINDOW_FLAG"
    : > "$FM_TEST_RETIRED_FLAG"
    ;;
esac
exit 0
SH
  chmod +x "$FAKEBIN/tmux"

  cat > "$FAKEBIN/herdr" <<'SH'
#!/usr/bin/env bash
set -u
printf '%q ' "$@" >> "$FM_TEST_HERDR_LOG"
printf '\n' >> "$FM_TEST_HERDR_LOG"
cmd=${1:-}
sub=${2:-}
case "$cmd $sub" in
  "status --json")
    printf '%s\n' '{"client":{"version":"0.7.5","protocol":17},"server":{"running":true}}'
    ;;
  "workspace list")
    printf '{"result":{"workspaces":[{"workspace_id":"w1","label":"2ndmate-%s"}]}}\n' "$FM_TEST_TASK_ID"
    ;;
  "tab list")
    printf '%s\n' '{"result":{"tabs":[]}}'
    ;;
  "tab create")
    : > "$FM_TEST_WINDOW_FLAG"
    printf '%s\n' '{"result":{"tab":{"tab_id":"w1:t2"},"root_pane":{"pane_id":"w1:p2"}}}'
    ;;
  "pane get")
    if [ ! -f "$FM_TEST_WINDOW_FLAG" ]; then
      printf '%s\n' '{"error":{"code":"pane_not_found"}}' >&2
      exit 1
    fi
    if [ "${FM_TEST_STATE_MODE:-}" = unreadable ] && [ ! -f "$FM_TEST_RETIRED_FLAG" ]; then
      printf '%s\n' '{"error":{"code":"internal_error"}}' >&2
      exit 1
    fi
    printf '{"result":{"pane":{"pane_id":"w1:p2","foreground_cwd":"%s"}}}\n' "$FM_TEST_HOME"
    ;;
  "agent get")
    if [ ! -f "$FM_TEST_WINDOW_FLAG" ]; then
      printf '%s\n' '{"error":{"code":"agent_not_found"}}' >&2
      exit 1
    fi
    if [ "${FM_TEST_STATE_MODE:-}" = dead ] && [ ! -f "$FM_TEST_RETIRED_FLAG" ]; then
      printf '%s\n' '{"error":{"code":"agent_not_found"}}' >&2
      exit 1
    fi
    if [ "${FM_TEST_STATE_MODE:-}" = unreadable ] && [ ! -f "$FM_TEST_RETIRED_FLAG" ]; then
      printf '%s\n' '{"error":{"code":"internal_error"}}' >&2
      exit 1
    fi
    printf '%s\n' '{"result":{"agent":{"agent":"omp","agent_status":"idle"}}}'
    ;;
  "pane run")
    ;;
  "pane send-text")
    printf '%s\n' "${4:-}" > "$FM_TEST_LAUNCH_LOG"
    ;;
  "pane send-keys")
    if [ "${4:-}" = enter ] && [ -s "$FM_TEST_LAUNCH_LOG" ] && [ "${FM_TEST_SKIP_ACK:-0}" != 1 ]; then
      mkdir -p "$FM_TEST_HOME/state/omp-sessions"
      session="$FM_TEST_HOME/state/omp-sessions/${FM_TEST_ACK_SESSION:-selected.jsonl}"
      printf '{"type":"session"}\n' > "$session"
      printf '%s\n' "$session" > "$FM_TEST_HOME/state/.omp-session"
      version=$(node -e 'const {createHash}=require("node:crypto"),{readFileSync}=require("node:fs");process.stdout.write("sha256:"+createHash("sha256").update(readFileSync(process.argv[1])).digest("hex"))' "$FM_TEST_HOME/.omp/extensions/fm-primary-omp.ts")
      printf '%s\n%s\n%s\n%s\n' "$version" "$FM_TEST_AGENT_PID" "$FM_TEST_OMP_BUN" "$FM_TEST_OMP_BIN" > "$FM_TEST_HOME/state/.omp-primary-extension-loaded"
      printf '%s\n' "$FM_TEST_AGENT_PID" > "$FM_TEST_HOME/state/.lock"
    fi
    ;;
  "pane close")
    rm -f "$FM_TEST_WINDOW_FLAG"
    : > "$FM_TEST_RETIRED_FLAG"
    ;;
esac
exit 0
SH
  chmod +x "$FAKEBIN/herdr"

  cat > "$FAKEBIN/treehouse" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FM_TEST_TREEHOUSE_LOG"
exit 1
SH
  chmod +x "$FAKEBIN/treehouse"
  : > "$CASE/treehouse.log"
}

run_spawn() { # [extra env NAME=VALUE ...]
  env \
    PATH="$FAKEBIN:$BASE_PATH" \
    TMPDIR="$CASE/tmp" \
    FM_ROOT_OVERRIDE="$ROOT" \
    FM_STATE_OVERRIDE="$MAIN_STATE" \
    FM_DATA_OVERRIDE="$MAIN_DATA" \
    FM_CONFIG_OVERRIDE="$MAIN_CONFIG" \
    FM_PROJECTS_OVERRIDE="$MAIN_PROJECTS" \
    FM_BACKEND=tmux \
    FM_TEST_TMUX_LOG="$TMUX_LOG" \
    FM_TEST_LAUNCH_LOG="$LAUNCH_LOG" \
    FM_TEST_WINDOW_FLAG="$WINDOW_FLAG" \
    FM_TEST_RETIRED_FLAG="$RETIRED_FLAG" \
    FM_TEST_WINDOW_NAME="$WINDOW_NAME" \
    FM_TEST_AGENT_PID="$AGENT_PID" \
    FM_TEST_OMP_BIN="$TEST_OMP_BIN" \
    FM_TEST_OMP_BUN="$TEST_OMP_BUN" \
    FM_TEST_HOME="$HOME_DIR" \
    FM_TEST_TREEHOUSE_LOG="$CASE/treehouse.log" \
    FM_TEST_STATE_MODE="${FM_TEST_STATE_MODE:-}" \
    FM_TEST_SKIP_ACK="${FM_TEST_SKIP_ACK:-0}" \
    FM_OMP_SECONDMATE_ACK_POLLS=3 \
    FM_OMP_LAUNCH_ACK_INTERVAL=0.01 \
    "$@" \
    "$ROOT/bin/fm-spawn.sh" "$TASK_ID" "$HOME_DIR" --secondmate
}

run_spawn_herdr() { # [extra env NAME=VALUE ...]
  env \
    PATH="$FAKEBIN:$BASE_PATH" \
    TMPDIR="$CASE/tmp" \
    FM_ROOT_OVERRIDE="$ROOT" \
    FM_STATE_OVERRIDE="$MAIN_STATE" \
    FM_DATA_OVERRIDE="$MAIN_DATA" \
    FM_CONFIG_OVERRIDE="$MAIN_CONFIG" \
    FM_PROJECTS_OVERRIDE="$MAIN_PROJECTS" \
    FM_BACKEND=herdr \
    HERDR_SESSION=fmtest \
    FM_TEST_HERDR_LOG="$HERDR_LOG" \
    FM_TEST_LAUNCH_LOG="$LAUNCH_LOG" \
    FM_TEST_WINDOW_FLAG="$WINDOW_FLAG" \
    FM_TEST_RETIRED_FLAG="$RETIRED_FLAG" \
    FM_TEST_AGENT_PID="$AGENT_PID" \
    FM_TEST_OMP_BIN="$TEST_OMP_BIN" \
    FM_TEST_OMP_BUN="$TEST_OMP_BUN" \
    FM_TEST_HOME="$HOME_DIR" \
    FM_TEST_TASK_ID="$TASK_ID" \
    FM_TEST_TREEHOUSE_LOG="$CASE/treehouse.log" \
    FM_TEST_STATE_MODE="${FM_TEST_STATE_MODE:-}" \
    FM_TEST_SKIP_ACK="${FM_TEST_SKIP_ACK:-0}" \
    FM_OMP_SECONDMATE_ACK_POLLS=3 \
    FM_OMP_LAUNCH_ACK_INTERVAL=0.01 \
    "$@" \
    "$ROOT/bin/fm-spawn.sh" "$TASK_ID" "$HOME_DIR" --secondmate
}

count_new_windows() {
  # shellcheck disable=SC2126  # wc keeps a zero count readable when grep finds none
  grep '^new-window ' "$TMUX_LOG" 2>/dev/null | wc -l | tr -d '[:space:]'
}

write_meta() {
  cat > "$MAIN_STATE/$TASK_ID.meta" <<EOF_META
window=firstmate:$WINDOW_NAME
endpoint_task_id=$TASK_ID
worktree=$HOME_DIR
project=$HOME_DIR
harness=omp
model=test/model
effort=low
kind=secondmate
home=$HOME_DIR
omp_bin=$TEST_OMP_BIN
omp_bun=$TEST_OMP_BUN
backend=tmux
EOF_META
}

write_herdr_meta() {
  cat > "$MAIN_STATE/$TASK_ID.meta" <<EOF_META
window=fmtest:w1:p2
endpoint_task_id=$TASK_ID
worktree=$HOME_DIR
project=$HOME_DIR
harness=omp
model=test/model
effort=low
kind=secondmate
home=$HOME_DIR
omp_bin=$TEST_OMP_BIN
omp_bun=$TEST_OMP_BUN
backend=herdr
herdr_session=fmtest
herdr_workspace_id=w1
herdr_tab_id=w1:t2
herdr_pane_id=w1:p2
EOF_META
}

test_herdr_launch_exact_resume_recovery_and_abort() {
  local out selected before
  setup_case herdr-launch

  out=$(run_spawn_herdr 2>&1) || fail "fresh OMP Herdr secondmate spawn failed: $out"
  assert_contains "$(cat "$LAUNCH_LOG")" "'$TEST_OMP_BUN' '$TEST_OMP_BIN' --session-dir '$HOME_DIR/state/omp-sessions'" \
    "OMP Herdr secondmate launch did not use its canonical Bun/OMP pair and isolated session directory"
  assert_contains "$(cat "$MAIN_STATE/$TASK_ID.meta")" 'harness=omp' "OMP Herdr secondmate identity was not exact"
  assert_contains "$(cat "$MAIN_STATE/$TASK_ID.meta")" 'backend=herdr' "OMP Herdr secondmate backend was not recorded"
  assert_contains "$(cat "$MAIN_STATE/$TASK_ID.meta")" 'herdr_pane_id=w1:p2' "OMP Herdr secondmate exact pane was not recorded"
  selected="$HOME_DIR/state/omp-sessions/selected.jsonl"
  [ -f "$selected" ] || fail "OMP Herdr secondmate acknowledgement did not create its selected durable session"

  rm -f "$WINDOW_FLAG" "$HOME_DIR/state/.omp-primary-extension-loaded" "$HOME_DIR/state/.lock"
  : > "$LAUNCH_LOG"
  out=$(FM_TEST_STATE_MODE=missing run_spawn_herdr 2>&1) || fail "OMP Herdr secondmate exact resume failed: $out"
  assert_contains "$(cat "$LAUNCH_LOG")" "--resume '$selected'" \
    "OMP Herdr secondmate recovery did not resume the pointer-bound exact session"

  setup_case herdr-live-refusal
  write_herdr_meta
  : > "$WINDOW_FLAG"
  before=$(grep -c '^tab create ' "$HERDR_LOG" 2>/dev/null || true)
  out=$(FM_TEST_STATE_MODE=alive run_spawn_herdr 2>&1) && fail "OMP Herdr secondmate accepted a live duplicate"
  assert_contains "$out" 'already has a live agent' "OMP Herdr live duplicate refusal was not actionable"
  [ "$(grep -c '^tab create ' "$HERDR_LOG" 2>/dev/null || true)" = "$before" ] \
    || fail "OMP Herdr live duplicate refusal created another endpoint: $(cat "$HERDR_LOG")"

  setup_case herdr-unreadable-refusal
  write_herdr_meta
  : > "$WINDOW_FLAG"
  out=$(FM_TEST_STATE_MODE=unreadable run_spawn_herdr 2>&1) && fail "OMP Herdr secondmate accepted an unreadable duplicate"
  assert_contains "$out" 'endpoint state is unreadable' "OMP Herdr unreadable duplicate refusal was not actionable"

  setup_case herdr-dead-recovery
  write_herdr_meta
  : > "$WINDOW_FLAG"
  out=$(FM_TEST_STATE_MODE=dead run_spawn_herdr 2>&1) || fail "dead OMP Herdr secondmate did not recover: $out"
  assert_contains "$(cat "$HERDR_LOG")" 'pane close w1:p2' "dead OMP Herdr endpoint was not retired"
  assert_contains "$(cat "$HERDR_LOG")" 'tab create' "dead OMP Herdr secondmate was not relaunched"

  setup_case herdr-abort
  printf 'preserve me\n' > "$HOME_DIR/state/sentinel"
  out=$(FM_TEST_SKIP_ACK=1 run_spawn_herdr 2>&1) && fail "OMP Herdr secondmate launch unexpectedly succeeded without acknowledgement"
  assert_contains "$out" 'preserving the persistent home' "OMP Herdr acknowledgement failure did not preserve its home contract"
  [ -f "$HOME_DIR/state/sentinel" ] || fail "OMP Herdr secondmate abort removed persistent home state"
  [ -f "$MAIN_STATE/$TASK_ID.meta" ] || fail "OMP Herdr secondmate abort removed recovery metadata"
  [ ! -f "$WINDOW_FLAG" ] || fail "OMP Herdr secondmate abort left its owned endpoint running"
  [ ! -s "$CASE/treehouse.log" ] || fail "OMP Herdr secondmate abort invoked treehouse against a persistent home"

  pass "OMP Herdr secondmate launch, exact resume, conservative recovery, and post-ack abort preserve the durable contract"
}
test_herdr_launch_exact_resume_recovery_and_abort

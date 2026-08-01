#!/usr/bin/env bash
set -u

. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot lavish-share-tests)
FAKEBIN=$(fm_fakebin "$TMP_ROOT")
ARGS_LOG="$TMP_ROOT/args"
ARTIFACT="$TMP_ROOT/artifact.html"
TOKEN_SECRET='token-secret-7f1a'
UPDATE_SECRET='update-secret-82bd'
PASSWORD_SECRET='password-secret-91ce'

printf '<!doctype html><title>Safe share</title>\n' > "$ARTIFACT"

cat > "$FAKEBIN/lavish-axi" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$ARGS_LOG"
[ "${LAVISH_AXI_HTML_APP_TOKEN:-}" = "$TOKEN_SECRET" ] || exit 9
printf '%s\n' \
  'share:' \
  "  url: https://example.invalid/review" \
  "  update_key: $UPDATE_SECRET" \
  "next_step: reflected $TOKEN_SECRET and $PASSWORD_SECRET"
printf 'stderr reflected %s\n' "$UPDATE_SECRET" >&2
SH
chmod +x "$FAKEBIN/lavish-axi"

out=$(PATH="$FAKEBIN:$PATH" \
  ARGS_LOG="$ARGS_LOG" \
  TOKEN_SECRET="$TOKEN_SECRET" \
  UPDATE_SECRET="$UPDATE_SECRET" \
  PASSWORD_SECRET="$PASSWORD_SECRET" \
  LAVISH_AXI_HTML_APP_TOKEN="$TOKEN_SECRET" \
  "$ROOT/.agents/skills/lavish/scripts/share-safe.sh" "$ARTIFACT" 2>&1)

[ "$out" = 'https://example.invalid/review' ] || fail "safe share returned more than the visitable URL: $out"
for secret in "$TOKEN_SECRET" "$UPDATE_SECRET" "$PASSWORD_SECRET"; do
  case "$out" in
    *"$secret"*) fail "safe share exposed a secret in returned output" ;;
  esac
  if grep -F "$secret" "$ARGS_LOG" >/dev/null; then
    fail "safe share exposed a secret in command arguments"
  fi
done

expected_args=$(printf 'share\n%s' "$ARTIFACT")
actual_args=$(cat "$ARGS_LOG")
[ "$actual_args" = "$expected_args" ] || fail "safe share invoked lavish-axi with unexpected arguments: $actual_args"
pass "safe share exposes only the URL and keeps secrets out of arguments"

rm -f "$ARGS_LOG"
if PATH="$FAKEBIN:$PATH" \
  "$ROOT/.agents/skills/lavish/scripts/share-safe.sh" "$ARTIFACT" "$PASSWORD_SECRET" \
  >"$TMP_ROOT/rejected.out" 2>&1; then
  fail "safe share accepted a password argument"
fi
[ ! -e "$ARGS_LOG" ] || fail "safe share invoked lavish-axi after rejecting a password argument"
if grep -F "$PASSWORD_SECRET" "$TMP_ROOT/rejected.out" >/dev/null; then
  fail "safe share exposed a rejected password argument"
fi
pass "safe share rejects password arguments before invoking lavish-axi"

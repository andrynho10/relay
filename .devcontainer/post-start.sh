#!/usr/bin/env bash
# Runs every time the container starts. Warns, never fails: a missing agent should not block
# opening the container, but commits would be rejected by the `main` ruleset without a signature.
set -uo pipefail

signing_key="$(git config --get user.signingkey || true)"

if [[ -z "${signing_key}" || "${signing_key}" == "key::" ]]; then
  echo "WARNING: RELAY_GIT_SIGNING_KEY is not set on the host; commits will not be signed."
  echo "         See docs/adr/0009-devcontainer.md (commit signing)."
  exit 0
fi

if ! agent_keys="$(ssh-add -L 2>/dev/null)"; then
  echo "WARNING: no SSH agent forwarded from the host; commits cannot be signed."
  echo "         Start the host ssh-agent with the signing key loaded and reopen the container."
  exit 0
fi

# Compare type and key material only; the comment may differ.
wanted="$(cut -d' ' -f1,2 <<<"${signing_key#key::}")"
if ! grep -qF "${wanted}" <<<"$(cut -d' ' -f1,2 <<<"${agent_keys}")"; then
  echo "WARNING: the signing key is not loaded in the forwarded SSH agent; run ssh-add on the host."
  exit 0
fi

echo "Commit signing: OK (key found in the forwarded SSH agent)."

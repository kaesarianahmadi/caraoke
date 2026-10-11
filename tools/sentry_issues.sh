#!/usr/bin/env bash
# Fetch latest crash issues from Sentry API for caraokeapp/apple-ios
# Usage: ./tools/sentry_issues.sh [LIMIT]
# Requires SENTRY_AUTH_TOKEN in environment or ~/.sentryclirc

TOKEN="${SENTRY_AUTH_TOKEN}"
if [ -z "$TOKEN" ] && [ -f "$PWD/.env" ]; then
    TOKEN=$(grep -E "^SENTRY_AUTH_TOKEN=" "$PWD/.env" | cut -d= -f2- | tr -d ' "')
fi
if [ -z "$TOKEN" ] && [ -f "$HOME/.sentryclirc" ]; then
    TOKEN=$(grep -E "^token=" "$HOME/.sentryclirc" | cut -d= -f2 | tr -d ' "')
fi

if [ -z "$TOKEN" ]; then
    echo "ERROR: SENTRY_AUTH_TOKEN not set."
    echo "Create a token at https://caraokeapp.sentry.io/settings/account/api/auth-tokens/ (scopes: project:read, event:read)"
    echo "Then export SENTRY_AUTH_TOKEN=\"<token>\" or add token=<token> to ~/.sentryclirc"
    exit 1
fi

LIMIT="${1:-5}"
curl -s -H "Authorization: Bearer $TOKEN" \
    "https://sentry.io/api/0/projects/caraokeapp/apple-ios/issues/?limit=${LIMIT}"

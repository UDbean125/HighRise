#!/usr/bin/env bash
#
# Reproducible dry run of HighRise's CSV → merge → AppleScript pipeline.
#
# Compiles the real, Foundation-only core (no AppKit, no Mail) together with a
# small driver and prints the AppleScript that *would* be sent for each sendable
# recipient — and why each blocked one was held back. Nothing is sent and Mail
# is never launched, so it's safe to run anywhere a Swift toolchain exists
# (macOS, or Linux with the open-source toolchain).
#
# Usage:
#   ./Tools/dry-run.sh [path/to/recipients.csv]
#
# Defaults to Examples/sample-recipients.csv.
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v swiftc >/dev/null 2>&1; then
    echo "swiftc not found — install the Swift toolchain (Xcode on macOS)." >&2
    exit 1
fi

# The exact source the app ships, in dependency order, plus the driver. These
# files are all Foundation-only; MailSender/Coordinator (AppKit, os) are
# deliberately excluded since the dry run never executes a script.
SRC=(
  HighRise/Models/Contact.swift
  HighRise/Models/RecipientTable.swift
  HighRise/Models/EmailTemplate.swift
  HighRise/Models/MergePreview.swift
  HighRise/Models/MailClient.swift
  HighRise/Services/EmailValidator.swift
  HighRise/Services/CSVParser.swift
  HighRise/Services/TemplateMergeEngine.swift
  HighRise/Services/AppleScriptBuilder.swift
  Tools/dry-run/main.swift
)

BIN="$(mktemp -d)/highrise-dryrun"
swiftc -o "$BIN" "${SRC[@]}"
"$BIN" "${1:-Examples/sample-recipients.csv}"

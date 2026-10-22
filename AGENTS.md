# Working through the user's Tera Term

When asked to execute a procedure on a device through this project, use the
existing visible Tera Term session and the local teraterm_logger.ps1 interface.
Read README.ja.md and docs/ai-workflow.md first. Device commands are sent by the
resident Tera Term macro; do not substitute another SSH or serial connection.

- List sessions and identify the intended host and log. Require an exact session
  ID; ask the user only when the intended session cannot be identified.
- Translate the authorized procedure into a plan. Always provide both range
  endpoints. The user does not need to write JSON or name log files.
- Match the actual device prompt, terminal mode, and expected responses. Inspect
  command output: observing a prompt is not proof the operation succeeded.
- Read Status until the requested run ends. Report the run ID, last sent step,
  last step whose expected response was observed, outcome, and log path.
- On timeout, error, or disconnect, stop and inspect the terminal and log. Do not
  automatically resend an uncertain command. Acknowledge only after the current
  outcome and prompt have been checked; it does not execute a command.

Development checks run with Windows PowerShell 5.1. The workflow integration
test uses only its own localhost mock device and isolated settings, never an
existing device session.

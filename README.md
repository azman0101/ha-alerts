# ha-alerts

## Shared agent skill

The reusable Android Rust/UniFFI skill has one canonical source:

- `.agents/skills/rust-uniffi-android/`: shared discovery path used by Codex and supported by Copilot CLI.
- `.claude/skills/rust-uniffi-android`: relative symlink to that directory for Claude Code discovery.

Edit the canonical directory; both paths expose the same instructions, references,
workflow template, and evaluations. Git tracks the symlink. On systems where Git
checks symlinks out as plain text files, enable symlink support or create a local
copy at the Claude path instead.

Discovery does not mean a skill is always loaded: the agent selects it when relevant
or when explicitly invoked. Agent-specific extensions may not work across clients.

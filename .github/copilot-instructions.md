## Purpose

This file gives succinct, actionable guidance to an AI coding agent working in this repository. It focuses on the high-value, discoverable patterns an agent should check first and the exact places to look for project-specific behavior.

> NOTE: a quick scan found no repository files in the current workspace snapshot. The guidance below therefore uses concrete, discoverable checks and placeholders — replace the placeholders with actual paths/names after a code scan.

### Immediate actions for the agent

- Run a repository-wide search for: `package.json`, `pyproject.toml`, `Pipfile`, `requirements.txt`, `Dockerfile`, `docker-compose.yml`, `Makefile`, `README.md`, `.github/workflows/*`, `src/`, `app/`, `services/`, `cmd/`.
- Identify the primary language/runtime from those manifests. Use the package manager scripts to infer build/test/debug commands.
- If a `.github/copilot-instructions.md` already exists, merge: preserve any custom sections and append or update the "Agent checklist" and "Key files" sections below.

### Agent checklist (quick, actionable)

1. Determine language/runtime:
   - Look for `package.json` (node), `pyproject.toml`/`requirements.txt` (python), `go.mod` (Go), `pom.xml` (Java), etc.
2. Find build/test commands:
   - For Node: `npm run build`, `npm test`; check `scripts` in `package.json`.
   - For Python: check `pyproject.toml` or `tox.ini` or `Makefile` for `test`, `lint` targets.
3. Check CI for extra steps: open `.github/workflows/*.yml` to find matrixes, additional linters, or secret requirements.
4. Identify entry points and services:
   - Look for `src/index.ts`, `src/main.py`, `cmd/*` or `services/*`.
5. Locate external integrations:
   - Look for `env` file references, `.env.example`, `docker-compose.yml`, or cloud infra files.
6. Search for architectural hints:
   - Directories: `api/`, `internal/`, `pkg/`, `lib/`, `worker/`, `migrations/`.

### What to document in this file (concise, concrete)

- Big-picture architecture (how components map to dirs/files). Example: "`/api` contains the HTTP handlers; `/worker` processes background jobs and reads from `redis`." Replace with real paths.
- Exact build, test and run commands discovered (copy from `package.json`, Makefile, or CI). These must be runnable in the developer shell.
- Unusual conventions you discover (e.g., single repo with many services under `services/*`, versioned migrations in `db/migrations`, codegen step required before build).
- Integration points and secrets (which env vars matter, where secrets are loaded, and what services are required to run locally).
- Patterns for PRs or commits if the repo enforces something unique (e.g., changelog generation, semantic-release, conventional commits).

### Examples and concrete checks (replace examples with real ones)

- If `package.json` exists, copy the `scripts` entries under "Build & test commands".
- If `docker-compose.yml` exists and contains a `db:` service, note how to start it: `docker-compose up db`.
- If there is a `services/` directory, list each service and its start command (e.g., `services/auth/README.md` -> `npm start`).

### Merge guidance (when updating existing copilot-instructions.md)

- Preserve non-agent-facing content. Only modify or append agent-specific sections:
  - `Agent checklist`
  - `Build & test commands`
  - `Key files`
- Add a short changelog entry at the bottom with date and agent initials when the file is updated.

### Minimal agent contract (2–3 bullets)

- Inputs: repository files, CI manifests, manifest files (`package.json`, `pyproject.toml`, `Dockerfile`).
- Outputs: updated `.github/copilot-instructions.md` containing (a) detected language/runtime, (b) precise build/test/run commands, (c) 6–10 high-value file pointers, (d) any non-obvious conventions.

### When you cannot discover something

- If key files are missing (no manifests, no README), add an explicit `TODO: missing manifest` block and ask the human for guidance. Don’t guess runtime or commands.

---

If you want I can now attempt a full scan and populate the placeholders above with real paths and commands — grant access to the repo snapshot or push the repository files, and I'll update this file with discovered, concrete examples.

Please review and tell me which sections you'd like expanded or any repo-specific details I should include.

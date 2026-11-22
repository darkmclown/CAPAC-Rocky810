# AGENTS guide: [fill in: project name]

<!--
TEMPLATE. Before agents use this file:
1. Replace every [fill in: ...] placeholder in "Project facts" and "Project notes".
2. Delete this comment.
3. Keep the file under 250 lines. Long explanations belong in agent/architecture/.
The section between the agent-layer markers is managed by the installer. Do not edit it by hand.
-->

Read this whole file at the start of every run. It is the map of the project.

## Project facts

| Fact | Value |
|---|---|
| What it does | [fill in: one sentence a new engineer would understand] |
| Who uses it | [fill in: roles or teams] |
| Status | [fill in: active / migrating from legacy / maintenance only] |
| Owner | [fill in: person who approves risky work] |
| Solution name | `<solution_name>` |
| Source folder | `src/<namespace>/<solution_name>/` |
| User interface | [fill in: Dash / none] |
| Ansys products used | [fill in: for example Mechanical, Fluent, MAPDL, or none] |
| Deployment | [fill in: desktop / on-premises / cloud] |
| Legacy code | [fill in: none, or in legacy/ and being ported feature by feature] |

### Flows that must never break

1. [fill in: the most important thing a user does with this solution]
2. [fill in: the second most important]

Run the tests for these flows before and after every change that touches them.

## SAF essentials

This project is a SAF solution. SAF hosts the application; do application work through the `saf` CLI, which the `just` recipes wrap.

| Part | Where | What it holds |
|---|---|---|
| Solution definition | `src/<namespace>/<solution_name>/solution/definition.py` | The steps of the workflow |
| Steps | `src/<namespace>/<solution_name>/solution/*.py` | One `StepModel` class per step: fields and `@transaction` methods |
| MCP guidance | `src/<namespace>/<solution_name>/solution/SOLUTION.md` | How to drive the running solution |
| User interface | `src/<namespace>/<solution_name>/ui/` | `app.py`, `pages/`, `assets/` |
| Tests | `tests/` | pytest tests using SAF's fixtures |
| User documentation | `doc/` | Sphinx sources |
| Deployment recipes | `deployments/` | Docker Compose files |

| Task | Command |
|---|---|
| Install or repair the environment | `just setup` |
| Run the tests | `just test` |
| Run the solution | `just run`, `just run --browser`, `just run-api` |
| Add a step from a template | `just add-step <name> <template>` |
| Run any command in the solution environment | `saf execute <solution_name> "<command>"` |
| Add a dependency | `saf execute <solution_name> "poetry add <package>"` |
| See a command's options | `saf <command> --help` |

Code follows PEP 8 with 120-character lines, type hints on public APIs and numpydoc docstrings. Add or update tests with every change in behaviour.

## Project notes

### Traps specific to this project

- [fill in: something that surprised the last person who worked here]

### External systems

- [fill in: system, what it is used for, and who to ask about it; or "none"]

<!-- agent-layer:start (managed by saf-agent-layer; change agent/ files, not this block) -->
## Agent layer

This project runs on the team platform: SAF hosts the application and the agent layer holds what agents need to work on it. [agent/standard.md](agent/standard.md) is the full reference.

### Every run

1. Read this file.
2. Run `just task-claim <id>`. It creates the task branch, opens a run and pushes the claim.
3. Load the skill that matches the task. Use `just find <term>` to locate the few files you need.
4. Do the work. Commit as `<type>: <summary> [<task-id>]`.
5. Run `just check` until it passes.
6. Update the entity files you touched, add a decision record if the design changed, and fill in the run summary.
7. Run `just task-done <id>`, then push and open a pull request.

Run `just --list` for every command. Without `just`, run `python agent/tools/agentkit.py --help`.

### Where things are

| Need | Where |
|---|---|
| Steps, transactions, UI pages, data sets | `agent/knowledge/entities/` |
| Why things are built this way | `agent/decisions/` |
| How parts work together | `agent/architecture/` |
| Work to do | `agent/tasks/backlog/` |
| What earlier runs did | `agent/logs/` |
| Data and heavy assets that exist | `local.manifest.jsonl` |
| How to drive the running solution | `SOLUTION.md` beside `definition.py` |
| Old project being ported | `legacy/`, only when a task points there |

### Rules

- Never commit `local/`. Secrets go in `local/secrets.env`, never in `.env`.
- Never work on the base branch, and never bypass git hooks.
- Change dependencies only through `saf execute`. Never edit `pyproject.toml` or `poetry.lock` by hand.
- Ask a human before anything irreversible: deploys, deletes, spending, and data or project migrations.
- Mark what you could not confirm as unverified. Never guess.
- Branch: `<feature|bugfix|hotfix|refactor>/T-0042-short-name`. Commit: `<type>: <summary> [T-0042]`.

### Skills

Load a skill from `agent/skills/<name>/SKILL.md` when its description matches the task.

- `add-step`: Use when the task needs a new workflow step in the solution.
- `change-backend`: Use when changing a step's fields or transaction methods, or the solution definition, in the GLOW backend.
- `change-ui`: Use when changing Dash pages or UI assets of the solution.
- `find-context`: Use before opening source files, to locate the few files a task needs through the index instead of scanning the project.
- `finish-task`: Use when the work is complete, to check it, write the run summary, close the task and open a pull request.
- `investigate-failed-run`: Use when a run, a check or the solution itself failed and you need to find out why.
- `manage-dependencies`: Use when adding, removing or updating a Python dependency of the solution.
- `port-legacy-feature`: Use when moving one feature from the old project in legacy/ into the SAF solution.
- `start-task`: Use at the start of every run, before touching any file, to claim a task and open a run.
- `update-knowledge`: Use after changing code, to bring entity files, decisions and SOLUTION.md back in line with it.
- `verify-with-mcp`: Use to verify a backend change end to end by driving the running solution through SAF's MCP server.
<!-- agent-layer:end -->

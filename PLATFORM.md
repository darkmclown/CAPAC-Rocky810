# Agent-driven development platform

Version 1.1 | 22 November 2026

This document describes the platform every team project moves to: its architecture, default tools, folder structure, workflows and the migration plan. It is written for the team and for agents that migrate projects.

Three documents work together:

| Document | Scope | Where |
|---|---|---|
| `PLATFORM.md` (this file) | The whole platform, once for the team | The kit repository |
| `AGENTS.md` | The map of one project, read by agents at the start of every run | Root of each project |
| `agent/standard.md` | The detailed rules of the agent layer | Each project |

## 1. Purpose

- Agents can work on any project without scanning it, because every project has the same map, commands and knowledge layout.
- Every project looks the same, so people and agents move between projects without relearning.
- People stay in control: agents do the work of a task, and humans approve anything irreversible.

## 2. Architecture

```
+--------------------------------------------------------------------+
| People      write tasks, review pull requests, approve risky work  |
+--------------------------------------------------------------------+
| Agents      any tool that reads AGENTS.md and can run commands     |
+--------------------------------------------------------------------+
| Commands    just  ->  saf CLI  +  agentkit                         |
+----------------------+----------------------+----------------------+
| Agent layer          | SAF host             | Git and CI           |
| agent/               | src/ tests/ doc/     | hooks, workflows,    |
| knowledge, tasks,    | GLOW backend, UI,    | branch and commit    |
| run logs, skills,    | MCP server, tests,   | rules, pull request  |
| tooling              | packaging            | template             |
+----------------------+----------------------+----------------------+
| Local store (not in git)   index, run events, data, assets, secrets|
+--------------------------------------------------------------------+
```

| Layer | Responsibility | Lives in | Owned by |
|---|---|---|---|
| People | Write tasks, review pull requests, approve irreversible actions | GitHub | The team |
| Agents | Do the work of one task, following `AGENTS.md` and the skills | Any agent tool | Whoever runs them |
| Commands | One entry point for every operation | `justfile` | The kit |
| SAF host | The application: backend, UI, tests, documentation, packaging, MCP server | `src/`, `tests/`, `doc/`, `deployments/` | SAF |
| Agent layer | Knowledge, decisions, tasks, run logs, skills, tooling | `agent/` | The kit and the project |
| Git and CI | Hooks, workflows, branch and commit rules, pull request template | `.pre-commit-config.yaml`, `.github/` | SAF and the kit |
| Local store | Index, run events, data, heavy assets, secrets | `local/` | Each machine |

### Design decisions

| Decision | Reason |
|---|---|
| SAF is the host and is never modified | Solutions stay upgradable with SAF's own tools |
| Everything the layer adds sits under `agent/` | SAF already uses `doc/`, `tests/` and `deployments/`, so nothing collides |
| Knowledge is drafted from code and checked for drift | Hand-written knowledge goes stale; a task cannot close while it lags |
| One ignored directory, `local/` | One rule for what never enters git |
| Tool-neutral: `AGENTS.md` plus plain skill folders | The team is not tied to one agent product |
| Tooling uses only Python's standard library | It runs in any environment with no install step |

## 3. Default tools

| Tool | Role | Needed | Notes |
|---|---|---|---|
| Python 3.11 or newer | Runtime for SAF and the tooling | Required | The tooling itself runs on 3.9 or newer |
| git | Version control and task claims | Required | |
| SAF CLI (`saf`) | Create, install, run, extend and package solutions | Required for SAF projects | |
| Poetry | Dependencies | Installed by `saf install` | Always used through `saf execute` |
| agentkit | Validate, scan, index, tasks, runs, manifest, git checks | Included in the kit | `agent/tools/agentkit.py` |
| just | The command surface | Recommended | Without it, call agentkit and `saf` directly |
| pytest | Tests | Required | With SAF's fixtures |
| pre-commit | Runs SAF's style hooks and the layer's hooks | Recommended | Fallback: `just hooks-native` |
| Gitleaks | Secret scanning | With pre-commit | Same revision SAF pins |
| GitHub Actions | Checks on pull requests | Recommended | The `Agent layer` workflow plus SAF's workflows |
| GLOW MCP server | Lets an agent drive the running solution | Optional per project | Needs the `core-mcp` extra |
| ripgrep | Fast text search | Recommended | |
| fd, ast-grep | File search; search and rewrite by syntax | Optional | |
| DuckDB | SQL over run events and the index | Optional | |

Add these only when the trigger applies:

| Addition | Trigger |
|---|---|
| A code graph MCP server, for example codebase-memory-mcp | The repository is too large for search to stay cheap |
| Serena | Edits need exact references and renames |
| Graphiti | Facts change often and their history matters |
| Langfuse | Several agents run at once and you need to see their traces |
| Object storage or Git LFS | More than one machine needs the data and heavy assets |

## 4. Folder structure

```
<solution>/
├── AGENTS.md                  project map: facts, SAF essentials, agent-layer section
├── justfile                   all commands
├── local.manifest.jsonl       list of irreplaceable files kept in local/
├── agent/                     the agent layer
│   ├── standard.md            detailed rules
│   ├── config.json            layer settings
│   ├── skills/                one folder per procedure, each with SKILL.md
│   ├── templates/             entity, task, decision and summary templates
│   ├── architecture/          how parts work together
│   ├── decisions/             numbered, append-only decision records
│   ├── knowledge/entities/    one file per step, UI page, service or data set
│   ├── tasks/                 backlog/ active/ done/
│   ├── logs/                  run summaries: <date>/<run-id>.md
│   ├── artifacts/             small agent outputs
│   └── tools/agentkit.py      the tooling
├── legacy/                    migrated projects only: the old project, untouched
├── local/                     ignored by git
│   ├── index/                 rebuildable
│   ├── logs/                  run events and their archive
│   ├── run/                   pointer to the open run
│   ├── data/                  irreplaceable, in the manifest
│   ├── assets/                irreplaceable, in the manifest
│   ├── artifacts/             heavy agent outputs, in the manifest
│   ├── secrets.env            secrets
│   └── run.env                generated: .env plus secrets.env
├── src/<namespace>/<solution>/
│   ├── solution/              definition.py, one module per step, SOLUTION.md
│   └── ui/                    app.py, pages/, assets/
├── tests/                     pytest tests
├── doc/                       Sphinx user documentation
├── deployments/               Docker Compose recipes
├── .env                       runtime configuration, tracked, no secrets
├── .pre-commit-config.yaml    SAF's hooks plus the layer's block
├── .github/                   SAF's workflows plus agent-layer.yml
└── pyproject.toml, poetry.lock
```

| Location | In git | Written by |
|---|---|---|
| `src/`, `tests/`, `doc/`, `deployments/` | Yes | Agents and people, through tasks |
| `agent/knowledge/`, `agent/decisions/`, `agent/architecture/` | Yes | Agents, drafted by `scan`, verified against code |
| `agent/tasks/` | Yes | People create, agents move |
| `agent/logs/` | Yes | Agents, one summary per run |
| `agent/skills/`, `agent/templates/` | Yes | The kit, editable per project |
| `agent/tools/`, `agent/standard.md` | Yes | The kit only |
| `local/` | No | Tools and agents |
| `.venv/`, `.poetry/` | No | `saf install` |
| `legacy/` | Yes | Nobody: frozen |

## 5. Commands

Every operation is a `just` recipe. Run `just --list` in a project for the full list.

| Group | Recipes |
|---|---|
| Environment and checks | `setup`, `test`, `style`, `check` |
| Run, extend, package | `run`, `run-api`, `templates`, `add-step`, `docs`, `build`, `archive`, `archive-clean` |
| Knowledge | `scan`, `index`, `find`, `validate`, `entity-new`, `decision-new` |
| Tasks and runs | `task-new`, `task-list`, `task-claim`, `task-done`, `run-start`, `run-end`, `log`, `status` |
| Local files and git | `manifest-add`, `compact`, `hooks`, `hooks-native` |

## 6. How work flows

### One agent run

| Step | Command | What happens | Recorded in |
|---|---|---|---|
| 1 | none | Agent reads `AGENTS.md` | |
| 2 | `just task-claim <id>` | Task branch created and pushed, task moved to `active/`, run opened | `agent/tasks/active/`, `agent/logs/` |
| 3 | `just find <term>` | Agent loads the matching skill and locates the files it needs | |
| 4 | `just log <event>` | Agent does the work and commits with the task ID | `local/logs/`, git history |
| 5 | `just check` | Tests, style hooks and validation | |
| 6 | `just scan` | Entity files, decisions and the run summary are brought up to date | `agent/knowledge/`, `agent/decisions/`, `agent/logs/` |
| 7 | `just task-done <id>` | Checks and validation rerun, run closed, task moved to `done/`, committed | `agent/tasks/done/` |

### Knowledge

Code is the source. `just scan` reads step classes, fields and transaction methods and drafts entity files. An agent or a person verifies each draft against the code and sets `last_verified`. `just index` builds the lookup that `just find` uses. When code and entity files disagree, validation reports drift and `just task-done` refuses to close the task.

### Git

1. A person adds a task to `agent/tasks/backlog/` on the base branch.
2. `just task-claim` creates `<type>/T-0042-short-name` on the remote. The first agent to push owns the task.
3. Commits carry the task ID: `feat: add CSV export [T-0042]`.
4. `just task-done` closes the task on the branch.
5. A pull request runs SAF's workflows and the `Agent layer` workflow.
6. A person reviews and merges.

### Verification

Business logic is tested as plain functions first, then through SAF's test fixtures with `just test`. For an end-to-end check, the agent drives the running solution through the GLOW MCP server: it creates a fresh project, sets fields, runs transactions and reads the results.

## 7. Git integration

| Part | What it enforces | Where |
|---|---|---|
| Local hooks | Validation before each commit; Gitleaks when installed through pre-commit; commit type and task ID on the message | `.pre-commit-config.yaml`, or plain hooks from `just hooks-native` |
| Pull request workflow | Validation, branch name, commit messages | `.github/workflows/agent-layer.yml` |
| Task workflow | One owner per task; pull request template with task, run summary and approvals | `agentkit`, `.github/pull_request_template.md` |

Recommended repository settings: protect the base branch, require pull requests, and require both the SAF checks and the `Agent layer` check to pass.

## 8. Conventions

| Thing | Convention | Example |
|---|---|---|
| Task | `T-` plus four digits, then a short name | `T-0042-add-csv-export.md` |
| Decision | `D-` plus four digits, then a short name | `D-0007-split-solve-step.md` |
| Entity ID | Same as its file name | `step-meshing` |
| Run ID | UTC time, agent name, four hex characters | `20261122T154100Z-builder-a3f9` |
| Branch | SAF branch type, then the task file name | `feature/T-0042-add-csv-export` |
| Commit | Conventional commit, then the task ID | `feat: add CSV export [T-0042]` |
| Timestamps | UTC in ISO 8601, from the system clock | `2026-11-22T15:41:00Z` |

## 9. Migrating team projects

### Choose the path

| Project today | Path |
|---|---|
| Already a SAF solution | Apply the layer. Review the drafted entity files and `SOLUTION.md` |
| Python project that should become a SAF solution | Create the solution with `saf new`, apply the layer, move the old project into `legacy/`, port one feature per task |
| Not a fit for SAF | Apply the layer with `--any-project`, replace the SAF recipes in the `justfile` with the project's own commands, and set `check_command` in `agent/config.json` |
| No longer used | Archive it. Do not migrate it |

### Order

1. **Pilot.** Migrate one active, medium-sized project end to end.
2. **Fix.** Feed what the pilot taught back into the kit and the skills.
3. **Active projects.** Migrate the projects people work on now, one at a time.
4. **The rest.** Migrate maintenance-only projects when they next need a change.

### Checklist for one project

1. Tag the current commit. Save the package list from the working environment. Back up data and heavy assets.
2. Run `python install.py <solution>`. For a project without SAF's `AGENTS.md`, or to adopt the team layout, add `--use-template`.
3. Fill in "Project facts" and "Project notes" in `AGENTS.md`. `just validate` warns while placeholders remain.
4. Verify the drafted entity files against the code and set `last_verified`.
5. Complete `SOLUTION.md` if agents will drive the solution through MCP.
6. Move secrets from `.env` to `local/secrets.env`.
7. Move data and heavy assets to `local/data/` and `local/assets/`, and register each with `just manifest-add`.
8. For an old project: move it into `legacy/` in one commit that contains nothing else, and give each part an entity file with `status: legacy`.
9. Install the hooks with `just hooks`, commit, and open a pull request for the migration itself.
10. Turn the old TODO list into task files with `just task-new`.
11. Run the cold-start test.

### A project is migrated when

- `just validate` passes with no drift and no placeholder warning;
- the hooks are installed and the `Agent layer` check is green on a pull request;
- a fresh agent given only `AGENTS.md` answers ten real questions about the project;
- one small task has gone through the full process, from claim to merge;
- every irreplaceable file is in the manifest and backed up off the machine.

### Known traps

- A virtual environment does not survive being moved. Recreate it with `just setup`.
- SAF tracks `.env` in git. A secret left there will be committed; validation catches the common key names only.
- `saf archive` packs the whole solution folder, including `local/` and `legacy/`. Always run `just archive-clean` on the result.
- Old code with hard-coded paths to its data: leave that data where it is and ignore the path in git.
- If new code and legacy code share a database, only one of them writes to each table.

## 10. Roles and approvals

| Role | Does | Approves |
|---|---|---|
| Platform maintainer | Owns the kit, releases versions, upgrades projects | Changes to the standard and the skills |
| Project owner | Writes and orders tasks, keeps "Project facts" current | Irreversible actions in the project |
| Reviewer | Reviews pull requests | Merges |
| Agent | Claims a task, does the work, updates knowledge, opens a pull request | Nothing |

An agent always asks a human before a deploy, a delete, any spending, a data or project migration, a new dependency that needs a private index or a license review, and removing anything from `legacy/`.

## 11. Operating the platform

- **Version.** `python agent/tools/agentkit.py --version` shows the layer version in a project. This document describes 1.1.0.
- **Upgrade.** Run the new kit's installer in each project and open a pull request titled `chore: update agent layer`. Tooling and the standard are replaced; skills, templates, knowledge and settings are kept unless `--force` is passed.
- **Weekly.** Run `just validate --full` for manifest checksums, `just compact` for old run events, and a stale check that re-verifies entity files.
- **Health signals.** Drift notes per project, tasks closed per week, pull requests that failed the `Agent layer` check, and the cold-start test result.

## 12. Status

Verified by running it, against SAF's solution template at commit `247a767` of 21 November 2026:

- the installer on the Dash and no-UI variants, including the team template for `AGENTS.md`;
- every agentkit command, the plain git hooks, and two agents racing for one task against a local remote;
- 12 automated tests.

Not yet run, because the tools were not available where the kit was built:

- the `saf` commands and the recipes that call them;
- the `justfile` under `just`;
- the pre-commit block under pre-commit, and the workflow on GitHub.

Run these on the pilot project first.

## 13. References

- [Solution Application Framework](https://github.com/ansys/saf)
- [AGENTS.md format](https://agents.md/)
- [Agent Skills standard](https://agentskills.io/)
- [just](https://github.com/casey/just)
- [ripgrep](https://github.com/BurntSushi/ripgrep)
- [ast-grep](https://github.com/ast-grep/ast-grep)
- [DuckDB](https://duckdb.org/)
- [codebase-memory-mcp](https://deusdata.github.io/codebase-memory-mcp/)
- [Graphiti](https://github.com/getzep/graphiti)
- [Langfuse](https://langfuse.com)

This platform is an unofficial add-on to SAF and is not affiliated with or endorsed by Ansys.

---
name: decision-log
description: Enforce updating DECISION.md before applying major architectural or operational decisions. Use whenever the user is about to make, implement, or commit a significant infrastructure change, technology swap, migration, or operational pattern change.
---

# Decision Log Skill

Enforce that major architectural and operational decisions are documented in `DECISION.md` before they are applied.

## When to Trigger

Use this skill whenever the user is about to:

- Make or implement a new architectural decision (e.g., choosing a technology, changing infrastructure patterns)
- Migrate between technologies (e.g., replacing one service with another)
- Change operational patterns (e.g., secret management, storage, networking)
- Add or remove a major component from the stack
- Change the project structure or layout conventions
- Adopt or deprecate a tool, framework, or platform

**Do not trigger** for routine tasks like dependency updates, config tweaks, bug fixes, or minor resource changes.

## Decision Log Location

`DECISION.md` in the project root (`{projectRoot}/DECISION.md`).

## How to Use

### 1. Determine if the change qualifies as a "major decision"

Ask yourself:
- Is this a technology swap or migration?
- Does it change how something operates fundamentally?
- Will this decision have long-term implications for the project?
- Would you need context on why this was done later?

If yes to any, proceed to step 2.

### 2. Check if DECISION.md already has an entry for this decision

Read `DECISION.md` and check if a relevant entry already exists. Look for:
- Similar decision titles or keywords
- The technology/component being discussed
- Recent PRs that may have already documented it

### 3. If no entry exists, draft one

Create a new entry following the existing format in `DECISION.md`:

```markdown
## N. <Decision Title>

- **Date:** <YYYY-MM-DD>
- **Status:** Accepted | Completed | Deferred | Rejected
- **Context:** <Brief description of the situation that led to this decision>
- **Decision:** <What was decided>
- **Rationale:** <Why this was chosen over alternatives>
```

Guidelines:
- **Title:** Use a clear, action-oriented title (e.g., "Replace Redis with DragonflyDB", "Deploy Netbird for remote access")
- **Status:**
  - `Accepted` — decision made but not yet implemented
  - `Completed` — decision implemented and merged
  - `Deferred` — decision postponed, revisit later
  - `Rejected` — considered but not pursued
- **Context:** What problem or situation prompted this decision?
- **Decision:** What was actually decided. Be specific.
- **Rationale:** Why this choice was made, including alternatives considered
- **PR reference:** If already merged, add `Completed (PR #NNN)` to Status
- **Date:** Use the date the decision was made (not necessarily merged). If unsure, use the current date.
- **Numbering:** Use the next available number in the document

If the decision has sub-decisions (like PR #153 which covered Gateway API, DragonflyDB, Infisical, and Kustomize restructuring), use numbered subsections (13a, 13b, etc.).

### 4. Show the draft to the user for review

Present the drafted entry and ask the user to confirm or adjust:
- Is the rationale accurate?
- Are there alternatives that should be mentioned?
- Is the date correct?
- Should any context be added or removed?

### 5. Only after user approval, add the entry to DECISION.md

Insert the entry in chronological order (sorted by date, not number). Update the numbering of all subsequent entries to keep the sequence continuous.

### 6. Commit the DECISION.md update before applying the decision

Ensure the decision log entry is committed before the user proceeds with the actual change. The log entry should exist alongside the implementation.

## Entry Format Reference

### Simple Decision

```markdown
## N. <Title>

- **Date:** YYYY-MM-DD
- **Status:** Accepted | Completed
- **Context:** <situation>
- **Decision:** <what was decided>
- **Rationale:** <why>
```

### Decision with Sub-decisions

```markdown
## N. <Title>

- **Date:** YYYY-MM-DD
- **Status:** Completed (PR #NNN)
- **Context:** <situation covering all sub-decisions>
- **Decision:** <summary of the broader change>

### N.a. <Sub-decision Title>

- **Decision:** <specific change>
- **Rationale:** <why>

### N.b. <Sub-decision Title>

- **Decision:** <specific change>
- **Rationale:** <why>
```

## Important

- **Never skip documenting a major decision.** The purpose of this skill is to ensure you have context for why architectural choices were made, so you can reason about them later without re-tracing your steps.
- **Be specific in rationale.** Don't just say "better performance" — explain what improved and by how much.
- **Mention alternatives considered.** This provides context for why the chosen path was selected.
- **Keep entries concise.** Each entry should be scannable — aim for 3-6 bullet points per sub-decision.
- **Order by date, not number.** The numeric heading is for reference; chronological ordering is the primary sort.

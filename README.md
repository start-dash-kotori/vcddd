# VCDDD

[中文说明](./README.zh-CN.md)

VCDDD (Vibe Coding Domain-Driven Design) is a skill and methodology for AI-assisted software design. It reframes DDD around business truth, semantic boundaries, decision ownership, process state, collaboration contracts, and validation barriers.

This repository is published as a single-skill repository. The repository root is the skill root.

## What Is Included

- `SKILL.md`: the main skill definition and operating rules
- `reference/methodology/`: whitepaper and methodology guides
- `reference/thinking/`: requirement clarification and domain design workflow
- `reference/coding/`: implementation-line guidance after design is confirmed

## Repository Structure

```text
vcddd/
├── SKILL.md
├── README.md
├── README.zh-CN.md
├── .gitignore
├── LICENSE
└── reference/
    ├── methodology/
    ├── thinking/
    └── coding/
```

## Core Position

VCDDD is built on one central claim:

> Code can change frequently. The system's expression of the business world must not drift.

The method focuses on:

- business truth before technical structure
- bounded contexts as semantic sovereignty, not package layout
- explicit process state for long-running business flows
- contracts instead of hidden coupling
- validation barriers instead of team memory

## Recommended Reading Order

1. `SKILL.md`
2. `reference/thinking/requirements.md`
3. `reference/thinking/design.md`
4. `reference/coding/tech-setup.md`
5. `reference/coding/implementation.md`

For the theory background, read:

- `reference/methodology/vcddd-whitepaper.md`
- `reference/methodology/vcddd-design-guide.md`
- `reference/methodology/vcddd-implementation.md`

## How To Use

This repository follows the shared `SKILL.md` convention used by multiple coding-agent ecosystems.

For Codex-style local skills, place this repository directory under your local skills path so that the root `SKILL.md` remains intact, for example:

```text
~/.codex/skills/vcddd/
```

Then use the skill when the task is about:

- clarifying business requirements into confirmed facts
- deriving domain boundaries from business truth
- designing invariants, states, events, and contracts
- keeping implementation aligned to a documented business model

## Workflow Summary

1. Translate user intent into confirmed business facts.
2. Derive domain boundaries from decision ownership and semantic scope.
3. Design invariants, state machines, and collaboration contracts.
4. Only after business design is confirmed, enter implementation guidance.
5. Keep code subordinate to the documented model, not the other way around.

## License

This repository is released under the MIT License.

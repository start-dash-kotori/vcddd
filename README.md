# VCDDD

[中文说明](./README.zh-CN.md)

VCDDD (Vibe Coding Domain-Driven Design) is a skill and methodology for AI-assisted software design. It carries two layers of meaning that are complementary, not alternative.

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

## Two Layers of VCDDD

```
┌─────────────────────────────────────────────────────┐
│         Layer 2: Five-Step Working Methodology       │
│   V → C → D¹ → D² → D³                             │
│   Vision · Context · Domain · Dev Setup · Develop   │
├─────────────────────────────────────────────────────┤
│         Layer 1: Theoretical Foundation              │
│   Vibe Coding × Domain-Driven Design                │
│   A redefinition of DDD for the AI era              │
└─────────────────────────────────────────────────────┘
```

### Layer 1 — Theoretical Foundation

VCDDD is not a lighter DDD or an AI-wrapped DDD. It is a redefinition of what DDD is fundamentally about.

In the AI era, code is no longer the scarcest asset — it can be regenerated frequently. What must be protected instead is:

- **Business truth** — the facts the system commits to
- **Semantic boundaries** — where concepts hold and where they stop
- **Decision ownership** — who has the final say on what judgment
- **Process state** — where a long-running flow is at any moment
- **Collaboration contracts** — stable agreements across boundaries
- **Validation barriers** — mechanisms that prevent implementation from drifting away from the above

> Code can change frequently. The system's expression of the business world must not drift.

"Vibe Coding" acknowledges the high changeability of AI-generated code while insisting that the business model remains the stable anchor. The two are not in conflict: precisely because code can always be rewritten, business truth must be established first, independently, and protected throughout.

### Layer 2 — Five-Step Working Methodology

| Step | Full Name | Core Task | Key Output |
|---|---|---|---|
| **V** | Vision | Capture and structure user intent — no analysis yet | `input.md` |
| **C** | Context | Clarify intent into user-confirmed business facts | `facts.md` + ubiquitous language |
| **D¹** | Domain Design | Derive boundaries, decision ownership, invariants, events, and contracts from facts alone | `boundary.md` + `business.md` per domain |
| **D²** | Dev Setup | Formalize tech choices as written architectural conventions | `tech-stack.md` |
| **D³** | Develop | Generate code governed by D¹ design and D² conventions | Working codebase + `implementation.md` |

Each step has a hard prerequisite gate. No step may begin until its predecessor output has been confirmed. This sequencing is not ceremony — it prevents building correct-looking code on top of unconfirmed business assumptions.

## Recommended Reading Order

1. `SKILL.md` — operating rules and prohibited actions
2. `reference/methodology/vcddd-methodology.md` — the five-step method in full
3. `reference/thinking/requirements.md` — how to run V and C
4. `reference/thinking/design.md` — how to run D¹
5. `reference/coding/tech-setup.md` — how to run D²
6. `reference/coding/implementation.md` — how to run D³

For deeper theory:

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

1. **V — Vision**: Capture the user's intent faithfully, without analysis or architecture.
2. **C — Context**: Clarify intent into user-confirmed business facts, state machines, and a shared ubiquitous language.
3. **D¹ — Domain Design**: From confirmed facts only, derive bounded contexts, decision boundaries, invariants, events, and collaboration contracts.
4. **D² — Dev Setup**: Lock technology choices and architectural conventions into a written document before any code is generated.
5. **D³ — Develop**: Write code that is fully governed by the domain design and the tech conventions — documentation leads, code follows.

## License

This repository is released under the Creative Commons Attribution 4.0
International license (`CC BY 4.0`).

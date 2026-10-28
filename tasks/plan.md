# Implementation Plan: Herd split Ctrl+L edge no-op

Source: [SPEC.md](../SPEC.md)

## Overview

Stop the herd right-split from forwarding **Ctrl+L** into the agent PTY when there is no window to the right (the double-press clear). Keep autofocus and leave **Ctrl+H/J/K** edge behavior unchanged. Change lives only in our `nvim-omarchy` overlay.

## Architecture Decisions

- **Touch `setup_nav` only** in `lua/herd/split_terminal.lua`; do not alter `setup_focus`.
- **Extract a tiny pure helper** (same pattern as `herd.split_width`) so the edge rule is assertable without a live UI: given `dir` + `has_neighbor`, return the expr string to send to the PTY, or `nil`/empty for no-op.
- **Only `dir == "l"`** no-ops at the edge; `h`/`j`/`k` still return `"<C-…>"` when `has_neighbor` is false.
- **No upstream PR**, no Cursor Agent patch, no omarchy-setup changes.

## Dependency graph

```
edge helper (pure)
    │
    └── setup_nav uses helper
            │
            └── plenary spec + manual checklist
```

## Task List

### Phase 1: Edge rule

- [x] Task 1: Pure edge helper + wire into `setup_nav` + unit spec
- [ ] Task 2: Manual verify autofocus + double Ctrl+L + leave via Ctrl+H

### Checkpoint: Complete

- [ ] Spec acceptance criteria 1–5 satisfied
- [ ] `nvim -l tests/run.lua tests/herd/*_spec.lua` passes
- [ ] Human OK before commit

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Expr map returning `""` vs `nil` still feeds a key | Med | Prefer empty string / documented neovim expr no-op; verify in Task 2 |
| Breaking leave-panel via Ctrl+H | High | Do not change h/j/k branches; Task 2 includes leave via Ctrl+H |
| Over-abstracting for one `if` | Low | Helper stays ~5 lines; no new deps |

## Open Questions

None (resolved in SPEC).

# Tasks: Herd split Ctrl+L edge no-op

Source: [SPEC.md](../SPEC.md) · [plan.md](plan.md)

## Task 1: Pure edge helper + wire + unit spec

**Description:** Add a tiny pure function that decides terminal-mode expr passthrough for herd window nav: when there is no neighbor and `dir` is `"l"`, return no-op; otherwise keep today’s passthrough string `"<C-{dir}>"`. When a neighbor exists, `setup_nav` still schedules `wincmd` (unchanged). Wire the helper into `setup_nav`’s edge branch only. Add a plenary busted spec under `tests/herd/` matching `split_width_spec.lua`.

**Acceptance criteria:**
- [x] At edge (`has_neighbor == false`), `dir == "l"` → no passthrough (empty/`nil` no-op)
- [x] At edge, `dir` in `h|j|k` → still `"<C-h>"` / `"<C-j>"` / `"<C-k>"`
- [x] With neighbor → helper is not used for send (nav still `wincmd`); autofocus code untouched
- [x] Diff stays in our overlay (`lua/herd/` + `tests/herd/`), not lazy `herd.nvim`

**Verification:**
- [x] `nvim -l tests/run.lua tests/herd/*_spec.lua` exits 0
- [x] Spec covers l-noop and h/j/k passthrough at edge

**Dependencies:** None

**Files likely touched:**
- `lua/herd/split_terminal.lua` (and/or new `lua/herd/nav_edge.lua` if extracted)
- `tests/herd/nav_edge_spec.lua` (name to match helper module)

**Estimated scope:** Small (1–2 files + 1 spec)

---

## Task 2: Manual verify live herd + Cursor Agent

**Description:** Confirm the real UX path from the SPEC commands section.

**Acceptance criteria:**
- [ ] Ctrl+L from editor → herd panel focused + terminal insert (autofocus)
- [ ] Second Ctrl+L in that rightmost panel → agent does **not** clear
- [ ] Ctrl+H from panel → back to editor
- [ ] `/clear` (or intentional clear) still available when desired

**Verification:**
- [ ] Manual checklist above in a live nvim + herdr cursor-agent split

**Dependencies:** Task 1

**Files likely touched:** None

**Estimated scope:** XS (manual only)

---

## Checkpoint: Complete

- [ ] Task 1 + Task 2 done
- [ ] SPEC success criteria met
- [ ] Ready for review / commit when asked

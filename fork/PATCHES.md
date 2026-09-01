# Patches

Every local change lives on its own branch cut from `master` (a pure mirror of
upstream), so each one is independently upstreamable as a single PR. This file
carries one entry per patch branch. The apply order is `fork/BRANCHES`; the
integration branch `minechunk` is rebuilt from those branches by
`scripts/rebuild-integration.sh`.

When upstream merges a patch, delete its branch from `fork/BRANCHES` and flip
its **Status** here to `merged upstream`. The entry stays as a record; the code
arrives with the next pin bump instead of as a local patch.

Entry template:

```
## <branch>
- **Why:** one sentence on the behaviour we need.
- **Touches:** crates/files the patch modifies.
- **Upstream PR:** link, or `not yet opened`.
- **Status:** carried | merged upstream | abandoned.
- **Risk:** low | medium | high — how likely this conflicts on rebase.
```

## meta

- **Why:** Everything fork-specific has to live somewhere that is not an
  upstream file, so the rest of the branches stay clean patches.
- **Touches:** `fork/` (docs and `PINNED_SHA`), `scripts/`, the CI workflows
  under `.github/workflows/`, `fork/Dockerfile`, `.dockerignore` and
  `.gitignore` adjustments.
- **Upstream PR:** n/a — fork-only by design, never upstreamable.
- **Status:** carried.
- **Risk:** low — touches almost no upstream files.

## fix/lever-placement-orientation

- **Why:** Restores correct lever placement orientation after an upstream
  regression.
- **Touches:** `crates/pumpkin/src/block/blocks/redstone/lever.rs`.
- **Upstream PR:** https://github.com/Pumpkin-MC/Pumpkin/pull/3132 (open).
- **Status:** carried.
- **Risk:** medium — block internals churn on a pre-1.0 codebase, and this is
  the same file as the next patch.

## fix/lever-moved-guard

- **Why:** Restores the lever's moved guard and its `normal_use` result.
- **Touches:** `crates/pumpkin/src/block/blocks/redstone/lever.rs`.
- **Upstream PR:** https://github.com/Pumpkin-MC/Pumpkin/pull/3135 (open).
- **Status:** carried.
- **Risk:** medium — same file as the previous patch; the two merge in
  sequence, so a conflict in one usually means resolving both.

## fix/sign-support-solidity

- **Why:** Uses the legacy-solid support check for plain signs so they attach
  like vanilla.
- **Touches:** `crates/pumpkin/src/block/blocks/signs.rs`.
- **Upstream PR:** https://github.com/Pumpkin-MC/Pumpkin/pull/3162 (open).
- **Status:** carried.
- **Risk:** medium.

## feat/leaves-decay-event

- **Why:** Fires `LeavesDecayEvent` for the plugin API when leaves decay.
- **Touches:** `crates/pumpkin/src/block/blocks/leaves.rs`.
- **Upstream PR:** https://github.com/Pumpkin-MC/Pumpkin/pull/3170 (open).
- **Status:** carried.
- **Risk:** low.

## feat/spawner-spawn-event

- **Why:** Fires `SpawnerSpawnEvent` from the monster spawner and puts the
  spawner on cooldown when a spawn is cancelled.
- **Touches:** `crates/pumpkin/src/block/entities/mob_spawner.rs`.
- **Upstream PR:** https://github.com/Pumpkin-MC/Pumpkin/pull/3168 (open).
- **Status:** carried.
- **Risk:** low.

## feat/plugin-command-sender-type

- **Why:** Implemented get-command-sender-type for the plugin API.
- **Touches:** plugin API command sender handling.
- **Upstream PR:** https://github.com/Pumpkin-MC/Pumpkin/pull/3164 (merged).
- **Status:** merged upstream — branch removed from `fork/BRANCHES`; kept here
  as the worked example of the lifecycle.
- **Risk:** n/a.

## fix/wasm-event-reentry-guard

- **Why:** A WASM plugin that reaches back into itself from inside one of its
  own host calls (an event fired by `teleport-world`, a command executing
  itself, IPC ping-pong) parks forever on its own store mutex and freezes the
  whole server (upstream issue #2056). The guard tracks guest calls per task
  chain and skips or rejects same-chain re-entrant deliveries instead of
  waiting.
- **Touches:** `crates/pumpkin/src/plugin/loader/wasm/wasm_host/` (new
  `reentry.rs` plus a wrap at every guest entry point) and
  `crates/pumpkin/src/server/scheduler.rs`.
- **Upstream PR:** not yet opened.
- **Status:** carried.
- **Risk:** medium — the wasm host sees steady upstream feature work, so the
  wrapped call sites will drift.

## Conventions

**Prefer a plugin over a core patch.** Pumpkin has a plugin API; if the
behaviour can be built as a plugin, build it as a plugin. If the plugin API
merely lacks a hook, upstream the *hook* — a small, generic patch that fires an
event and does nothing else. Small generic patches merge; big bespoke ones sit
open and rot into rebase debt.

**Risk defaults.** Any patch touching networking, chunk handling, or entity
internals is **Risk: high** by default. Those areas move fastest upstream and
are the ones most likely to need a manual rebase.

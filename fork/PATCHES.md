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
- **Upstream PR:** https://github.com/Pumpkin-MC/Pumpkin/pull/3170 (open, and
  now redundant — close it).
- **Status:** merged upstream, by another route. Upstream wrote its own fire
  site in `f8d162769` ("fix: many non event firing", 2026-09-03) rather than
  taking the PR, so the pin bump to `8f4329b86` brought the behaviour in and
  the branch conflicts with it. Removed from `fork/BRANCHES`.
- **Risk:** n/a.

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

## feat/persist-world-name

- **Why:** A player who logs out in a plugin-created world (overworld-typed,
  e.g. the skyblock world) rejoined in the primary overworld at the same
  coordinates, because player data only recorded the dimension type.
- **Touches:** `crates/pumpkin/src/entity/player.rs` (writes `WorldName`),
  `crates/pumpkin/src/server/mod.rs` (`get_world_by_name`, preferred on rejoin).
- **Upstream PR:** not yet opened.
- **Status:** carried.
- **Risk:** low — additive NBT key, falls back to the old lookup.

## fix/custom-name-styling

- **Why:** Item custom names lost their colour, bold and `italic = false`
  on the wire, so plugin GUIs could not style item titles.
- **Touches:** `crates/pumpkin-protocol/src/codec/data_component.rs`
  (`CustomNameImpl::serialize` encodes the full component like lore).
- **Upstream PR:** not yet opened.
- **Status:** carried.
- **Risk:** low — one codec arm, mirrors `LoreImpl`.

## fix/raycast-start-block

- **Why:** `World::raycast` accepted the block the ray starts in (the
  player's eye block, air treated as a full cube) without asking `hit_check`,
  so buckets poured next to the player's head instead of where they looked.
- **Touches:** `crates/pumpkin/src/world/mod.rs` (one extra condition).
- **Upstream PR:** not yet opened.
- **Status:** carried.
- **Risk:** low.

## fix/lever-click-sound

- **Why:** Flipping a lever was silent and emitted no game event, so nothing
  nearby (note blocks, sculk sensors, a listening plugin) heard it.
- **Touches:** `crates/pumpkin/src/block/blocks/redstone/lever.rs`.
- **Upstream PR:** https://github.com/Pumpkin-MC/Pumpkin/pull/3204 (open).
- **Status:** carried.
- **Risk:** medium — third patch in this file; the three lever branches merge
  in sequence, so a conflict in one usually means resolving all three.

## fix/button-use-result

- **Why:** Clicking an already pressed button returned the wrong action
  result, so the client replayed the swing and the arm twitched.
- **Touches:** `crates/pumpkin/src/block/blocks/redstone/buttons.rs`.
- **Upstream PR:** https://github.com/Pumpkin-MC/Pumpkin/pull/3205 (open).
- **Status:** carried.
- **Risk:** low.

## fix/sign-waterlogging

- **Why:** A sign placed in water displaced it instead of waterlogging, which
  vanilla clients render as a sign in an air pocket.
- **Touches:** `crates/pumpkin/src/block/blocks/signs.rs`.
- **Upstream PR:** https://github.com/Pumpkin-MC/Pumpkin/pull/3206 (open).
- **Status:** carried.
- **Risk:** medium — same file as `fix/sign-support-solidity`, which merges
  immediately before it.

## feat/lava-block-form-event

- **Why:** `BlockFormEvent` was fired for basalt only, so cobblestone and
  obsidian forming from lava next to water set the block directly and a plugin
  could neither see nor cancel it — which is exactly the hook the skyblock ore
  generator needs. Fixing that exposed two more bugs in the same path: the
  conversion never notified clients (the block stayed lava until a reload) and
  the neighbour scan did not match vanilla's.
- **Touches:** `crates/pumpkin/src/block/fluid/lava.rs`.
- **Upstream PR:** a stack of three, oldest first —
  https://github.com/Pumpkin-MC/Pumpkin/pull/3214 (client notify),
  https://github.com/Pumpkin-MC/Pumpkin/pull/3215 (neighbour scan),
  https://github.com/Pumpkin-MC/Pumpkin/pull/3216 (the event). All open.
- **Status:** carried. The branch is the tip of the stack and contains all
  three commits, so it is the only one listed in `fork/BRANCHES`; the other two
  exist as branches purely to keep the PRs reviewable one change at a time.
- **Risk:** medium — a rewrite of the conversion path rather than an addition,
  and upstream merging any one of the three PRs rebases the other two.

## feat/block-form-fluids

- **Why:** The first cut of the lava `BlockFormEvent` hook.
- **Touches:** `crates/pumpkin/src/block/fluid/lava.rs`.
- **Upstream PR:** never opened.
- **Status:** abandoned — superseded by `feat/lava-block-form-event`, which
  does the same job in the form the upstream PRs were cut from. The branch is
  kept until those PRs land so the old shape can still be diffed; it must not
  be listed in `fork/BRANCHES` alongside its successor, as the two rewrite the
  same function.
- **Risk:** n/a.

## Conventions

**Prefer a plugin over a core patch.** Pumpkin has a plugin API; if the
behaviour can be built as a plugin, build it as a plugin. If the plugin API
merely lacks a hook, upstream the *hook* — a small, generic patch that fires an
event and does nothing else. Small generic patches merge; big bespoke ones sit
open and rot into rebase debt.

**Risk defaults.** Any patch touching networking, chunk handling, or entity
internals is **Risk: high** by default. Those areas move fastest upstream and
are the ones most likely to need a manual rebase.

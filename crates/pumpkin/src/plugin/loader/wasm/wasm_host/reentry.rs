//! Task-chain re-entry guard for host → guest WASM plugin calls.
//!
//! Every guest call locks the plugin's `Store` mutex for its entire duration,
//! and host imports run nested inside that call on the same task chain. If a
//! host import (directly or transitively) tries to call back into the same
//! plugin — an event fired by `teleport-world` reaching the plugin's own
//! handler, a command executing itself through `execute-command`, an IPC
//! ping-pong — waiting on the store lock can provably never complete: the
//! lock is held by an ancestor frame of the current task, and that frame
//! cannot resume until the nested call returns. See
//! <https://github.com/Pumpkin-MC/Pumpkin/issues/2056>.
//!
//! The guard tracks which plugins are mid-guest-call on the current task
//! chain. Call sites wrap the "lock store + call guest" future in [`scope`];
//! delivery sites that could form a cycle check [`is_reentrant`] first and
//! skip (or reject) the nested call instead of deadlocking. Everything nested
//! under a guest call inherits the chain, including futures driven by
//! `block_in_place` + `block_on` (the `fire_blocking` path), because those
//! polls happen synchronously inside the outer task's poll frame. Futures
//! handed to `tokio::spawn`/`Server::spawn_task` deliberately start a fresh,
//! empty chain: [`scope`] reads the ambient stack lazily at its first poll,
//! which for a spawned future happens on the new task.
//!
//! Plugin instantiation (`init_plugin`) is deliberately unguarded: it runs on
//! a local `Store` before the `WasmPlugin` exists, and at that point the host
//! state has no server reference, so no event-firing import can complete.
//!
//! Limitation: the guard sees a single task chain. Cycles built from two
//! *concurrent* chains (e.g. simultaneous A→B and B→A IPC from different
//! tasks) are outside its scope, as is work handed to another thread or task
//! and synchronously awaited from under a guest call (no such path exists
//! today).

use std::collections::HashSet;
use std::future::Future;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{LazyLock, Mutex};
use tracing::warn;

tokio::task_local! {
    /// Ids of the plugins currently mid-guest-call on this task chain
    /// (innermost last).
    static GUEST_CALL_STACK: Vec<u64>;
}

/// Source of process-unique plugin ids; see [`next_plugin_id`].
static NEXT_PLUGIN_ID: AtomicU64 = AtomicU64::new(0);

/// `(plugin id, context)` pairs that have already produced a skip warning.
static WARNED: LazyLock<Mutex<HashSet<(u64, &'static str)>>> =
    LazyLock::new(|| Mutex::new(HashSet::new()));

/// Allocates a process-unique id for one `WasmPlugin` instance.
///
/// Ids are never reused, so a stale handler that outlives a hot-reloaded
/// plugin can never be mistaken for the plugin that replaced it.
#[must_use]
pub fn next_plugin_id() -> u64 {
    NEXT_PLUGIN_ID.fetch_add(1, Ordering::Relaxed)
}

/// Returns `true` if the plugin is already mid-guest-call on the current task
/// chain, i.e. calling into it from here would deadlock on its store lock.
#[must_use]
pub fn is_reentrant(plugin_id: u64) -> bool {
    GUEST_CALL_STACK
        .try_with(|stack| stack.contains(&plugin_id))
        .unwrap_or(false)
}

/// Runs `fut` with `plugin_id` pushed onto the current task chain's
/// guest-call stack.
///
/// Wrap the future that locks the plugin's store and calls into the guest, so
/// that everything executing beneath it observes the plugin as busy via
/// [`is_reentrant`].
pub async fn scope<F: Future>(plugin_id: u64, fut: F) -> F::Output {
    let mut stack = GUEST_CALL_STACK.try_with(Vec::clone).unwrap_or_default();
    stack.push(plugin_id);
    GUEST_CALL_STACK.scope(stack, fut).await
}

/// Records the pair and returns `true` the first time it is seen.
fn first_occurrence(plugin_id: u64, context: &'static str) -> bool {
    WARNED
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .insert((plugin_id, context))
}

/// Warns that a re-entrant guest call into `plugin_name` was skipped, once
/// per `(plugin, context)` pair for the lifetime of the process.
pub fn warn_skipped(plugin_id: u64, plugin_name: &str, context: &'static str) {
    if first_occurrence(plugin_id, context) {
        warn!(
            "Skipping re-entrant guest call into plugin `{plugin_name}` ({context}): \
             the plugin is already executing on this call chain and waiting for it would \
             deadlock (see Pumpkin-MC/Pumpkin issue #2056); logged once per plugin and context"
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn empty_chain_is_not_reentrant() {
        let id = next_plugin_id();
        assert!(!is_reentrant(id));
    }

    #[tokio::test]
    async fn scope_marks_only_that_plugin() {
        let first = next_plugin_id();
        let second = next_plugin_id();
        scope(first, async {
            assert!(is_reentrant(first));
            assert!(!is_reentrant(second));
        })
        .await;
        assert!(!is_reentrant(first));
    }

    #[tokio::test]
    async fn nested_scopes_stack() {
        let outer = next_plugin_id();
        let inner = next_plugin_id();
        scope(outer, async {
            scope(inner, async {
                assert!(is_reentrant(outer));
                assert!(is_reentrant(inner));
            })
            .await;
            assert!(is_reentrant(outer));
            assert!(!is_reentrant(inner));
        })
        .await;
    }

    /// Regression test for the `fire_blocking` path: the guard must stay
    /// visible inside a future driven by `block_in_place` + `block_on`.
    #[tokio::test(flavor = "multi_thread")]
    async fn visible_through_block_in_place_block_on() {
        let id = next_plugin_id();
        scope(id, async {
            tokio::task::block_in_place(|| {
                tokio::runtime::Handle::current().block_on(async {
                    assert!(is_reentrant(id));
                });
            });
        })
        .await;
    }

    /// Futures handed to `tokio::spawn` start a fresh chain by design.
    #[tokio::test]
    async fn spawned_tasks_start_fresh() {
        let id = next_plugin_id();
        scope(id, async {
            let seen_in_task = tokio::spawn(async move { is_reentrant(id) })
                .await
                .unwrap_or(true);
            assert!(!seen_in_task);
        })
        .await;
    }

    #[test]
    fn warn_dedup_is_per_plugin_and_context() {
        let first = next_plugin_id();
        let second = next_plugin_id();
        assert!(first_occurrence(first, "event"));
        assert!(!first_occurrence(first, "event"));
        assert!(first_occurrence(first, "command"));
        assert!(first_occurrence(second, "event"));
    }
}

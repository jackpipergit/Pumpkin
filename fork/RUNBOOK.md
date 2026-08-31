# Runbook

Steady-state procedure for moving the fork onto a newer upstream commit and
getting the result in front of a client. Upstream is pre-1.0 with no releases,
so the pin in `fork/PINNED_SHA` is a `master` SHA that was known good at the
time it was chosen.

## 1. Bump the pin

1. Run `scripts/check-upstream.sh`. It is read-only: it replays every rebase in
   a scratch worktree, reports which branches conflict, and exits non-zero if
   any do. This answers one question — is the bump clean?
2. Pick the target SHA. It must build and test clean, so check that upstream's
   own CI is green on that commit before choosing it. Do not pick the tip
   blindly.
3. Update `fork/PINNED_SHA` on the `meta` branch and commit there. The pin is
   fork metadata; it never lands on a patch branch.
4. Run `scripts/rebuild-integration.sh` (optionally with an explicit
   `TARGET_SHA`). It rebases every branch listed in `fork/BRANCHES` onto the
   target, re-creates `minechunk` from the target, and merges each branch
   `--no-ff` in list order. A conflict aborts the script: rebase the named
   branch by hand, resolve, then re-run. `git rerere` records the resolution so
   the same conflict resolves itself on later runs.
5. Review `git diff --stat <SHA>..HEAD`. That diff is the whole fork. If the
   surface area grew and you cannot say which patch grew it, find out why before
   shipping — an unexplained hunk is usually a bad conflict resolution.

**If a bump conflicts badly, stay on the old SHA.** There is no obligation to
be current. A hurried conflict resolution surfaces weeks later looking exactly
like an upstream bug, and you will waste a day proving it isn't one.

## 2. Push

```sh
# patch branches first — they were rebased, so history changed
git push --force-with-lease origin fix/lever-placement-orientation
# ...one per branch in fork/BRANCHES
git push origin minechunk
```

`--force-with-lease`, never `--force`. Pushing the patch branches also
refreshes the open upstream PRs onto the new base, which is the point of
keeping them as standalone branches.

The push to `minechunk` triggers `build.yml`: fmt, clippy, test, then a
linux/arm64 image built from `fork/Dockerfile` and pushed to GHCR.

## 3. Deploy

Images are tagged `ghcr.io/jackpipergit/pumpkin:<short-sha>` plus a moving
`:latest`. **Deployments pin the SHA tag. Never `latest`.**

Staging first. The compose stack at `../../pumpkin/docker-compose.yml` (the
pumpkin workspace) carries a `pumpkin-fork` service on staging port 25566 with
its own `./server-fork` volume, separate from the main service's data.

1. Update the `pumpkin-fork` image tag to the new short-sha.
2. `docker compose up -d pumpkin-fork`
3. Connect a client to `:25566` and exercise whatever the patches touch.
4. Check the container logs before calling it good.

Only then move production.

## 4. Rollback

Set the compose image tag back to the previous short-sha and
`docker compose up -d` again. Old tags stay in GHCR; nothing needs rebuilding
and nothing needs reverting in git.

**Record the previous tag before you deploy.** This is the step that gets
skipped, and finding it afterwards from GHCR while the server is down is
avoidable work.

## 5. Production note

The minechunk.net VPS currently self-updates from upstream's nightly releases
via its own `update.sh`. It is not running these images. Cutting it over to the
fork images is a separate, deliberate decision — until that decision is made,
this runbook covers staging only.

## 6. Config hygiene

Live server config (`pumpkin.toml`) is never committed. `fork/pumpkin.example.toml`
holds a sanitized example. The example file name is deliberate: Pumpkin reads
`pumpkin.toml` from its working directory, so the example must be copied and
renamed, not committed under the real name.

## 7. When upstream merges a PR

1. Delete the branch line from `fork/BRANCHES`.
2. Flip that entry's **Status** in `fork/PATCHES.md` to `merged upstream`.
3. Rebuild the integration branch.

Once the pin moves past the merge commit, the patch disappears from
`git diff <SHA>..HEAD` on its own. Nothing else to do.

## 8. Fresh clone checklist

```sh
git clone git@github.com:jackpipergit/Pumpkin.git
cd Pumpkin
git submodule update --init --recursive   # pumpkin-plugin-wit; the build fails without it
git remote add upstream https://github.com/Pumpkin-MC/Pumpkin.git
git remote set-url --push upstream DISABLED   # pushes go to origin only
git config rerere.enabled true
git config rerere.autoupdate true
git fetch upstream
```

`rerere` is what replays recorded conflict resolutions on later rebases — a
clone without it re-raises every conflict that was already solved once.

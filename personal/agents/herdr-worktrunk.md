# Herdr session — Worktrunk-first workflow

You are running inside a Herdr pane. Other agents may be operating on this repo
concurrently, so branch switching in the shared checkout is unsafe. Use the
Worktrunk plugin commands below, never `git worktree`.

## Usage

Create or switch a Worktrunk checkout from the default branch:

    herdr plugin action invoke open --plugin worktrunk

Create or switch a Worktrunk checkout from the current branch:

    herdr plugin action invoke open-current --plugin worktrunk

Remove a Worktrunk checkout:

    herdr plugin action invoke remove --plugin worktrunk

List Worktrunk checkouts (fallback when the plugin has no list action):

    wt list

## Working in Worktrunk

Do all feature work inside the Worktrunk checkout that Herdr opens. Do not run
`git checkout` or `git switch` in the parent/shared workspace.

Untracked files do not come along. Copy `.env`, `.env.local`, and any other
local config the build needs. Install dependencies fresh; `node_modules` is
not shared across checkouts.

## Keybindings

Use the Herdr Worktrunk keybindings for open, open-current, and remove when
available in your setup.

## Stay in the current checkout when

- The user explicitly asks to work in place
- The task is read-only investigation
- The change is a trivial one-liner
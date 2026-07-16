# MCPs

## Why
Sometimes the tools are noisier than they need to be. And sometimes, deterministic workflows are useful to avoid re-thinking to derive the same answer.

### `apple-tools-mcp`
Wrappers around the following commands:
- `notarytool`
- `swift` and subcommands: `build`, `test`
- `swift` and `actions` (quick fixes, refactorings, etc), `completion` suggestions, `list`ing all symbol and their `definition`, `diagnostics` (errors, warnings, notes) from a file, 
- `swiftlint` and `swiftformat`
- `xcodebuild` and subcommands: `build`, `test`, `clean`, `archive`, `analyze` and helpers to `list_schemes` and `show_build_settings` for a given build configuration

### `git-tools-mcp`
Wrappers around the following `git` commands:
- `init` to get started
- `status`, `diff`, and `show` to see state of changes
- `log` and `blame` to see history of changes
- `add`, `mv` to update files
- `commit`, `checkout`, `reset` and `stash` to save or reset state
- `merge_analysis` to identify conflicts and attempt resolution
- `remote`, `merge`, `rebase`, `cherry_pick`, `push` and `pull` to work with remotes
- `tag` to view git tags

And workflows sequencing `git` commands together:
- `branch_create`, `branch_delete`, `branch_rename`, `branch_prune` and `branch_find_duplicates` to manage and clean up branches
- `worktree_list`, `worktree_find_by_branch_name`, `worktree_add`, `worktree_remove` and `worktree_prune` to manage and clean up worktrees
- `stack` management to visualize, sync, split, rebase, merge, and clean up branches of branches
- `list-active-prs` to list open and draft pull requests, flagging failing and pending CI checks per PR

### `process-watch-tool`
Keep an eye on processes - builds, other MCPs, and so on - without wasting context in the main session

# tmux tab naming

If this session is running inside tmux (check `$TMUX` is set), early on —
once you have enough context to know what the task is about (after the
first user message is usually enough) — pick a punchy 2-word kebab-case
identifier summarizing the task (e.g. `fix-auth`, `tmux-tabs`, `db-migrate`)
and run:

```
tmux rename-window "<id>" && tmux set-window-option -t "$TMUX_PANE" @pinned 1
```

This pins the tab so it keeps your identifier instead of reverting to the
directory name (a shell hook in `~/.bashrc` otherwise renames tmux windows
to track `cwd`; pinning suppresses that). If the task's focus shifts
significantly mid-session, feel free to re-run the command with a new
identifier. Don't do this outside tmux, and don't bother for very short
one-off questions.

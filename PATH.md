# PATH

On Jason's Mac, `git grep -E <pattern> <rev> -- <paths with binary files>` (as omp agents run it in phoneware/monorepo) finishes with bounded memory and the same matches, because the `git` on PATH is Homebrew's git rebuilt with the upstream macOS TRE regexec leak workaround, shipped from his tap jwaldrip/homebrew-on-tap.

- Surface: Jason's MacBook Pro (M5 Max, macOS 27.0.1). `git` as a shell or an omp agent resolves it from PATH: `/opt/homebrew/bin/git`.
- Install: `brew uninstall git`, then `brew install --yes jwaldrip/on-tap/git`. Core's git and this formula share the `git` keg name, so only one of them can be installed.
- Transport: none. A local binary built from the kernel.org git 2.56.0 tarball plus the upstream patch vendored after `__END__` in `git.rb`.
- Check: `python3 checks/git-tre-leak.py`, run from this repo. Exit 0 and a final `PASS` line are green; anything else is red.

The check reads phoneware/monorepo at the pinned commit `648289ddc594c61f5e70c532b308fc178db8b835`, runs each probe in `en_US.UTF-8` and in `C` with the same `git`, and kills any run past 4 GB.

## Expected output

```
identity  git=/opt/homebrew/bin/git keg=/opt/homebrew/Cellar/git/2.56.0 version='git version 2.56.0' tap=jwaldrip/on-tap marker=_darwin_regexec_buf:present  OK
agents    en_US.UTF-8: exited rc=0 peak=0.19GB ... lines=41/41 binary_files=0 same=yes  OK
binary    en_US.UTF-8: exited rc=0 peak=0.04GB ... lines=905/905 binary_files=772 same=yes  OK
PASS
```

## Known miss

The homebrew/core 2.55.0 bottle on PATH, 2026-10-19:

```
identity  git=/opt/homebrew/bin/git keg=/opt/homebrew/Cellar/git/2.55.0 version='git version 2.55.0' tap=homebrew/core marker=_darwin_regexec_buf:absent  FAIL
agents    en_US.UTF-8: KILLED_AT_CAP rc=-9 peak=4.91GB secs=0.3 ... same=no  FAIL
binary    en_US.UTF-8: exited rc=0 peak=0.77GB secs=0.2 ... same=no  FAIL
FAIL
```

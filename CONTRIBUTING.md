# Contributing

Thanks for contributing to this packaging project.

## Scope and Priorities

Current priorities:
- Reliability and portability of scripts
- Snap packaging quality and store-readiness
- Clear, testable behavior across supported topologies

Out of scope for now:
- Broad distro-specific support beyond Ubuntu-first behavior
- ARM64 expansion as a primary goal

## Development Workflow

1. Make focused changes with minimal unrelated edits.
2. Run smoke tests:

```bash
bash test.sh
```

3. For behavior changes, run targeted manual validation for affected topology.
4. Keep version references consistent (`rebuild.sh` is the canonical patch path).

## Coding Guidelines

- Keep shell scripts POSIX/Bash-safe and defensive.
- Prefer explicit validation and clear error messages.
- Avoid hardcoded user-specific paths.
- Keep cleanup operations safe and predictable.

## Documentation Guidelines

- Keep documentation operational and concrete.
- Prefer direct wording over promotional language.
- Ensure commands are copy/paste-safe and tested.
- Update [README.md](README.md) and [TESTING.md](TESTING.md) when behavior changes.

## Commit/PR Expectations

Include:
- What changed
- Why it changed
- How it was tested (paste commands + outcomes)

Recommended test notes in PR description:
- `bash test.sh` output summary
- Any manual topology checks performed (Snap/LXD/Docker/Podman)

## Reporting Issues

When filing an issue, include:
- Host OS/version
- Topology used
- Exact command run
- Full error output
- Whether cleanup was run before retry

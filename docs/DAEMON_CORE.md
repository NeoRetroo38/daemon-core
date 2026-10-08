# Daemon operational foundation

This is a separate C++20 operational component. It does not link, include, copy,
or change the Neo Cube engine. The inherited engine import remains isolated.

```sh
cmake -S . -B build/daemon
cmake --build build/daemon
ctest --test-dir build/daemon --output-on-failure
./build/daemon/daemon snapshot --repo /explicit/repository --json
```

On the currently audited Mac, the default SDK 27 linker is incompatible with
its installed TAPI. The verified configure command adds
`-DCMAKE_OSX_SYSROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk`.
This selects a compatible installed SDK for this build without changing the
machine's global Xcode selection.

Targets: `daemon_core` (static library), `daemon_cli` (the `daemon` executable),
`daemon_tests`. No runtime packages or network services are required. The CLI
only observes explicitly supplied repositories and emits JSON; it does not sync,
fetch, commit, push, run arbitrary commands, or read environment/secret files.

The portable model represents repositories, service observations, agents and
trace events. Unknown values remain null. Empty services/agents mean no evidence
was collected, not healthy/idle. `nextAction` is a suggestion, never execution.
Ahead/behind describe the locally cached upstream ref; no network refresh is
performed and they are not a claim about the current GitHub HEAD.

`Policy` separates READ_ONLY, WRITE, NETWORK and PRIVILEGED. Default rules allow
read-only observation and deny writes/network. Privileged actions always require
explicit approval. This first version does not expose an action executor.

The POSIX adapter calls `/usr/bin/git` (the trusted system installation) with
two fixed Git built-ins and separate argv entries,
without a shell. It disables optional Git locks, prompts, global Git overrides,
hooks and fsmonitor. Child environment inheritance is limited to PATH, TMPDIR,
LANG and LC_ALL; application credentials are never forwarded. Each child has a
deadline, cancellation and a shared 64 KiB
stdout/stderr budget; failed observations expose result codes, never raw output.
The internal process primitive is not a CLI or C ABI feature. The selected
repository and installed Git are trusted local inputs; this is not a sandbox
for hostile repositories or binaries. POSIX installations with Git outside
`/usr/bin/git` report unavailable; this first version does not search arbitrary
PATH directories or download a Git implementation.

Trace events contain timestamp, actor, machine, repository, branch, commit,
operation, result and duration. No token/database value/process output is put
in events. Serialization also redacts common credential assignments, PostgreSQL
URLs, Bearer values and PEM private keys as defense in depth.

## C ABI / Apple bridge

`include/daemon/daemon_bridge.h` exposes only:

- `const char* daemon_core_version(void)`: static string; do not free.
- `char* daemon_snapshot_json(const char* repo_path)`: one explicit local path;
  malloc-owned UTF-8 JSON; free with `daemon_free_string`.
- `void daemon_free_string(char*)`: accepts null.

Allocation failure returns null. Invalid/unavailable paths return JSON containing
an unavailable repository, not a false clean result. Exceptions do not escape
the C ABI. Schema version 1 contains `timestamp`, `mode`, `repositories`,
`services`, `agents`, `events` and `nextAction`. Repository fields are `name`,
`path`, `branch`, `head`, `upstream`, `dirty`, `ahead`, `behind`, `status`, `error`.
Status is `ready`, `unknown` or `unavailable`; absence is represented with null.

Apple iOS is detected by TargetConditionals, or explicitly by
`DAEMON_PLATFORM_IOS=1`. Local processes are compiled out. Its snapshot uses
`mode: remote-required` and guides the user to connect with a Mac. A remote
authenticated control channel, network health checks and service lifecycle are
not implemented in this foundation. SwiftUI is a consumer of this C ABI, never
part of the C++ model or authorization policy.

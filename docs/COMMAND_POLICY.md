# Command policy and supplied exposure evidence

`Policy::evaluate(StructuredCommand)` accepts an executable path and a separate
argv vector. It returns a derived command class and Allow, RequireApproval or
Deny. It does not run the command. Calling the legacy class-only rule query is
not a substitute for inspection, and an Allow result is not user authorization
to execute an action through a future controller.

The current public C ABI and CLI continue to expose only explicit repository
snapshots. GitAdapter checks both fixed Git built-ins with their actual argv
before calling the internal POSIX primitive. No generic action runner, network
control channel, approval endpoint or listener collector was added.

## Permanent prohibitions

These structured commands remain Deny with permissive write/network rules:

- Git force-push flags (including `-f`, combined short flags, force-with-lease)
  and `+refspec`; filter-branch/filter-repo; alias/executable configuration that
  could bypass inspection.
- sudo, csrutil, disabling spctl security controls, tccutil reset and security
  dump-keychain.
- Shell command mode (`bash -c`, combined `-lc`, analogous native shell options)
  and command chains passed as executable strings.
- Recursive forced deletion with root, traversal, tilde/home placeholders,
  wildcard or unresolved variable targets. Every explicit deletion still
  requires target approval, including a narrow path. Without filesystem context
  this evaluator cannot identify resolved home or workspace roots.

Only Git status/rev-parse form the read allowlist. The existing trusted adapter
configuration (`core.fsmonitor=false`, disabled hooks) is recognized. Unknown
programs/configuration require approval even with permissive class rules.
Whitespace in program directory paths and literal shell-looking argument values
are preserved as argv; they are not interpreted as commands. Program names are
recognized by basename, which is classification rather than executable trust
verification. The actual adapter still selects the trusted system Git path.
Repositories and installed Git remain trusted local inputs, not a sandbox for
hostile repositories, binaries or filesystem symlinks.

## Exposure result

`check_exposure(BindingObservation)` is a pure check of supplied numeric binding
evidence. Its statuses are SAFE, EXPOSED and UNKNOWN. The caller must explicitly
mark a complete inventory; default or partial evidence cannot prove safety.
One known binding outside `127.0.0.1:8765` is EXPOSED even if other evidence is
partial. IPv6 bindings violate the existing IPv4-only motor contract. A complete
inventory with no port 8765 yields ENGINE_PORT_NOT_LISTENING, not a claim of a
healthy engine. Hostnames or missing address data remain UNKNOWN.

This function does **not** collect listeners, enumerate processes, probe the
PC/network, start a server or configure a firewall. The app still shows service
state as unverified until a separate collector supplies actual evidence.

## Verification

Offline fixtures inspect argv without executing dangerous commands. They cover
default/permissive rules, option/refspec/alias variants, benign literal argv,
synthetic generic URL credentials, malformed/partial/exposed bindings and the
existing real fixed Git observation. The normal CMake/CTest suite runs in macOS
with the selected compatible SDK; these tests do not establish Windows, Linux,
iOS or Android builds, remote connectivity or actual motor exposure.

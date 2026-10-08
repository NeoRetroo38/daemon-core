#ifndef DAEMON_BRIDGE_H
#define DAEMON_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

// Static version string: do not release it.
const char* daemon_core_version(void);

// One explicitly selected local repository. UTF-8 JSON, owned by the caller.
// A valid JSON error snapshot is returned for unavailable/invalid paths.
// Returns NULL only if allocation fails. iOS never starts local processes.
char* daemon_snapshot_json(const char* repo_path);
void daemon_free_string(char* value);

#ifdef __cplusplus
}
#endif

#endif

#ifndef DAEMON_BRIDGE_H
#define DAEMON_BRIDGE_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Static version string: do not release it.
const char* daemon_core_version(void);

// One explicitly selected local repository. UTF-8 JSON, owned by the caller.
// A valid JSON error snapshot is returned for unavailable/invalid paths.
// Returns NULL only if allocation fails. iOS never starts local processes.
char* daemon_snapshot_json(const char* repo_path);

// Multiple explicitly selected local repositories in one coherent snapshot.
// Each path must remain valid for the duration of the call. An empty catalog
// returns a valid snapshot with no repository evidence.
char* daemon_snapshot_json_many(const char* const* repo_paths, size_t repo_count);
void daemon_free_string(char* value);

#ifdef __cplusplus
}
#endif

#endif

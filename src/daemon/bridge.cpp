#include "daemon/daemon_bridge.h"
#include "daemon/git_adapter.hpp"

#include <cstdlib>
#include <cstring>
#include <new>
#include <string>
#include <string_view>
#include <vector>

namespace {
char* copyJson(std::string_view json) {
    auto* result = static_cast<char*>(std::malloc(json.size() + 1));
    if (result) {
        std::memcpy(result, json.data(), json.size());
        result[json.size()] = '\0';
    }
    return result;
}
}

extern "C" {

const char* daemon_core_version(void) { return "0.1.0"; }

char* daemon_snapshot_json_many(const char* const* repo_paths, size_t repo_count) {
    try {
        std::vector<std::string> paths;
        paths.reserve(repo_count);
        for (size_t index = 0; index < repo_count; ++index) {
            paths.emplace_back(repo_paths && repo_paths[index] ? repo_paths[index] : "");
        }
        return copyJson(daemonx::snapshotJson(daemonx::observeRepositories(paths)));
    } catch (const std::bad_alloc&) {
        return nullptr;
    } catch (...) {
        // Never cross the C boundary with an exception or raw diagnostic output.
        return copyJson("{\"schemaVersion\":1,\"timestamp\":null,\"mode\":\"unavailable\",\"repositories\":[],\"services\":[],\"agents\":[],\"events\":[],\"nextAction\":\"Snapshot unavailable\",\"error\":\"CORE_ERROR\"}");
    }
}

char* daemon_snapshot_json(const char* repo_path) {
    const char* paths[] = {repo_path};
    return daemon_snapshot_json_many(paths, 1);
}

void daemon_free_string(char* value) { std::free(value); }

}

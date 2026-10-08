#include "daemon/daemon_bridge.h"
#include "daemon/git_adapter.hpp"

#include <cstdlib>
#include <cstring>
#include <new>
#include <string_view>

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

char* daemon_snapshot_json(const char* repo_path) {
    try {
        return copyJson(daemonx::snapshotJson(daemonx::observeRepositories({repo_path ? repo_path : ""})));
    } catch (const std::bad_alloc&) {
        return nullptr;
    } catch (...) {
        // Never cross the C boundary with an exception or raw diagnostic output.
        return copyJson("{\"schemaVersion\":1,\"timestamp\":null,\"mode\":\"unavailable\",\"repositories\":[],\"services\":[],\"agents\":[],\"events\":[],\"nextAction\":\"Snapshot unavailable\",\"error\":\"CORE_ERROR\"}");
    }
}

void daemon_free_string(char* value) { std::free(value); }

}

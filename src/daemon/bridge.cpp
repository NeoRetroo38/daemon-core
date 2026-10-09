#include "daemon/daemon_bridge.h"
#include "daemon/exposure.hpp"
#include "daemon/git_adapter.hpp"
#include "daemon/policy.hpp"
#include "daemon/trace.hpp"

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

const char* daemon_core_version(void) { return "0.2.0"; }

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

char* daemon_policy_evaluate(const char* executable, const char* const* arguments, size_t argument_count,
                             int allow_write, int allow_network) {
    try {
        daemonx::StructuredCommand command{executable ? executable : "", {}};
        for (size_t index = 0; index < argument_count; ++index)
            command.arguments.emplace_back(arguments && arguments[index] ? arguments[index] : "");
        const daemonx::Policy policy({true, allow_write != 0, allow_network != 0});
        const auto decision = policy.evaluate(command);
        const char* verdict = decision.verdict == daemonx::PolicyVerdict::Allow ? "allow"
                            : decision.verdict == daemonx::PolicyVerdict::RequireApproval ? "approval" : "deny";
        const char* classification = decision.classification == daemonx::CommandClass::READ_ONLY ? "READ_ONLY"
                                   : decision.classification == daemonx::CommandClass::WRITE ? "WRITE"
                                   : decision.classification == daemonx::CommandClass::NETWORK ? "NETWORK" : "PRIVILEGED";
        // Reasons are fixed uppercase codes defined in policy.cpp; no escaping needed.
        return copyJson(std::string("{\"verdict\":\"") + verdict + "\",\"classification\":\"" + classification +
                        "\",\"reason\":\"" + decision.reason + "\"}");
    } catch (const std::bad_alloc&) {
        return nullptr;
    } catch (...) {
        return copyJson("{\"verdict\":\"deny\",\"classification\":\"PRIVILEGED\",\"reason\":\"POLICY_ERROR\"}");
    }
}

char* daemon_check_exposure(const char* const* addresses, const unsigned short* ports, size_t count, int complete) {
    try {
        daemonx::BindingObservation observation;
        observation.complete = complete != 0;
        for (size_t index = 0; index < count; ++index) {
            if (!addresses || !ports || !addresses[index]) { observation.complete = false; continue; }
            observation.bindings.push_back({addresses[index], ports[index]});
        }
        const auto result = daemonx::check_exposure(observation);
        const char* status = result.status == daemonx::ExposureStatus::SAFE ? "SAFE"
                           : result.status == daemonx::ExposureStatus::EXPOSED ? "EXPOSED" : "UNKNOWN";
        return copyJson(std::string("{\"status\":\"") + status + "\",\"reason\":\"" + result.reason + "\"}");
    } catch (const std::bad_alloc&) {
        return nullptr;
    } catch (...) {
        return copyJson("{\"status\":\"UNKNOWN\",\"reason\":\"EXPOSURE_CHECK_ERROR\"}");
    }
}

char* daemon_redact(const char* text) {
    try {
        return copyJson(daemonx::redact(text ? text : ""));
    } catch (...) {
        return nullptr;
    }
}

}

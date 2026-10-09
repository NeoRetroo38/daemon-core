#pragma once

#include "model.hpp"
#include "policy.hpp"

#include <chrono>
#include <stop_token>
#include <string>
#include <string_view>
#include <vector>

namespace daemonx {

struct GitObservationOptions {
    std::chrono::milliseconds timeout{5000};
    std::size_t maxOutputBytes{64 * 1024};
};

class GitAdapter {
public:
    explicit GitAdapter(Policy policy = Policy{}, GitObservationOptions options = {})
        : policy_(policy), options_(options) {}
    [[nodiscard]] RepositoryState observe(const std::string& explicitPath,
                                          std::stop_token cancellation = {}) const;

private:
    Policy policy_;
    GitObservationOptions options_;
};

// Pure parser for the documented porcelain v2 branch format.
bool parseGitStatus(std::string_view text, RepositoryState& repository);
Snapshot observeRepositories(const std::vector<std::string>& explicitPaths,
                             std::stop_token cancellation = {});
bool localProcessesAvailable();

}  // namespace daemonx

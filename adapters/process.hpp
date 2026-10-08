#pragma once

#include <chrono>
#include <cstdint>
#include <stop_token>
#include <string>
#include <vector>

// Internal adapter primitive. It is not exposed through the C ABI or CLI.
namespace daemonx::detail {

struct ProcessResult {
    int exitCode{-1};
    std::string standardOutput;
    std::string standardError;
    bool timedOut{};
    bool cancelled{};
    bool outputLimitExceeded{};
    bool unavailable{};
    std::uint64_t durationMs{};
};

ProcessResult runProcess(const std::string& executable,
                         const std::vector<std::string>& arguments,
                         std::chrono::milliseconds timeout,
                         std::size_t maxOutputBytes,
                         std::stop_token cancellation = {});

}  // namespace daemonx::detail

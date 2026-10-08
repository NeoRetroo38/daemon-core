#include "daemon/git_adapter.hpp"
#include "daemon/trace.hpp"
#include "platform.hpp"
#include "process.hpp"

#include <charconv>
#include <filesystem>
#include <sstream>

namespace daemonx {
namespace {

std::optional<std::uint64_t> number(std::string_view value) {
    std::uint64_t result{};
    const auto parsed = std::from_chars(value.data(), value.data() + value.size(), result);
    if (parsed.ec != std::errc{} || parsed.ptr != value.data() + value.size()) return std::nullopt;
    return result;
}

RepositoryState failure(RepositoryState repository, const std::string& code) {
    repository.status = ObservationStatus::unavailable;
    repository.error = code;
    return repository;
}

std::string processError(const detail::ProcessResult& process) {
    if (process.cancelled) return "CANCELLED";
    if (process.timedOut) return "TIMED_OUT";
    if (process.outputLimitExceeded) return "OUTPUT_LIMIT_EXCEEDED";
    if (process.unavailable) return "GIT_UNAVAILABLE";
    return "GIT_OBSERVATION_FAILED";
}

std::string displayName(const std::string& path) {
    const auto directory = std::filesystem::path(path);
    // Scenarys checkouts commonly use product/repo; keep the label useful
    // without reading or disclosing a remote URL that may carry credentials.
    return directory.filename() == "repo" ? directory.parent_path().filename().string()
                                          : directory.filename().string();
}

}  // namespace

bool localProcessesAvailable() { return DAEMON_HAS_LOCAL_PROCESSES != 0; }

bool parseGitStatus(std::string_view text, RepositoryState& repository) {
    bool sawHead = false;
    bool sawOid = false;
    bool dirty = false;
    std::istringstream lines{std::string(text)};
    std::string line;
    for (; std::getline(lines, line);) {
        if (line.starts_with("# branch.oid ")) {
            const auto value = line.substr(13);
            if (value != "(initial)") {
                if ((value.size() != 40 && value.size() != 64) || value.find_first_not_of("0123456789abcdef") != std::string::npos) return false;
                repository.head = value;
            }
            sawOid = true;
        } else if (line.starts_with("# branch.head ")) {
            const auto value = line.substr(14);
            if (value.empty()) return false;
            repository.branch = value == "(detached)" ? "detached" : value;
            sawHead = true;
        } else if (line.starts_with("# branch.upstream ")) {
            const auto value = line.substr(18);
            if (value.empty()) return false;
            repository.upstream = value;
        } else if (line.starts_with("# branch.ab +")) {
            const auto separator = line.find(" -", 13);
            if (separator == std::string::npos) return false;
            repository.ahead = number(std::string_view(line).substr(13, separator - 13));
            repository.behind = number(std::string_view(line).substr(separator + 2));
            if (!repository.ahead || !repository.behind) return false;
        } else if (!line.empty() && line[0] != '#') {
            if (line[0] != '1' && line[0] != '2' && line[0] != 'u' && line[0] != '?') return false;
            dirty = true;
        }
    }
    if (!sawHead || !sawOid) return false;
    repository.dirty = dirty;
    return true;
}

RepositoryState GitAdapter::observe(const std::string& explicitPath, std::stop_token cancellation) const {
    RepositoryState repository;
    repository.path = explicitPath;
    repository.name = displayName(explicitPath);
    if (explicitPath.empty() || explicitPath.find('\0') != std::string::npos) return failure(repository, "EXPLICIT_REPOSITORY_REQUIRED");
    const std::vector<std::string> prefix{"--no-pager", "-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null", "-C", explicitPath};
    auto arguments = prefix;
    arguments.insert(arguments.end(), {"rev-parse", "--show-toplevel"});
    if (!policy_.evaluate(StructuredCommand{"/usr/bin/git", arguments}).allowed) return failure(repository, "READ_ONLY_DENIED");
    if (!localProcessesAvailable()) return failure(repository, "LOCAL_PROCESSES_UNAVAILABLE");
    if (cancellation.stop_requested()) return failure(repository, "CANCELLED");
    const auto root = detail::runProcess("/usr/bin/git", arguments, options_.timeout, options_.maxOutputBytes, cancellation);
    if (root.unavailable || root.cancelled || root.timedOut || root.outputLimitExceeded) return failure(repository, processError(root));
    if (root.exitCode != 0) return failure(repository, "NOT_A_REPOSITORY");
    auto path = root.standardOutput;
    while (!path.empty() && (path.back() == '\n' || path.back() == '\r')) path.pop_back();
    if (path.empty()) return failure(repository, "INVALID_REPOSITORY_ROOT");
    repository.path = path;
    repository.name = displayName(path);
    arguments = prefix;
    arguments.insert(arguments.end(), {"status", "--porcelain=v2", "--branch", "--untracked-files=normal"});
    if (!policy_.evaluate(StructuredCommand{"/usr/bin/git", arguments}).allowed) return failure(repository, "READ_ONLY_DENIED");
    const auto status = detail::runProcess("/usr/bin/git", arguments, options_.timeout, options_.maxOutputBytes, cancellation);
    if (status.exitCode != 0 || status.unavailable || status.cancelled || status.timedOut || status.outputLimitExceeded) return failure(repository, processError(status));
    if (!parseGitStatus(status.standardOutput, repository)) return failure(repository, "INVALID_GIT_STATUS");
    repository.status = ObservationStatus::verified;
    return repository;
}

Snapshot observeRepositories(const std::vector<std::string>& explicitPaths, std::stop_token cancellation) {
    Snapshot snapshot;
    snapshot.timestamp = utcTimestamp();
    snapshot.mode = localProcessesAvailable() ? "local" : "remote-required";
    GitAdapter adapter;
    for (const auto& path : explicitPaths) {
        const auto started = std::chrono::steady_clock::now();
        auto repository = adapter.observe(path, cancellation);
        TraceEvent event;
        event.timestamp = utcTimestamp();
        event.actor = "daemon";
        event.machine = snapshot.mode == "local" ? "local" : "iOS/unsupported";
        event.repository = repository.name;
        event.branch = repository.branch.value_or("");
        event.commit = repository.head.value_or("");
        event.operation = "git-snapshot";
        event.result = repository.error.value_or("OBSERVED");
        event.durationMs = static_cast<std::uint64_t>(std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - started).count());
        snapshot.events.push_back(sanitizedEvent(std::move(event)));
        snapshot.repositories.push_back(std::move(repository));
        if (cancellation.stop_requested()) break;
    }
    selectNextAction(snapshot);
    return snapshot;
}

}  // namespace daemonx

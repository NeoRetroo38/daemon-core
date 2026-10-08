#include "daemon/daemon_bridge.h"
#include "daemon/git_adapter.hpp"
#include "daemon/policy.hpp"
#include "daemon/trace.hpp"
#include "platform.hpp"
#include "process.hpp"
#include "security_cases.hpp"

#include <chrono>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <stdexcept>
#include <stop_token>
#include <thread>

using namespace std::chrono_literals;

namespace {
void require(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
}

void policyTests() {
    const daemonx::Policy policy;
    require(policy.evaluate(daemonx::CommandClass::READ_ONLY).allowed, "read-only enabled");
    for (const auto command : {daemonx::CommandClass::WRITE, daemonx::CommandClass::NETWORK, daemonx::CommandClass::PRIVILEGED}) {
        require(!policy.evaluate(command).allowed, "mutating/network/privileged denied by default");
        require(policy.evaluate(command).requiresApproval, "denied action requires rule/approval");
    }
    const daemonx::Policy explicitRules({true, true, true});
    require(explicitRules.evaluate(daemonx::CommandClass::WRITE).allowed, "explicit write rule");
    require(!explicitRules.evaluate(daemonx::CommandClass::PRIVILEGED).allowed, "privileged never silently authorized");
    const daemonx::GitAdapter denied(daemonx::Policy({false, false, false}));
    require(denied.observe(DAEMON_TEST_REPOSITORY).error == "READ_ONLY_DENIED", "policy gates observation");
}

void parserTests() {
    daemonx::RepositoryState repository;
    const std::string status = "# branch.oid 0123456789abcdef0123456789abcdef01234567\n# branch.head codex/foundation\n# branch.upstream origin/main\n# branch.ab +2 -3\n? local.txt\n";
    require(daemonx::parseGitStatus(status, repository), "porcelain parsed");
    require(repository.branch == "codex/foundation" && repository.ahead == 2 && repository.behind == 3 && repository.dirty == true, "branch/ahead/behind/dirty exact");
    daemonx::RepositoryState unborn;
    require(daemonx::parseGitStatus("# branch.oid (initial)\n# branch.head main\n", unborn), "unborn supported");
    require(!unborn.head && !unborn.ahead && unborn.dirty == false, "unknown remains nullable");
    daemonx::RepositoryState detached;
    require(daemonx::parseGitStatus("# branch.oid 0123456789abcdef0123456789abcdef01234567\n# branch.head (detached)\n", detached), "detached supported");
    require(detached.branch == "detached", "detached explicit");
    require(!daemonx::parseGitStatus("# branch.head main\n# branch.ab +not-a-number -1\n", repository), "malformed rejected");
}

void traceAndJsonTests() {
    const auto sanitized = daemonx::redact("DATABASE_URL=postgresql://example:credential@db.example/db password=secret-value Authorization: Bearer example-session-token");
    require(sanitized.find("credential") == std::string::npos && sanitized.find("secret-value") == std::string::npos && sanitized.find("example-session-token") == std::string::npos, "secret values redacted");
    const auto prefixed = daemonx::redact("CHOISYS_LOCAL_API_TOKEN=example-credential {\"token\":\"json-credential\"} postgresql://u:semi;colon@host/db NEON_DATABASE_URL=opaque-credential AWS_SECRET_ACCESS_KEY=opaque-secret");
    require(prefixed.find("example-credential") == std::string::npos && prefixed.find("json-credential") == std::string::npos && prefixed.find("colon@host") == std::string::npos && prefixed.find("opaque-credential") == std::string::npos && prefixed.find("opaque-secret") == std::string::npos, "prefixed keys/JSON/URL punctuation redacted");
    require(daemonx::redact("-----BEGIN PRIVATE KEY-----\nexample-body\n-----END PRIVATE KEY-----").find("example-body") == std::string::npos, "PEM redacted");
    daemonx::Snapshot snapshot;
    snapshot.timestamp = daemonx::utcTimestamp();
    daemonx::RepositoryState repository;
    repository.name = "name\"\\\n";
    repository.path = "/explicit/path";
    snapshot.repositories.push_back(repository);
    daemonx::selectNextAction(snapshot);
    const auto json = daemonx::snapshotJson(snapshot);
    require(json.find("name\\\"\\\\\\n") != std::string::npos, "JSON escaping");
    require(json.find("\"dirty\":null") != std::string::npos, "unknown not clean");
    require(json.find("\"services\":[]") != std::string::npos && json.find("\"agents\":[]") != std::string::npos, "no invented services/agents");
    require(std::strcmp(daemon_core_version(), "0.1.0") == 0, "ABI version");
    char* invalid = daemon_snapshot_json(nullptr);
    require(invalid && std::strstr(invalid, "EXPLICIT_REPOSITORY_REQUIRED"), "ABI handles explicit path error");
    daemon_free_string(invalid);
    daemon_free_string(nullptr);
}

void processAndGitTests() {
#if DAEMON_HAS_LOCAL_PROCESSES
    setenv("DAEMON_TEST_CHILD_SECRET", "synthetic-not-a-real-secret", 1);
    const auto environment = daemonx::detail::runProcess("/usr/bin/env", {}, 2s, 8192);
    require(environment.exitCode == 0 && environment.standardOutput.find("DAEMON_TEST_CHILD_SECRET") == std::string::npos && environment.standardOutput.find("synthetic-not-a-real-secret") == std::string::npos, "child environment excludes secrets");
    const auto literal = daemonx::detail::runProcess("/usr/bin/printf", {"%s", "$(echo injected); untouched"}, 2s, 1024);
    require(literal.exitCode == 0 && literal.standardOutput == "$(echo injected); untouched", "argv is never a shell string");
    const auto timeout = daemonx::detail::runProcess("/bin/sleep", {"2"}, 50ms, 1024);
    require(timeout.timedOut && timeout.durationMs < 1000, "timeout kills and reaps child promptly");
    std::stop_source cancellation;
    std::jthread stop([&] { std::this_thread::sleep_for(50ms); cancellation.request_stop(); });
    const auto cancelled = daemonx::detail::runProcess("/bin/sleep", {"2"}, 2s, 1024, cancellation.get_token());
    require(cancelled.cancelled && cancelled.durationMs < 1000, "cancellation kills and reaps child");
    const auto bounded = daemonx::detail::runProcess("/usr/bin/yes", {}, 2s, 128);
    require(bounded.outputLimitExceeded && bounded.standardOutput.size() + bounded.standardError.size() <= 128 && bounded.durationMs < 1000, "combined output bounded");
    const auto repository = daemonx::GitAdapter().observe(DAEMON_TEST_REPOSITORY);
    require(repository.status == daemonx::ObservationStatus::verified && repository.branch && repository.head && repository.dirty.has_value(), "real repository observation");
    const auto missing = daemonx::GitAdapter().observe("/daemon-foundation-does-not-exist");
    require(missing.status == daemonx::ObservationStatus::unavailable && !missing.dirty, "invalid repo not called clean");
    char* json = daemon_snapshot_json(DAEMON_TEST_REPOSITORY);
    require(json && std::strstr(json, "\"status\":\"ready\"") && std::strstr(json, "\"operation\":\"git-snapshot\""), "real C ABI snapshot");
    daemon_free_string(json);
#else
    const auto snapshot = daemonx::observeRepositories({DAEMON_TEST_REPOSITORY});
    require(snapshot.mode == "remote-required" && snapshot.repositories[0].error == "LOCAL_PROCESSES_UNAVAILABLE", "iOS processes unavailable and honest");
    const auto unavailable = daemonx::detail::runProcess("git", {"--version"}, 2s, 128);
    require(unavailable.unavailable, "no subprocess on iOS/unsupported platform");
#endif
}
}

int main() {
    try {
        policyTests(); daemonx::tests::commandPolicyCases(); daemonx::tests::urlRedactionCases(); daemonx::tests::exposureCases();
        parserTests(); traceAndJsonTests(); processAndGitTests();
        std::cout << "DAEMON TESTS PASSED: policy, parser, redaction, JSON, C ABI, process bounds and platform behavior\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "Daemon test failed: " << error.what() << '\n';
        return 1;
    }
}

#include "security_cases.hpp"
#include "daemon/exposure.hpp"
#include "daemon/policy.hpp"
#include "daemon/trace.hpp"

#include <stdexcept>
#include <string>
#include <vector>

namespace daemonx::tests {
namespace {
void require(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
}

void expect(const Policy& policy, const StructuredCommand& command, PolicyVerdict verdict, const char* message) {
    const auto actual = policy.evaluate(command);
    require(actual.verdict == verdict, message);
    require(actual.allowed == (verdict == PolicyVerdict::Allow) &&
            actual.requiresApproval == (verdict == PolicyVerdict::RequireApproval), "verdict and compatibility flags agree");
}
}

void commandPolicyCases() {
    const Policy standard;
    const Policy permissive({true, true, true});
    const std::vector<StructuredCommand> permanentDenials{
        {"git", {"push", "--force", "origin", "main"}},
        {"/usr/bin/git", {"-C", "/explicit/repo", "push", "-f", "origin", "main"}},
        {"git", {"push", "origin", "+local:remote"}},
        {"git", {"push", "--force-with-lease=main", "origin", "main"}},
        {"git", {"push", "-vf", "origin", "main"}},
        {"git", {"--git-dir", "/explicit/repo/.git", "push", "-f"}},
        {"git", {"filter-branch", "--all"}},
        {"git", {"-c", "alias.erase=!rm -rf /", "erase"}},
        {"git", {"-cALIAS.erase=!bash -c echo", "erase"}},
        {"git", {"-c", "core.fsmonitor=/untrusted/helper", "status"}},
        {"sudo", {"git", "status"}},
        {"/usr/bin/sudo", {"-n", "anything"}},
        {"rm", {"-rf", "/"}}, {"rm", {"-fr", "/./"}}, {"rm", {"-rf", "//"}},
        {"rm", {"--recursive", "--force", "$TASK_DIR"}},
        {"rm", {"-rf", "${TASK_DIR}/child"}},
        {"rm", {"-rf", "~"}}, {"rm", {"-rf", "~/child"}},
        {"rm", {"-rf", ".."}}, {"rm", {"-rf", "/safe/../other"}},
        {"rm", {"-rf", "."}}, {"rm", {"-rf", "*"}},
        {"rm", {"-rf", "C:\\"}}, {"rm", {"-rf", "%TASK_DIR%"}},
        {"csrutil", {"disable"}}, {"csrutil", {"status"}},
        {"spctl", {"--master-disable"}}, {"spctl", {"--global-disable"}},
        {"tccutil", {"reset", "All"}}, {"security", {"dump-keychain"}},
        {"bash", {"-c", "echo synthetic"}}, {"/bin/bash", {"-lc", "echo synthetic"}},
        {"zsh", {"-c", "echo synthetic"}}, {"cmd.exe", {"/C", "echo synthetic"}},
        {"git status && sudo whatever", {}}, {"git status", {}},
        {"/usr/bin/git status", {}}, {"/usr/bin/git;anything", {}},
        {"$(anything)", {}}, {"git\nanything", {}},
    };
    for (const auto& command : permanentDenials) {
        expect(standard, command, PolicyVerdict::Deny, "dangerous command permanently denied by default");
        expect(permissive, command, PolicyVerdict::Deny, "dangerous command remains denied with permissive rules");
    }
    const std::vector<StructuredCommand> safeReads{
        {"/usr/bin/git", {"--no-pager", "-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null", "-C", "/explicit/repo", "rev-parse", "--show-toplevel"}},
        {"git", {"status", "--porcelain=v2", "--branch"}},
        {"/Applications/Trusted Git Tools/git", {"-C", "/repo with spaces/$(literal);name", "status"}},
        {"C:\\Program Files\\Git\\bin\\git.exe", {"-C", "C:\\repo with spaces", "status"}},
        {"git", {"status", "--", "literal bash -c; sudo string"}},
    };
    for (const auto& command : safeReads) {
        expect(standard, command, PolicyVerdict::Allow, "trusted read argv and paths are not shell text");
        require(standard.evaluate(command).classification == CommandClass::READ_ONLY, "read classification derived from command");
        expect(Policy({false, true, true}), command, PolicyVerdict::Deny, "read-only rule still gates structured observation");
    }
    expect(standard, {"git", {"commit", "-m", "literal push --force; bash -c"}}, PolicyVerdict::RequireApproval, "commit message does not become a command");
    expect(permissive, {"git", {"commit", "-m", "literal push --force; bash -c"}}, PolicyVerdict::Allow, "explicit write rule permits known write only");
    expect(standard, {"git", {"push", "origin", "main"}}, PolicyVerdict::RequireApproval, "normal push is a network action");
    require(standard.evaluate(StructuredCommand{"git", {"push", "origin", "main"}}).classification == CommandClass::NETWORK, "push network classification");
    expect(standard, {"rm", {"-rf", "/tmp/explicit-narrow-fixture"}}, PolicyVerdict::RequireApproval, "narrow deletion requires target approval");
    expect(permissive, {"rm", {"-rf", "/tmp/explicit-narrow-fixture"}}, PolicyVerdict::RequireApproval, "class rule does not approve deletion targets");
    expect(permissive, {"/Applications/Trusted Tools/custom program", {"literal bash -c"}}, PolicyVerdict::RequireApproval, "unknown program paths with spaces are not falsely denied or auto-allowed");
    expect(permissive, {"git", {"-c", "user.name=synthetic", "status"}}, PolicyVerdict::RequireApproval, "unknown config does not bypass inspection");
    expect(permissive, {"git", {"status", "--help"}}, PolicyVerdict::RequireApproval, "read-looking help must not auto-launch a pager");
    expect(permissive, {"git", {"status", "--unknown-option"}}, PolicyVerdict::RequireApproval, "read flags are narrowly recognized");
    require(standard.evaluate(StructuredCommand{"security", {"find-keychain"}}).classification == CommandClass::PRIVILEGED,
            "security tools remain privileged without a permanently denied subcommand");
}

void urlRedactionCases() {
    const auto value = redact("https://synthetic-user:synthetic-pass@example.invalid/path?q=public ssh://synthetic-login@example.invalid/repo https://encoded:pass%40word@example.invalid/next");
    for (const auto secret : {"synthetic-user", "synthetic-pass", "synthetic-login", "pass%40word"})
        require(value.find(secret) == std::string::npos, "generic URL userinfo is redacted");
    require(value.find("https://[REDACTED]@example.invalid/path?q=public") != std::string::npos, "URL endpoint and public path remain useful");
    require(redact("https://example.invalid/path?q=hello@public") == "https://example.invalid/path?q=hello@public", "public URL query is not userinfo");
    require(redact("public status: clean") == "public status: clean", "benign text unchanged");
    const auto original = redact("Bearer synthetic-bearer DATABASE_URL=postgresql://synthetic:password@example.invalid/db TOKEN=synthetic-token");
    require(original.find("synthetic-bearer") == std::string::npos && original.find("synthetic-token") == std::string::npos &&
            original.find("password@example") == std::string::npos, "existing redaction continues to protect token and database fixtures");
}

void exposureCases() {
    require(check_exposure({}).status == ExposureStatus::UNKNOWN, "no observation is unknown, not safe");
    require(check_exposure({false, {{"127.0.0.1", 8765}}}).status == ExposureStatus::UNKNOWN, "partial loopback evidence cannot rule out another binding");
    require(check_exposure({true, {{"127.0.0.1", 8765}}}).status == ExposureStatus::SAFE, "complete approved loopback binding");
    require(check_exposure({true, {}}).reason == "ENGINE_PORT_NOT_LISTENING", "complete absence is not a claim that the engine runs");
    for (const auto address : {"0.0.0.0", "192.0.2.10", "203.0.113.10", "::", "::1", "*"})
        require(check_exposure({true, {{address, 8765}}}).status == ExposureStatus::EXPOSED, "engine binding must preserve exact IPv4 loopback contract");
    require(check_exposure({false, {{"0.0.0.0", 8765}}}).status == ExposureStatus::EXPOSED, "known exposure dominates incomplete evidence");
    require(check_exposure({true, {{"127.0.0.1", 8765}, {"0.0.0.0", 8765}}}).status == ExposureStatus::EXPOSED, "a second nonloopback listener is not hidden");
    require(check_exposure({true, {{"localhost", 8765}}}).status == ExposureStatus::UNKNOWN, "hostnames are not observed numeric bindings");
    require(check_exposure({true, {{"not-observed", 8765}}}).status == ExposureStatus::UNKNOWN, "invalid binding data is unknown");
    require(check_exposure({true, {{"127.0.0.1", 8765}, {"not-observed", 8765}}}).status == ExposureStatus::UNKNOWN, "an unknown second binding prevents safety claim");
    require(check_exposure({true, {{"0.0.0.0", 3000}}}).reason == "ENGINE_PORT_NOT_LISTENING", "other ports do not describe engine exposure");
}

}  // namespace daemonx::tests

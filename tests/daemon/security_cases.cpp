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

void observationToolCases() {
    const Policy standard;
    const Policy permissive({true, true, true});
    const std::vector<StructuredCommand> reads{
        {"/usr/sbin/lsof", {"-nP", "-iTCP", "-sTCP:LISTEN", "-FpcnT"}},
        {"/usr/sbin/lsof", {"-nP", "-iTCP:8765", "-sTCP:LISTEN", "-Fpcn"}},
        {"/bin/ps", {"-axo", "pid,ppid,%cpu,rss,etime,comm"}},
        {"/bin/ps", {"-o", "pid,%cpu,rss,etime", "-p", "12,34"}},
        {"/Applications/Tailscale.app/Contents/MacOS/Tailscale", {"status", "--json"}},
        {"tailscale", {"ip", "-4"}},
        {"/opt/homebrew/bin/gh", {"pr", "list", "-R", "NeoRetroo38/daemon-core", "--state", "all", "--json", "number,title,state", "--limit", "20"}},
        {"gh", {"run", "list", "--repo", "NeoRetroo38/choisys", "--limit", "5", "--json", "status,conclusion"}},
        {"gh", {"auth", "status", "--hostname", "github.com"}},
        {"/usr/bin/git", {"-C", "/repo", "log", "--no-color", "--format=%H%x09%ct%x09%s", "-20"}},
        {"git", {"-C", "/repo", "diff", "--no-ext-diff", "--no-textconv", "--numstat"}},
        {"git", {"-C", "/repo", "rev-list", "--count", "--all"}},
        {"git", {"-C", "/repo", "branch", "-a", "--format=%(refname:short)"}},
        {"git", {"-C", "/repo", "remote", "get-url", "origin"}},
        {"git", {"-C", "/repo", "ls-files", "-z"}},
        {"git", {"--version"}}, {"ssh", {"-V"}},
        {"/usr/sbin/sysctl", {"-n", "hw.memsize"}}, {"/usr/bin/vm_stat", {}}, {"/usr/bin/pmset", {"-g", "batt"}},
        {"/usr/bin/sw_vers", {}}, {"/opt/homebrew/bin/brew", {"info", "--json=v2", "--installed"}},
        {"/opt/homebrew/bin/node", {"--version"}}, {"/usr/bin/xcode-select", {"-p"}},
    };
    for (const auto& command : reads) {
        expect(standard, command, PolicyVerdict::Allow, "observation tool allowed as a narrow read");
        require(standard.evaluate(command).classification == CommandClass::READ_ONLY, "observation classified as read");
    }
    const std::vector<StructuredCommand> approvals{
        {"lsof", {"+D", "/"}}, {"lsof", {"-p", "1"}},
        {"gh", {"pr", "merge", "1"}}, {"gh", {"api", "repos/x/y", "-X", "DELETE"}}, {"gh", {"pr", "list", "--web"}},
        {"git", {"-C", "/repo", "diff", "--ext-diff"}}, {"git", {"-C", "/repo", "log", "--output=/tmp/x"}},
        {"git", {"-C", "/repo", "remote", "-v"}}, {"git", {"-C", "/repo", "remote", "add", "x", "y"}},
        {"git", {"-C", "/repo", "branch", "new-branch"}},
        {"tailscale", {"up"}}, {"tailscale", {"serve", "8765"}}, {"tailscale", {"funnel", "8765"}},
        {"sysctl", {"-w", "kern.maxfiles=1"}}, {"sysctl", {"kern.maxfiles=1"}},
        {"pmset", {"sleepnow"}}, {"brew", {"install", "anything"}},
        {"ssh", {"desktop"}}, {"ssh", {"-L", "8765:127.0.0.1:8765", "desktop"}},
    };
    for (const auto& command : approvals) {
        require(!standard.evaluate(command).allowed, "mutating or unknown observation shapes are not auto-allowed");
    }
    const std::vector<StructuredCommand> denials{
        {"ssh", {"-N", "-L", "0.0.0.0:8765:127.0.0.1:8765", "desktop"}},
        {"ssh", {"-N", "-L", "*:8765:127.0.0.1:8765", "desktop"}},
        {"ssh", {"-N", "-L", "8765:192.0.2.1:8765", "desktop"}},
        {"ssh", {"-N", "-g", "-L", "8765:127.0.0.1:8765", "desktop"}},
        {"ssh", {"-N", "-R", "8765:127.0.0.1:8765", "desktop"}},
        {"ssh", {"-o", "ProxyCommand=sh -c x", "-N", "desktop"}},
        {"ssh", {"-oLocalCommand=x", "-N", "desktop"}},
    };
    for (const auto& command : denials) {
        expect(permissive, command, PolicyVerdict::Deny, "tunnels never bind or forward outside loopback");
    }
    expect(standard, {"ssh", {"-N", "-L", "8765:127.0.0.1:8765", "neo@desktop"}}, PolicyVerdict::RequireApproval, "loopback tunnel needs network rule");
    expect(permissive, {"ssh", {"-N", "-L", "127.0.0.1:8765:127.0.0.1:8765", "neo@desktop"}}, PolicyVerdict::Allow, "loopback tunnel allowed with network rule");
    expect(permissive, {"tailscale", {"up"}}, PolicyVerdict::Allow, "tailscale mutation is network class under explicit rule");
    require(standard.evaluate(StructuredCommand{"tailscale", {"funnel", "8765"}}).classification == CommandClass::NETWORK, "funnel is network class");
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

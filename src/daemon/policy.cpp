#include <cstdio>
#include "daemon/policy.hpp"

#include <algorithm>
#include <cctype>
#include <initializer_list>
#include <string_view>

namespace daemonx {
namespace {

PolicyDecision decision(PolicyVerdict verdict, CommandClass classification, const char* reason) {
    return {verdict == PolicyVerdict::Allow, verdict == PolicyVerdict::RequireApproval,
            reason, verdict, classification};
}

std::string programName(std::string_view executable) {
    const auto separator = executable.find_last_of("/\\");
    std::string name(executable.substr(separator == std::string_view::npos ? 0 : separator + 1));
    std::transform(name.begin(), name.end(), name.begin(), [](unsigned char value) {
        return static_cast<char>(std::tolower(value));
    });
    if (name.ends_with(".exe")) name.resize(name.size() - 4);
    return name;
}

bool shellString(std::string_view executable) {
    if (executable.find_first_of(";|&\r\n`") != std::string_view::npos ||
        executable.find("$(") != std::string_view::npos || executable.find('\0') != std::string_view::npos) return true;
    const auto name = programName(executable);
    // Spaces inside a directory path are valid. A bare multiword string is not
    // an executable path, and known command names followed by argv are not paths.
    if (executable.find_first_of("/\\") == std::string_view::npos && name.find_first_of(" \t") != std::string::npos) return true;
    for (const auto prefix : {"git ", "bash ", "sh ", "sudo ", "rm ", "cmd ", "powershell "})
        if (name.starts_with(prefix)) return true;
    return false;
}

bool shellProgram(std::string_view name) {
    return name == "bash" || name == "sh" || name == "zsh" || name == "dash" ||
           name == "ksh" || name == "fish" || name == "cmd" || name == "powershell" || name == "pwsh";
}

bool commandMode(const std::string& argument) {
    std::string lower(argument);
    std::transform(lower.begin(), lower.end(), lower.begin(), [](unsigned char value) { return static_cast<char>(std::tolower(value)); });
    if (lower == "--command" || lower == "-command" || lower == "/c" || lower == "/k") return true;
    return lower.size() > 1 && lower[0] == '-' && lower[1] != '-' && lower.find('c', 1) != std::string::npos;
}

bool broadDeleteTarget(std::string_view path) {
    if (path.empty() || path.front() == '~' || path.find_first_of("$`*?[%") != std::string_view::npos) return true;
    bool meaningfulComponent = false;
    std::size_t start = 0;
    for (std::size_t index = 0; index <= path.size(); ++index) {
        if (index != path.size() && path[index] != '/' && path[index] != '\\') continue;
        const auto component = path.substr(start, index - start);
        if (component == "..") return true;
        if (!component.empty() && component != ".") meaningfulComponent = true;
        start = index + 1;
    }
    if (!meaningfulComponent) return true;
    return path.size() <= 3 && path.size() >= 2 && std::isalpha(static_cast<unsigned char>(path[0])) && path[1] == ':';
}

struct GitCommand {
    std::size_t index{};
    bool found{};
    bool knownConfiguration{true};
    bool dangerousConfiguration{};
};

bool readOptionsKnown(const std::vector<std::string>& arguments, std::size_t commandIndex) {
    bool literalPaths = false;
    for (std::size_t index = commandIndex + 1; index < arguments.size(); ++index) {
        const auto& value = arguments[index];
        if (literalPaths) continue;
        if (value == "--") { literalPaths = true; continue; }
        if (!value.starts_with('-')) continue;
        if (arguments[commandIndex] == "status" &&
            (value == "--porcelain=v2" || value == "--porcelain" || value == "--branch" ||
             value == "--short" || value == "--untracked-files=normal" || value == "--untracked-files=no")) continue;
        if (arguments[commandIndex] == "rev-parse" &&
            (value == "--show-toplevel" || value == "--git-dir" || value == "--verify" || value == "--abbrev-ref")) continue;
        return false;
    }
    return true;
}

GitCommand gitCommand(const std::vector<std::string>& arguments) {
    GitCommand result;
    const auto config = [&](std::string_view value) {
        std::string lower(value);
        std::transform(lower.begin(), lower.end(), lower.begin(), [](unsigned char character) { return static_cast<char>(std::tolower(character)); });
        if (lower.starts_with("alias.") || lower.starts_with("core.sshcommand=") ||
            (lower.starts_with("core.fsmonitor=") && lower != "core.fsmonitor=false") ||
            lower.starts_with("filter.") || lower.starts_with("protocol.ext.")) result.dangerousConfiguration = true;
        if (value != "core.fsmonitor=false" && value != "core.hooksPath=/dev/null" && value != "core.hooksPath=NUL")
            result.knownConfiguration = false;
    };
    for (std::size_t index = 0; index < arguments.size(); ++index) {
        const auto& value = arguments[index];
        if (value == "--no-pager" || value == "-P" || value == "--no-optional-locks" || value == "--literal-pathspecs") continue;
        if (value == "-C" || value == "-c") {
            if (index + 1 == arguments.size() || arguments[index + 1].empty()) { result.knownConfiguration = false; return result; }
            if (value == "-c") config(arguments[index + 1]);
            ++index;
            continue;
        }
        if (value == "--git-dir" || value == "--work-tree" || value == "--namespace") {
            result.knownConfiguration = false;
            if (index + 1 == arguments.size()) return result;
            ++index; continue;
        }
        if (value.starts_with("-c") && !value.starts_with("--")) { config(std::string_view(value).substr(2)); continue; }
        if (value.starts_with("--config-env")) { result.dangerousConfiguration = true; return result; }
        if (value.starts_with('-')) { result.knownConfiguration = false; continue; }
        result.index = index; result.found = true; return result;
    }
    return result;
}


bool inSet(std::string_view value, std::initializer_list<std::string_view> values) {
    return std::find(values.begin(), values.end(), value) != values.end();
}

bool digits(std::string_view value, std::string_view extra = {}) {
    return !value.empty() && std::all_of(value.begin(), value.end(), [&](char c) {
        return (c >= '0' && c <= '9') || extra.find(c) != std::string_view::npos;
    });
}

bool identifier(std::string_view value, std::string_view extra) {
    return !value.empty() && value.size() <= 256 && std::all_of(value.begin(), value.end(), [&](char c) {
        return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || extra.find(c) != std::string_view::npos;
    });
}

// Git reads used by Daemon's repository tools. Options that can run helpers,
// write files or open pagers are never part of the allowlist.
bool gitReadAction(const std::vector<std::string>& arguments, std::size_t commandIndex) {
    const auto& action = arguments[commandIndex];
    static const std::initializer_list<std::string_view> actions{
        "log", "rev-list", "branch", "diff", "show", "ls-files", "for-each-ref", "shortlog", "remote", "count-objects"};
    if (!inSet(action, actions)) return false;
    if (action == "remote") {
        // Only `remote get-url <name>`; `remote -v` and mutations are excluded.
        return arguments.size() == commandIndex + 3 && arguments[commandIndex + 1] == "get-url" &&
               identifier(arguments[commandIndex + 2], "-_.");
    }
    if (action == "branch") {
        for (std::size_t index = commandIndex + 1; index < arguments.size(); ++index)
            if (!inSet(arguments[index], {"--list", "-a", "--all", "-r", "--remotes", "-v", "-vv", "--no-color", "--show-current"}) &&
                !arguments[index].starts_with("--format=") && !arguments[index].starts_with("--sort=")) return false;
        return true;
    }
    bool literalPaths = false;
    for (std::size_t index = commandIndex + 1; index < arguments.size(); ++index) {
        const auto& value = arguments[index];
        if (literalPaths) continue;
        if (value == "--") { literalPaths = true; continue; }
        if (!value.starts_with('-')) continue;
        if (value.starts_with("--output") || value.starts_with("--ext-diff") || value.starts_with("--textconv") ||
            value.starts_with("--exec") || value.starts_with("-O") || value.starts_with("--open-files-in-pager") ||
            value.starts_with("--upload-pack") || value == "--help" || value == "-h") return false;
        static const std::initializer_list<std::string_view> exact{
            "--no-ext-diff", "--no-textconv", "--no-color", "--stat", "--numstat", "--shortstat", "--name-only",
            "--name-status", "--oneline", "--no-merges", "--cached", "--staged", "--count", "--left-right",
            "--all", "-z", "-s", "-n", "-sn", "-v", "--summary", "--reverse", "--date=iso-strict", "--others",
            "--exclude-standard", "--abbrev-commit", "--no-patch", "--first-parent", "--heads", "--remotes", "-e"};
        if (inSet(value, exact)) continue;
        if (value.starts_with("--format=") || value.starts_with("--pretty=format:") || value.starts_with("--since=") ||
            value.starts_with("--until=") || value.starts_with("--max-count=") || value.starts_with("--sort=") ||
            value.starts_with("--stat=") || value.starts_with("--date=") || value.starts_with("--count=")) continue;
        if (value.size() > 1 && value[0] == '-' && digits(std::string_view(value).substr(1))) continue;  // -20
        return false;
    }
    return true;
}

// Observation programs used by Daemon's system tools. Each one is accepted only
// with the exact read-only options listed here.
bool systemRead(std::string_view program, const std::vector<std::string>& arguments) {
    const auto all = [&](auto predicate) { return std::all_of(arguments.begin(), arguments.end(), predicate); };
    if (program == "lsof") {
        return !arguments.empty() && all([](const std::string& value) {
            return inSet(value, {"-n", "-P", "-nP", "-Pn", "-iTCP", "-iUDP", "-sTCP:LISTEN", "-Fpcn", "-FpcnT", "-FpcnPT", "-Fpcnt", "-w"}) ||
                   (value.starts_with("-iTCP:") && digits(std::string_view(value).substr(6), ",-"));
        });
    }
    if (program == "ps") {
        for (std::size_t index = 0; index < arguments.size(); ++index) {
            const auto& value = arguments[index];
            if (value == "-ax" || value == "-A" || value == "-ww") continue;
            if ((value == "-o" || value == "-axo") && index + 1 < arguments.size() && identifier(arguments[index + 1], ",%=_")) { ++index; continue; }
            if (value == "-p" && index + 1 < arguments.size() && digits(arguments[index + 1], ",")) { ++index; continue; }
            return false;
        }
        return true;
    }
    if (program == "tailscale") {
        if (arguments == std::vector<std::string>{"status", "--json"} || arguments == std::vector<std::string>{"version"} ||
            arguments == std::vector<std::string>{"ip", "-4"} || arguments == std::vector<std::string>{"ip"}) return true;
        // Un ping de latencia a un nodo de la tailnet (100.64.0.0/10) es lectura; a cualquier otra IP, no.
        if (arguments.size() == 6 && arguments[0] == "ping" && arguments[1] == "-c" && arguments[2] == "1" &&
            arguments[3] == "--timeout" && arguments[4] == "2s") {
            unsigned a = 0, b = 0, c = 0, d = 0;
            char tail = 0;
            if (std::sscanf(arguments[5].c_str(), "%u.%u.%u.%u%c", &a, &b, &c, &d, &tail) != 4) return false;
            return a == 100 && b >= 64 && b <= 127 && c <= 255 && d <= 255;
        }
        return false;
    }
    if (program == "gh") {
        if (arguments == std::vector<std::string>{"--version"}) return true;
        if (arguments.size() < 2) return false;
        const auto noun = arguments[0], verb = arguments[1];
        const bool listing = (inSet(noun, {"pr", "issue", "run", "release"}) && verb == "list") ||
                             (noun == "repo" && verb == "view") || (noun == "auth" && verb == "status");
        if (!listing) return false;
        for (std::size_t index = 2; index < arguments.size(); ++index) {
            const auto& value = arguments[index];
            if (inSet(value, {"--json", "-R", "--repo", "--limit", "-L", "--state", "-s", "--branch", "-b"}) && index + 1 < arguments.size() &&
                identifier(arguments[index + 1], ",-_./")) { ++index; continue; }
            if (value == "--hostname" && index + 1 < arguments.size() && arguments[index + 1] == "github.com") { ++index; continue; }
            if (noun == "repo" && index == 2 && identifier(value, "-_./")) continue;
            return false;
        }
        return true;
    }
    if (program == "sw_vers" || program == "uname" || program == "vm_stat" || program == "uptime") {
        return all([](const std::string& value) { return value.size() <= 32 && identifier(value, "-"); });
    }
    if (program == "sysctl") {
        return !arguments.empty() && all([](const std::string& value) {
            return value == "-n" || (identifier(value, "._") && value.find('=') == std::string::npos && value != "-w");
        });
    }
    if (program == "df") return all([](const std::string& value) { return inSet(value, {"-k", "-h", "-P", "/"}); });
    if (program == "pmset") return arguments == std::vector<std::string>{"-g", "batt"};
    if (program == "brew") {
        return arguments == std::vector<std::string>{"list", "--versions"} ||
               arguments == std::vector<std::string>{"info", "--json=v2", "--installed"} ||
               arguments == std::vector<std::string>{"--version"};
    }
    // `<tool> --version` probes for the toolchain inventory.
    static const std::initializer_list<std::string_view> versioned{
        "node", "npm", "swift", "clang", "clang++", "cmake", "make", "jq", "openssl", "python3", "docker",
        "psql", "code", "blender", "xcodebuild", "xcode-select", "ssh", "curl", "tailscale", "gh", "git", "npx", "c++"};
    if (inSet(program, versioned) && arguments.size() == 1 &&
        inSet(arguments[0], {"--version", "-version", "-V", "version", "-p", "--print-path"})) return true;
    return false;
}

// SSH is only a transport for private tunnels. Execution hooks, gateway
// forwarding and local binds outside loopback are never allowed.
PolicyDecision sshDecision(const std::vector<std::string>& arguments, const PolicyRules& rules) {
    const auto make = [](PolicyVerdict verdict, const char* reason) {
        return PolicyDecision{verdict == PolicyVerdict::Allow, verdict == PolicyVerdict::RequireApproval, reason, verdict, CommandClass::NETWORK};
    };
    for (std::size_t index = 0; index < arguments.size(); ++index) {
        const auto& value = arguments[index];
        std::string lower(value);
        std::transform(lower.begin(), lower.end(), lower.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
        if (lower.find("proxycommand") != std::string::npos || lower.find("localcommand") != std::string::npos ||
            lower.find("permitlocalcommand") != std::string::npos || lower.find("gatewayports") != std::string::npos)
            return make(PolicyVerdict::Deny, "SSH_EXECUTION_OPTION_DENIED");
        if (value == "-g" || value == "-R" || value.starts_with("-R")) return make(PolicyVerdict::Deny, "SSH_EXPOSING_FORWARD_DENIED");
        if (value == "-L" || value.starts_with("-L")) {
            const std::string spec = value == "-L" ? (index + 1 < arguments.size() ? arguments[index + 1] : "") : value.substr(2);
            if (value == "-L") ++index;
            // Accept only port:127.0.0.1:port or 127.0.0.1:port:127.0.0.1:port.
            const auto colons = static_cast<std::size_t>(std::count(spec.begin(), spec.end(), ':'));
            const bool loopbackBind = colons == 2 || spec.starts_with("127.0.0.1:");
            const bool loopbackTarget = spec.find(":127.0.0.1:") != std::string::npos;
            if (!loopbackBind || !loopbackTarget) return make(PolicyVerdict::Deny, "SSH_TUNNEL_OUTSIDE_LOOPBACK_DENIED");
        }
    }
    const bool tunnelOnly = std::find(arguments.begin(), arguments.end(), "-N") != arguments.end();
    if (!tunnelOnly) return make(PolicyVerdict::RequireApproval, "SSH_SESSION_REQUIRES_APPROVAL");
    return make(rules.allowNetwork ? PolicyVerdict::Allow : PolicyVerdict::RequireApproval,
                rules.allowNetwork ? "SSH_LOOPBACK_TUNNEL_ALLOWED" : "SSH_TUNNEL_REQUIRES_RULE");
}

}  // namespace

PolicyDecision Policy::evaluate(CommandClass command) const {
    switch (command) {
    case CommandClass::READ_ONLY:
        return decision(rules_.allowReadOnly ? PolicyVerdict::Allow : PolicyVerdict::Deny, command,
                        rules_.allowReadOnly ? "READ_ONLY_ALLOWED" : "READ_ONLY_DENIED");
    case CommandClass::WRITE:
        return decision(rules_.allowWrite ? PolicyVerdict::Allow : PolicyVerdict::RequireApproval, command,
                        rules_.allowWrite ? "WRITE_RULE_ALLOWED" : "WRITE_REQUIRES_RULE");
    case CommandClass::NETWORK:
        return decision(rules_.allowNetwork ? PolicyVerdict::Allow : PolicyVerdict::RequireApproval, command,
                        rules_.allowNetwork ? "NETWORK_RULE_ALLOWED" : "NETWORK_REQUIRES_RULE");
    case CommandClass::PRIVILEGED:
        return decision(PolicyVerdict::RequireApproval, command, "PRIVILEGED_REQUIRES_EXPLICIT_APPROVAL");
    }
    return decision(PolicyVerdict::Deny, CommandClass::PRIVILEGED, "UNKNOWN_COMMAND_DENIED");
}

PolicyDecision Policy::evaluate(const StructuredCommand& command) const {
    const auto deny = [](CommandClass classification, const char* reason) { return decision(PolicyVerdict::Deny, classification, reason); };
    if (command.executable.empty() || shellString(command.executable)) return deny(CommandClass::PRIVILEGED, "EXECUTABLE_STRING_DENIED");
    if (std::any_of(command.arguments.begin(), command.arguments.end(), [](const auto& argument) { return argument.find('\0') != std::string::npos; }))
        return deny(CommandClass::PRIVILEGED, "INVALID_ARGUMENT_DENIED");
    const auto program = programName(command.executable);
    const auto& arguments = command.arguments;
    if (program == "sudo" || program == "csrutil") return deny(CommandClass::PRIVILEGED, "SECURITY_OVERRIDE_DENIED");
    if (program == "spctl" && std::any_of(arguments.begin(), arguments.end(), [](const auto& value) {
            return value == "--master-disable" || value == "--global-disable" || value == "--disable" || value == "-d";
        })) return deny(CommandClass::PRIVILEGED, "SECURITY_OVERRIDE_DENIED");
    if (program == "tccutil" && std::find(arguments.begin(), arguments.end(), "reset") != arguments.end())
        return deny(CommandClass::PRIVILEGED, "TCC_RESET_DENIED");
    if (program == "security" && std::find(arguments.begin(), arguments.end(), "dump-keychain") != arguments.end())
        return deny(CommandClass::PRIVILEGED, "KEYCHAIN_DUMP_DENIED");
    if (program == "spctl" || program == "tccutil" || program == "security") return evaluate(CommandClass::PRIVILEGED);
    if (shellProgram(program)) {
        if (std::any_of(arguments.begin(), arguments.end(), commandMode)) return deny(CommandClass::PRIVILEGED, "SHELL_COMMAND_DENIED");
        return decision(PolicyVerdict::RequireApproval, CommandClass::PRIVILEGED, "SHELL_REQUIRES_APPROVAL");
    }
    if (program == "rm") {
        bool recursive = false, force = false, targets = false;
        std::vector<std::string_view> paths;
        for (const auto& value : arguments) {
            if (!targets && value == "--") { targets = true; continue; }
            if (!targets && value.starts_with('-')) {
                recursive |= value == "--recursive" || (value.size() > 1 && value[1] != '-' && value.find_first_of("rR", 1) != std::string::npos);
                force |= value == "--force" || (value.size() > 1 && value[1] != '-' && value.find('f', 1) != std::string::npos);
            } else { paths.push_back(value); }
        }
        if (recursive && force && (paths.empty() || std::any_of(paths.begin(), paths.end(), broadDeleteTarget)))
            return deny(CommandClass::WRITE, "BROAD_RECURSIVE_DELETE_DENIED");
        // A class-wide write rule is not an approval for a filesystem target.
        return decision(PolicyVerdict::RequireApproval, CommandClass::WRITE, "DELETE_REQUIRES_TARGET_APPROVAL");
    }
    if ((program == "git" || program == "ssh") && arguments.size() == 1 && (arguments[0] == "--version" || arguments[0] == "-V"))
        return evaluate(CommandClass::READ_ONLY);
    if (program == "git") {
        const auto parsed = gitCommand(arguments);
        if (parsed.dangerousConfiguration) return deny(CommandClass::PRIVILEGED, "GIT_EXECUTION_CONFIG_DENIED");
        if (!parsed.found) return decision(PolicyVerdict::RequireApproval, CommandClass::WRITE, "GIT_COMMAND_UNRECOGNIZED");
        const auto& action = arguments[parsed.index];
        if (action == "filter-branch" || action == "filter-repo") return deny(CommandClass::WRITE, "GIT_HISTORY_REWRITE_DENIED");
        if (action == "push") {
            for (std::size_t index = parsed.index + 1; index < arguments.size(); ++index) {
                const auto& value = arguments[index];
                if (value.starts_with("--force") || value.starts_with('+') ||
                    (value.size() > 1 && value[0] == '-' && value[1] != '-' && value.find('f', 1) != std::string::npos))
                    return deny(CommandClass::NETWORK, "GIT_FORCE_PUSH_DENIED");
            }
        }
        if (!parsed.knownConfiguration) return decision(PolicyVerdict::RequireApproval, CommandClass::PRIVILEGED, "GIT_CONFIGURATION_REQUIRES_APPROVAL");
        if (action == "status" || action == "rev-parse") {
            if (!readOptionsKnown(arguments, parsed.index))
                return decision(PolicyVerdict::RequireApproval, CommandClass::READ_ONLY, "GIT_READ_OPTIONS_REQUIRE_APPROVAL");
            return evaluate(CommandClass::READ_ONLY);
        }
        if (gitReadAction(arguments, parsed.index)) return evaluate(CommandClass::READ_ONLY);
        if (action == "fetch" || action == "pull" || action == "push" || action == "clone" || action == "ls-remote")
            return evaluate(CommandClass::NETWORK);
        if (action == "add" || action == "commit" || action == "merge" || action == "branch" || action == "tag" ||
            action == "checkout" || action == "switch" || action == "restore" || action == "reset" || action == "rm")
            return evaluate(CommandClass::WRITE);
    }
    if (program == "ssh") return sshDecision(arguments, rules_);
    if (program == "sysctl" && std::any_of(arguments.begin(), arguments.end(), [](const auto& value) {
            return value == "-w" || value.find('=') != std::string::npos;
        })) return decision(PolicyVerdict::RequireApproval, CommandClass::PRIVILEGED, "SYSTEM_SETTING_REQUIRES_APPROVAL");
    if (systemRead(program, arguments)) return evaluate(CommandClass::READ_ONLY);
    if (program == "tailscale" || program == "curl") return evaluate(CommandClass::NETWORK);
    return decision(PolicyVerdict::RequireApproval, CommandClass::WRITE, "COMMAND_REQUIRES_APPROVAL");
}

}  // namespace daemonx

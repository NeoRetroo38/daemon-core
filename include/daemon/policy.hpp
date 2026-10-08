#pragma once

#include <string>
#include <vector>

namespace daemonx {

enum class CommandClass { READ_ONLY, WRITE, NETWORK, PRIVILEGED };
enum class PolicyVerdict { Allow, RequireApproval, Deny };

struct StructuredCommand {
    std::string executable;
    std::vector<std::string> arguments;
};

struct PolicyRules {
    bool allowReadOnly{true};
    bool allowWrite{false};
    bool allowNetwork{false};
};

struct PolicyDecision {
    bool allowed{};
    bool requiresApproval{};
    std::string reason;
    PolicyVerdict verdict{PolicyVerdict::Deny};
    CommandClass classification{CommandClass::PRIVILEGED};
};

class Policy {
public:
    explicit Policy(PolicyRules rules = {}) : rules_(rules) {}
    [[nodiscard]] PolicyDecision evaluate(CommandClass command) const;
    // Inspect the executable and argv, rather than trusting a caller's label.
    // This is an evaluator only; it does not execute the command.
    [[nodiscard]] PolicyDecision evaluate(const StructuredCommand& command) const;

private:
    PolicyRules rules_;
};

}  // namespace daemonx

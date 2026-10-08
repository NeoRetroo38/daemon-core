#pragma once

#include <string>

namespace daemonx {

enum class CommandClass { READ_ONLY, WRITE, NETWORK, PRIVILEGED };

struct PolicyRules {
    bool allowReadOnly{true};
    bool allowWrite{false};
    bool allowNetwork{false};
};

struct PolicyDecision {
    bool allowed{};
    bool requiresApproval{};
    std::string reason;
};

class Policy {
public:
    explicit Policy(PolicyRules rules = {}) : rules_(rules) {}
    [[nodiscard]] PolicyDecision evaluate(CommandClass command) const;

private:
    PolicyRules rules_;
};

}  // namespace daemonx

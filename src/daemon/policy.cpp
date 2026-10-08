#include "daemon/policy.hpp"

namespace daemonx {

PolicyDecision Policy::evaluate(CommandClass command) const {
    switch (command) {
    case CommandClass::READ_ONLY:
        return {rules_.allowReadOnly, false, rules_.allowReadOnly ? "READ_ONLY_ALLOWED" : "READ_ONLY_DENIED"};
    case CommandClass::WRITE:
        return {rules_.allowWrite, !rules_.allowWrite, rules_.allowWrite ? "WRITE_RULE_ALLOWED" : "WRITE_REQUIRES_RULE"};
    case CommandClass::NETWORK:
        return {rules_.allowNetwork, !rules_.allowNetwork, rules_.allowNetwork ? "NETWORK_RULE_ALLOWED" : "NETWORK_REQUIRES_RULE"};
    case CommandClass::PRIVILEGED:
        return {false, true, "PRIVILEGED_REQUIRES_EXPLICIT_APPROVAL"};
    }
    return {false, true, "UNKNOWN_COMMAND_DENIED"};
}

}  // namespace daemonx

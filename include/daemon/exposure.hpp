#pragma once

#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace daemonx {

enum class ExposureStatus { SAFE, EXPOSED, UNKNOWN };

struct ObservedBinding {
    std::string address;
    std::uint16_t port{};
};

struct BindingObservation {
    bool complete{false};
    std::vector<ObservedBinding> bindings;
};

struct ExposureCheck {
    ExposureStatus status{ExposureStatus::UNKNOWN};
    std::string reason;
};

namespace detail {
inline bool observedIpv4(std::string_view address) {
    unsigned parts = 0;
    std::size_t start = 0;
    for (std::size_t index = 0; index <= address.size(); ++index) {
        if (index != address.size() && address[index] != '.') continue;
        const auto part = address.substr(start, index - start);
        if (part.empty() || part.size() > 3) return false;
        unsigned value = 0;
        for (const char digit : part) {
            if (digit < '0' || digit > '9') return false;
            value = value * 10 + static_cast<unsigned>(digit - '0');
        }
        if (value > 255) return false;
        ++parts; start = index + 1;
    }
    return parts == 4;
}
}  // namespace detail

// Pure check of supplied evidence, not a listener collector or health probe.
// The engine contract is IPv4 127.0.0.1:8765; IPv6 is not a permitted binding.
inline ExposureCheck check_exposure(const BindingObservation& observation) {
    bool unknown = !observation.complete;
    bool found = false;
    for (const auto& binding : observation.bindings) {
        if (binding.port != 8765) continue;
        found = true;
        if (binding.address == "127.0.0.1") continue;
        if (binding.address == "*" || detail::observedIpv4(binding.address) || binding.address.find(':') != std::string::npos)
            return {ExposureStatus::EXPOSED, "ENGINE_BINDING_OUTSIDE_APPROVED_LOOPBACK"};
        unknown = true;
    }
    if (unknown) return {ExposureStatus::UNKNOWN, "BINDING_EVIDENCE_INCOMPLETE"};
    return {ExposureStatus::SAFE, found ? "ENGINE_BINDING_LOOPBACK_ONLY" : "ENGINE_PORT_NOT_LISTENING"};
}

}  // namespace daemonx

#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace daemonx {

enum class ObservationStatus { unknown, verified, unavailable };

struct RepositoryState {
    std::string name;
    std::string path;
    std::optional<std::string> branch;
    std::optional<std::string> head;
    std::optional<std::string> upstream;
    std::optional<bool> dirty;
    std::optional<std::uint64_t> ahead;
    std::optional<std::uint64_t> behind;
    ObservationStatus status{ObservationStatus::unknown};
    std::optional<std::string> error;
};

struct ServiceObservation {
    std::string name;
    ObservationStatus status{ObservationStatus::unknown};
    std::optional<bool> healthy;
    std::string observedAt;
};

struct AgentObservation {
    std::string name;
    ObservationStatus status{ObservationStatus::unknown};
    std::optional<std::string> activity;
    std::string observedAt;
};

struct TraceEvent {
    std::string timestamp;
    std::string actor;
    std::string machine;
    std::string repository;
    std::string branch;
    std::string commit;
    std::string operation;
    std::string result;
    std::uint64_t durationMs{};
};

struct Snapshot {
    std::string timestamp;
    std::string mode{"local"};
    std::vector<RepositoryState> repositories;
    std::vector<ServiceObservation> services;
    std::vector<AgentObservation> agents;
    std::vector<TraceEvent> events;
    std::string nextAction;
};

std::string utcTimestamp();
std::string snapshotJson(const Snapshot& snapshot);
void selectNextAction(Snapshot& snapshot);

}  // namespace daemonx

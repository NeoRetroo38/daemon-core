#include "daemon/model.hpp"
#include "daemon/trace.hpp"

#include <algorithm>
#include <chrono>
#include <ctime>
#include <iomanip>
#include <sstream>

namespace daemonx {
namespace {

std::string jsonQuoted(std::string_view text) {
    std::ostringstream out;
    out << '"';
    for (const unsigned char value : text) {
        switch (value) {
        case '"': out << "\\\""; break;
        case '\\': out << "\\\\"; break;
        case '\n': out << "\\n"; break;
        case '\r': out << "\\r"; break;
        case '\t': out << "\\t"; break;
        default:
            if (value < 0x20) {
                out << "\\u" << std::hex << std::setw(4) << std::setfill('0') << static_cast<int>(value) << std::dec;
            } else {
                out << static_cast<char>(value);
            }
        }
    }
    out << '"';
    return out.str();
}

std::string textValue(const std::optional<std::string>& value) {
    return value ? jsonQuoted(redact(*value)) : "null";
}

std::string numberValue(const std::optional<std::uint64_t>& value) {
    return value ? std::to_string(*value) : "null";
}

std::string boolValue(const std::optional<bool>& value) {
    return value ? (*value ? "true" : "false") : "null";
}

const char* statusName(ObservationStatus status) {
    switch (status) {
    case ObservationStatus::verified: return "ready";
    case ObservationStatus::unavailable: return "unavailable";
    case ObservationStatus::unknown: return "unknown";
    }
    return "unknown";
}

template <typename Collection, typename Write>
void array(std::ostringstream& out, const Collection& collection, Write write) {
    out << '[';
    bool first = true;
    for (const auto& value : collection) {
        if (!first) out << ',';
        first = false;
        write(value);
    }
    out << ']';
}

}  // namespace

std::string utcTimestamp() {
    const auto time = std::chrono::system_clock::to_time_t(std::chrono::system_clock::now());
    std::tm utc{};
#if defined(_WIN32)
    gmtime_s(&utc, &time);
#else
    gmtime_r(&time, &utc);
#endif
    std::ostringstream result;
    result << std::put_time(&utc, "%Y-%m-%dT%H:%M:%SZ");
    return result.str();
}

void selectNextAction(Snapshot& snapshot) {
    if (snapshot.mode == "remote-required") {
        snapshot.nextAction = "Conectar con Daemon en el Mac para observar repositorios y ejecutar acciones autorizadas.";
    } else if (snapshot.repositories.empty()) {
        snapshot.nextAction = "Seleccionar explícitamente un repositorio local.";
    } else if (std::any_of(snapshot.repositories.begin(), snapshot.repositories.end(), [](const auto& repository) {
                   return repository.status != ObservationStatus::verified;
               })) {
        snapshot.nextAction = "Revisar el repositorio no disponible antes de sincronizar.";
    } else if (std::any_of(snapshot.repositories.begin(), snapshot.repositories.end(), [](const auto& repository) {
                   return repository.dirty.value_or(false);
               })) {
        snapshot.nextAction = "Revisar los cambios locales antes de sincronizar.";
    } else {
        snapshot.nextAction = "Repositorios observados. Servicios y agentes requieren evidencia explícita.";
    }
}

std::string snapshotJson(const Snapshot& snapshot) {
    std::ostringstream out;
    out << "{\"schemaVersion\":1,\"timestamp\":" << jsonQuoted(snapshot.timestamp)
        << ",\"mode\":" << jsonQuoted(snapshot.mode) << ",\"repositories\":";
    array(out, snapshot.repositories, [&](const auto& repository) {
        out << "{\"name\":" << jsonQuoted(redact(repository.name)) << ",\"path\":" << jsonQuoted(redact(repository.path))
            << ",\"branch\":" << textValue(repository.branch) << ",\"head\":" << textValue(repository.head)
            << ",\"upstream\":" << textValue(repository.upstream) << ",\"dirty\":" << boolValue(repository.dirty)
            << ",\"ahead\":" << numberValue(repository.ahead) << ",\"behind\":" << numberValue(repository.behind)
            << ",\"status\":" << jsonQuoted(statusName(repository.status)) << ",\"error\":" << textValue(repository.error) << '}';
    });
    out << ",\"services\":";
    array(out, snapshot.services, [&](const auto& service) {
        out << "{\"name\":" << jsonQuoted(redact(service.name)) << ",\"status\":" << jsonQuoted(statusName(service.status))
            << ",\"healthy\":" << boolValue(service.healthy) << ",\"observedAt\":" << jsonQuoted(service.observedAt) << '}';
    });
    out << ",\"agents\":";
    array(out, snapshot.agents, [&](const auto& agent) {
        out << "{\"name\":" << jsonQuoted(redact(agent.name)) << ",\"status\":" << jsonQuoted(statusName(agent.status))
            << ",\"activity\":" << textValue(agent.activity) << ",\"observedAt\":" << jsonQuoted(agent.observedAt) << '}';
    });
    out << ",\"events\":";
    array(out, snapshot.events, [&](const auto& rawEvent) {
        const auto event = sanitizedEvent(rawEvent);
        out << "{\"timestamp\":" << jsonQuoted(event.timestamp) << ",\"actor\":" << jsonQuoted(event.actor)
            << ",\"machine\":" << jsonQuoted(event.machine) << ",\"repository\":" << jsonQuoted(event.repository)
            << ",\"branch\":" << jsonQuoted(event.branch) << ",\"commit\":" << jsonQuoted(event.commit)
            << ",\"operation\":" << jsonQuoted(event.operation) << ",\"result\":" << jsonQuoted(event.result)
            << ",\"durationMs\":" << event.durationMs << '}';
    });
    out << ",\"nextAction\":" << jsonQuoted(redact(snapshot.nextAction)) << '}';
    return out.str();
}

}  // namespace daemonx

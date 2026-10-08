#include "daemon/trace.hpp"

#include <regex>

namespace daemonx {

std::string redact(std::string_view value) {
    std::string result(value);
    static const std::regex privateKey("-----BEGIN [A-Z ]*PRIVATE KEY-----[\\s\\S]*?-----END [A-Z ]*PRIVATE KEY-----");
    static const std::regex database("postgres(?:ql)?://[^\\s\"'<>]+", std::regex::icase);
    static const std::regex bearer("\\bBearer\\s+[^\\s\"'<>]+", std::regex::icase);
    static const std::regex assignment("\\b([A-Z0-9_-]*(?:DATABASE_URL|DIRECT_URL|PASSWORD|PASSWD|TOKEN|SECRET|API[_-]?KEY|PRIVATE[_-]?KEY|AUTHORIZATION)[A-Z0-9_-]*)\\b[\"']?\\s*[:=]\\s*(\"[^\"]*\"|'[^']*'|[^\\s]+)", std::regex::icase);
    result = std::regex_replace(result, privateKey, "[REDACTED PRIVATE KEY]");
    result = std::regex_replace(result, database, "[REDACTED DATABASE URL]");
    result = std::regex_replace(result, bearer, "Bearer [REDACTED]");
    result = std::regex_replace(result, assignment, "$1=[REDACTED]");
    return result;
}

TraceEvent sanitizedEvent(TraceEvent event) {
    event.timestamp = redact(event.timestamp);
    event.actor = redact(event.actor);
    event.machine = redact(event.machine);
    event.repository = redact(event.repository);
    event.branch = redact(event.branch);
    event.commit = redact(event.commit);
    event.operation = redact(event.operation);
    event.result = redact(event.result);
    return event;
}

}  // namespace daemonx

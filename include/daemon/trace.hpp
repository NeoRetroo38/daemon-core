#pragma once

#include "model.hpp"

#include <string>
#include <string_view>

namespace daemonx {

// Trace fields accept operational metadata, never process output or credentials.
std::string redact(std::string_view value);
TraceEvent sanitizedEvent(TraceEvent event);

}  // namespace daemonx

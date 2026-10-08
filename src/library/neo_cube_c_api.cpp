#include "../../include/scenarys/neo_cube.h"

#include <new>

#include "../core/cube.hpp"

struct scenarys_neo_cube_run {
    scenarys::Run value;

    scenarys_neo_cube_run() {
        value.start();
    }
};

namespace {

constexpr const char* libraryVersion = "0.1.0";

void fillState(const scenarys::Run& run, scenarys_neo_cube_state& state) {
    state.completed = run.finished ? 1u : 0u;
    state.next_phase = run.finished ? 0u : static_cast<uint32_t>(run.currentPhase + 1u);
    state.measurement_count = run.selectionCount();
}

} // namespace

extern "C" {

uint32_t scenarys_neo_cube_abi_version(void) {
    return SCENARYS_NEO_CUBE_ABI_VERSION;
}

const char* scenarys_neo_cube_version(void) {
    return libraryVersion;
}

scenarys_neo_cube_run* scenarys_neo_cube_run_create(void) {
    return new (std::nothrow) scenarys_neo_cube_run();
}

void scenarys_neo_cube_run_destroy(scenarys_neo_cube_run* run) {
    delete run;
}

scenarys_neo_cube_result scenarys_neo_cube_run_reset(scenarys_neo_cube_run* run) {
    if (run == nullptr) return SCENARYS_NEO_CUBE_INVALID_ARGUMENT;
    run->value = scenarys::Run{};
    run->value.start();
    return SCENARYS_NEO_CUBE_OK;
}

scenarys_neo_cube_result scenarys_neo_cube_run_state(
    const scenarys_neo_cube_run* run,
    scenarys_neo_cube_state* state
) {
    if (run == nullptr || state == nullptr) return SCENARYS_NEO_CUBE_INVALID_ARGUMENT;
    fillState(run->value, *state);
    return SCENARYS_NEO_CUBE_OK;
}

scenarys_neo_cube_result scenarys_neo_cube_run_select(
    scenarys_neo_cube_run* run,
    uint32_t row,
    uint32_t column,
    scenarys_neo_cube_state* state
) {
    if (run == nullptr || state == nullptr || row == 0u || column == 0u) {
        return SCENARYS_NEO_CUBE_INVALID_ARGUMENT;
    }
    if (run->value.finished) return SCENARYS_NEO_CUBE_INVALID_STATE;
    if (!run->value.select(row - 1u, column - 1u)) {
        return SCENARYS_NEO_CUBE_INVALID_ARGUMENT;
    }
    fillState(run->value, *state);
    return SCENARYS_NEO_CUBE_OK;
}

scenarys_neo_cube_result scenarys_neo_cube_run_measurements(
    const scenarys_neo_cube_run* run,
    scenarys_neo_cube_measurement* output,
    size_t capacity,
    size_t* written
) {
    if (run == nullptr || written == nullptr) return SCENARYS_NEO_CUBE_INVALID_ARGUMENT;
    const auto measurements = run->value.measurements();
    *written = measurements.size();
    if (measurements.empty()) return SCENARYS_NEO_CUBE_OK;
    if (output == nullptr || capacity < measurements.size()) {
        return SCENARYS_NEO_CUBE_BUFFER_TOO_SMALL;
    }
    for (size_t index = 0; index < measurements.size(); ++index) {
        output[index] = {
            static_cast<uint32_t>(measurements[index].phase),
            static_cast<uint32_t>(measurements[index].row),
            static_cast<uint32_t>(measurements[index].column)
        };
    }
    return SCENARYS_NEO_CUBE_OK;
}

} // extern "C"

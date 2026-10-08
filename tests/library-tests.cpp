#include "../include/scenarys/neo_cube.h"

#include <array>
#include <cassert>
#include <cstring>

int main() {
    assert(scenarys_neo_cube_abi_version() == SCENARYS_NEO_CUBE_ABI_VERSION);
    assert(std::strcmp(scenarys_neo_cube_version(), "0.1.0") == 0);

    auto* run = scenarys_neo_cube_run_create();
    assert(run != nullptr);

    scenarys_neo_cube_state state{};
    assert(scenarys_neo_cube_run_state(run, &state) == SCENARYS_NEO_CUBE_OK);
    assert(state.next_phase == 1u && state.completed == 0u && state.measurement_count == 0u);

    assert(scenarys_neo_cube_run_select(run, 1u, 3u, &state) == SCENARYS_NEO_CUBE_OK);
    assert(state.next_phase == 2u && state.measurement_count == 1u);
    assert(scenarys_neo_cube_run_select(run, 2u, 2u, &state) == SCENARYS_NEO_CUBE_OK);
    assert(scenarys_neo_cube_run_select(run, 3u, 1u, &state) == SCENARYS_NEO_CUBE_OK);
    assert(state.next_phase == 0u && state.completed == 1u && state.measurement_count == 3u);

    size_t required = 0;
    assert(scenarys_neo_cube_run_measurements(run, nullptr, 0u, &required) == SCENARYS_NEO_CUBE_BUFFER_TOO_SMALL);
    assert(required == 3u);

    std::array<scenarys_neo_cube_measurement, 3> measurements{};
    assert(scenarys_neo_cube_run_measurements(run, measurements.data(), measurements.size(), &required) == SCENARYS_NEO_CUBE_OK);
    assert(measurements[0].phase == 1u && measurements[0].row == 1u && measurements[0].column == 3u);
    assert(measurements[2].phase == 3u && measurements[2].row == 3u && measurements[2].column == 1u);

    assert(scenarys_neo_cube_run_select(run, 1u, 1u, &state) == SCENARYS_NEO_CUBE_INVALID_STATE);
    assert(scenarys_neo_cube_run_reset(run) == SCENARYS_NEO_CUBE_OK);
    assert(scenarys_neo_cube_run_state(run, &state) == SCENARYS_NEO_CUBE_OK);
    assert(state.next_phase == 1u && state.completed == 0u && state.measurement_count == 0u);

    scenarys_neo_cube_run_destroy(run);
    return 0;
}

#ifndef SCENARYS_NEO_CUBE_H
#define SCENARYS_NEO_CUBE_H

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32) && defined(SCENARYS_NEO_CUBE_BUILD)
#define SCENARYS_NEO_CUBE_API __declspec(dllexport)
#elif defined(_WIN32)
#define SCENARYS_NEO_CUBE_API __declspec(dllimport)
#else
#define SCENARYS_NEO_CUBE_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

#define SCENARYS_NEO_CUBE_ABI_VERSION 1u

typedef struct scenarys_neo_cube_run scenarys_neo_cube_run;

typedef enum scenarys_neo_cube_result {
    SCENARYS_NEO_CUBE_OK = 0,
    SCENARYS_NEO_CUBE_INVALID_ARGUMENT = 1,
    SCENARYS_NEO_CUBE_INVALID_STATE = 2,
    SCENARYS_NEO_CUBE_BUFFER_TOO_SMALL = 3
} scenarys_neo_cube_result;

typedef struct scenarys_neo_cube_state {
    uint32_t next_phase;
    uint32_t completed;
    size_t measurement_count;
} scenarys_neo_cube_state;

typedef struct scenarys_neo_cube_measurement {
    uint32_t phase;
    uint32_t row;
    uint32_t column;
} scenarys_neo_cube_measurement;

SCENARYS_NEO_CUBE_API uint32_t scenarys_neo_cube_abi_version(void);
SCENARYS_NEO_CUBE_API const char* scenarys_neo_cube_version(void);

SCENARYS_NEO_CUBE_API scenarys_neo_cube_run* scenarys_neo_cube_run_create(void);
SCENARYS_NEO_CUBE_API void scenarys_neo_cube_run_destroy(scenarys_neo_cube_run* run);
SCENARYS_NEO_CUBE_API scenarys_neo_cube_result scenarys_neo_cube_run_reset(
    scenarys_neo_cube_run* run
);

SCENARYS_NEO_CUBE_API scenarys_neo_cube_result scenarys_neo_cube_run_state(
    const scenarys_neo_cube_run* run,
    scenarys_neo_cube_state* state
);

SCENARYS_NEO_CUBE_API scenarys_neo_cube_result scenarys_neo_cube_run_select(
    scenarys_neo_cube_run* run,
    uint32_t row,
    uint32_t column,
    scenarys_neo_cube_state* state
);

SCENARYS_NEO_CUBE_API scenarys_neo_cube_result scenarys_neo_cube_run_measurements(
    const scenarys_neo_cube_run* run,
    scenarys_neo_cube_measurement* output,
    size_t capacity,
    size_t* written
);

#ifdef __cplusplus
}
#endif

#endif

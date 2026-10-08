#pragma once

#if defined(__APPLE__)
#include <TargetConditionals.h>
#endif

#if defined(DAEMON_PLATFORM_IOS) || (defined(__APPLE__) && TARGET_OS_IPHONE)
#define DAEMON_HAS_LOCAL_PROCESSES 0
#elif defined(__unix__) || defined(__APPLE__)
#define DAEMON_HAS_LOCAL_PROCESSES 1
#else
#define DAEMON_HAS_LOCAL_PROCESSES 0
#endif

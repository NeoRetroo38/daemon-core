#include "process.hpp"
#include "platform.hpp"

#include <algorithm>
#include <cstdint>

#if DAEMON_HAS_LOCAL_PROCESSES
#include <cerrno>
#include <csignal>
#include <fcntl.h>
#include <poll.h>
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>
extern char** environ;
#endif

namespace daemonx::detail {

ProcessResult runProcess(const std::string& executable, const std::vector<std::string>& arguments,
                         std::chrono::milliseconds timeout, std::size_t maxOutputBytes,
                         std::stop_token cancellation) {
    ProcessResult result;
    const auto start = std::chrono::steady_clock::now();
    if (cancellation.stop_requested()) { result.cancelled = true; return result; }
#if !DAEMON_HAS_LOCAL_PROCESSES
    (void)executable; (void)arguments; (void)timeout; (void)maxOutputBytes; (void)start;
    result.unavailable = true;
    return result;
#else
    int outputPipe[2]{-1, -1};
    int errorPipe[2]{-1, -1};
    const auto closePipes = [&] {
        for (const int fd : {outputPipe[0], outputPipe[1], errorPipe[0], errorPipe[1]}) if (fd >= 0) close(fd);
    };
    if (pipe(outputPipe) != 0 || pipe(errorPipe) != 0) {
        closePipes(); result.unavailable = true; return result;
    }
    for (const int fd : {outputPipe[0], outputPipe[1], errorPipe[0], errorPipe[1]}) fcntl(fd, F_SETFD, FD_CLOEXEC);
    fcntl(outputPipe[0], F_SETFL, O_NONBLOCK);
    fcntl(errorPipe[0], F_SETFL, O_NONBLOCK);
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0);
    posix_spawn_file_actions_adddup2(&actions, outputPipe[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, errorPipe[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&actions, outputPipe[0]);
    posix_spawn_file_actions_addclose(&actions, errorPipe[0]);
    posix_spawn_file_actions_addclose(&actions, outputPipe[1]);
    posix_spawn_file_actions_addclose(&actions, errorPipe[1]);
    posix_spawnattr_t attributes;
    posix_spawnattr_init(&attributes);
    posix_spawnattr_setflags(&attributes, POSIX_SPAWN_SETPGROUP);
    posix_spawnattr_setpgroup(&attributes, 0);
    std::vector<std::string> argumentStorage{executable};
    argumentStorage.insert(argumentStorage.end(), arguments.begin(), arguments.end());
    std::vector<char*> argv;
    for (auto& argument : argumentStorage) argv.push_back(argument.data());
    argv.push_back(nullptr);
    std::vector<std::string> environmentStorage;
    for (char** value = environ; value && *value; ++value) {
        // Child tools receive only operational locale/path values. Never pass
        // database URLs, tokens, credentials or inherited Git overrides.
        const std::string_view entry(*value);
        const auto separator = entry.find('=');
        const auto key = entry.substr(0, separator);
        if (key == "PATH" || key == "TMPDIR" || key == "LANG" || key == "LC_ALL")
            environmentStorage.emplace_back(*value);
    }
    for (const char* value : {"GIT_OPTIONAL_LOCKS=0", "GIT_TERMINAL_PROMPT=0", "GIT_CONFIG_NOSYSTEM=1", "GIT_CONFIG_GLOBAL=/dev/null"})
        environmentStorage.emplace_back(value);
    std::vector<char*> environment;
    for (auto& value : environmentStorage) environment.push_back(value.data());
    environment.push_back(nullptr);
    pid_t pid{};
    const int spawned = posix_spawnp(&pid, executable.c_str(), &actions, &attributes, argv.data(), environment.data());
    posix_spawn_file_actions_destroy(&actions);
    posix_spawnattr_destroy(&attributes);
    close(outputPipe[1]); outputPipe[1] = -1;
    close(errorPipe[1]); errorPipe[1] = -1;
    if (spawned != 0) { closePipes(); result.unavailable = true; return result; }
    bool reaped = false;
    bool terminating = false;
    int childStatus{};
    auto terminationAt = start;
    const auto drain = [&](int& fd, std::string& destination) {
        if (fd < 0) return;
        char buffer[4096];
        for (;;) {
            const auto count = read(fd, buffer, sizeof(buffer));
            if (count > 0) {
                const auto used = result.standardOutput.size() + result.standardError.size();
                const auto room = used < maxOutputBytes ? maxOutputBytes - used : 0;
                const auto accepted = std::min<std::size_t>(static_cast<std::size_t>(count), room);
                destination.append(buffer, accepted);
                if (accepted != static_cast<std::size_t>(count)) { result.outputLimitExceeded = true; break; }
            } else if (count == 0) {
                close(fd); fd = -1; break;
            } else if (errno == EINTR) {
                continue;
            } else {
                if (errno != EAGAIN && errno != EWOULDBLOCK) { close(fd); fd = -1; }
                break;
            }
        }
    };
    while (!reaped || outputPipe[0] >= 0 || errorPipe[0] >= 0) {
        drain(outputPipe[0], result.standardOutput);
        drain(errorPipe[0], result.standardError);
        if (!reaped) {
            const auto waited = waitpid(pid, &childStatus, WNOHANG);
            if (waited == pid || (waited < 0 && errno == ECHILD)) reaped = true;
        }
        const auto now = std::chrono::steady_clock::now();
        if (!reaped && !terminating) {
            result.cancelled = cancellation.stop_requested();
            result.timedOut = now - start >= timeout;
            if (result.cancelled || result.timedOut || result.outputLimitExceeded) {
                kill(-pid, SIGTERM); terminating = true; terminationAt = now;
            }
        }
        if (terminating && now - terminationAt >= std::chrono::milliseconds(150)) {
            kill(-pid, SIGKILL);
            if (!reaped) {
                while (waitpid(pid, &childStatus, 0) < 0 && errno == EINTR) {}
                reaped = true;
            }
            drain(outputPipe[0], result.standardOutput);
            drain(errorPipe[0], result.standardError);
            break;
        }
        // A child may have finished while descendants keep its pipe open. The
        // same deadline applies; never wait forever for those descriptors.
        if (reaped && (outputPipe[0] >= 0 || errorPipe[0] >= 0) && now - start >= timeout) {
            result.timedOut = true; kill(-pid, SIGKILL); break;
        }
        if (reaped && outputPipe[0] < 0 && errorPipe[0] < 0) break;
        pollfd descriptors[2]{{outputPipe[0], POLLIN, 0}, {errorPipe[0], POLLIN, 0}};
        poll(descriptors, 2, 20);
    }
    closePipes();
    if (!reaped) {
        kill(-pid, SIGKILL);
        while (waitpid(pid, &childStatus, 0) < 0 && errno == EINTR) {}
    }
    if (WIFEXITED(childStatus)) result.exitCode = WEXITSTATUS(childStatus);
    else if (WIFSIGNALED(childStatus)) result.exitCode = 128 + WTERMSIG(childStatus);
    result.durationMs = static_cast<std::uint64_t>(std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - start).count());
    return result;
#endif
}

}  // namespace daemonx::detail

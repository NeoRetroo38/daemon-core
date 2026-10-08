#include "daemon/daemon_bridge.h"
#include "daemon/git_adapter.hpp"

#include <algorithm>
#include <iostream>
#include <string>
#include <vector>

int main(int argc, char** argv) {
    if (argc == 2 && std::string(argv[1]) == "--version") {
        std::cout << "daemon " << daemon_core_version() << '\n';
        return 0;
    }
    const auto usage = [] {
        std::cerr << "Usage: daemon snapshot --repo /explicit/path [--repo /other/path] [--json]\n";
    };
    if (argc < 2 || std::string(argv[1]) != "snapshot") {
        usage();
        return argc == 2 && std::string(argv[1]) == "--help" ? 0 : 2;
    }
    std::vector<std::string> paths;
    for (int index = 2; index < argc; ++index) {
        const std::string argument(argv[index]);
        if (argument == "--json") continue;
        if (argument != "--repo" || index + 1 == argc || std::string(argv[index + 1]).empty()) {
            usage(); return 2;
        }
        paths.emplace_back(argv[++index]);
    }
    if (paths.empty()) { usage(); return 2; }
    const auto snapshot = daemonx::observeRepositories(paths);
    std::cout << daemonx::snapshotJson(snapshot) << '\n';
    return std::all_of(snapshot.repositories.begin(), snapshot.repositories.end(), [](const auto& repository) {
        return repository.status == daemonx::ObservationStatus::verified;
    }) ? 0 : 1;
}

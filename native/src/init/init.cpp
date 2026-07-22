#include <sys/stat.h>
#include <sys/types.h>

#include <base.hpp>

#include "init.hpp"

using namespace std;

// Kyubi installs in system mode only and never patches a boot image, so
// magiskinit never runs as PID 1. The single entry point Kyubi uses is the
// sepolicy patcher invoked by the installer (manager.sh: magiskinit --patch-sepol).
int main(int argc, char *argv[]) {
    umask(0);

    if (argc > 2 && argv[1] == "--patch-sepol"sv) {
        return patch_sepol(argv[2], (argc > 3) ? argv[3] : argv[2]);
    }

    return 1;
}

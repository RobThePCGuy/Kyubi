#include <memory>

#include <sepolicy.hpp>

#include "init.hpp"

using namespace std;

int patch_sepol(const char *in, const char *out) {
    auto sepol = unique_ptr<sepolicy>(sepolicy::from_file(in));
    if (!sepol) return 1;
    sepol->magisk_rules();
    if (!sepol->to_file(out)) return 2;
    return 0;
}

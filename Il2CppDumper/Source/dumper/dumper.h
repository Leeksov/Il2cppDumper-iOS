#pragma once
#include "../il2cpp/api.h"
#include "../il2cpp/tabledefs.h"
#include "../utils/file.h"
#include "../utils/json.h"
#include <functional>

namespace Dumper {
    enum Status : int8_t { NONE = -1, OK = 0, ERR = 1, ERR_FRAMEWORK = 2, ERR_SYMBOLS = 3 };
    extern Status status;
    extern std::string dumpDir;

    // Feature toggles (set from prefs before dump()):
    extern bool genScript;
    extern bool genHeader;
    extern bool genDll;

    // Progress callback — called from background thread during dump.
    // (status message, progress 0..1, #assemblies, #classes, #methods)
    using ProgressFn = std::function<void(const char*, float, int64_t, int64_t, int64_t)>;
    extern ProgressFn onProgress;

    Status dump(const std::string& dir, const std::string& headersDir);
    void Log(const char* fmt, ...);
}

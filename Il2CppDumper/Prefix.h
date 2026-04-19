//
//  Prefix.h — single unified include
//

#pragma once

// C standard
#include <cstdint>
#include <cstdio>
#include <cstddef>
#include <cstring>
#include <cstdarg>
#include <cctype>

// C++ standard
#include <string>
#include <vector>
#include <set>
#include <map>
#include <unordered_map>
#include <algorithm>
#include <functional>
#include <sstream>
#include <fstream>
#include <filesystem>

// Darwin / iOS
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <os/log.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach/mach.h>
#import <mach/mach_init.h>
#import <mach/vm_map.h>

// Macros
#define FORCEINLINE inline __attribute__((always_inline))
#define ENTRY_POINT __attribute__((constructor(101)))
#define CallAfterSeconds(sec) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, sec * NSEC_PER_SEC), dispatch_get_main_queue(), ^

// Project config
#include "UI/Config.h"

// Logging
#include "Utilities/Logger.hpp"

// fmt
#include "Utilities/fmt/format.h"

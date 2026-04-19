#pragma once
#import <os/log.h>
#import <Foundation/Foundation.h>

#define ASURA_SUBSYSTEM "com.asura.resolver"

inline os_log_t GetLogger(const char* category) {
    return os_log_create(ASURA_SUBSYSTEM, category);
}

// Logging Macros
#define LOG_TYPE(category, type, fmt, ...) \
    do { \
        \
        os_log_with_type(GetLogger(category), type, fmt, ##__VA_ARGS__); \
        \
    } while(0)

// Default/Info
#define LOG_INFO(fmt, ...) LOG_TYPE("General", OS_LOG_TYPE_DEFAULT, fmt, ##__VA_ARGS__)

// Debug
#define LOG_DEBUG(fmt, ...) LOG_TYPE("Debug", OS_LOG_TYPE_DEBUG, fmt, ##__VA_ARGS__)
#define LOG_ERROR(fmt, ...) os_log_with_type(GetLogger("Error"), OS_LOG_TYPE_ERROR, fmt, ##__VA_ARGS__)
#define LOG_FAULT(fmt, ...) os_log_with_type(GetLogger("Fault"), OS_LOG_TYPE_FAULT, fmt, ##__VA_ARGS__)

// Specific Category Log
#define LOG_CAT(category, fmt, ...) LOG_TYPE(category, OS_LOG_TYPE_DEFAULT, fmt, ##__VA_ARGS__)

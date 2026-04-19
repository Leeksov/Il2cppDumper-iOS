//
//  api.cpp — IL2CPP runtime binding via dlsym
//

#include "api.h"

namespace IL2CPP {
    MemoryInfo info = {};

    void*  (*domain_get)() = nullptr;
    void** (*domain_get_assemblies)(const void*, size_t*) = nullptr;

    const void* (*assembly_get_image)(const void*) = nullptr;

    const char* (*image_get_name)(const void*) = nullptr;
    size_t      (*image_get_class_count)(const void*) = nullptr;
    void*       (*image_get_class)(const void*, size_t) = nullptr;

    const char* (*class_get_name)(void*) = nullptr;
    const char* (*class_get_namespace)(void*) = nullptr;
    int32_t     (*class_get_flags)(void*) = nullptr;
    void*       (*class_get_methods)(void*, void**) = nullptr;
    void*       (*class_get_fields)(void*, void**) = nullptr;
    void*       (*class_get_properties)(void*, void**) = nullptr;
    void*       (*class_from_type)(void*) = nullptr;
    bool        (*class_is_enum)(void*) = nullptr;
    bool        (*class_is_valuetype)(void*) = nullptr;

    const char* (*method_get_name)(void*) = nullptr;
    void*       (*method_get_param)(void*, uint32_t) = nullptr;
    const char* (*method_get_param_name)(void*, uint32_t) = nullptr;
    int32_t     (*method_get_param_count)(void*) = nullptr;
    void*       (*method_get_return_type)(void*) = nullptr;
    uint32_t    (*method_get_flags)(void*, uint32_t*) = nullptr;

    const char* (*property_get_name)(void*) = nullptr;
    void*       (*property_get_get_method)(void*) = nullptr;
    void*       (*property_get_set_method)(void*) = nullptr;

    const char* (*field_get_name)(void*) = nullptr;
    void*       (*field_get_type)(void*) = nullptr;
    int32_t     (*field_get_flags)(void*) = nullptr;
    size_t      (*field_get_offset)(void*) = nullptr;
    void        (*field_static_get_value)(void*, void*) = nullptr;

    uint16_t*   (*string_chars)(void*) = nullptr;

    char*       (*type_get_name)(void*) = nullptr;
    bool        (*type_is_byref)(void*) = nullptr;
    uint32_t    (*type_get_attrs)(void*) = nullptr;
}

static MemoryInfo findBase(const char* binaryName) {
    MemoryInfo mi = {};
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char* name = _dyld_get_image_name(i);
        if (!name) continue;
        if (strstr(name, binaryName)) {
            mi.index = i;
            mi.header = (const mach_header_64*)_dyld_get_image_header(i);
            mi.name = name;
            mi.address = _dyld_get_image_vmaddr_slide(i);
            break;
        }
    }
    return mi;
}

bool IL2CPP::attach(const char* binaryPath) {
    // Use RTLD_NOLOAD — don't re-initialize, just get handle to already-loaded binary
    void* handle = dlopen(binaryPath, RTLD_NOLOAD);
    if (!handle) {
        // Fallback: try loading if not yet loaded
        handle = dlopen(binaryPath, RTLD_LAZY);
    }
    if (!handle) return false;

    info = findBase(BINARY_NAME);

    #define BIND(name) \
        *(void**)&IL2CPP::name = dlsym(handle, "il2cpp_" #name); \
        if (!IL2CPP::name) { NSLog(@"[IL2CPP] missing: il2cpp_%s", #name); }

    #define BIND_REQUIRED(name) \
        *(void**)&IL2CPP::name = dlsym(handle, "il2cpp_" #name); \
        if (!IL2CPP::name) { NSLog(@"[IL2CPP] CRITICAL missing: il2cpp_%s", #name); return false; }

    BIND_REQUIRED(domain_get);
    BIND_REQUIRED(domain_get_assemblies);
    BIND_REQUIRED(assembly_get_image);
    BIND_REQUIRED(image_get_name);
    BIND_REQUIRED(image_get_class_count);
    BIND_REQUIRED(image_get_class);
    BIND_REQUIRED(class_get_name);
    BIND_REQUIRED(class_from_type);
    BIND_REQUIRED(type_get_name);

    BIND(class_get_namespace);
    BIND(class_get_flags);
    BIND(class_get_methods);
    BIND(class_get_fields);
    BIND(class_get_properties);
    BIND(class_is_enum);
    BIND(class_is_valuetype);

    BIND(method_get_name);
    BIND(method_get_param);
    BIND(method_get_param_name);
    BIND(method_get_param_count);
    BIND(method_get_return_type);
    BIND(method_get_flags);

    BIND(property_get_name);
    BIND(property_get_get_method);
    BIND(property_get_set_method);

    BIND(field_get_name);
    BIND(field_get_type);
    BIND(field_get_flags);
    BIND(field_get_offset);
    BIND(field_static_get_value);

    BIND(string_chars);
    BIND(type_is_byref);
    BIND(type_get_attrs);

    #undef BIND
    #undef BIND_REQUIRED
    return true;
}

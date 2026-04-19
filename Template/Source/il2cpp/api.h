//
//  api.h — IL2CPP runtime API (void* based, version-independent)
//

#pragma once
#include "../../Prefix.h"

struct MemoryInfo {
    uint32_t index;
    const mach_header_64* header;
    const char* name;
    intptr_t address;
};

namespace IL2CPP {
    extern MemoryInfo info;

    // domain
    extern void*  (*domain_get)();
    extern void** (*domain_get_assemblies)(const void* domain, size_t* size);

    // assembly
    extern const void* (*assembly_get_image)(const void* assembly);

    // image
    extern const char* (*image_get_name)(const void* image);
    extern size_t      (*image_get_class_count)(const void* image);
    extern void*       (*image_get_class)(const void* image, size_t index);

    // class
    extern const char* (*class_get_name)(void* klass);
    extern const char* (*class_get_namespace)(void* klass);
    extern int32_t     (*class_get_flags)(void* klass);
    extern void*       (*class_get_methods)(void* klass, void** iter);
    extern void*       (*class_get_fields)(void* klass, void** iter);
    extern void*       (*class_get_properties)(void* klass, void** iter);
    extern void*       (*class_from_type)(void* type);
    extern bool        (*class_is_enum)(void* klass);
    extern bool        (*class_is_valuetype)(void* klass);

    // method
    extern const char* (*method_get_name)(void* method);
    extern void*       (*method_get_param)(void* method, uint32_t index);
    extern const char* (*method_get_param_name)(void* method, uint32_t index);
    extern int32_t     (*method_get_param_count)(void* method);
    extern void*       (*method_get_return_type)(void* method);
    extern uint32_t    (*method_get_flags)(void* method, uint32_t* iflags);

    // property
    extern const char* (*property_get_name)(void* prop);
    extern void*       (*property_get_get_method)(void* prop);
    extern void*       (*property_get_set_method)(void* prop);

    // field
    extern const char* (*field_get_name)(void* field);
    extern void*       (*field_get_type)(void* field);
    extern int32_t     (*field_get_flags)(void* field);
    extern size_t      (*field_get_offset)(void* field);
    extern void        (*field_static_get_value)(void* field, void* value);

    // string
    extern uint16_t*   (*string_chars)(void* str);

    // type
    extern char*       (*type_get_name)(void* type);
    extern bool        (*type_is_byref)(void* type);
    extern uint32_t    (*type_get_attrs)(void* type);

    // init
    bool attach(const char* binaryPath);
}

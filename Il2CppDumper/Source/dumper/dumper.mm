//
//  dumper.mm — core dump logic (dump.cs, script.json, il2cpp.h, DummyDll)
//
//  Crash-safe: every class/field/method is wrapped in @try/@catch.
//  Continues on error instead of aborting.
//

#include "dumper.h"
#include "dummy_dll.h"
#include <objc/objc.h>

namespace Dumper {
    Status status = Status::NONE;
    std::string dumpDir;
    bool genScript = true;
    bool genHeader = true;
    bool genDll    = true;
    ProgressFn onProgress = nullptr;
}

static inline void reportProgress(const char* msg, float p, int64_t a, int64_t c, int64_t m) {
    if (Dumper::onProgress) Dumper::onProgress(msg, p, a, c, m);
}

void Dumper::Log(const char* fmt, ...) {
    File logfile(dumpDir + "/logs.txt", "a");
    if (!logfile.ok()) return;
    va_list args; va_start(args, fmt);
    vfprintf(logfile, fmt, args); fprintf(logfile, "\n");
    va_end(args); logfile.close();
}

// ── Safe pointer check ──

static bool isBadPtr(const void* ptr) {
    if (!ptr || (uintptr_t)ptr < 0x1000) return true;
    vm_size_t sz = 0;
    uint8_t buf;
    return vm_read_overwrite(mach_task_self(), (vm_address_t)ptr, 1, (vm_address_t)&buf, &sz) != KERN_SUCCESS;
}

// ── Type name helpers (local resolution first, API fallback) ──

static std::string normalizeType(const std::string& t) {
    static const std::unordered_map<std::string, std::string> m = {
        {"Void","void"},{"Boolean","bool"},{"Byte","byte"},{"SByte","sbyte"},
        {"Int16","short"},{"UInt16","ushort"},{"Int32","int"},{"UInt32","uint"},
        {"Int64","long"},{"UInt64","ulong"},{"Single","float"},{"Double","double"},
        {"Char","char"},{"String","string"},{"Object","object"},{"Decimal","decimal"},
    };
    auto it = m.find(t);
    return it != m.end() ? it->second : t;
}

static std::string getClassName(void* klass) {
    if (!klass || isBadPtr(klass)) return "???";
    const char* name = IL2CPP::class_get_name(klass);
    if (!name || isBadPtr(name)) return "???";

    const char* bt = strchr(name, '`');
    if (!bt) return name;
    int n = atoi(bt + 1);
    if (n <= 0) n = 1;
    std::string base(name, bt - name);
    base += "<";
    for (int i = 0; i < n; i++) {
        if (i) base += ", ";
        base += "T" + std::to_string(i);
    }
    return base + ">";
}

static std::string getTypeName(void* type) {
    if (!type || isBadPtr(type)) return "object";

    // Resolve via class first (safe — doesn't dereference type internals)
    if (IL2CPP::class_from_type) {
        @try {
            void* klass = IL2CPP::class_from_type(type);
            if (klass && !isBadPtr(klass)) {
                std::string name = getClassName(klass);
                // For generic instances / arrays, try type_get_name for full name
                if (IL2CPP::type_get_name && (name.find('`') != std::string::npos || name == "???")) {
                    @try {
                        char* tn = IL2CPP::type_get_name(type);
                        if (tn && !isBadPtr(tn) && tn[0] != '\0')
                            return normalizeType(tn);
                    } @catch (...) {}
                }
                return normalizeType(name);
            }
        } @catch (...) {}
    }

    return "object";
}

// ── Modifiers ──

static std::string methodModifier(uint32_t flags) {
    std::string out;
    switch (flags & METHOD_ATTRIBUTE_MEMBER_ACCESS_MASK) {
        case METHOD_ATTRIBUTE_PRIVATE: out += "private "; break;
        case METHOD_ATTRIBUTE_PUBLIC: out += "public "; break;
        case METHOD_ATTRIBUTE_FAMILY: out += "protected "; break;
        case METHOD_ATTRIBUTE_ASSEM: case METHOD_ATTRIBUTE_FAM_AND_ASSEM: out += "internal "; break;
        case METHOD_ATTRIBUTE_FAM_OR_ASSEM: out += "protected internal "; break;
    }
    if (flags & METHOD_ATTRIBUTE_STATIC) out += "static ";
    if (flags & METHOD_ATTRIBUTE_ABSTRACT) {
        out += "abstract ";
        if ((flags & METHOD_ATTRIBUTE_VTABLE_LAYOUT_MASK) == METHOD_ATTRIBUTE_REUSE_SLOT)
            out += "override ";
    } else if (flags & METHOD_ATTRIBUTE_FINAL) {
        if ((flags & METHOD_ATTRIBUTE_VTABLE_LAYOUT_MASK) == METHOD_ATTRIBUTE_REUSE_SLOT)
            out += "sealed override ";
    } else if (flags & METHOD_ATTRIBUTE_VIRTUAL) {
        if ((flags & METHOD_ATTRIBUTE_VTABLE_LAYOUT_MASK) == METHOD_ATTRIBUTE_NEW_SLOT)
            out += "virtual ";
        else
            out += "override ";
    }
    if (flags & METHOD_ATTRIBUTE_PINVOKE_IMPL) out += "extern ";
    return out;
}

// ── Field dumper (crash-safe) ──

static std::string dumpField(void* klass) {
    if (!IL2CPP::class_get_fields) return "";
    std::string out = "\n\t// Fields\n";
    bool isEnum = IL2CPP::class_is_enum ? IL2CPP::class_is_enum(klass) : false;
    void* iter = nullptr;
    int count = 0;

    @try {
        while (auto field = IL2CPP::class_get_fields(klass, &iter)) {
            if (isBadPtr(field)) break;

            auto attrs = IL2CPP::field_get_flags(field);
            const char* fname = IL2CPP::field_get_name(field);
            if (!fname || isBadPtr(fname)) continue;

            out += "\t";
            switch (attrs & FIELD_ATTRIBUTE_FIELD_ACCESS_MASK) {
                case FIELD_ATTRIBUTE_PRIVATE: out += "private "; break;
                case FIELD_ATTRIBUTE_PUBLIC: out += "public "; break;
                case FIELD_ATTRIBUTE_FAMILY: out += "protected "; break;
                case FIELD_ATTRIBUTE_ASSEMBLY: case FIELD_ATTRIBUTE_FAM_AND_ASSEM: out += "internal "; break;
                case FIELD_ATTRIBUTE_FAM_OR_ASSEM: out += "protected internal "; break;
            }

            if (attrs & FIELD_ATTRIBUTE_LITERAL) out += "const ";
            else {
                if (attrs & FIELD_ATTRIBUTE_STATIC) out += "static ";
                if (attrs & FIELD_ATTRIBUTE_INIT_ONLY) out += "readonly ";
            }

            auto fieldType = IL2CPP::field_get_type(field);
            std::string typeName = getTypeName(fieldType);
            out += typeName + " " + fname;

            if (attrs & FIELD_ATTRIBUTE_LITERAL) {
                if (IL2CPP::field_static_get_value) {
                    @try {
                        if (isEnum || typeName != "string") {
                            int64_t val = 0;
                            IL2CPP::field_static_get_value(field, &val);
                            out += fmt::format(" = {};\n", val);
                        } else {
                            void* val = nullptr;
                            IL2CPP::field_static_get_value(field, &val);
                            if (!val || isBadPtr(val)) { out += " = null;\n"; }
                            else {
                                uint16_t* chars = IL2CPP::string_chars ? IL2CPP::string_chars(val) : nullptr;
                                if (chars && !isBadPtr(chars)) {
                                    std::string s;
                                    for (int i = 0; i < 4096 && chars[i]; i++) s += (char)chars[i];
                                    out += " = \"" + s + "\";\n";
                                } else out += " = null;\n";
                            }
                        }
                    } @catch (...) { out += ";\n"; }
                } else out += ";\n";
            } else {
                out += fmt::format("; // 0x{:X}\n", IL2CPP::field_get_offset(field));
            }
            count++;
        }
    } @catch (...) {
        Dumper::Log("  [!] Exception in dumpField");
    }
    return count ? out : "";
}

// ── Property dumper (crash-safe) ──

static std::string dumpProperty(void* klass) {
    if (!IL2CPP::class_get_properties) return "";
    std::string out = "\n\t// Properties\n";
    void* iter = nullptr;
    int count = 0;

    @try {
        while (auto prop = IL2CPP::class_get_properties(klass, &iter)) {
            if (isBadPtr(prop)) break;
            auto get = IL2CPP::property_get_get_method(prop);
            auto set = IL2CPP::property_get_set_method(prop);
            const char* pname = IL2CPP::property_get_name(prop);
            if (!pname || isBadPtr(pname)) continue;

            out += "\t";
            void* propType = nullptr;
            uint32_t iflags = 0;
            if (get && !isBadPtr(get)) {
                out += methodModifier(IL2CPP::method_get_flags(get, &iflags));
                propType = IL2CPP::method_get_return_type(get);
            } else if (set && !isBadPtr(set)) {
                out += methodModifier(IL2CPP::method_get_flags(set, &iflags));
                propType = IL2CPP::method_get_param(set, 0);
            }
            if (propType) {
                out += getTypeName(propType) + " " + pname + " { ";
                if (get) out += "get; ";
                if (set) out += "set; ";
                out += "}\n";
                count++;
            }
        }
    } @catch (...) {
        Dumper::Log("  [!] Exception in dumpProperty");
    }
    return count ? out : "";
}

// ── Method dumper (crash-safe) ──

static std::string dumpMethod(void* klass, Json::JArr& scriptMethods, std::set<uint64_t>& seenAddrs) {
    if (!IL2CPP::class_get_methods) return "";
    std::string out = "\n\t// Methods\n\n";
    void* iter = nullptr;
    int count = 0;
    const char* classNs = IL2CPP::class_get_namespace ? IL2CPP::class_get_namespace(klass) : "";
    std::string className = getClassName(klass);

    @try {
        while (auto method = IL2CPP::class_get_methods(klass, &iter)) {
            if (isBadPtr(method)) break;

            const char* mname = IL2CPP::method_get_name(method);
            if (!mname || isBadPtr(mname)) continue;

            uint32_t iflags = 0;
            auto flags = IL2CPP::method_get_flags(method, &iflags);
            auto methodPtr = *(void**)method; // first field = methodPointer (stable across all versions)

            if (!methodPtr || isBadPtr(methodPtr) || (flags & METHOD_ATTRIBUTE_ABSTRACT))
                out += "\t// RVA: -1";
            else
                out += fmt::format("\t// RVA: 0x{:X}", (uint64_t)methodPtr - IL2CPP::info.address);

            out += "\n\t" + methodModifier(flags);

            auto retType = IL2CPP::method_get_return_type(method);
            if (retType && IL2CPP::type_is_byref && IL2CPP::type_is_byref(retType)) out += "ref ";
            out += getTypeName(retType) + " " + mname + "(";

            int pc = IL2CPP::method_get_param_count(method);
            for (int i = 0; i < pc; i++) {
                if (i) out += ", ";
                auto param = IL2CPP::method_get_param(method, i);
                if (param && IL2CPP::type_is_byref && IL2CPP::type_is_byref(param)) {
                    auto attrs = IL2CPP::type_get_attrs ? IL2CPP::type_get_attrs(param) : 0;
                    if (attrs & PARAM_ATTRIBUTE_OUT && !(attrs & PARAM_ATTRIBUTE_IN)) out += "out ";
                    else if (attrs & PARAM_ATTRIBUTE_IN && !(attrs & PARAM_ATTRIBUTE_OUT)) out += "in ";
                    else out += "ref ";
                }
                out += getTypeName(param);
                const char* pn = IL2CPP::method_get_param_name ? IL2CPP::method_get_param_name(method, i) : nullptr;
                out += std::string(" ") + ((pn && !isBadPtr(pn)) ? pn : fmt::format("p{}", i));
            }
            out += ") { }\n\n";

            // script.json
            if (methodPtr && !isBadPtr(methodPtr) && !(flags & METHOD_ATTRIBUTE_ABSTRACT)) {
                uint64_t rva = (uint64_t)methodPtr - IL2CPP::info.address;
                if (seenAddrs.insert(rva).second) {
                    std::string fullName;
                    if (classNs && classNs[0]) fullName = std::string(classNs) + ".";
                    fullName += className + "$$" + mname;
                    Json::JObj entry;
                    entry.num("Address", rva);
                    entry.str("Name", fullName);
                    scriptMethods.obj(entry);
                }
            }
            count++;
        }
    } @catch (...) {
        Dumper::Log("  [!] Exception in dumpMethod for %s", className.c_str());
    }
    return count ? out : "";
}

// ── il2cpp.h generation (crash-safe) ──

static void generateHeader(const std::string& dir) {
    Dumper::Log("Generating il2cpp.h...");
    File out(dir + "/il2cpp.h", "w");
    if (!out.ok()) return;

    out.write("// il2cpp.h — generated by Il2CppDumper-iOS\n#pragma once\n#include <stdint.h>\n\n");

    void* domain = IL2CPP::domain_get();
    size_t asmCount = 0;
    void** assemblies = IL2CPP::domain_get_assemblies(domain, &asmCount);

    for (size_t a = 0; a < asmCount; a++) {
        auto* image = IL2CPP::assembly_get_image(assemblies[a]);
        size_t classCount = IL2CPP::image_get_class_count(image);

        for (size_t c = 0; c < classCount; c++) {
            @try {
                void* klass = IL2CPP::image_get_class(image, c);
                if (!klass || isBadPtr(klass)) continue;

                const char* ns = IL2CPP::class_get_namespace ? IL2CPP::class_get_namespace(klass) : "";
                const char* name = IL2CPP::class_get_name(klass);
                if (!name || isBadPtr(name)) continue;

                std::string sname;
                if (ns && ns[0]) sname = std::string(ns) + "_";
                sname += name;
                for (char& ch : sname) if (!isalnum(ch) && ch != '_') ch = '_';

                out.write(fmt::format("// {}{}{}\n", ns && ns[0] ? ns : "", ns && ns[0] ? "." : "", name));
                out.write(fmt::format("struct {}_Fields {{\n", sname));

                if (IL2CPP::class_get_fields) {
                    void* fIter = nullptr;
                    while (auto field = IL2CPP::class_get_fields(klass, &fIter)) {
                        if (isBadPtr(field)) break;
                        auto attrs = IL2CPP::field_get_flags(field);
                        if (attrs & FIELD_ATTRIBUTE_STATIC) continue;
                        if (attrs & FIELD_ATTRIBUTE_LITERAL) continue;
                        const char* fn = IL2CPP::field_get_name(field);
                        if (!fn || isBadPtr(fn)) continue;
                        out.write(fmt::format("    void* {}; // 0x{:X}\n", fn, IL2CPP::field_get_offset(field)));
                    }
                }
                out.write("};\n\n");
            } @catch (...) {
                continue;
            }
        }
    }
    Dumper::Log("il2cpp.h written.");
}

// ── Main dump ──

Dumper::Status Dumper::dump(const std::string& dir, const std::string& headersDir) {
    dumpDir = dir;
    Log("BaseAddress: 0x%llx", IL2CPP::info.address);
    Log("Init Dumping...");

    reportProgress("Initializing…", 0.02f, 0, 0, 0);

    void* domain = IL2CPP::domain_get();
    if (!domain) { Log("FATAL: Failed to get domain"); return Status::ERR; }

    size_t asmCount = 0;
    void** assemblies = IL2CPP::domain_get_assemblies(domain, &asmCount);
    if (!assemblies || !asmCount) { Log("FATAL: No assemblies found"); return Status::ERR; }

    File dumpFile(dir + "/dump.cs", "w");
    if (!dumpFile.ok()) return Status::ERR;

    Json::JArr scriptMethods;
    std::set<uint64_t> seenAddrs;
    std::stringstream dumpOut;

    Log("Total Assemblies: %zu", asmCount);
    reportProgress("Collecting assemblies…", 0.05f, (int64_t)asmCount, 0, 0);

    for (size_t i = 0; i < asmCount; i++) {
        auto* image = IL2CPP::assembly_get_image(assemblies[i]);
        const char* imgName = IL2CPP::image_get_name(image);
        dumpOut << "// Image " << i << ": " << (imgName ? imgName : "???") << "\n";
    }

    int totalClasses = 0, errorClasses = 0;
    // 65% of progress is spent on class/method dump; the rest on post-processing.
    const float DUMP_PHASE = 0.65f;

    for (size_t a = 0; a < asmCount; a++) {
        auto* image = IL2CPP::assembly_get_image(assemblies[a]);
        const char* imageName = IL2CPP::image_get_name(image);
        if (!imageName) imageName = "unknown";

        size_t classCount = IL2CPP::image_get_class_count(image);
        std::string asmFileName = headersDir + "/" + imageName + ".cs";
        File asmFile(asmFileName, "w");
        std::stringstream asmOut;

        Log("Assembly %s: %zu classes", imageName, classCount);
        {
            float prog = 0.05f + DUMP_PHASE * ((float)a / (float)asmCount);
            char msg[256];
            snprintf(msg, sizeof(msg), "Dumping %s (%zu classes)", imageName, classCount);
            reportProgress(msg, prog, (int64_t)asmCount, totalClasses, (int64_t)seenAddrs.size());
        }

        for (size_t c = 0; c < classCount; c++) {
            @try {
                void* klass = IL2CPP::image_get_class(image, c);
                if (!klass || isBadPtr(klass)) { errorClasses++; continue; }

                const char* cn = IL2CPP::class_get_name(klass);
                if (!cn || isBadPtr(cn)) { errorClasses++; continue; }

                const char* classNs = IL2CPP::class_get_namespace ? IL2CPP::class_get_namespace(klass) : "";

                if (classNs) {
                    dumpOut << "// Namespace: " << classNs << "\n";
                    asmOut << "// Namespace: " << classNs << "\n";
                }

                auto flags = IL2CPP::class_get_flags ? IL2CPP::class_get_flags(klass) : 0;
                bool isEnum = IL2CPP::class_is_enum ? IL2CPP::class_is_enum(klass) : false;
                bool isVT = IL2CPP::class_is_valuetype ? IL2CPP::class_is_valuetype(klass) : false;

                std::string prefix;
                switch (flags & TYPE_ATTRIBUTE_VISIBILITY_MASK) {
                    case TYPE_ATTRIBUTE_PUBLIC: case TYPE_ATTRIBUTE_NESTED_PUBLIC: prefix = "public "; break;
                    case TYPE_ATTRIBUTE_NOT_PUBLIC: case TYPE_ATTRIBUTE_NESTED_FAM_AND_ASSEM:
                    case TYPE_ATTRIBUTE_NESTED_ASSEMBLY: prefix = "internal "; break;
                    case TYPE_ATTRIBUTE_NESTED_PRIVATE: prefix = "private "; break;
                    case TYPE_ATTRIBUTE_NESTED_FAMILY: prefix = "protected "; break;
                    case TYPE_ATTRIBUTE_NESTED_FAM_OR_ASSEM: prefix = "protected internal "; break;
                }

                if ((flags & TYPE_ATTRIBUTE_ABSTRACT) && (flags & TYPE_ATTRIBUTE_SEALED)) prefix += "static ";
                else if (!(flags & TYPE_ATTRIBUTE_INTERFACE) && (flags & TYPE_ATTRIBUTE_ABSTRACT)) prefix += "abstract ";
                else if (!isVT && !isEnum && (flags & TYPE_ATTRIBUTE_SEALED)) prefix += "sealed ";

                if (flags & TYPE_ATTRIBUTE_INTERFACE) prefix += "interface ";
                else if (isEnum) prefix += "enum ";
                else if (isVT) prefix += "struct ";
                else prefix += "class ";

                std::string className = getClassName(klass);
                std::string decl = prefix + className + "\n{\n";
                dumpOut << decl; asmOut << decl;

                std::string fields = dumpField(klass);
                dumpOut << fields; asmOut << fields;

                std::string props = dumpProperty(klass);
                dumpOut << props; asmOut << props;

                std::string methods = dumpMethod(klass, scriptMethods, seenAddrs);
                dumpOut << methods; asmOut << methods;

                dumpOut << "}\n\n"; asmOut << "}\n\n";
                totalClasses++;

            } @catch (...) {
                errorClasses++;
                Log("  [!] Exception dumping class %zu in %s", c, imageName);
                dumpOut << "// [ERROR] class index " << c << " crashed\n\n";
                asmOut << "// [ERROR] class index " << c << " crashed\n\n";
            }
        }
        asmFile.write(asmOut);
        asmFile.close();
    }

    dumpFile.write(dumpOut);
    dumpFile.close();
    Log("dump.cs written. Classes: %d ok, %d errors.", totalClasses, errorClasses);
    reportProgress("Writing dump.cs", 0.72f, (int64_t)asmCount, totalClasses, (int64_t)seenAddrs.size());

    // script.json
    if (genScript) {
        reportProgress("Generating script.json", 0.78f, (int64_t)asmCount, totalClasses, (int64_t)seenAddrs.size());
        Log("Generating script.json...");
        std::string scriptJson = "{\"ScriptMethod\":" + scriptMethods.dump() + "}\n";
        File scriptFile(dir + "/script.json", "w");
        if (scriptFile.ok()) { scriptFile.write(scriptJson); scriptFile.close(); }
        Log("script.json: %zu methods.", scriptMethods.items.size());
    }

    // il2cpp.h
    if (genHeader) {
        reportProgress("Generating il2cpp.h", 0.85f, (int64_t)asmCount, totalClasses, (int64_t)seenAddrs.size());
        @try { generateHeader(dir); } @catch (...) { Log("[!] il2cpp.h generation failed"); }
    }

    // DummyDll
    if (genDll) {
        reportProgress("Building DummyDll…", 0.90f, (int64_t)asmCount, totalClasses, (int64_t)seenAddrs.size());
        @try {
            Log("Generating DummyDll...");
            DummyDll::Generate(dir);
        } @catch (...) { Log("[!] DummyDll generation failed"); }
    }

    reportProgress("Finalizing…", 0.97f, (int64_t)asmCount, totalClasses, (int64_t)seenAddrs.size());
    return Status::OK;
}

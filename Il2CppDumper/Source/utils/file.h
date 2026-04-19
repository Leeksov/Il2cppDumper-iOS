#pragma once
#include "../../Prefix.h"

class File {
public:
    FILE* file = nullptr;

    File() = default;
    File(const std::string& path, const char* mode) { open(path, mode); }
    ~File() { close(); }

    void open(const std::string& path, const char* mode) { close(); file = fopen(path.c_str(), mode); }
    void close() { if (file) { fclose(file); file = nullptr; } }
    bool ok() const { return file != nullptr; }

    operator FILE*() const { return file; }

    void write(const char* data) { if (file) fputs(data, file); }
    void write(const std::string& data) { write(data.c_str()); }
    void write(const std::stringstream& ss) { write(ss.str()); }
};

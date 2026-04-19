#pragma once
#include "../../Prefix.h"

// Minimal write-only JSON builder
namespace Json {

inline std::string escape(const std::string& s) {
    std::string out;
    out.reserve(s.size() + 8);
    for (char c : s) {
        switch (c) {
            case '"':  out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default:
                if ((unsigned char)c < 0x20)
                    out += fmt::format("\\u{:04x}", (unsigned)c);
                else
                    out += c;
        }
    }
    return out;
}

struct JObj {
    std::vector<std::pair<std::string, std::string>> f;
    void num(const std::string& k, uint64_t v) { f.push_back({k, std::to_string(v)}); }
    void str(const std::string& k, const std::string& v) { f.push_back({k, "\"" + escape(v) + "\""}); }
    std::string dump() const {
        std::string s = "{";
        for (size_t i = 0; i < f.size(); i++) {
            if (i) s += ",";
            s += "\"" + f[i].first + "\":" + f[i].second;
        }
        return s + "}";
    }
};

struct JArr {
    std::vector<std::string> items;
    void obj(const JObj& o) { items.push_back(o.dump()); }
    void num(uint64_t v) { items.push_back(std::to_string(v)); }
    std::string dump() const {
        if (items.empty()) return "[]";
        std::string s = "[\n";
        for (size_t i = 0; i < items.size(); i++) {
            s += "  " + items[i];
            if (i + 1 < items.size()) s += ",";
            s += "\n";
        }
        return s + "]";
    }
};

} // namespace Json

//
//  dummy_dll.h — .NET PE/DLL generator with RVA/Offset attributes
//
//  Safe: never calls il2cpp_type_get_name. All type resolution via class_from_type.
//  Adds [Address(RVA="0x..", Offset="0x..")] and [FieldOffset(Offset="0x..")] attributes.
//

#pragma once
#include "dumper.h"

static bool _badPtr(const void* p) {
    if (!p || (uintptr_t)p < 0x1000) return true;
    vm_size_t sz = 0; uint8_t buf;
    return vm_read_overwrite(mach_task_self(), (vm_address_t)p, 1, (vm_address_t)&buf, &sz) != KERN_SUCCESS;
}

namespace DummyDll {

class Buf {
public:
    std::vector<uint8_t> d;
    void u8(uint8_t v) { d.push_back(v); }
    void u16(uint16_t v) { u8(v & 0xFF); u8(v >> 8); }
    void u32(uint32_t v) { u16(v & 0xFFFF); u16(v >> 16); }
    void u64(uint64_t v) { u32((uint32_t)v); u32((uint32_t)(v >> 32)); }
    void raw(const void* p, size_t n) { auto b = (const uint8_t*)p; d.insert(d.end(), b, b + n); }
    void zeros(size_t n) { d.insert(d.end(), n, 0); }
    void pad4() { while (d.size() & 3) u8(0); }
    void idx(uint32_t v, bool wide) { if (wide) u32(v); else u16((uint16_t)v); }
    size_t sz() const { return d.size(); }
};

class StrH {
    Buf b; std::unordered_map<std::string, uint32_t> c;
public:
    StrH() { b.u8(0); }
    uint32_t add(const std::string& s) {
        if (s.empty()) return 0;
        auto it = c.find(s); if (it != c.end()) return it->second;
        uint32_t o = (uint32_t)b.sz(); b.raw(s.c_str(), s.size() + 1); c[s] = o; return o;
    }
    Buf& buf() { return b; }
    bool wide() const { return b.sz() >= 0x10000; }
};

class BlobH {
    Buf b;
public:
    BlobH() { b.u8(0); }
    uint32_t add(const std::vector<uint8_t>& v) {
        if (v.empty()) return 0;
        uint32_t o = (uint32_t)b.sz(), n = (uint32_t)v.size();
        if (n < 0x80) b.u8(n);
        else if (n < 0x4000) { b.u8(0x80 | (n >> 8)); b.u8(n & 0xFF); }
        else { b.u8(0xC0 | (n >> 24)); b.u8((n >> 16) & 0xFF); b.u8((n >> 8) & 0xFF); b.u8(n & 0xFF); }
        b.raw(v.data(), v.size()); return o;
    }
    Buf& buf() { return b; }
    bool wide() const { return b.sz() >= 0x10000; }
};

class GuidH {
    Buf b; uint32_t n = 0;
public:
    uint32_t add() { ++n; for (int i = 0; i < 16; i++) b.u8((uint8_t)(i * 17 + n * 31)); return n; }
    Buf& buf() { return b; }
};

static void cmpU(std::vector<uint8_t>& b, uint32_t v) {
    if (v < 0x80) b.push_back(v);
    else if (v < 0x4000) { b.push_back(0x80 | (v >> 8)); b.push_back(v & 0xFF); }
    else { b.push_back(0xC0 | (v >> 24)); b.push_back((v >> 16) & 0xFF); b.push_back((v >> 8) & 0xFF); b.push_back(v & 0xFF); }
}
static uint32_t tdor(uint8_t tag, uint32_t row) { return (row << 2) | tag; }

static uint8_t primitiveElement(const char* name) {
    if (!name) return 0;
    static const std::unordered_map<std::string, uint8_t> m = {
        {"Void",0x01},{"Boolean",0x02},{"Char",0x03},{"SByte",0x04},{"Byte",0x05},
        {"Int16",0x06},{"UInt16",0x07},{"Int32",0x08},{"UInt32",0x09},{"Int64",0x0A},
        {"UInt64",0x0B},{"Single",0x0C},{"Double",0x0D},{"String",0x0E},
        {"IntPtr",0x18},{"UIntPtr",0x19},{"Object",0x1C},
    };
    auto it = m.find(name); return it != m.end() ? it->second : 0;
}

// ═══════ Custom attribute blob builders ═══════

// Encode a SerString into blob (compressed length + UTF-8)
static void blobSerStr(std::vector<uint8_t>& b, const std::string& s) {
    cmpU(b, (uint32_t)s.size());
    for (char c : s) b.push_back((uint8_t)c);
}

// Build blob: [Address(RVA="0x..", Offset="0x..")]
// .ctor() has 0 params, values as named FIELDS
static std::vector<uint8_t> buildAddressBlob(const std::string& rva, const std::string& offset) {
    std::vector<uint8_t> b;
    b.push_back(0x01); b.push_back(0x00); // prolog
    // 0 fixed args
    uint16_t numNamed = 2;
    b.push_back(numNamed & 0xFF); b.push_back(numNamed >> 8);
    // Named field: string RVA = "0x..."
    b.push_back(0x53); b.push_back(0x0E); // FIELD, STRING
    blobSerStr(b, "RVA"); blobSerStr(b, rva);
    // Named field: string Offset = "0x..."
    b.push_back(0x53); b.push_back(0x0E);
    blobSerStr(b, "Offset"); blobSerStr(b, offset);
    return b;
}

// Build blob: [FieldOffset(Offset="0x..")]
static std::vector<uint8_t> buildFieldOffsetBlob(const std::string& offset) {
    std::vector<uint8_t> b;
    b.push_back(0x01); b.push_back(0x00); // prolog
    uint16_t numNamed = 1;
    b.push_back(numNamed & 0xFF); b.push_back(numNamed >> 8);
    b.push_back(0x53); b.push_back(0x0E); // FIELD, STRING
    blobSerStr(b, "Offset"); blobSerStr(b, offset);
    return b;
}

// ═══════ DLL Builder ═══════
class Builder {
    StrH str; BlobH blob; GuidH guid;
    std::string asmNameStr;

    struct RTypeDef  { uint32_t flags, name, ns, extends, fldList, methList; };
    struct RField    { uint16_t flags; uint32_t name, sig; };
    struct RMethod   { uint32_t rva; uint16_t implF, flags; uint32_t name, sig, paramList; };
    struct RParam    { uint16_t flags, seq; uint32_t name; };
    struct RTypeRef  { uint32_t scope, name, ns; };
    struct RAsmRef   { uint16_t mj, mn, bld, rev; uint32_t fl, pk, name, cult, hv; };
    struct RCustomA  { uint32_t parent, type, value; }; // HasCustomAttribute, CustomAttributeType, Blob

    std::vector<RTypeDef> tTD;
    std::vector<RField>   tFld;
    std::vector<RMethod>  tMth;
    std::vector<RParam>   tPar;
    std::vector<RTypeRef> tTR;
    std::vector<RAsmRef>  tAR;
    std::vector<RCustomA> tCA;

    std::unordered_map<void*, uint32_t> tdMap;
    std::unordered_map<void*, uint32_t> trMap;
    std::unordered_map<std::string, uint32_t> arMap;
    uint32_t objRef = 0, vtRef = 0, enumRef = 0, attrRef = 0;
    uint32_t addrCtorRow = 0, foCtorRow = 0; // MethodDef rows for attribute .ctors

    // Track method/field rows for custom attributes
    struct MethodRVAInfo { uint32_t methodRow; std::string rva; std::string offset; };
    struct FieldOffInfo  { uint32_t fieldRow; std::string offset; };
    std::vector<MethodRVAInfo> pendingMethodAttrs;
    std::vector<FieldOffInfo> pendingFieldAttrs;

    uint32_t addAR(const std::string& name) {
        auto it = arMap.find(name); if (it != arMap.end()) return it->second;
        RAsmRef r = {}; r.name = str.add(name); tAR.push_back(r);
        uint32_t row = (uint32_t)tAR.size(); arMap[name] = row; return row;
    }
    uint32_t addTR(uint8_t scopeTag, uint32_t scopeRow, const std::string& ns, const std::string& name) {
        RTypeRef r; r.scope = (scopeRow << 2) | scopeTag; r.name = str.add(name); r.ns = str.add(ns);
        tTR.push_back(r); return (uint32_t)tTR.size();
    }
    uint32_t getRef(void* klass) {
        if (!klass || _badPtr(klass)) return objRef;
        auto it = trMap.find(klass); if (it != trMap.end()) return it->second;
        const char* n = IL2CPP::class_get_name(klass);
        const char* ns = IL2CPP::class_get_namespace ? IL2CPP::class_get_namespace(klass) : "";
        if (!n || _badPtr(n)) return objRef;
        uint32_t ar = addAR("mscorlib");
        uint32_t row = addTR(2, ar, ns ? ns : "", n);
        trMap[klass] = row; return row;
    }

    void encType(std::vector<uint8_t>& s, void* type) {
        if (!type || _badPtr(type)) { s.push_back(0x1C); return; }
        void* klass = nullptr;
        @try { klass = IL2CPP::class_from_type ? IL2CPP::class_from_type(type) : nullptr; } @catch (...) {}
        if (!klass || _badPtr(klass)) { s.push_back(0x1C); return; }
        const char* name = IL2CPP::class_get_name(klass);
        if (!name || _badPtr(name)) { s.push_back(0x1C); return; }
        bool byref = IL2CPP::type_is_byref ? IL2CPP::type_is_byref(type) : false;
        if (byref) s.push_back(0x10);
        uint8_t et = primitiveElement(name);
        if (et) { s.push_back(et); return; }
        std::string nameStr(name);
        if (nameStr.size() > 2 && nameStr.substr(nameStr.size() - 2) == "[]") {
            s.push_back(0x1D); s.push_back(0x1C); return;
        }
        bool isVT = IL2CPP::class_is_valuetype ? IL2CPP::class_is_valuetype(klass) : false;
        s.push_back(isVT ? 0x11 : 0x12);
        auto it = tdMap.find(klass);
        if (it != tdMap.end()) cmpU(s, tdor(0, it->second));
        else cmpU(s, tdor(1, getRef(klass)));
    }

    uint32_t fldSig(void* type) {
        std::vector<uint8_t> s; s.push_back(0x06); encType(s, type); return blob.add(s);
    }
    uint32_t methSig(void* method) {
        std::vector<uint8_t> s;
        uint32_t ifl = 0; auto fl = IL2CPP::method_get_flags(method, &ifl);
        s.push_back((fl & METHOD_ATTRIBUTE_STATIC) ? 0x00 : 0x20);
        int pc = IL2CPP::method_get_param_count(method); cmpU(s, (uint32_t)pc);
        @try { encType(s, IL2CPP::method_get_return_type(method)); } @catch (...) { s.push_back(0x01); }
        for (int i = 0; i < pc; i++) {
            @try { encType(s, IL2CPP::method_get_param(method, i)); } @catch (...) { s.push_back(0x1C); }
        }
        return blob.add(s);
    }

    // Create attribute TypeDefs at the end of the type list
    void createAttributeTypes() {
        // TypeRef: System.Attribute
        uint32_t mscor = arMap["mscorlib"];
        attrRef = addTR(2, mscor, "System", "Attribute");

        // .ctor signature: HASTHIS, 0 params, void return
        std::vector<uint8_t> ctorSig = {0x20, 0x00, 0x01};
        uint32_t ctorSigBlob = blob.add(ctorSig);
        // string field signature
        std::vector<uint8_t> strFldSig = {0x06, 0x0E};
        uint32_t strFldSigBlob = blob.add(strFldSig);

        // ── AddressAttribute ──
        RTypeDef addrTD = {};
        addrTD.flags = 0x00100001; // Public | BeforeFieldInit
        addrTD.name = str.add("AddressAttribute");
        addrTD.ns = str.add("");
        addrTD.extends = tdor(1, attrRef);
        addrTD.fldList = (uint32_t)tFld.size() + 1;
        addrTD.methList = (uint32_t)tMth.size() + 1;
        // Fields: public string RVA, Offset, VA, Slot
        for (const char* fn : {"RVA", "Offset", "VA", "Slot"}) {
            RField f = {}; f.flags = 0x0006; // Public
            f.name = str.add(fn); f.sig = strFldSigBlob; tFld.push_back(f);
        }
        // .ctor method
        RMethod addrCtor = {};
        addrCtor.rva = 1; // placeholder
        addrCtor.flags = 0x0806; // Public | HideBySig | SpecialName | RTSpecialName
        addrCtor.implF = 0;
        addrCtor.name = str.add(".ctor");
        addrCtor.sig = ctorSigBlob;
        addrCtor.paramList = (uint32_t)tPar.size() + 1;
        tMth.push_back(addrCtor);
        addrCtorRow = (uint32_t)tMth.size(); // 1-based
        tTD.push_back(addrTD);

        // ── FieldOffsetAttribute ──
        RTypeDef foTD = {};
        foTD.flags = 0x00100001;
        foTD.name = str.add("FieldOffsetAttribute");
        foTD.ns = str.add("");
        foTD.extends = tdor(1, attrRef);
        foTD.fldList = (uint32_t)tFld.size() + 1;
        foTD.methList = (uint32_t)tMth.size() + 1;
        // Field: public string Offset
        RField foFld = {}; foFld.flags = 0x0006; foFld.name = str.add("Offset"); foFld.sig = strFldSigBlob;
        tFld.push_back(foFld);
        // .ctor
        RMethod foCtor = addrCtor;
        foCtor.paramList = (uint32_t)tPar.size() + 1;
        tMth.push_back(foCtor);
        foCtorRow = (uint32_t)tMth.size();
        tTD.push_back(foTD);
    }

    // Build CustomAttribute entries from pending lists
    void buildCustomAttributes() {
        // HasCustomAttribute: (row << 5) | tag. MethodDef=0, Field=1
        // CustomAttributeType: (row << 3) | tag. MethodDef=3
        for (auto& m : pendingMethodAttrs) {
            RCustomA ca = {};
            ca.parent = (m.methodRow << 5) | 0; // MethodDef
            ca.type = (addrCtorRow << 3) | 3;   // MethodDef .ctor
            ca.value = blob.add(buildAddressBlob(m.rva, m.offset));
            tCA.push_back(ca);
        }
        for (auto& f : pendingFieldAttrs) {
            RCustomA ca = {};
            ca.parent = (f.fieldRow << 5) | 1; // Field
            ca.type = (foCtorRow << 3) | 3;
            ca.value = blob.add(buildFieldOffsetBlob(f.offset));
            tCA.push_back(ca);
        }
    }

    void serializeTables(Buf& out) {
        bool ws = str.wide(), wb = blob.wide(), wg = false;
        uint32_t nTR = (uint32_t)tTR.size(), nTD = (uint32_t)tTD.size();
        uint32_t nFld = (uint32_t)tFld.size(), nMth = (uint32_t)tMth.size();
        uint32_t nPar = (uint32_t)tPar.size(), nCA = (uint32_t)tCA.size();
        bool wRS = std::max({1u, (uint32_t)tAR.size(), nTR}) >= (1u << 14);
        bool wTDOR = std::max({nTD, nTR, 0u}) >= (1u << 14);
        bool wF = nFld >= 0x10000, wM = nMth >= 0x10000, wP = nPar >= 0x10000;
        // HasCustomAttribute: 5 tag bits → wide if max table >= 2^11
        bool wHCA = std::max({nMth, nFld, nTR, nTD, nPar}) >= (1u << 11);
        // CustomAttributeType: 3 tag bits → wide if max >= 2^13
        bool wCAT = nMth >= (1u << 13);

        out.u32(0); out.u8(2); out.u8(0);
        uint8_t hs = 0; if (ws) hs |= 1; if (wg) hs |= 2; if (wb) hs |= 4;
        out.u8(hs); out.u8(1);

        uint64_t valid = (1ULL<<0)|(1ULL<<1)|(1ULL<<2)|(1ULL<<4)|(1ULL<<6)|(1ULL<<8)|(1ULL<<32)|(1ULL<<35);
        if (nCA > 0) valid |= (1ULL << 0x0C);
        out.u64(valid); out.u64(0);

        // Row counts (in table number order)
        out.u32(1); out.u32(nTR); out.u32(nTD); out.u32(nFld);
        out.u32(nMth); out.u32(nPar);
        if (nCA > 0) out.u32(nCA);
        out.u32(1); out.u32((uint32_t)tAR.size());

        // 0x00 Module
        out.u16(0); out.idx(str.add(asmNameStr + ".dll"), ws);
        out.idx(guid.add(), wg); out.idx(0, wg); out.idx(0, wg);
        // 0x01 TypeRef
        for (auto& r : tTR) { out.idx(r.scope, wRS); out.idx(r.name, ws); out.idx(r.ns, ws); }
        // 0x02 TypeDef
        for (auto& r : tTD) { out.u32(r.flags); out.idx(r.name, ws); out.idx(r.ns, ws); out.idx(r.extends, wTDOR); out.idx(r.fldList, wF); out.idx(r.methList, wM); }
        // 0x04 Field
        for (auto& r : tFld) { out.u16(r.flags); out.idx(r.name, ws); out.idx(r.sig, wb); }
        // 0x06 MethodDef
        for (auto& r : tMth) { out.u32(r.rva); out.u16(r.implF); out.u16(r.flags); out.idx(r.name, ws); out.idx(r.sig, wb); out.idx(r.paramList, wP); }
        // 0x08 Param
        for (auto& r : tPar) { out.u16(r.flags); out.u16(r.seq); out.idx(r.name, ws); }
        // 0x0C CustomAttribute
        for (auto& r : tCA) { out.idx(r.parent, wHCA); out.idx(r.type, wCAT); out.idx(r.value, wb); }
        // 0x20 Assembly
        out.u32(0x8004); out.u16(0); out.u16(0); out.u16(0); out.u16(0);
        out.u32(0); out.idx(0, wb); out.idx(str.add(asmNameStr), ws); out.idx(0, ws);
        // 0x23 AssemblyRef
        for (auto& r : tAR) {
            out.u16(r.mj); out.u16(r.mn); out.u16(r.bld); out.u16(r.rev);
            out.u32(r.fl); out.idx(r.pk, wb); out.idx(r.name, ws); out.idx(r.cult, ws); out.idx(r.hv, wb);
        }
    }

    void buildMetadata(Buf& meta) {
        Buf tabS; serializeTables(tabS); tabS.pad4();
        str.buf().pad4(); blob.buf().pad4(); guid.buf().pad4();
        Buf usS; usS.u8(0); usS.pad4();
        const char* ver = "v4.0.30319";
        uint32_t verLen = ((uint32_t)strlen(ver) + 1 + 3) & ~3u;
        auto padN = [](const char* n) -> uint32_t { return ((uint32_t)strlen(n) + 1 + 3) & ~3u; };
        uint32_t hdrSz = 16 + verLen + 4 + 5 * 8 + padN("#~") + padN("#Strings") + padN("#US") + padN("#GUID") + padN("#Blob");
        uint32_t off0 = hdrSz, off1 = off0 + (uint32_t)tabS.sz();
        uint32_t off2 = off1 + (uint32_t)str.buf().sz(), off3 = off2 + (uint32_t)usS.sz();
        uint32_t off4 = off3 + (uint32_t)guid.buf().sz();
        meta.u32(0x424A5342); meta.u16(1); meta.u16(1); meta.u32(0); meta.u32(verLen);
        meta.raw(ver, strlen(ver) + 1); meta.pad4(); meta.u16(0); meta.u16(5);
        auto hdr = [&](uint32_t off, uint32_t sz, const char* name) { meta.u32(off); meta.u32(sz); meta.raw(name, strlen(name) + 1); meta.pad4(); };
        hdr(off0, (uint32_t)tabS.sz(), "#~"); hdr(off1, (uint32_t)str.buf().sz(), "#Strings");
        hdr(off2, (uint32_t)usS.sz(), "#US"); hdr(off3, (uint32_t)guid.buf().sz(), "#GUID"); hdr(off4, (uint32_t)blob.buf().sz(), "#Blob");
        meta.raw(tabS.d.data(), tabS.sz()); meta.raw(str.buf().d.data(), str.buf().sz());
        meta.raw(usS.d.data(), usS.sz()); meta.raw(guid.buf().d.data(), guid.buf().sz()); meta.raw(blob.buf().d.data(), blob.buf().sz());
    }

    void writePE(const std::string& path) {
        const uint32_t FA = 0x200, SA = 0x2000, BODY_RVA = SA + 72;
        for (auto& m : tMth) if (m.rva != 0) m.rva = BODY_RVA;
        Buf meta; buildMetadata(meta);
        uint32_t metaOff = 76, textVSz = metaOff + (uint32_t)meta.sz();
        uint32_t textFSz = (textVSz + FA - 1) & ~(FA - 1);
        uint32_t sizeOfImage = SA + ((textVSz + SA - 1) & ~(SA - 1));
        Buf pe;
        pe.u16(0x5A4D); pe.zeros(0x3A); pe.u32(0x80); pe.zeros(0x40);
        pe.u32(0x00004550);
        pe.u16(0x014C); pe.u16(1); pe.u32(0); pe.u32(0); pe.u32(0); pe.u16(0xE0); pe.u16(0x2102);
        pe.u16(0x010B); pe.u8(8); pe.u8(0);
        pe.u32(textFSz); pe.u32(0); pe.u32(0); pe.u32(0); pe.u32(SA); pe.u32(0);
        pe.u32(0x10000000); pe.u32(SA); pe.u32(FA);
        pe.u16(4); pe.u16(0); pe.u16(0); pe.u16(0); pe.u16(4); pe.u16(0);
        pe.u32(0); pe.u32(sizeOfImage); pe.u32(FA); pe.u32(0);
        pe.u16(3); pe.u16(0x8540);
        pe.u32(0x100000); pe.u32(0x1000); pe.u32(0x100000); pe.u32(0x1000);
        pe.u32(0); pe.u32(16);
        for (int i = 0; i < 14; i++) pe.u64(0);
        pe.u32(SA); pe.u32(72); pe.u64(0);
        pe.raw(".text\0\0\0", 8);
        pe.u32(textVSz); pe.u32(SA); pe.u32(textFSz); pe.u32(FA);
        pe.u32(0); pe.u32(0); pe.u16(0); pe.u16(0); pe.u32(0x60000020);
        while (pe.sz() < FA) pe.u8(0);
        pe.u32(72); pe.u16(2); pe.u16(5);
        pe.u32(SA + metaOff); pe.u32((uint32_t)meta.sz());
        pe.u32(1); pe.u32(0);
        pe.u64(0); pe.u64(0); pe.u64(0); pe.u64(0); pe.u64(0); pe.u64(0);
        pe.u8(0x06); pe.u8(0x2A); pe.u8(0); pe.u8(0);
        pe.raw(meta.d.data(), meta.sz());
        while (pe.sz() < FA + textFSz) pe.u8(0);
        FILE* f = fopen(path.c_str(), "wb");
        if (f) { fwrite(pe.d.data(), 1, pe.sz(), f); fclose(f); }
    }

public:
    void build(const std::string& asmName, const void* image, const std::string& outPath) {
        asmNameStr = asmName;
        uint32_t mscor = addAR("mscorlib");
        objRef  = addTR(2, mscor, "System", "Object");
        vtRef   = addTR(2, mscor, "System", "ValueType");
        enumRef = addTR(2, mscor, "System", "Enum");

        RTypeDef modTD = {}; modTD.name = str.add("<Module>"); modTD.fldList = 1; modTD.methList = 1;
        tTD.push_back(modTD);

        size_t classCount = IL2CPP::image_get_class_count(image);
        std::vector<void*> classes;
        for (size_t i = 0; i < classCount; i++) {
            void* k = nullptr;
            @try { k = IL2CPP::image_get_class(image, i); } @catch (...) {}
            classes.push_back(k);
            if (k && !_badPtr(k)) tdMap[k] = (uint32_t)(i + 2);
        }

        for (auto* klass : classes) {
            if (!klass || _badPtr(klass)) continue;
            @try {
                const char* cn = IL2CPP::class_get_name(klass);
                if (!cn || _badPtr(cn)) continue;

                RTypeDef td = {};
                td.flags = IL2CPP::class_get_flags ? IL2CPP::class_get_flags(klass) : 0;
                td.name = str.add(cn);
                td.ns = str.add(IL2CPP::class_get_namespace ? (IL2CPP::class_get_namespace(klass) ?: "") : "");
                bool isEnum = IL2CPP::class_is_enum && IL2CPP::class_is_enum(klass);
                bool isVT = IL2CPP::class_is_valuetype && IL2CPP::class_is_valuetype(klass);
                bool isIF = (td.flags & TYPE_ATTRIBUTE_INTERFACE) != 0;
                if (isIF) td.extends = 0;
                else if (isEnum) td.extends = tdor(1, enumRef);
                else if (isVT) td.extends = tdor(1, vtRef);
                else td.extends = tdor(1, objRef);

                td.fldList = (uint32_t)tFld.size() + 1;
                td.methList = (uint32_t)tMth.size() + 1;

                // Fields
                if (IL2CPP::class_get_fields) {
                    void* fi = nullptr;
                    while (auto* f = IL2CPP::class_get_fields(klass, &fi)) {
                        if (_badPtr(f)) break;
                        const char* fn = IL2CPP::field_get_name(f);
                        if (!fn || _badPtr(fn)) continue;
                        uint32_t fieldRow = (uint32_t)tFld.size() + 1;
                        RField fr = {}; fr.flags = (uint16_t)IL2CPP::field_get_flags(f);
                        fr.name = str.add(fn);
                        @try { fr.sig = fldSig(IL2CPP::field_get_type(f)); }
                        @catch (...) { std::vector<uint8_t> fb = {0x06, 0x1C}; fr.sig = blob.add(fb); }
                        tFld.push_back(fr);

                        // Queue FieldOffset attribute for non-literal non-static fields
                        if (!(fr.flags & 0x0040) && !(fr.flags & 0x0010)) { // !LITERAL && !STATIC
                            size_t off = IL2CPP::field_get_offset(f);
                            pendingFieldAttrs.push_back({fieldRow, fmt::format("0x{:X}", off)});
                        }
                    }
                }

                // Methods
                if (IL2CPP::class_get_methods) {
                    void* mi = nullptr;
                    while (auto* m = IL2CPP::class_get_methods(klass, &mi)) {
                        if (_badPtr(m)) break;
                        const char* mn = IL2CPP::method_get_name(m);
                        if (!mn || _badPtr(mn)) continue;
                        uint32_t ifl = 0; auto fl = IL2CPP::method_get_flags(m, &ifl);
                        uint32_t methodRow = (uint32_t)tMth.size() + 1;
                        RMethod mr = {};
                        mr.rva = (fl & METHOD_ATTRIBUTE_ABSTRACT) ? 0 : 1;
                        mr.implF = (uint16_t)ifl; mr.flags = (uint16_t)fl;
                        mr.name = str.add(mn);
                        @try { mr.sig = methSig(m); }
                        @catch (...) { std::vector<uint8_t> fb = {0x00, 0x00, 0x01}; mr.sig = blob.add(fb); }
                        mr.paramList = (uint32_t)tPar.size() + 1;
                        tMth.push_back(mr);

                        // Queue Address attribute for non-abstract methods
                        if (!(fl & METHOD_ATTRIBUTE_ABSTRACT)) {
                            auto methodPtr = *(void**)m;
                            if (methodPtr && !_badPtr(methodPtr)) {
                                uint64_t rva = (uint64_t)methodPtr - IL2CPP::info.address;
                                pendingMethodAttrs.push_back({
                                    methodRow,
                                    fmt::format("0x{:X}", rva),
                                    fmt::format("0x{:X}", rva)
                                });
                            }
                        }

                        int pc = IL2CPP::method_get_param_count(m);
                        for (int p = 0; p < pc; p++) {
                            RParam pr = {}; pr.seq = (uint16_t)(p + 1);
                            const char* pn = IL2CPP::method_get_param_name ? IL2CPP::method_get_param_name(m, p) : nullptr;
                            pr.name = str.add((pn && !_badPtr(pn)) ? pn : fmt::format("p{}", p));
                            tPar.push_back(pr);
                        }
                    }
                }
                tTD.push_back(td);
            } @catch (...) { continue; }
        }

        // Add attribute types & build custom attributes
        createAttributeTypes();
        buildCustomAttributes();

        writePE(outPath);
    }
};

static void Generate(const std::string& dir) {
    std::string dllDir = dir + "/DummyDll";
    std::filesystem::create_directories(dllDir);
    void* domain = IL2CPP::domain_get();
    size_t count = 0;
    void** asms = IL2CPP::domain_get_assemblies(domain, &count);
    int generated = 0;
    for (size_t i = 0; i < count; i++) {
        @try {
            auto* image = IL2CPP::assembly_get_image(asms[i]);
            const char* imgName = IL2CPP::image_get_name(image);
            if (!imgName) continue;
            std::string asmName = imgName;
            if (asmName.size() > 4 && asmName.substr(asmName.size() - 4) == ".dll")
                asmName = asmName.substr(0, asmName.size() - 4);
            std::string outPath = dllDir + "/" + imgName;
            if (outPath.size() < 4 || outPath.substr(outPath.size() - 4) != ".dll")
                outPath += ".dll";
            Builder b;
            b.build(asmName, image, outPath);
            generated++;
        } @catch (...) {
            Dumper::Log("DummyDll: assembly %zu crashed, skipping.", i);
        }
    }
    Dumper::Log("DummyDll: Generated %d/%zu assemblies.", generated, count);
}

} // namespace DummyDll

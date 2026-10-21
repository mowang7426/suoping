#pragma once
#include <map>
#include <set>
#include <string>
#include <utility>
#include <vector>
namespace LSGCNotifications {
constexpr size_t MutationBudget=32;
constexpr size_t MaxProjectedRequests=512;
inline bool ProjectionWithinBudget(size_t visible,size_t hidden) {
    return visible<=MaxProjectedRequests && hidden<=MaxProjectedRequests-visible;
}
// Body-free immutable identity input. No synthetic success or semantic allowlist.
struct Identity { std::string app,request; };
struct Group { std::string app; size_t count; };
struct Snapshot {
    bool valid=false;
    std::vector<Group> groups;
    size_t total=0;
    std::string reason="snapshot-unavailable";
};
inline Snapshot BuildSnapshot(const std::vector<Identity>& input) {
    Snapshot out;
    if (input.size()>8192) { out.reason="snapshot-budget-exceeded"; return out; }
    std::set<std::pair<std::string,std::string>> seen;
    std::map<std::string,size_t> counts;
    for (const auto &row:input) {
        if (row.app.empty() || row.request.empty() || row.app.size()>512 || row.request.size()>512) {
            out.reason="request-identity-unavailable"; return out;
        }
        if (seen.emplace(row.app,row.request).second) ++counts[row.app];
    }
    for (const auto &pair:counts) out.groups.push_back({pair.first,pair.second});
    out.total=seen.size(); out.valid=true; out.reason="snapshot-ready";
    return out;
}
}

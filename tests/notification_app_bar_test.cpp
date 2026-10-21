#include "../LSGCNotificationsAppBarPolicy.h"
#include <cassert>
#include <iostream>
using namespace LSGCNotifications;
int main() {
    auto counts=BuildSnapshot({{"a","1"},{"a","1"},{"a","2"},{"b","1"}});
    assert(counts.valid && counts.total==3 && counts.groups.size()==2);
    assert(counts.groups[0].app=="a" && counts.groups[0].count==2 && counts.groups[1].count==1);
    assert(BuildSnapshot({}).valid && BuildSnapshot({}).total==0);
    assert(!BuildSnapshot({{"","1"}}).valid && !BuildSnapshot({{"a",""}}).valid);
    assert(!BuildSnapshot({{std::string(513,'a'),"1"}}).valid);
    std::vector<Identity> overflow(8193,{"a","1"}); assert(!BuildSnapshot(overflow).valid);
    std::vector<Identity> active;
    for (unsigned i=0;i<512;i++) active.push_back({i%2?"a":"b",std::to_string(i)});
    assert(BuildSnapshot(active).total==512);
    active.erase(active.begin()); assert(BuildSnapshot(active).total==511);
    assert(ProjectionWithinBudget(512,0) && ProjectionWithinBudget(0,512) && ProjectionWithinBudget(400,112));
    assert(!ProjectionWithinBudget(513,0) && !ProjectionWithinBudget(500,13) && !ProjectionWithinBudget(0,size_t(-1)));
    static_assert(MutationBudget==32,"bounded production batch contract");
    std::cout << "PASS production identity dedup, app counts, active insert/delete, malformed/overflow input, finite projection budget\n";
}

#ifndef NR_H
#define NR_H

#include "DafnyRuntime.h"

#include "Extern.h"
#include "LinearExtern.h"

#ifdef USE_COUNTER
#include "BundleCounter.i.h"
#else
#include "BundleVSpace.i.h"
#endif

#include <cinttypes>
#include <optional>
#include <iostream>
#include <chrono>
#include <vector>

#include <thread>
#include <mutex>
#include <condition_variable>

#include <memory>

using LinearExtern::lseq;

#ifdef USE_COUNTER
namespace nr = Impl_ON_CounterIfc__Compile;
namespace nrinit = Init_ON_CounterIfc__Compile;
#else
namespace nr = Impl_ON_VSpaceIfc__Compile;
namespace nrinit = Init_ON_VSpaceIfc__Compile;
#endif

constexpr size_t CACHELINE_SIZE = 128;

constexpr size_t CLPAD(size_t sz) {
  return ((sz / CACHELINE_SIZE) * CACHELINE_SIZE) +
          (((sz % CACHELINE_SIZE) > 0) * CACHELINE_SIZE) - sz;
}

template<class T, bool = false>
struct padded
{
  padded(const T& value) : value{value} {}
  alignas(CACHELINE_SIZE)T value;
  char padding[CLPAD(sizeof(T))];
};

template<class T>
struct padded<T, true>
{
  padded(const T& value) : value{value} {}
  alignas(CACHELINE_SIZE)T value;
};

template<class T>
using cache_padded = padded<T, (sizeof(T) % CACHELINE_SIZE == 0)>;

class nr_helper {
  uint32_t n_threads_per_replica;
  std::optional<nr::NR> nr;
  std::mutex init_mutex;
  lseq<nrinit::NodeCreationToken> node_creation_tokens;
  std::unordered_map<uint8_t, std::unique_ptr<cache_padded<nr::Node>>> nodes;
  /// Maps NodeId to vector of ThreadOwnedContexts for that Node.
  std::unordered_map<uint8_t, lseq<nr::ThreadOwnedContext>> thread_owned_contexts;
  std::condition_variable all_nodes_init;

 public:
  static uint64_t num_replicas() {
    return Constants_Compile::__default::NUM__REPLICAS;
  }

  nr_helper(size_t n_threads)
    : n_threads_per_replica{static_cast<uint32_t>(n_threads / num_replicas())}
    , nr{}
    , init_mutex{}
    , node_creation_tokens{}
    , nodes{}
    , thread_owned_contexts{}
    , all_nodes_init{}
  {
    assert(num_replicas() > 0);
    assert(num_replicas() <= n_threads);
    assert(n_threads_per_replica * num_replicas() == n_threads);
  }

  ~nr_helper() {
    for (auto seq : thread_owned_contexts)
      delete seq.second;

    delete node_creation_tokens;
  }

  nr::NR& get_nr() { return *nr; }

  nr::Node& get_node(uint8_t thread_id) {
    return nodes[thread_id / n_threads_per_replica]->value;
  }

  void init_nr() {
    auto init = nrinit::__default::initNR();
    nr.emplace(init.get<0>());

    node_creation_tokens = init.get<1>();
    assert(node_creation_tokens->size() == num_replicas());
  }

  nr::ThreadOwnedContext* register_thread(uint8_t thread_id) {
    std::unique_lock<std::mutex> lock{init_mutex};

    nrinit::NodeCreationToken* token{nullptr};
    if (thread_id % n_threads_per_replica == 0)
      token = &node_creation_tokens->at(thread_id / n_threads_per_replica).a;

    if (token) {
      auto r = nrinit::__default::initNode(*token);
      uint64_t node_id = r.get<0>().nodeId;
      std::cerr << "thread_id " << static_cast<uint32_t>(thread_id)
                << " done initializing node_id " << node_id << std::endl;

      auto node = new cache_padded<nr::Node>{nr::Node(r.get<0>())};
      nodes.emplace(node_id, std::unique_ptr<cache_padded<nr::Node>>{node});
      thread_owned_contexts.emplace(node_id, r.get<1>());

      if (nodes.size() == num_replicas())
        all_nodes_init.notify_all();
    }

    while (nodes.size() < num_replicas())
      all_nodes_init.wait(lock);

    // TODO(stutsman) no pinning, affinity, and threads on different
    // nodes may actually use the wrong replica; all this needs to be
    // fixed if we want to use this harness.
    const uint8_t node_id = thread_id / n_threads_per_replica;
    const uint8_t context_index = thread_id % n_threads_per_replica;

    std::cerr << "thread_id " << static_cast<uint32_t>(thread_id)
              << " registered with node_id " << static_cast<uint32_t>(node_id)
              << " context " << static_cast<uint32_t>(context_index)
              << std::endl;

    return &thread_owned_contexts.at(node_id)->at(context_index).a;
  }
};

/*
  //LogWrapper& lw = createLog();
  //ReplicaWrapper* rw = createReplica(lw);
  //auto tkn = rw->RegisterWrapper();
  //rw->ReplicaMap(tkn, 0x2000, 0x3000);
  //rw->ReplicaResolve(tkn, 0x2000);
*/

class nr_rust_helper {
  uint32_t n_threads_per_replica;
  LogWrapper& log;
  std::mutex init_mutex;
  std::unordered_map<uint8_t, ReplicaWrapper*> nodes;
  /// Maps NodeId to vector of ReplicaToken Ids for that Node.
  std::unordered_map<uint8_t, lseq<size_t>> thread_owned_contexts;
  std::condition_variable all_nodes_init;

 public:
  static uint64_t num_replicas() {
    return Constants_Compile::__default::NUM__REPLICAS;
  }

  nr_rust_helper(size_t n_threads)
    : n_threads_per_replica{static_cast<uint32_t>(n_threads / num_replicas())}
    , log{ createLog()}
    , init_mutex{}
    , nodes{}
    , thread_owned_contexts{}
    , all_nodes_init{}
  {
    assert(num_replicas() > 0);
    assert(num_replicas() <= n_threads);
    assert(n_threads_per_replica * num_replicas() == n_threads);
  }

  ~nr_rust_helper() {
    // NYI
  }

  //nr::NR& get_nr() { return *nr; }

  ReplicaWrapper *get_node(uint8_t thread_id)
  {
    return nodes[thread_id / n_threads_per_replica];
  }

  void init_nr() {
  }

  size_t register_thread(uint8_t thread_id) {
    std::unique_lock<std::mutex> lock{init_mutex};
    uint64_t node_id = thread_id / n_threads_per_replica;

    if (thread_id % n_threads_per_replica == 0)
    {
      auto replica = createReplica(log);
      std::cerr << "thread_id " << static_cast<uint32_t>(thread_id)
                << " done initializing node_id " << node_id << std::endl;
      nodes.emplace(node_id, replica);

      if (nodes.size() == num_replicas())
        all_nodes_init.notify_all();
    }

    while (nodes.size() < num_replicas())
      all_nodes_init.wait(lock);

    // TODO(stutsman) no pinning, affinity, and threads on different
    // nodes may actually use the wrong replica; all this needs to be
    // fixed if we want to use this harness.
    auto context = nodes[node_id]->RegisterWrapper();

    std::cerr << "thread_id " << static_cast<uint32_t>(thread_id)
              << " registered with node_id " << static_cast<uint32_t>(node_id)
              << " context " << static_cast<uint32_t>(context)
              << std::endl;

    return context;
  }
};


#endif
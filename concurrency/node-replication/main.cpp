#include <cinttypes>
#include <optional>
#include <iostream>
#include <chrono>
#include <vector>

#include <thread>
#include <mutex>
#include <shared_mutex>
#include <condition_variable>

#include "nr.h"
#include "thread_pin.h"

using duration = std::chrono::duration<uint64_t>;

struct benchmark_state {
  size_t n_threads;
  duration run_duration;
  core_map cores;
  std::atomic<size_t> n_threads_ready;
  std::vector<std::thread> threads;
  std::atomic<bool> start_benchmark;
  std::atomic<bool> exit_benchmark;
  std::atomic<uint64_t> total_updates;
  std::atomic<uint64_t> total_reads;

  benchmark_state(size_t n_threads,
                  duration run_duration,
                  core_map::numa_policy numa_policy,
                  core_map::core_policy core_policy)
    : n_threads{n_threads}
    , run_duration{run_duration}
    , cores{numa_policy, core_policy}
    , n_threads_ready{}
    , threads{}
    , start_benchmark{}
    , exit_benchmark{}
    , total_updates{}
    , total_reads{}
  {}
};


template <typename Monitor>
void run_thread(
    uint8_t thread_id,
    benchmark_state& state,
    Monitor& monitor)
{
  state.cores.pin(thread_id);

  void* thread_context = monitor.create_thread_context(thread_id);

  state.n_threads_ready++;
  while (!state.start_benchmark) {}

  uint64_t updates = 0;
  uint64_t reads = 0;
  while (!state.exit_benchmark.load(std::memory_order_relaxed)) {
    if ((reads + updates) & 0xf) { // do a read
      monitor.get(thread_id, thread_context);
      ++reads;
    } else { // do a write
      monitor.inc(thread_id, thread_context);
      ++updates;
    }
  }

  state.total_updates += updates;
  state.total_reads += reads;
}

// - C++ shared_mutex Benchmarking -

struct cpp_shared_mutex_monitor {
  using s_lock = std::shared_lock<std::shared_mutex>;
  using x_lock = std::unique_lock<std::shared_mutex>;

  std::shared_mutex mutex;
  uint64_t value;

  cpp_shared_mutex_monitor()
    : mutex{}
    , value{}
  {}

  void* create_thread_context(uint8_t thread_id) {
    return nullptr;
  }

  uint64_t get(uint8_t thread_id, void* thread_context) {
    s_lock lock{mutex};
    return value;
  }

  void inc(uint8_t thread_id, void* thread_context) {
    x_lock lock{mutex};
    ++value;
  }

  static void run_thread(
      uint8_t thread_id,
      benchmark_state& state,
      cpp_shared_mutex_monitor& monitor)
  {
    ::run_thread(thread_id, state, monitor);
  }
};

// - RwLock Benchmarking -

// Give a friendlier name to Dafny's generated namespace.
namespace rwlock = RwLockImpl_ON_Uint64ContentsTypeMod__Compile;
typedef rwlock::RwLock RwLockUint64;

struct dafny_rwlock_monitor{
  RwLockUint64 lock;

  dafny_rwlock_monitor()
    : lock{rwlock::__default::new__mutex(0lu)}
  {}

  void* create_thread_context(uint8_t thread_id) {
    return nullptr;
  }

  uint64_t get(uint8_t thread_id, void* thread_context) {
    auto shared_guard = lock.acquire__shared(thread_id);
    uint64_t value = *rwlock::__default::borrow__shared(lock, shared_guard);
    lock.release__shared(shared_guard);
    return value;
  }

  void inc(uint8_t thread_id, void* thread_context) {
    uint64_t value = lock.acquire();
    lock.release(value + 1);
  }

  static void run_thread(
      uint8_t thread_id,
      benchmark_state& state,
      dafny_rwlock_monitor& monitor)
  {
    ::run_thread(thread_id, state, monitor);
  }
};

// - NR Benchmarking -

struct dafny_nr_monitor{
  nr_helper helper;

  dafny_nr_monitor()
    : helper{}
  {
    helper.init_nr();
  }

  void* create_thread_context(uint8_t thread_id) {
    return helper.register_thread(thread_id);
  }

  uint64_t get(uint8_t thread_id, void* context) {
    auto c = static_cast<nr::ThreadOwnedContext*>(context);
    Tuple<uint64_t, nr::ThreadOwnedContext> r =
      Impl_ON_CounterIfc__Compile::__default::do__read(
        helper.get_nr(),
        helper.get_node(thread_id),
        CounterIfc_Compile::ReadonlyOp{},
        *c);
    return r.get<0>();
  }

  void inc(uint8_t thread_id, void* context) {
    auto c = static_cast<nr::ThreadOwnedContext*>(context);
    Impl_ON_CounterIfc__Compile::__default::do__update(
      helper.get_nr(),
      helper.get_node(thread_id),
      CounterIfc_Compile::UpdateOp{},
      *c);
  }

  static void run_thread(
      uint8_t thread_id,
      benchmark_state& state,
      dafny_nr_monitor& monitor)
  {
    ::run_thread(thread_id, state, monitor);
  }
};

template <typename Monitor>
void bench(benchmark_state& state, Monitor& monitor)
{
  for (uint8_t thread_id = 0; thread_id < state.n_threads; ++thread_id) {
    state.threads.emplace_back(std::thread{Monitor::run_thread,
                                           thread_id,
                                           std::ref(state),
                                           std::ref(monitor)});
  }

  while (state.n_threads_ready < state.n_threads);
  state.start_benchmark = true;
  std::this_thread::sleep_for(state.run_duration);
  state.exit_benchmark = true;

  for (auto& thread : state.threads)
    thread.join();

  std::cout << std::endl
            << "threads " << state.n_threads << std::endl
            << "updates " << state.total_updates << std::endl
            << "reads   " << state.total_reads << std::endl;
}

int main(int argc, char* argv[]) {
  disable_dvfs();

  const auto run_duration = std::chrono::seconds{5};

  if (argc < 2) {
    std::cerr << "usage: " << argv[0] << " <benchmarkname>" << std::endl;
    exit(-1);
  }

  std::string test = std::string{argv[1]};

  benchmark_state state{
    NUM_THREADS,
    run_duration,
    core_map::NUMA_FILL,
    core_map::CORES_FILL
  };

#define BENCHMARK(test_name) \
  if (test == #test_name) { \
    test_name ## _monitor monitor{}; \
    bench(state, monitor); \
    exit(0); \
  }

  BENCHMARK(cpp_shared_mutex);
  BENCHMARK(dafny_rwlock);
  BENCHMARK(dafny_nr);

  std::cerr << "unrecognized benchmark name " << test << std::endl;

  return -1;
}

using System;
using System.Diagnostics;
using System.Collections.Generic;

abstract class Benchmark {
  public abstract string Name { get; }

  public void Run() {
    FSUtil.ClearIfExists();
    FSUtil.Mkfs();
    Application app = new Application();
    app.verbose = false;

    Prepare(app);

    GC.Collect();

    Stopwatch sw = Stopwatch.StartNew();
    Go(app);
    sw.Stop();

    Console.WriteLine("Benchmark " + Name + " " + sw.ElapsedMilliseconds.ToString() + " ms");
  }

  abstract protected void Prepare(Application app);
  abstract protected void Go(Application app);

  protected List<byte[]> RandomKeys(int n, int seed) {
    Random rand = new Random(seed);

    List<byte[]> l = new List<byte[]>();
    for (int i = 0; i < n; i++) {
      int sz = rand.Next(1, 1024 + 1);
      byte[] bytes = new byte[sz];
      rand.NextBytes(bytes);
      l.Add(bytes);
    }

    return l;
  }

  protected List<byte[]> RandomValues(int n, int seed) {
    return RandomKeys(n, seed);
  }

  protected List<byte[]> RandomSortedKeys(int n, int seed) {
    List<byte[]> data = RandomKeys(n, seed);
    data.Sort(new ArrayComparer());
    return data;
  }

  class ArrayComparer : IComparer<byte[]>
  {
    // Call CaseInsensitiveComparer.Compare with the parameters reversed.
    public int Compare(byte[] x, byte[] y)
    {
      byte[] a = (byte[]) x;
      byte[] b = (byte[]) y;
      for (int i = 0; i < a.Length && i < b.Length; i++) {
        if (a[i] < b[i]) return -1;
        if (a[i] > b[i]) return 1;
      }
      if (a.Length < b.Length) return -1;
      if (a.Length > b.Length) return 1;
      return 0;
    }
  }

  // Generate random keys to query.
  // Half will be existing keys, half will be totally random keys
  protected List<byte[]> RandomQueryKeys(int n, int seed, List<byte[]> insertedKeys) {
    Random rand = new Random(seed);

    List<byte[]> l = new List<byte[]>();
    for (int i = 0; i < n; i++) {
      if (rand.Next(0, 2) == 0) {
        int sz = rand.Next(1, 1024 + 1);
        byte[] bytes = new byte[sz];
        rand.NextBytes(bytes);
        l.Add(bytes);
      } else {
        int idx = rand.Next(0, insertedKeys.Count);
        l.Add(insertedKeys[idx]);
      }
    }

    return l;
  }
}

class BenchmarkRandomInserts : Benchmark {
  public override string Name { get { return "RandomInserts"; } }

  List<byte[]> keys;
  List<byte[]> values;

  public BenchmarkRandomInserts() {
    int seed1 = 1234;
    int seed2 = 527;
    keys = RandomKeys(2000, seed1);
    values = RandomValues(2000, seed2);
  }

  override protected void Prepare(Application app) {
  }

  override protected void Go(Application app) {
    for (int i = 0; i < keys.Count; i++) {
      app.Insert(keys[i], values[i]);
    }
    app.Sync();
  }
}

class BenchmarkRandomQueries : Benchmark {
  public override string Name { get { return "RandomQueries"; } }

  List<byte[]> keys;
  List<byte[]> values;
  List<byte[]> query_keys;

  public BenchmarkRandomQueries() {
    int seed1 = 1234;
    int seed2 = 527;
    int seed3 = 19232;
    keys = RandomKeys(2000, seed1);
    values = RandomValues(2000, seed2);
    query_keys = RandomQueryKeys(2000, seed3, keys);
  }

  override protected void Prepare(Application app) {
    for (int i = 0; i < keys.Count; i++) {
      app.Insert(keys[i], values[i]);
    }
    app.Sync();
    app.crash();
  }

  override protected void Go(Application app) {
    for (int i = 0; i < query_keys.Count; i++) {
      app.Query(query_keys[i]);
    }
  }
}

class BenchmarkSequentialInserts : Benchmark {
  public override string Name { get { return "SeqentialInserts"; } }

  List<byte[]> keys;
  List<byte[]> values;

  public BenchmarkSequentialInserts() {
    int seed1 = 1234;
    int seed2 = 527;
    keys = RandomSortedKeys(2000, seed1);
    values = RandomValues(2000, seed2);
  }

  override protected void Prepare(Application app) {
  }

  override protected void Go(Application app) {
    for (int i = 0; i < keys.Count; i++) {
      app.Insert(keys[i], values[i]);
    }
    app.Sync();
  }
}

class BenchmarkSequentialQueries : Benchmark {
  public override string Name { get { return "SequentialQueries"; } }

  List<byte[]> keys;
  List<byte[]> values;

  public BenchmarkSequentialQueries() {
    int seed1 = 1234;
    int seed2 = 527;
    keys = RandomSortedKeys(2000, seed1);
    values = RandomValues(2000, seed2);
  }

  override protected void Prepare(Application app) {
    for (int i = 0; i < keys.Count; i++) {
      app.Insert(keys[i], values[i]);
    }
    app.Sync();
    app.crash();
  }

  override protected void Go(Application app) {
    for (int i = 0; i < keys.Count; i++) {
      app.Query(keys[i]);
    }
  }
}

class Benchmarks {
  public void RunAllBenchmarks() {
    new BenchmarkRandomQueries().Run();
    new BenchmarkRandomInserts().Run();
    new BenchmarkSequentialQueries().Run();
    new BenchmarkSequentialInserts().Run();
  }
}
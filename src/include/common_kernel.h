/*************************************************************************
 * Copyright (c) 2015-2016, NVIDIA CORPORATION. All rights reserved.
 *
 * See LICENSE.txt for license information
 ************************************************************************/

#ifndef NCCL_COMMON_KERNEL_H_
#define NCCL_COMMON_KERNEL_H_

#include "core.h"
#include <cstdio>
#include <cstdint>

#include <cuda_runtime.h>

// BAR macro and helpers
#define WARP_SIZE 32
#define ROUNDUP(x, y)                                                           \
    (((((x) + (y) - 1) / (y))) * (y))
#define DIVUP(x, y) \
    (((x)+(y)-1)/(y))
#define BAR_EXEC(type, barid, nthreads) \
    asm("bar." #type " " #barid ", " #nthreads ";\n\t")
#define BAR_EXPAND(type, barid, nthreads) \
    BAR_EXEC(type, barid, (nthreads))

// Named barrier macro.
// Expands to asm("bar.type barid, nthreads") where
// nthreads has been rounded up to WARP_SIZE.
#define BAR(type, barid, nthreads) \
    BAR_EXPAND(type, barid, ROUNDUP(nthreads, WARP_SIZE))

__device__ unsigned int spinct;

static __device__ int min(int a, ssize_t b) {
  if (a < b) return a;
  return (int)b;
}

// Spin wait until func evaluates to true
template<typename FUNC>
__device__ inline void Wait(const FUNC& func) {
  while (!func()) {
    // waste time
    atomicInc(&spinct, 10);
  }
}

typedef uint64_t PackType;

// unpack x and y to elements of type T and apply FUNC to each element
template<class FUNC, typename T>
struct MULTI {
  __device__ PackType operator()(const PackType x, const PackType y) const;
};

template<class FUNC>
struct MULTI<FUNC, int8_t> {
  static_assert(sizeof(PackType) == 2 * sizeof(uint32_t),
      "PackType must be twice the size of uint32_t.");
  union converter {
    PackType storage;
    struct {
      uint32_t a, b;
    };
  };

  __device__ PackType operator()(const PackType x, const PackType y) const {
    converter cx, cy, cr;
    cx.storage = x;
    cy.storage = y;

    // for char, we do these as vector ops
    cr.a = FUNC()(cx.a, cy.a);
    cr.b = FUNC()(cx.b, cy.b);

    return cr.storage;
  }
};

template<class FUNC>
struct MULTI<FUNC, uint8_t> {
  static_assert(sizeof(PackType) == 2 * sizeof(uint32_t),
      "PackType must be twice the size of uint32_t.");
  union converter {
    PackType storage;
    struct {
      uint32_t a, b;
    };
  };

  __device__ PackType operator()(const PackType x, const PackType y) const {
    converter cx, cy, cr;
    cx.storage = x;
    cy.storage = y;

    // for char, we do these as vector ops
    cr.a = FUNC()(cx.a, cy.a);
    cr.b = FUNC()(cx.b, cy.b);

    return cr.storage;
  }
};

template<class FUNC>
struct MULTI<FUNC, int32_t> {
  static_assert(sizeof(PackType) == 2 * sizeof(int32_t),
      "PackType must be twice the size of int.");
  union converter {
    PackType storage;
    struct {
      int32_t a, b;
    };
  };

  __device__ PackType operator()(const PackType x, const PackType y) const {
    converter cx, cy, cr;
    cx.storage = x;
    cy.storage = y;

    cr.a = FUNC()(cx.a, cy.a);
    cr.b = FUNC()(cx.b, cy.b);

    return cr.storage;
  }
};

template<class FUNC>
struct MULTI<FUNC, uint32_t> {
  static_assert(sizeof(PackType) == 2 * sizeof(uint32_t),
      "PackType must be twice the size of int.");
  union converter {
    PackType storage;
    struct {
      uint32_t a, b;
    };
  };

  __device__ PackType operator()(const PackType x, const PackType y) const {
    converter cx, cy, cr;
    cx.storage = x;
    cy.storage = y;

    cr.a = FUNC()(cx.a, cy.a);
    cr.b = FUNC()(cx.b, cy.b);

    return cr.storage;
  }
};

template<class FUNC>
struct MULTI<FUNC, half> {
  static_assert(sizeof(PackType) == 2 * sizeof(float),
      "PackType must be twice the size of float.");
  union converter {
    PackType storage;
    struct {
      half2 a, b;
    };
  };

  __device__ PackType operator()(const PackType x, const PackType y) const {
    converter cx, cy, cr;
    cx.storage = x;
    cy.storage = y;

    cr.a = FUNC()(cx.a, cy.a);
    cr.b = FUNC()(cx.b, cy.b);

    return cr.storage;
  }
};

template<class FUNC>
struct MULTI<FUNC, float> {
  static_assert(sizeof(PackType) == 2 * sizeof(float),
      "PackType must be twice the size of float.");
  union converter {
    PackType storage;
    struct {
      float a, b;
    };
  };

  __device__ PackType operator()(const PackType x, const PackType y) const {
    converter cx, cy, cr;
    cx.storage = x;
    cy.storage = y;

    cr.a = FUNC()(cx.a, cy.a);
    cr.b = FUNC()(cx.b, cy.b);

    return cr.storage;
  }
};

template<class FUNC>
struct MULTI<FUNC, double> {
  static_assert(sizeof(PackType) == sizeof(double),
      "PackType must be the same size as double.");
  __device__ PackType operator()(const PackType x, const PackType y) const {
    double rv = FUNC()(__longlong_as_double(x), __longlong_as_double(y));
    return __double_as_longlong(rv);
  }
};

template<class FUNC>
struct MULTI<FUNC, uint64_t> {
  static_assert(sizeof(PackType) == sizeof(uint64_t),
      "PackType must be the same size as uint64_t.");
  __device__ PackType operator()(const PackType x, const PackType y) const {
    uint64_t rv = FUNC()(x, y);
    return rv;
  }
};

template<class FUNC>
struct MULTI<FUNC, int64_t> {
  static_assert(sizeof(PackType) == sizeof(int64_t),
      "PackType must be the same size as int64_t.");
  __device__ PackType operator()(const PackType x, const PackType y) const {
    int64_t rv = FUNC()((int64_t)x, (int64_t)y);
    return rv;
  }
};

template<class FUNC, typename T, bool TWO_INPUTS, bool TWO_OUTPUTS>
__device__ inline void ReduceCopy(
    const volatile T * __restrict__ const src0,
    const volatile T * __restrict__ const src1,
    volatile T * __restrict__ const dest0,
    volatile T * __restrict__ const dest1, const int idx) {
  T val = vFetch(src0+idx);
  if (TWO_INPUTS) {
    val = FUNC()(val, vFetch(src1+idx));
  }
  vStore(dest0+idx, val);
  if (TWO_OUTPUTS) {
    vStore(dest1+idx, val);
  }
}

template<class FUNC, typename T, bool TWO_INPUTS, bool TWO_OUTPUTS, int UNROLL, int THREADS>
__device__ inline void ReduceCopy64b(
    const volatile T * __restrict__ const src0,
    const volatile T * __restrict__ const src1,
    volatile T * __restrict__ const dest0,
    volatile T * __restrict__ const dest1, const int offset) {
  PackType t0[UNROLL];
  PackType t1[UNROLL];
  #pragma unroll
  for (int u = 0; u < UNROLL; ++u) {
    int idx = offset + u*THREADS;
    t0[u] = (reinterpret_cast<const volatile PackType *>(src0))[idx];
    if (TWO_INPUTS) {
      t1[u] = (reinterpret_cast<const volatile PackType *>(src1))[idx];
    }
  }
  #pragma unroll
  for (int u = 0; u < UNROLL; ++u) {
    int idx = offset + u*THREADS;
    PackType val = TWO_INPUTS ? MULTI<FUNC, T>()(t0[u], t1[u]) : t0[u];
    (reinterpret_cast<volatile PackType *>(dest0))[idx] = val;
    if (TWO_OUTPUTS) {
      (reinterpret_cast<volatile PackType *>(dest1))[idx] = val;
    }
  }
}

#define ALIGNUP(x, a)   ((((x)-1) & ~((a)-1)) + (a))

template<typename T>
__device__ inline volatile T* AlignUp(volatile T * ptr, size_t align) {
  size_t ptrval = reinterpret_cast<size_t>(ptr);
  return reinterpret_cast<volatile T*>(ALIGNUP(ptrval, align));
}

template<typename T> inline __device__
T vFetch(const volatile T* ptr) {
  return *ptr;
}

template<> inline __device__
half vFetch<half>(const volatile half* ptr) {
  half r;
  r.x = ptr->x;
  return r;
}

template<typename T> inline __device__
void vStore(volatile T* ptr, const T val) {
  *ptr = val;
}

template<> inline __device__
void vStore<half>(volatile half* ptr, const half val) {
  ptr->x = val.x;
}

// Assumptions:
// - there is exactly 1 block
// - THREADS is the number of producer threads
// - this function is called by all producer threads
template<int UNROLL, int THREADS, class FUNC, typename T, bool HAS_DEST1,
    bool HAS_SRC1>
__device__ inline void ReduceOrCopy(const int tid,
    volatile T * __restrict__ dest0, volatile T * __restrict__ dest1,
    const volatile T * __restrict__ src0, const volatile T * __restrict__ src1,
    int N) {
  if (N<=0) {
    return;
  }

  int Npreamble = (N<alignof(PackType)) ? N : AlignUp(dest0, alignof(PackType)) - dest0;

  // stage 0: check if we'll be able to use the fast, 64-bit aligned path.
  // If not, we'll just use the slow preamble path for the whole operation
  bool alignable = (((AlignUp(src0,  alignof(PackType)) == src0  + Npreamble)) &&
      (!HAS_DEST1 || (AlignUp(dest1, alignof(PackType)) == dest1 + Npreamble)) &&
      (!HAS_SRC1  || (AlignUp(src1,  alignof(PackType)) == src1  + Npreamble)));

  if (!alignable) {
    Npreamble = N;
  }

  // stage 1: preamble: handle any elements up to the point of everything coming
  // into alignment
  for (int idx = tid; idx < Npreamble; idx += THREADS) {
    // ought to be no way this is ever more than one iteration, except when
    // alignable is false
    ReduceCopy<FUNC, T, HAS_SRC1, HAS_DEST1>(src0, src1, dest0, dest1, idx);
  }

  // stage 2: fast path: use 64b loads/stores to do the bulk of the work,
  // assuming the pointers we have are all 64-bit alignable.
  if (alignable) {
    const int PackFactor = sizeof(PackType) / sizeof(T);
    int Nrem = N - Npreamble;
    dest0 += Npreamble; if (HAS_DEST1) { dest1 += Npreamble; }
    src0  += Npreamble; if (HAS_SRC1)  { src1  += Npreamble; }

    // stage 2a: main loop
    int Nalign2a = (Nrem / (PackFactor * UNROLL * THREADS))
        * (UNROLL * THREADS); // round down

    #pragma unroll 1 // don't unroll this loop
    for (int idx = tid; idx < Nalign2a; idx += UNROLL * THREADS) {
      ReduceCopy64b<FUNC, T, HAS_SRC1, HAS_DEST1, UNROLL, THREADS>(src0, src1, dest0, dest1, idx);
    }

    int Ndone2a = Nalign2a * PackFactor;
    Nrem -= Ndone2a;

    // stage 2b: slightly less optimized for section when we don't have full
    // UNROLLs

    int Nalign2b = Nrem / PackFactor;

    #pragma unroll 4
    for (int idx = Nalign2a + tid; idx < Nalign2a + Nalign2b; idx += THREADS) {
      ReduceCopy64b<FUNC, T, HAS_SRC1, HAS_DEST1, 1, 0>(src0, src1, dest0, dest1, idx);
    }

    int Ndone2b = Nalign2b * PackFactor;
    Nrem -= Ndone2b;
    int Ndone2 = Ndone2a + Ndone2b;
    dest0 += Ndone2; if (HAS_DEST1) { dest1 += Ndone2; }
    src0  += Ndone2; if (HAS_SRC1)  { src1  += Ndone2; }

    // stage 2c: tail

    for (int idx = tid; idx < Nrem; idx += THREADS) {
      // never ought to make it more than one time through this loop.  only a
      // few threads should even participate
      ReduceCopy<FUNC, T, HAS_SRC1, HAS_DEST1>(src0, src1, dest0, dest1, idx);
    }
  } // done fast path
}

#endif // COMMON_KERNEL_H_

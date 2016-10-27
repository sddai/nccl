#include "transport.h"
#include "core.h"
#include "common_kernel.h"

extern struct ncclTransport p2pTransport;
extern struct ncclTransport shmTransport;
extern struct ncclTransport socketTransport;

struct ncclTransport ncclTransports[NTRANSPORTS] = {
  p2pTransport,
  shmTransport,
  socketTransport
  // mpiTransport
};

static void WaitSync(struct transportProxyInfo* info, int value) {
  pthread_mutex_lock(&info->mutex);
  while (info->sync != value)
    pthread_cond_wait(&info->cond, &info->mutex);
  pthread_mutex_unlock(&info->mutex);
}

static void SetSync(struct transportProxyInfo* info, int value) {
  pthread_mutex_lock(&info->mutex);
  info->sync = value;
  pthread_cond_signal(&info->cond);
  pthread_mutex_unlock(&info->mutex);
}

template <int type>
static void StartProxy(int substeps, int nsteps, struct ncclRing* ring) {
  struct ncclConnector* connector = (type == 0) ? &ring->recv : &ring->send;
  struct transportProxyInfo* info = connector->proxyInfo;
  if (info) {
    struct ncclProxyArgs* args = &info->args;
    args->ring = ring;
    args->substeps = substeps;
    args->nsteps = nsteps;
    //printf("Launching %s proxy, nsteps = %d\n", type == 0 ? "recv" : "send", nsteps);
    WaitSync(info, 0);
    printf("Ready to start thread ...\n");
    SetSync(info, 1);
    printf("Thread signaled.\n");
  }
}

ncclResult_t transportStartProxies(int substeps, int subchunks, int nsteps_per_round, int nblocks_per_round, int size, struct ncclComm* comm) {
  for (int r=0; r<comm->nRings; r++) {
    int nrounds = DIVUP(size, comm->nRings * nblocks_per_round * (comm->rings[r].buffSize/subchunks));
    int nsteps = nsteps_per_round * nrounds * substeps;
    StartProxy<0>(substeps*subchunks, nsteps, comm->rings+r);
    StartProxy<1>(substeps*subchunks, nsteps, comm->rings+r);
  }
  return ncclSuccess;
}

void* persistentThread(void *opaqueInfo) {
  struct transportProxyInfo* info = (struct transportProxyInfo*)opaqueInfo;
  printf("Proxy initializing context ...\n");
  cudaFree(0);
  SetSync(info, 0);
  printf("Proxy ready, acked\n");
  while (1) {
    WaitSync(info, 1);
    printf("Persistent thread got signal and sync, starting function ...\n");
    ncclResult_t res = info->func(&info->args);
    printf("Function done\n");
    if (res != ncclSuccess) {
      WARN("Persistent proxy : proxy function returned with code %d\n", res);
    }    
    SetSync(info, 0);
    printf("Sync reset\n");
  }
}

ncclResult_t transportCreateProxy(int type, struct ncclRing* ring) {
  struct ncclConnector* connector = (type == 0) ? &ring->recv : &ring->send;
  threadFunc_t proxyfunc = (threadFunc_t) ((type == 0) ? connector->transport->recv.proxy : connector->transport->send.proxy);
  if (proxyfunc) {
    struct transportProxyInfo * info = connector->proxyInfo = (struct transportProxyInfo*)malloc(sizeof(struct transportProxyInfo));
    info->sync = 1;
    info->cond = PTHREAD_COND_INITIALIZER;
    info->mutex = PTHREAD_MUTEX_INITIALIZER;
    info->func = proxyfunc;
    pthread_create(&connector->proxyInfo->thread, NULL, persistentThread, info);
    printf("Waiting for proxy to start and set CUDA CTX\n");
    WaitSync(info, 0);
    printf("Proxy acked\n");
  }
  return ncclSuccess;
}


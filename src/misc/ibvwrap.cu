/*************************************************************************
 * Copyright (c) 2015-2016, NVIDIA CORPORATION. All rights reserved.
 *
 * See LICENSE.txt for license information
 ************************************************************************/

//#define IBV_DIRECT 1
#ifndef IBV_DIRECT
#include "ibvwrap.h"
#include <sys/types.h>
#include <unistd.h>

#include <dlfcn.h>
#include "core.h"

static enum { ibvUninitialized, ibvInitializing, ibvInitialized, ibvError } ibvState = ibvUninitialized;

struct ibv_device** (*ibv_internal_get_device_list)(int *num_devices); 
void (*ibv_internal_free_device_list)(struct ibv_device **list);
const char * (*ibv_internal_get_device_name)(struct ibv_device *device);
struct ibv_context* (*ibv_internal_open_device)(struct ibv_device* device);
int (*ibv_internal_close_device)(struct ibv_context *context);
int (*ibv_internal_get_async_event)(struct ibv_context *context, struct ibv_async_event *event);
void (*ibv_internal_ack_async_event)(struct ibv_async_event *event);
int (*ibv_internal_query_device)(struct ibv_context *context, struct ibv_device_attr *device_attr);
int (*ibv_internal_query_port)(struct ibv_context *context, uint8_t port_num, struct ibv_port_attr *port_attr);
struct ibv_pd * (*ibv_internal_alloc_pd)(struct ibv_context *context);
int (*ibv_internal_dealloc_pd)(struct ibv_pd *pd);
struct ibv_mr * (*ibv_internal_reg_mr)(struct ibv_pd *pd, void *addr, size_t length, int access);
int (*ibv_internal_dereg_mr)(struct ibv_mr *mr);
struct ibv_comp_channel * (*ibv_internal_create_comp_channel)(struct ibv_context *context);
struct ibv_cq * (*ibv_internal_create_cq)(struct ibv_context *context, int cqe, void *cq_context, struct ibv_comp_channel *channel, int comp_vector);
int (*ibv_internal_destroy_cq)(struct ibv_cq *cq);
struct ibv_qp * (*ibv_internal_create_qp)(struct ibv_pd *pd, struct ibv_qp_init_attr *qp_init_attr);
int (*ibv_internal_modify_qp)(struct ibv_qp *qp, struct ibv_qp_attr *attr, int attr_mask);
const char * (*ibv_internal_event_type_str)(enum ibv_event_type event);

ncclResult_t wrap_ibv_symbols(void) {
  if (ibvState == ibvInitialized)
    return ncclSuccess;
  if (ibvState == ibvError)
    return ncclSystemError;
  
  if (__sync_bool_compare_and_swap(&ibvState, ibvUninitialized, ibvInitializing) == false) {
    // Another thread raced in front of us. Wait for it to be done.
    while (ibvState == ibvInitializing) pthread_yield();
    return (ibvState == ibvInitialized) ? ncclSuccess : ncclSystemError;
  }

  static void* ibvhandle = NULL;
  void* tmp;
  void** cast;

  ibvhandle=dlopen("libibverbs.so", RTLD_NOW);
  if (!ibvhandle) {
    ibvhandle=dlopen("libibverbs.so.1", RTLD_NOW);
    if (!ibvhandle) {
      WARN("Failed to open libibverbs.so[.1]");
      goto teardown;
    }
  }

  #define LOAD_SYM(handle, symbol, funcptr) do {         \
    cast = (void**)&funcptr;                             \
    tmp = dlsym(handle, symbol);                         \
    if (tmp == NULL) {                                   \
      WARN("dlsym failed on %s - %s", symbol, dlerror());\
      goto teardown;                                     \
    }                                                    \
    *cast = tmp;                                         \
  } while (0)

  LOAD_SYM(ibvhandle, "ibv_get_device_list", ibv_internal_get_device_list);
  LOAD_SYM(ibvhandle, "ibv_free_device_list", ibv_internal_free_device_list);
  LOAD_SYM(ibvhandle, "ibv_get_device_name", ibv_internal_get_device_name);
  LOAD_SYM(ibvhandle, "ibv_open_device", ibv_internal_open_device);
  LOAD_SYM(ibvhandle, "ibv_close_device", ibv_internal_close_device);
  LOAD_SYM(ibvhandle, "ibv_get_async_event", ibv_internal_get_async_event);
  LOAD_SYM(ibvhandle, "ibv_ack_async_event", ibv_internal_ack_async_event);
  LOAD_SYM(ibvhandle, "ibv_query_device", ibv_internal_query_device);
  LOAD_SYM(ibvhandle, "ibv_query_port", ibv_internal_query_port);
  LOAD_SYM(ibvhandle, "ibv_alloc_pd", ibv_internal_alloc_pd);
  LOAD_SYM(ibvhandle, "ibv_dealloc_pd", ibv_internal_dealloc_pd);
  LOAD_SYM(ibvhandle, "ibv_reg_mr", ibv_internal_reg_mr);
  LOAD_SYM(ibvhandle, "ibv_dereg_mr", ibv_internal_dereg_mr);
  LOAD_SYM(ibvhandle, "ibv_create_comp_channel", ibv_internal_create_comp_channel);
  LOAD_SYM(ibvhandle, "ibv_create_cq", ibv_internal_create_cq);
  LOAD_SYM(ibvhandle, "ibv_destroy_cq", ibv_internal_destroy_cq);
  LOAD_SYM(ibvhandle, "ibv_create_qp", ibv_internal_create_qp);
  LOAD_SYM(ibvhandle, "ibv_modify_qp", ibv_internal_modify_qp);
  LOAD_SYM(ibvhandle, "ibv_event_type_str", ibv_internal_event_type_str);

  ibvState = ibvInitialized;
  return ncclSuccess;

  teardown:
  ibv_internal_get_device_list = NULL;
  ibv_internal_free_device_list = NULL;
  ibv_internal_get_device_name = NULL;
  ibv_internal_open_device = NULL;
  ibv_internal_close_device = NULL;
  ibv_internal_get_async_event = NULL;
  ibv_internal_ack_async_event = NULL;
  ibv_internal_query_device = NULL;
  ibv_internal_query_port = NULL;
  ibv_internal_alloc_pd = NULL;
  ibv_internal_dealloc_pd = NULL;
  ibv_internal_reg_mr = NULL;
  ibv_internal_dereg_mr = NULL;
  ibv_internal_create_comp_channel = NULL;
  ibv_internal_create_cq = NULL;
  ibv_internal_destroy_cq = NULL;
  ibv_internal_create_qp = NULL;
  ibv_internal_modify_qp = NULL;
  ibv_internal_event_type_str = NULL;

  if (ibvhandle != NULL) dlclose(ibvhandle);
  ibvState = ibvError;
  return ncclSystemError;
}

struct ibv_device **wrap_ibv_get_device_list(int *num_devices) {
  if (ibv_internal_get_device_list == NULL) {
     WARN("lib wrapper not initialized.");
     exit(-1);
  }
  return ibv_internal_get_device_list(num_devices);
}

void wrap_ibv_free_device_list(struct ibv_device **list) {
  if (ibv_internal_free_device_list == NULL) {
     WARN("lib wrapper not initialized.");
     exit(-1);
  }
  ibv_internal_free_device_list(list);
}

const char *wrap_ibv_get_device_name(struct ibv_device *device) {
  if (ibv_internal_get_device_name == NULL) {
     WARN("lib wrapper not initialized.");
     exit(-1);
  }
  return ibv_internal_get_device_name(device);
}

struct ibv_context *wrap_ibv_open_device(struct ibv_device *device) { /*returns 0 on success, -1 on failure*/
  INFO("dynloaded ibv_open_device");
  if (ibv_internal_open_device == NULL) {
     WARN("lib wrapper not initialized.");
     exit(-1);
  }
  return ibv_internal_open_device(device);
}

int wrap_ibv_close_device(struct ibv_context *context) { /*returns 0 on success, -1 on failure*/
  if (ibv_internal_close_device == NULL) {
     WARN("lib wrapper not initialized.");
     exit(-1);
  }
  int ret = ibv_internal_close_device(context);
  if (ret != IBV_SUCCESS) {
    WARN("ibv_close_device() failed");
    return ret; 
  }
  return ncclSuccess;
}

int wrap_ibv_get_async_event(struct ibv_context *context, struct ibv_async_event *event) { /*returns 0 on success, and -1 on error*/
  if (ibv_internal_get_async_event == NULL) {
     WARN("lib wrapper not initialized.");
     exit(-1);
  }
  int ret = ibv_internal_get_async_event(context, event);
  if (ret < IBV_SUCCESS) {
    WARN("ibv_get_async_event() failed");
    return ret; 
  }
  return ncclSuccess;
}

void wrap_ibv_ack_async_event(struct ibv_async_event *event) {
  if (ibv_internal_ack_async_event == NULL) {
     WARN("lib wrapper not initialized.");
     exit(-1);
  }
  ibv_internal_ack_async_event(event);
}

int wrap_ibv_query_device(struct ibv_context *context, struct ibv_device_attr *device_attr) { /*returns 0 on success, or the value of errno on failure (which indicates the failure reason)*/
  if (ibv_internal_query_device == NULL) {
     WARN("lib wrapper not initialized.");
     exit(-1);
  }
  int ret = ibv_internal_query_device(context, device_attr);
  if (ret != IBV_SUCCESS) {
    WARN("ibv_query_device() failed");
    return ret; 
  }
  return ncclSuccess;
}

int wrap_ibv_query_port(struct ibv_context *context, uint8_t port_num, struct ibv_port_attr *port_attr) { /*returns 0 on success, or the value of errno on failure (which indicates the failure reason)*/
  if (ibv_internal_query_port == NULL) {
     WARN("lib wrapper not initialized.");
     exit(-1);
  }
  int ret = ibv_internal_query_port(context, port_num, port_attr);
  if (ret != IBV_SUCCESS) {
    WARN("ibv_query_port() failed");
    return ret; 
  }
  return ncclSuccess;
}

struct ibv_pd *wrap_ibv_alloc_pd(struct ibv_context *context) {
  if (ibv_internal_alloc_pd == NULL) {
     WARN("lib wrapper not initialized.");
     exit(-1);
  }
  return ibv_internal_alloc_pd(context);
}

int wrap_ibv_dealloc_pd(struct ibv_pd *pd) { /*returns 0 on success, or the value of errno on failure (which indicates the failure reason)*/
  if (ibv_internal_dealloc_pd == NULL) {
     WARN("lib wrapper not initialized.");
     exit(-1);
  }
  int ret = ibv_internal_dealloc_pd(pd);
  if (ret != IBV_SUCCESS) {
    WARN("ibv_internal_dealloc_pd() failed");
    return ret; 
  }
  return ncclSuccess;
}

struct ibv_mr *wrap_ibv_reg_mr(struct ibv_pd *pd, void *addr, size_t length, int access) {
  if (ibv_internal_reg_mr == NULL) {
     WARN("lib wrapper not initialized.");
     exit(-1);
  }
  return ibv_internal_reg_mr(pd, addr, length, access);
}

int wrap_ibv_dereg_mr(struct ibv_mr *mr) { /*returns 0 on success, or the value of errno on failure (which indicates the failure reason)*/
  if (ibv_internal_dereg_mr == NULL) {
     WARN("lib wrapper not initialized.");
     exit(-1);
  }
  int ret = ibv_internal_dereg_mr(mr);
  if (ret != IBV_SUCCESS) {
    WARN("ibv_dereg_mr() failed");
    return ret; 
  }
  return ncclSuccess;
}

struct ibv_comp_channel *wrap_ibv_create_comp_channel(struct ibv_context *context) {
  if (ibv_internal_create_comp_channel == NULL) {
     WARN("lib wrapper not initialized.");
     exit(-1);
  }
  return ibv_internal_create_comp_channel(context);
}

struct ibv_cq *wrap_ibv_create_cq(struct ibv_context *context, int cqe, void *cq_context, struct ibv_comp_channel *channel, int comp_vector) {
  if (ibv_internal_create_cq == NULL) {
     WARN("lib wrapper not initialized.");
     exit(-1);
  }
  return ibv_internal_create_cq(context, cqe, cq_context, channel, comp_vector);
}

int wrap_ibv_destroy_cq(struct ibv_cq *cq) {
  if (ibv_internal_destroy_cq == NULL) {
     WARN("lib wrapper not initialized.");
     exit(-1);
  }
  int ret = ibv_internal_destroy_cq(cq);
  if (ret != IBV_SUCCESS) {
    WARN("ibv_destroy_cq() failed");
    return ret; 
  }
  return ncclSuccess;
}

struct ibv_qp *wrap_ibv_create_qp(struct ibv_pd *pd, struct ibv_qp_init_attr *qp_init_attr) {
  if (ibv_internal_create_qp == NULL) {
     WARN("lib wrapper not initialized.");
     exit(-1);
  }
  return ibv_internal_create_qp(pd, qp_init_attr);
}

int wrap_ibv_modify_qp(struct ibv_qp *qp, struct ibv_qp_attr *attr, int attr_mask) { /*returns 0 on success, or the value of errno on failure (which indicates the failure reason)*/
  if (ibv_internal_modify_qp == NULL) {
     WARN("lib wrapper not initialized.");
     exit(-1);
  }
  int ret = ibv_internal_modify_qp(qp, attr, attr_mask);
  if (ret != IBV_SUCCESS) {
    WARN("ibv_modify_qp() failed");
    return ret; 
  }
  return ncclSuccess;
}

const char *wrap_ibv_event_type_str(enum ibv_event_type event) {
  if (ibv_internal_event_type_str == NULL) {
     WARN("lib wrapper not initialized.");
     exit(-1);
  }
  return ibv_internal_event_type_str(event);
}
#endif

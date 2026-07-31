/*
 * Copyright (c) 2026 Stefano Cacciatore
 * SPDX-License-Identifier: MIT
 */

#ifndef FAISSR_API_H
#define FAISSR_API_H

#include <R_ext/Rdynload.h>
#include <Rinternals.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef int (*faissR_c_api_version_fun)(void);

typedef SEXP (*faissR_nn_float32_fun)(
    SEXP x,
    SEXP k,
    SEXP backend,
    SEXP metric,
    SEXP include_self,
    SEXP n_threads);

typedef SEXP (*faissR_nn_float32_output_fun)(
    SEXP x,
    SEXP k,
    SEXP backend,
    SEXP metric,
    SEXP include_self,
    SEXP n_threads,
    SEXP distances);

typedef SEXP (*faissR_nn_cuda_tuned_gpu_fun)(
    SEXP x,
    SEXP k,
    SEXP method,
    SEXP metric,
    SEXP include_self,
    SEXP target_recall);

static inline int faissR_c_api_version(void) {
  faissR_c_api_version_fun fn =
      (faissR_c_api_version_fun) R_GetCCallable(
          "faissR", "faissR_c_api_version");
  return fn();
}

static inline faissR_nn_float32_fun faissR_get_nn_float32(void) {
  return (faissR_nn_float32_fun) R_GetCCallable(
      "faissR", "faissR_nn_float32_call");
}

static inline faissR_nn_float32_output_fun
faissR_get_nn_float32_output(void) {
  return (faissR_nn_float32_output_fun) R_GetCCallable(
      "faissR", "faissR_nn_float32_call_output");
}

static inline faissR_nn_cuda_tuned_gpu_fun
faissR_get_nn_cuda_tuned_gpu(void) {
  return (faissR_nn_cuda_tuned_gpu_fun) R_GetCCallable(
      "faissR", "faissR_nn_cuda_tuned_gpu_call");
}

#ifdef __cplusplus
}
#endif

#endif

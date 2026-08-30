#include <R_ext/Rdynload.h>
#include <Rinternals.h>

extern SEXP faissr_consumer_make_gpu_knn(
    SEXP, SEXP, SEXP, SEXP, SEXP, SEXP);
extern SEXP faissr_consumer_gpu_checksum(SEXP);

static const R_CallMethodDef call_methods[] = {
    {"faissr_consumer_make_gpu_knn",
     (DL_FUNC) &faissr_consumer_make_gpu_knn, 6},
    {"faissr_consumer_gpu_checksum",
     (DL_FUNC) &faissr_consumer_gpu_checksum, 1},
    {NULL, NULL, 0}
};

void attribute_visible R_init_faissRGpuConsumer(DllInfo *dll) {
    R_registerRoutines(dll, NULL, call_methods, NULL, NULL);
    R_useDynamicSymbols(dll, FALSE);
}

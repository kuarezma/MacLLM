#ifndef MTMD_SHIM_H
#define MTMD_SHIM_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

struct llama_context;
struct llama_model;
typedef int32_t llama_pos;

typedef struct mtmd_shim_handle mtmd_shim_handle;

mtmd_shim_handle * mtmd_shim_create(
    const char * mmproj_path,
    struct llama_model * model,
    int32_t n_threads,
    bool use_gpu
);

void mtmd_shim_free(mtmd_shim_handle * handle);

bool mtmd_shim_supports_vision(mtmd_shim_handle * handle);
bool mtmd_shim_supports_audio(mtmd_shim_handle * handle);

/// prompt içinde `<__media__>` işaretçileri; paths ile sayısı eşleşmeli (eksikse başa eklenir).
/// 0 başarı, aksi hata.
int32_t mtmd_shim_eval_prompt(
    mtmd_shim_handle * handle,
    struct llama_context * lctx,
    const char * prompt,
    const char ** media_paths,
    size_t n_media,
    int32_t n_batch,
    llama_pos n_past_in,
    llama_pos * n_past_out
);

#ifdef __cplusplus
}
#endif

#endif

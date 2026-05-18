#include "mtmd_shim.h"

#include "llama.h"
#include "mtmd.h"
#include "mtmd-helper.h"

#include <stdlib.h>
#include <string.h>

struct mtmd_shim_handle {
    mtmd_context * ctx;
};

mtmd_shim_handle * mtmd_shim_create(
    const char * mmproj_path,
    struct llama_model * model,
    int32_t n_threads,
    bool use_gpu
) {
    if (!mmproj_path || !model) {
        return NULL;
    }
    struct mtmd_context_params params = mtmd_context_params_default();
    params.use_gpu = use_gpu;
    params.n_threads = n_threads > 0 ? n_threads : 4;
    params.print_timings = false;
    params.warmup = true;

    mtmd_context * ctx = mtmd_init_from_file(mmproj_path, model, params);
    if (!ctx) {
        return NULL;
    }
    mtmd_shim_handle * handle = calloc(1, sizeof(mtmd_shim_handle));
    if (!handle) {
        mtmd_free(ctx);
        return NULL;
    }
    handle->ctx = ctx;
    return handle;
}

void mtmd_shim_free(mtmd_shim_handle * handle) {
    if (!handle) {
        return;
    }
    if (handle->ctx) {
        mtmd_free(handle->ctx);
    }
    free(handle);
}

bool mtmd_shim_supports_vision(mtmd_shim_handle * handle) {
    return handle && handle->ctx && mtmd_support_vision(handle->ctx);
}

bool mtmd_shim_supports_audio(mtmd_shim_handle * handle) {
    return handle && handle->ctx && mtmd_support_audio(handle->ctx);
}

static size_t count_marker(const char * text, const char * marker) {
    if (!text || !marker || marker[0] == '\0') {
        return 0;
    }
    size_t count = 0;
    const char * pos = text;
    const size_t len = strlen(marker);
    while ((pos = strstr(pos, marker)) != NULL) {
        count++;
        pos += len;
    }
    return count;
}

int32_t mtmd_shim_eval_prompt(
    mtmd_shim_handle * handle,
    struct llama_context * lctx,
    const char * prompt,
    const char ** media_paths,
    size_t n_media,
    int32_t n_batch,
    llama_pos n_past_in,
    llama_pos * n_past_out
) {
    if (!handle || !handle->ctx || !lctx || !prompt || !n_past_out) {
        return -1;
    }
    if (n_media == 0) {
        return -2;
    }

    const char * marker = mtmd_default_marker();
    char * prompt_buf = NULL;
    const char * prompt_use = prompt;

    size_t markers = count_marker(prompt, marker);
    if (markers < n_media) {
        const size_t extra = n_media - markers;
        const size_t marker_len = strlen(marker);
        const size_t prompt_len = strlen(prompt);
        const size_t buf_len = extra * marker_len + prompt_len + 1;
        prompt_buf = malloc(buf_len);
        if (!prompt_buf) {
            return -3;
        }
        size_t offset = 0;
        for (size_t i = 0; i < extra; i++) {
            memcpy(prompt_buf + offset, marker, marker_len);
            offset += marker_len;
        }
        memcpy(prompt_buf + offset, prompt, prompt_len + 1);
        prompt_use = prompt_buf;
    }

    mtmd_bitmap ** bitmaps = calloc(n_media, sizeof(mtmd_bitmap *));
    if (!bitmaps) {
        free(prompt_buf);
        return -4;
    }

    for (size_t i = 0; i < n_media; i++) {
        bitmaps[i] = mtmd_helper_bitmap_init_from_file(handle->ctx, media_paths[i]);
        if (!bitmaps[i]) {
            for (size_t j = 0; j < i; j++) {
                mtmd_bitmap_free(bitmaps[j]);
            }
            free(bitmaps);
            free(prompt_buf);
            return -5;
        }
    }

    mtmd_input_chunks * chunks = mtmd_input_chunks_init();
    if (!chunks) {
        for (size_t i = 0; i < n_media; i++) {
            mtmd_bitmap_free(bitmaps[i]);
        }
        free(bitmaps);
        free(prompt_buf);
        return -6;
    }

    mtmd_input_text text = {
        .text = prompt_use,
        .add_special = n_past_in == 0,
        .parse_special = true,
    };

    int32_t tok_res = mtmd_tokenize(
        handle->ctx,
        chunks,
        &text,
        (const mtmd_bitmap **) bitmaps,
        n_media
    );

    for (size_t i = 0; i < n_media; i++) {
        mtmd_bitmap_free(bitmaps[i]);
    }
    free(bitmaps);
    free(prompt_buf);

    if (tok_res != 0) {
        mtmd_input_chunks_free(chunks);
        return tok_res + 10;
    }

    llama_pos new_n_past = n_past_in;
    int32_t eval_res = mtmd_helper_eval_chunks(
        handle->ctx,
        lctx,
        chunks,
        n_past_in,
        0,
        n_batch > 0 ? n_batch : 512,
        true,
        &new_n_past
    );

    mtmd_input_chunks_free(chunks);

    if (eval_res != 0) {
        return eval_res + 20;
    }

    *n_past_out = new_n_past;
    return 0;
}

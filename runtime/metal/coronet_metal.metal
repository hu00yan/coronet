#include <metal_stdlib>
#include <metal_simdgroup>
using namespace metal;

// Coronet Metal GPU Runtime: Interaction Calculus & Vector Stream Reduction Kernel
// Architecture: Native Warp-Aggregated Parallel Reducer & Vector Compute for Apple Silicon (UMA)

#define TAG_MASK   (0x7FU)
#define SUB_MASK   (1U << 7)
#define LAB_MASK   (0xFFU)
#define LOC_MASK   (0xFFFFU)
#define LAB_SHIFT  (8)
#define LOC_SHIFT  (16)

// Tags
#define TAG_DP0 0x00
#define TAG_DP1 0x01
#define TAG_VAR 0x02
#define TAG_SUB 0x03
#define TAG_REF 0x04
#define TAG_LET 0x05
#define TAG_APP 0x06
#define TAG_MAT 0x08
#define TAG_IFL 0x09
#define TAG_SWI 0x0A
#define TAG_OPX 0x0B
#define TAG_OPY 0x0C
#define TAG_ERA 0x0D
#define TAG_LAM 0x0E
#define TAG_SUP 0x0F
#define TAG_CTR 0x10
#define TAG_W32 0x11
#define TAG_CHR 0x12

// Operators
#define OP_ADD 0x00
#define OP_SUB 0x01
#define OP_MUL 0x02
#define OP_DIV 0x03
#define OP_MOD 0x04
#define OP_EQ  0x05
#define OP_NE  0x06
#define OP_LT  0x07
#define OP_GT  0x08
#define OP_AND 0x09
#define OP_OR  0x0A
#define OP_XOR 0x0B
#define OP_SHL 0x0C
#define OP_SHR 0x0D

typedef uchar  Tag;
typedef uchar  Lab;
typedef ushort Loc;
typedef uint   Term;

inline Tag  metal_tag(Term t) { return (Tag)(t & TAG_MASK); }
inline bool metal_sub(Term t) { return (bool)((t >> 7) & 1); }
inline Lab  metal_lab(Term t) { return (Lab)((t >> LAB_SHIFT) & LAB_MASK); }
inline Loc  metal_loc(Term t) { return (Loc)((t >> LOC_SHIFT) & LOC_MASK); }
inline Term metal_set_sub(Term t)  { return t | SUB_MASK; }
inline Term metal_rem_sub(Term t)  { return t & ~SUB_MASK; }

inline Term metal_term_new(Tag tg, Lab lb, Loc lc) {
    return ((Term)tg) | (((Term)lb) << LAB_SHIFT) | (((Term)lc) << LOC_SHIFT);
}

struct RedexPair {
    Term fst;
    Term snd;
};

// 1. High-Throughput Interaction Net Graph Rewriting Step with SIMD Group Aggregation
kernel void coronet_metal_reduce_step(
    device atomic_uint*       heap        [[buffer(0)]],
    device const RedexPair*   rbag_in     [[buffer(1)]],
    device RedexPair*         rbag_out    [[buffer(2)]],
    constant uint&            in_count    [[buffer(3)]],
    device atomic_uint*       out_count   [[buffer(4)]],
    device atomic_uint*       alloc_head  [[buffer(5)]],
    device atomic_uint*       itrs        [[buffer(6)]],
    uint                      gid         [[thread_position_in_grid]],
    uint                      lid         [[thread_position_in_threadgroup]],
    uint                      simd_lane   [[thread_index_in_simdgroup]]
) {
    bool has_work = (gid < in_count);
    RedexPair out_pair = {0, 0};
    uint has_out = 0;
    uint local_itrs = 0;

    if (has_work) {
        RedexPair pair = rbag_in[gid];
        Term a = pair.fst;
        Term b = pair.snd;

        Tag tag_a = metal_tag(a);
        Tag tag_b = metal_tag(b);

        if (tag_a > tag_b) {
            Term tmp_t = a; a = b; b = tmp_t;
            Tag tmp_g = tag_a; tag_a = tag_b; tag_b = tmp_g;
        }

        // APP - LAM Interaction
        if (tag_a == TAG_APP && tag_b == TAG_LAM) {
            Loc app_loc = metal_loc(a);
            Loc lam_loc = metal_loc(b);

            Term bod = atomic_load_explicit(&heap[lam_loc + 0], memory_order_relaxed);
            Term arg = atomic_load_explicit(&heap[app_loc + 1], memory_order_relaxed);

            atomic_store_explicit(&heap[lam_loc + 0], metal_set_sub(arg), memory_order_relaxed);
            local_itrs++;

            out_pair = RedexPair{ bod, metal_term_new(TAG_VAR, 0, lam_loc + 0) };
            has_out = 1;
        }
        // OPX - W32 Setup
        else if (tag_a == TAG_OPX && tag_b == TAG_W32) {
            Loc opx_loc = metal_loc(a);
            Lab op = metal_lab(a);

            atomic_store_explicit(&heap[opx_loc + 1], b, memory_order_relaxed);
            local_itrs++;

            out_pair = RedexPair{ metal_term_new(TAG_OPY, op, opx_loc), atomic_load_explicit(&heap[opx_loc + 0], memory_order_relaxed) };
            has_out = 1;
        }
        // OPY - W32 Arithmetic
        else if (tag_a == TAG_OPY && tag_b == TAG_W32) {
            Loc opy_loc = metal_loc(a);
            Lab op = metal_lab(a);

            Term x_term = atomic_load_explicit(&heap[opy_loc + 1], memory_order_relaxed);
            uint x = (uint)metal_loc(x_term);
            uint y = (uint)metal_loc(b);
            uint res = 0;

            switch (op) {
                case OP_ADD: res = x + y; break;
                case OP_SUB: res = x - y; break;
                case OP_MUL: res = x * y; break;
                case OP_DIV: res = (y != 0) ? (x / y) : 0; break;
                case OP_MOD: res = (y != 0) ? (x % y) : 0; break;
                case OP_EQ:  res = (x == y) ? 1 : 0; break;
                case OP_NE:  res = (x != y) ? 1 : 0; break;
                case OP_LT:  res = (x < y) ? 1 : 0; break;
                case OP_GT:  res = (x > y) ? 1 : 0; break;
                case OP_AND: res = x & y; break;
                case OP_OR:  res = x | y; break;
                case OP_XOR: res = x ^ y; break;
                case OP_SHL: res = x << (y & 15); break;
                case OP_SHR: res = x >> (y & 15); break;
                default: res = 0; break;
            }

            atomic_store_explicit(&heap[opy_loc], metal_set_sub(metal_term_new(TAG_W32, 0, (Loc)(res & 0xFFFF))), memory_order_relaxed);
            local_itrs++;
        }
        // DUP - SUP Projection
        else if ((tag_a == TAG_DP0 || tag_a == TAG_DP1) && tag_b == TAG_SUP) {
            Lab dup_lab = metal_lab(a);
            Lab sup_lab = metal_lab(b);
            Loc dup_loc = metal_loc(a);
            Loc sup_loc = metal_loc(b);

            if (dup_lab == sup_lab) {
                Term tm0 = atomic_load_explicit(&heap[sup_loc + 0], memory_order_relaxed);
                Term tm1 = atomic_load_explicit(&heap[sup_loc + 1], memory_order_relaxed);

                if (tag_a == TAG_DP0) {
                    atomic_store_explicit(&heap[dup_loc], metal_set_sub(tm1), memory_order_relaxed);
                    out_pair = RedexPair{ tm0, metal_term_new(TAG_VAR, 0, dup_loc) };
                } else {
                    atomic_store_explicit(&heap[dup_loc], metal_set_sub(tm0), memory_order_relaxed);
                    out_pair = RedexPair{ tm1, metal_term_new(TAG_VAR, 0, dup_loc) };
                }
                local_itrs++;
                has_out = 1;
            }
        }
        // SWI - W32 Branch
        else if (tag_a == TAG_SWI && tag_b == TAG_W32) {
            Loc swi_loc = metal_loc(a);
            uint cond = (uint)metal_loc(b);

            Term zero_br = atomic_load_explicit(&heap[swi_loc + 0], memory_order_relaxed);
            Term succ_br = atomic_load_explicit(&heap[swi_loc + 1], memory_order_relaxed);

            local_itrs++;
            if (cond == 0) {
                out_pair = RedexPair{ zero_br, metal_term_new(TAG_VAR, 0, swi_loc) };
                has_out = 1;
            } else {
                uint new_nodes = atomic_fetch_add_explicit(alloc_head, 2, memory_order_relaxed);
                atomic_store_explicit(&heap[new_nodes + 0], succ_br, memory_order_relaxed);
                atomic_store_explicit(&heap[new_nodes + 1], metal_term_new(TAG_W32, 0, (Loc)(cond - 1)), memory_order_relaxed);
                out_pair = RedexPair{ metal_term_new(TAG_APP, 0, (Loc)new_nodes), metal_term_new(TAG_VAR, 0, swi_loc) };
                has_out = 1;
            }
        }
        // VAR Dereference
        else if (tag_a == TAG_VAR) {
            Loc var_loc = metal_loc(a);
            Term subst = atomic_load_explicit(&heap[var_loc], memory_order_relaxed);
            if (metal_sub(subst)) {
                local_itrs++;
                out_pair = RedexPair{ metal_rem_sub(subst), b };
                has_out = 1;
            } else {
                out_pair = RedexPair{ a, b };
                has_out = 1;
            }
        }
    }

    // SIMD Group Collective Queue Enqueue: Eliminates Atomic Bottleneck
    uint lane_offset = simd_prefix_exclusive_sum(has_out);
    uint warp_total_out = simd_sum(has_out);

    uint warp_base_slot = 0;
    if (simd_lane == 0 && warp_total_out > 0) {
        warp_base_slot = atomic_fetch_add_explicit(out_count, warp_total_out, memory_order_relaxed);
    }
    warp_base_slot = simd_broadcast(warp_base_slot, 0);

    if (has_out) {
        rbag_out[warp_base_slot + lane_offset] = out_pair;
    }

    // SIMD Group Interaction Counter Aggregation
    uint warp_itrs = simd_sum(local_itrs);
    if (simd_lane == 0 && warp_itrs > 0) {
        atomic_fetch_add_explicit(itrs, warp_itrs, memory_order_relaxed);
    }
}

// 2. High-Performance Vector Inner Product / Stream Fusion Reduction Kernel
// Computes dot(u, v) = sum(u[i] * v[i]) using SIMD group parallel fused multiply-add
kernel void coronet_metal_vector_dot(
    device const uint*        vec_u       [[buffer(0)]],
    device const uint*        vec_v       [[buffer(1)]],
    device atomic_uint*       acc_result  [[buffer(2)]],
    device atomic_uint*       total_itrs  [[buffer(3)]],
    constant uint&            length      [[buffer(4)]],
    uint                      gid         [[thread_position_in_grid]],
    uint                      lid         [[thread_position_in_threadgroup]],
    uint                      simd_lane   [[thread_index_in_simdgroup]]
) {
    uint prod = 0;
    if (gid < length) {
        prod = vec_u[gid] * vec_v[gid];
    }

    // SIMD group reduction
    uint warp_sum = simd_sum(prod);
    uint warp_ops = simd_sum(gid < length ? 2 : 0); // 1 mul + 1 add = 2 ops

    if (simd_lane == 0) {
        if (warp_sum > 0) {
            atomic_fetch_add_explicit(acc_result, warp_sum, memory_order_relaxed);
        }
        if (warp_ops > 0) {
            atomic_fetch_add_explicit(total_itrs, warp_ops, memory_order_relaxed);
        }
    }
}

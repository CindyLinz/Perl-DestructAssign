#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

#include "const-c.inc"

//#define DEBUG
#define PERL_VERSION_DECIMAL(r,v,s) (r*1000000 + v*1000 + s)
#define PERL_DECIMAL_VERSION \
  PERL_VERSION_DECIMAL(PERL_REVISION,PERL_VERSION,PERL_SUBVERSION)
#define PERL_VERSION_GE(r,v,s) \
  (PERL_DECIMAL_VERSION >= PERL_VERSION_DECIMAL(r,v,s))

#ifndef UNLIKELY
#  define UNLIKELY(x) (x)
#endif
#ifndef LIKELY
#  define LIKELY(x) (x)
#endif

#define OPT_MY 1
#define OPT_ALIAS 2

static int sv_alias_get(pTHX_ SV* sv, MAGIC *mg){
#ifdef DEBUG
    puts("sv_alias_get");
#endif
    sv_setsv_flags(sv, mg->mg_obj, SV_GMAGIC);
    return 0;
}
static int sv_alias_set(pTHX_ SV* sv, MAGIC *mg){
#ifdef DEBUG
    puts("sv_alias_set");
#endif
    sv_setsv_flags(mg->mg_obj, sv, 0);
    SvSETMAGIC(mg->mg_obj);
    return 0;
}
static MGVTBL sv_alias_vtbl = {
    sv_alias_get,
    sv_alias_set,
    (U32 (*)(pTHX_ SV*, MAGIC*)) NULL,
    (int (*)(pTHX_ SV*, MAGIC*)) NULL,
    (int (*)(pTHX_ SV*, MAGIC*)) NULL
};

static void prepare_anonlist_node(pTHX_ OP * o, U32 opt);
static void prepare_anonhash_node(pTHX_ OP * o, U32 opt);

static inline void my_sv_set(pTHX_ SV ** dst, SV ** src, U32 is_alias){
    if( src ){
        if( is_alias ){
            sv_magicext(*dst, *src, PERL_MAGIC_ext, &sv_alias_vtbl, NULL, 0);
        }
        else{
            SvGETMAGIC(*src);
            SvSetMagicSV_nosteal(*dst, *src);
        }
    }
    else{
        if( is_alias ){
            warn("take alias on a non-exist magic element");
            SvSetSV(*dst, &PL_sv_undef);
        }
        else{
            SvSetMagicSV(*dst, &PL_sv_undef);
        }
    }
}

static inline int anonlist_set_common(pTHX_ SV * sv, MAGIC * mg, U32 opt){
    SV * src;
    I32 key, i;
    SV ** list_holder = (SV**)(mg->mg_ptr + sizeof(I32*));
    I32 * const_index = *(I32**)mg->mg_ptr;
    I32 nitems = (mg->mg_len - sizeof(I32*)) / sizeof(SV*);

#ifdef DEBUG
    printf("anonlist_set opt=%u, nitems=%d\nconst_index =", (unsigned int)opt, (int)nitems);
    for(i=0; const_index[i]<nitems; ++i)
        printf(" %d", const_index[i]);
    printf(" %d\n", nitems);
#endif

    if( !SvROK(sv) ){
        warn("assign non-ref value but %d to a list pattern", SvTYPE(sv));
        return 0;
    }

    src = SvRV(sv);
    if( SvTYPE(src)!=SVt_PVAV ){
        warn("assign non array ref value but %d ref to a list pattern", SvTYPE(SvRV(sv)));
        return 0;
    }

    key = 0;
    for(i=0; i<nitems; ++i, ++list_holder){
        if( i==*const_index ){
            if( SvOK(*list_holder) )
                key = (I32) SvIV(*list_holder);
            else
                ++key;
            ++const_index;
        }
        else{
            switch( SvTYPE(*list_holder) ){
                case SVt_PVAV:
                    {
                        AV *dst = (AV*)(*list_holder);
                        int magic = SvMAGICAL(dst) != 0;
                        I32 last_key = key < 0 ? -1 : AvFILL((AV*)src);
                        I32 i;
                        SV * sv;

                        ENTER;
                        SAVEFREESV(SvREFCNT_inc_simple_NN((SV*)dst));
                        av_clear(dst);
                        av_extend(dst, last_key+1-key);
                        i = 0;
                        while( key <= last_key ){
                            SV ** ptr_val = av_fetch((AV*)src, key, 0);
                            SV * new_sv;
                            SV ** didstore;
                            new_sv = newSV(0);
                            my_sv_set(aTHX_ &new_sv, ptr_val, i != -*const_index-1 && opt & OPT_ALIAS);
                            didstore = av_store(dst, i, new_sv);
                            if( magic ){
                                if( !didstore )
                                    sv_2mortal(new_sv);
                                SvSETMAGIC(new_sv);
                            }
                            ++i;
                            ++key;
                        }
#if PERL_VERSION_GE(5,14,0)
                        if( PL_delaymagic & DM_ARRAY_ISA )
                            SvSETMAGIC(*list_holder);
#endif
                        LEAVE;
                    }
                    break;
                case SVt_PVHV:
                    {
                        HV *dst = (HV*)(*list_holder);
                        int magic = SvMAGICAL(dst) != 0;
                        I32 last_key = key < 0 ? -1 : AvFILL((AV*)src);
                        I32 i;
                        SV * sv;

                        if( key <= last_key && ((last_key - key) & 1) == 0 )
                            Perl_warner(aTHX_ packWARN(WARN_MISC), "Odd number of elements in hash assignment");

                        ENTER;
                        SAVEFREESV(SvREFCNT_inc_simple_NN((SV*)dst));
                        hv_clear(dst);
                        while( key <= last_key ){
                            SV ** ptr_key = av_fetch((AV*)src, key, 0);
                            SV ** ptr_val = key < last_key ? av_fetch((AV*)src, key+1, 0) : NULL;
                            SV * new_key;
                            SV * new_val;
                            HE * didstore;
                            if( ptr_key )
                                if( SvGMAGICAL(*ptr_key) )
                                    new_key = sv_mortalcopy(*ptr_key);
                                else
                                    new_key = *ptr_key;
                            else
                                new_key = newSV(0);
                            new_val = newSV(0);
                            my_sv_set(aTHX_ &new_val, ptr_val, i != -*const_index-1 && opt & OPT_ALIAS);
                            didstore = hv_store_ent(dst, new_key, new_val, 0);
                            if( magic ){
                                if( !didstore )
                                    sv_2mortal(new_val);
                                SvSETMAGIC(new_val);
                            }
                            key += 2;
                        }
                        LEAVE;
                    }
                    break;
                default:
                    {
                        SV ** ptr_val = av_fetch((AV*)src, key, 0);
                        my_sv_set(aTHX_ list_holder, ptr_val, (i != -*const_index-1 && opt & OPT_ALIAS));
                    }
            }
            if( i == -*const_index-1 )
                ++const_index;
            ++key;
        }
    }
    return 0;
}
static int anonlist_set(pTHX_ SV * sv, MAGIC * mg){
    return anonlist_set_common(aTHX_ sv, mg, 0);
}
static int anonlist_alias_set(pTHX_ SV * sv, MAGIC * mg){
    return anonlist_set_common(aTHX_ sv, mg, OPT_ALIAS);
}

static inline int anonhash_set_common(pTHX_ SV * sv, MAGIC * mg, U32 opt){
    SV * src;
    char *key = "";
    STRLEN keylen = 0;
    I32 i;
    SV ** list_holder = (SV**)(mg->mg_ptr + sizeof(I32*));
    I32 * const_index = *(I32**)mg->mg_ptr;
    I32 nitems = (mg->mg_len - sizeof(I32*)) / sizeof(SV*);

#ifdef DEBUG
    printf("anonhash_set opt=%u\n", (unsigned int)opt);
#endif

    if( !SvROK(sv) ){
        warn("assign non-ref value to a hash pattern");
        return 0;
    }

    src = SvRV(sv);
    if( SvTYPE(src)!=SVt_PVHV ){
        warn("assign non hash ref value to a hash pattern");
        return 0;
    }

    for(i=0; i<nitems; ++i, ++list_holder){
        if( i==*const_index ){
            key = SvPV(*list_holder, keylen);
            ++const_index;
        }
        else{
            SV ** ptr_val = hv_fetch((HV*)src, key, keylen, 0);
            my_sv_set(aTHX_ list_holder, ptr_val, (i != -*const_index-1 && opt & OPT_ALIAS));
            if( i == -*const_index-1 )
                ++const_index;
        }
    }
    return 0;
}
static int anonhash_alias_set(pTHX_ SV * sv, MAGIC * mg){
    return anonhash_set_common(aTHX_ sv, mg, OPT_ALIAS);
}
static int anonhash_set(pTHX_ SV * sv, MAGIC * mg){
    return anonhash_set_common(aTHX_ sv, mg, 0);
}

#define MY_HANDLER_GEN(type) \
    static MGVTBL anon ## type ## _vtbl = { \
        (int (*)(pTHX_ SV*, MAGIC*)) NULL, \
        anon ## type ## _set, \
        (U32 (*)(pTHX_ SV*, MAGIC*)) NULL, \
        (int (*)(pTHX_ SV*, MAGIC*)) NULL, \
        (int (*)(pTHX_ SV*, MAGIC*)) NULL \
    }; \
 \
    static OP * my_pp_anon ## type (pTHX){ \
        dVAR; dSP; dMARK; \
        SV ** body; \
        int nitems = SP-MARK; \
        SV * ret; \
        I32 holder_size = nitems * sizeof(SV*) + sizeof(I32*); \
        char * list_holder = alloca(holder_size); \
 \
        Copy(MARK+1, list_holder + sizeof(I32*), nitems, SV*); \
        *(I32**)list_holder = (I32*)SvPVX(cSVOPx_sv(PL_op->op_sibling)); \
 \
        SP = MARK+1; \
 \
        ret = SETs(sv_2mortal(newSV(0))); \
        SvUPGRADE(ret, SVt_PVMG); \
        sv_magicext(ret, ret, PERL_MAGIC_ext, &anon ## type ## _vtbl, list_holder, holder_size); \
 \
        RETURN; \
    }

MY_HANDLER_GEN(list);
MY_HANDLER_GEN(hash);
MY_HANDLER_GEN(list_alias);
MY_HANDLER_GEN(hash_alias);

static void prepare_anonlisthash_list1(pTHX_ OP *o, U32 opt, UV *const_count, UV *pattern_count){
    OP *kid;
    if( cLISTOPo->op_first->op_type!=OP_PUSHMARK )
        croak("invalid des pattern");
    for(kid=cLISTOPo->op_first->op_sibling; kid; kid=kid->op_sibling)
        switch( kid->op_type ){
            case OP_LIST:
                prepare_anonlisthash_list1(aTHX_ kid, opt, const_count, pattern_count);
                break;
            case OP_ANONLIST:
                ++*pattern_count;
                prepare_anonlist_node(aTHX_ kid, opt);
                kid = kid->op_sibling; /* skip pattern structure op node */
                break;
            case OP_ANONHASH:
                ++*pattern_count;
                prepare_anonhash_node(aTHX_ kid, opt);
                kid = kid->op_sibling; /* skip pattern structure op node */
                break;
            case OP_CONST:
            case OP_UNDEF:
                ++*const_count;
                break;
            case OP_PADAV:
            case OP_PADHV:
            case OP_RV2AV:
            case OP_RV2HV:
                kid->op_flags |= OPf_REF;
                break;
            case OP_PADSV:
            case OP_RV2SV:
                break;
            default:
                croak("invalid des pattern (can't contain %s)", OP_NAME(kid));
        }
}
static void prepare_anonlisthash_list2(pTHX_ OP *o, U32 opt, I32 *const_index_buffer, I32 *p, I32 *q){
    OP *kid;
    for(kid=cLISTOPo->op_first->op_sibling; kid; kid=kid->op_sibling){
        if( kid->op_type == OP_LIST ){
            prepare_anonlisthash_list2(aTHX_ kid, opt, const_index_buffer, p, q);
            continue;
        }
        if( kid->op_type == OP_CONST || kid->op_type == OP_UNDEF )
            const_index_buffer[(*p)++] = *q;
        else if( kid->op_type == OP_ANONLIST || kid->op_type == OP_ANONHASH ){
            const_index_buffer[(*p)++] = -*q-1;
            kid = kid->op_sibling;
        }
        ++*q;
    }
}
static void prepare_anonlisthash_node(pTHX_ OP *o, U32 opt){
    OP *kid;
    UV const_count = 0;
    UV pattern_count = 0;

    prepare_anonlisthash_list1(aTHX_ o, opt, &const_count, &pattern_count);

    {
        I32 * const_index_buffer;
        OP *buffer_op;
        SV *buffer_sv;
        I32 p = 0, q = 0;
        I32 buffer_len = (const_count+pattern_count+1) * sizeof(I32);
        #ifdef DEBUG
        I32 i;
        #endif

        buffer_sv = newSV(buffer_len+1);
        *(SvPVX(buffer_sv)+buffer_len) = '\0';

        const_index_buffer = (I32*)SvPVX(buffer_sv);

        prepare_anonlisthash_list2(aTHX_ o, opt, const_index_buffer, &p, &q);
        const_index_buffer[p] = q;

        #ifdef DEBUG
        printf("const_index:");
        for(i=0; i<=p; ++i)
            printf(" %d", const_index_buffer[i]);
        puts("");
        #endif

        buffer_op = newSVOP(OP_NULL, 0, buffer_sv);
        buffer_op->op_targ = OP_CONST;
        buffer_op->op_sibling = o->op_sibling;
        o->op_sibling = buffer_op;
    }
}

static void prepare_anonlist_node(pTHX_ OP * o, U32 opt){
#ifdef DEBUG
    printf("prepare anonlist node\n");
#endif
    prepare_anonlisthash_node(aTHX_ o, opt);
    if( opt & OPT_ALIAS )
        o->op_ppaddr = my_pp_anonlist_alias;
    else
        o->op_ppaddr = my_pp_anonlist;
}

static void prepare_anonhash_node(pTHX_ OP * o, U32 opt){
#ifdef DEBUG
    printf("prepare anonhash node\n");
#endif
    prepare_anonlisthash_node(aTHX_ o, opt);
    if( opt & OPT_ALIAS )
        o->op_ppaddr = my_pp_anonhash_alias;
    else
        o->op_ppaddr = my_pp_anonhash;
}

static unsigned int traverse_args(pTHX_ U32 opt, unsigned int found_index, OP * o){
    if( o->op_type == OP_NULL ){
        if( o->op_flags & OPf_KIDS ){
            OP *kid;
            for(kid=cUNOPo->op_first; kid; kid=kid->op_sibling)
                found_index = traverse_args(aTHX_ opt, found_index, kid);
        }
        return found_index;
    }

    // use the second kid (the first arg)
    if( found_index==1 ){
        switch( o->op_type ){
           case OP_ANONLIST:
                prepare_anonlist_node(aTHX_ o, opt);
                break;
           case OP_ANONHASH:
                prepare_anonhash_node(aTHX_ o, opt);
                break;
           default:
                croak("des arg must be exactly an anonymous list or anonymous hash");
        }
    }
    else if( found_index==4 ){
        croak("des arg must be exactly an anonymous list or anonymous hash");
    }

    return found_index+1;
}

static OP* my_pp_entersub(pTHX){
    dVAR;
    dMARK; // drop the first pushmark
    dSP;
    POPs; // drop the sub name
#ifdef DEBUG
    printf("my_pp_entersub\n");
#endif
    RETURN;
}

static OP* des_check(pTHX_ OP* o, GV *namegv, SV *ckobj){
    if( o->op_flags & OPf_KIDS ){
        OP *kid;
        unsigned int found_index = 0;
        for(kid=cUNOPo->op_first; kid; kid=kid->op_sibling)
            found_index = traverse_args(aTHX_ 0, found_index, kid);
        o->op_ppaddr = my_pp_entersub;
    }
    return o;
}

static OP* des_alias_check(pTHX_ OP* o, GV *namegv, SV *ckobj){
    if( o->op_flags & OPf_KIDS ){
        OP *kid;
        unsigned int found_index = 0;
        for(kid=cUNOPo->op_first; kid; kid=kid->op_sibling)
            found_index = traverse_args(aTHX_ OPT_ALIAS, found_index, kid);
        o->op_ppaddr = my_pp_entersub;
    }
    return o;
}

#if !PERL_VERSION_GE(5,14,0)
static CV* my_des_cvs[2];
static OP* (*orig_entersub_check)(pTHX_ OP*);
static OP* my_entersub_check(pTHX_ OP* o){
    CV *cv;
    OP *cvop = ((cUNOPo->op_first->op_sibling) ? cUNOPo : ((UNOP*)cUNOPo->op_first))->op_first->op_sibling;
    while( cvop->op_sibling )
        cvop = cvop->op_sibling;
    if( cvop->op_type == OP_RV2CV && !(o->op_private & OPpENTERSUB_AMPER) ){
        SVOP *tmpop = (SVOP*)((UNOP*)cvop)->op_first;
        GV *gv = NULL;
        switch (tmpop->op_type) {
            case OP_GV: {
                gv = cGVOPx_gv(tmpop);
                cv = GvCVu(gv);
                if (!cv)
                    tmpop->op_private |= OPpEARLY_CV;
            } break;
            case OP_CONST: {
                SV *sv = cSVOPx_sv(tmpop);
                if (SvROK(sv) && SvTYPE(SvRV(sv)) == SVt_PVCV)
                    cv = (CV*)SvRV(sv);
            } break;
        }
        if( cv==my_des_cvs[0] )
            return des_check(aTHX_ o, NULL, NULL);
        if( cv==my_des_cvs[1] )
            return des_alias_check(aTHX_ o, NULL, NULL);
    }
    return orig_entersub_check(aTHX_ o);
}
#endif

MODULE = DestructAssign		PACKAGE = DestructAssign		

INCLUDE: const-xs.inc

BOOT:
#if PERL_VERSION_GE(5,14,0)
    cv_set_call_checker(get_cv("DestructAssign::des", TRUE), des_check, &PL_sv_undef);
    cv_set_call_checker(get_cv("DestructAssign::des_alias", TRUE), des_alias_check, &PL_sv_undef);
#else
    my_des_cvs[0] = get_cv("DestructAssign::des", TRUE);
    my_des_cvs[1] = get_cv("DestructAssign::des_alias", TRUE);
    orig_entersub_check = PL_check[OP_ENTERSUB];
    PL_check[OP_ENTERSUB] = my_entersub_check;
#endif

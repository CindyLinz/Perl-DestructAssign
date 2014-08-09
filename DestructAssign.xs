#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

#include "const-c.inc"

//#define DEBUG

static void prepare_anonlist_node(pTHX_ OP * o);
static void prepare_anonhash_node(pTHX_ OP * o);

static int anonlist_set(pTHX_ SV * sv, MAGIC * mg){
    SV * src;
    I32 key, i;
    SV ** list_holder = (SV**)(mg->mg_ptr + sizeof(I32*));
    I32 * const_index = *(I32**)mg->mg_ptr;
    I32 nitems = (mg->mg_len - sizeof(I32*)) / sizeof(SV*);

#ifdef DEBUG
    puts("anonlist_set");
#endif

    if( !SvROK(sv) ){
        warn("assign non-ref value to a list pattern");
        return 0;
    }

    src = SvRV(sv);
    if( SvTYPE(src)!=SVt_PVAV ){
        warn("assign non array ref value to a list pattern");
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
                        AV *dst = MUTABLE_AV(*list_holder);
                        int magic = SvMAGICAL(dst) != 0;
                        I32 last_key = key < 0 ? -1 : av_top_index((AV*)src);
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
                            if( ptr_val )
                                new_sv = newSVsv(*ptr_val);
                            else
                                new_sv = newSV(0);
                            didstore = av_store(dst, i, new_sv);
                            if( magic ){
                                if( !didstore )
                                    sv_2mortal(new_sv);
                                SvSETMAGIC(new_sv);
                            }
                            ++i;
                            ++key;
                        }
                        if( PL_delaymagic & DM_ARRAY_ISA )
                            SvSETMAGIC(*list_holder);
                        LEAVE;
                    }
                    break;
                case SVt_PVHV:
                    {
                        HV *dst = MUTABLE_HV(*list_holder);
                        int magic = SvMAGICAL(dst) != 0;
                        I32 last_key = key < 0 ? -1 : av_top_index((AV*)src);
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
                            if( ptr_val )
                                new_val = newSVsv(*ptr_val);
                            else
                                new_val = newSV(0);
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
                        if( ptr_val ){
                            SvGETMAGIC(*ptr_val);
                            SvSetMagicSV_nosteal(*list_holder, *ptr_val);
                        }
                        else{
                            SvSetMagicSV(*list_holder, &PL_sv_undef);
                        }
                    }
            }
            ++key;
        }
    }
    return 0;
}

static int anonhash_set(pTHX_ SV * sv, MAGIC * mg){
    SV * src;
    char *key = "";
    STRLEN keylen = 0;
    I32 i;
    SV ** list_holder = (SV**)(mg->mg_ptr + sizeof(I32*));
    I32 * const_index = *(I32**)mg->mg_ptr;
    I32 nitems = (mg->mg_len - sizeof(I32*)) / sizeof(SV*);

#ifdef DEBUG
    puts("anonhash_set");
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
            if( ptr_val ){
                SvGETMAGIC(*ptr_val);
                SvSetMagicSV_nosteal(*list_holder, *ptr_val);
            }
            else{
                SvSetSV(*list_holder, &PL_sv_undef);
            }
        }
    }
    return 0;
}

static MGVTBL anonlist_vtbl = {
    (int (*)(pTHX_ SV*, MAGIC*)) NULL,
    anonlist_set,
    (U32 (*)(pTHX_ SV*, MAGIC*)) NULL,
    (int (*)(pTHX_ SV*, MAGIC*)) NULL,
    (int (*)(pTHX_ SV*, MAGIC*)) NULL
};

static MGVTBL anonhash_vtbl = {
    (int (*)(pTHX_ SV*, MAGIC*)) NULL,
    anonhash_set,
    (U32 (*)(pTHX_ SV*, MAGIC*)) NULL,
    (int (*)(pTHX_ SV*, MAGIC*)) NULL,
    (int (*)(pTHX_ SV*, MAGIC*)) NULL
};

static OP * my_pp_anonlist(pTHX){
    dVAR; dSP; dMARK; dTARGET;
    SV ** body;
    int nitems = SP-MARK;
    SV * ret;
    I32 holder_size = nitems * sizeof(SV*) + sizeof(I32*);
    char * list_holder = alloca(holder_size);

    Copy(MARK+1, list_holder + sizeof(I32*), nitems, SV*);
    *(I32**)list_holder = (I32*)SvPV_nolen(TARG);

    SP = MARK+1;

    TOPs = ret = newSV(0);
    SvUPGRADE(ret, SVt_PVMG);
    sv_magicext(ret, ret, PERL_MAGIC_ext, &anonlist_vtbl, list_holder, holder_size);

    RETURN;
}

static OP * my_pp_anonhash(pTHX){
    dVAR; dSP; dMARK; dTARGET;
    SV ** body;
    int nitems = SP-MARK;
    SV * ret;
    I32 holder_size = nitems * sizeof(SV*) + sizeof(I32*);
    char * list_holder = alloca(holder_size);

    Copy(MARK+1, list_holder + sizeof(I32*), nitems, SV*);
    *(I32**)list_holder = (I32*)SvPV_nolen(TARG);

    SP = MARK+1;

    TOPs = ret = newSV(0);
    SvUPGRADE(ret, SVt_PVMG);
    sv_magicext(ret, ret, PERL_MAGIC_ext, &anonhash_vtbl, list_holder, holder_size);

    RETURN;
}

static void prepare_anonlisthash_node(pTHX_ OP *o){
    OP *kid;
    UV const_count = 0;

    if( cLISTOPo->op_first->op_type!=OP_PUSHMARK )
        croak("invalid des pattern");
    for(kid=cLISTOPo->op_first->op_sibling; kid; kid=kid->op_sibling)
        switch( kid->op_type ){
            case OP_ANONLIST:
                prepare_anonlist_node(aTHX_ kid);
                break;
            case OP_ANONHASH:
                prepare_anonhash_node(aTHX_ kid);
                break;
            case OP_CONST:
            case OP_UNDEF:
                ++const_count;
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

    if( UNLIKELY(o->op_targ) ) // for safe.. it should be always 0
        Perl_pad_free(aTHX_ o->op_targ);
    o->op_targ = pad_alloc(o->op_type, SVs_PADTMP);
    {
        dTARG;
        I32 * const_index_buffer;
        char *buffer;
        STRLEN len;
        I32 p = 0, q = 0;
        TARG = PAD_SV(o->op_targ);
        sv_grow(TARG, (const_count+1) * sizeof(I32) + 1);
        buffer = SvPV_force(TARG, len);
        buffer[(const_count+1)*sizeof(I32)] = '\0';
        const_index_buffer = (I32*)SvPV_nolen(TARG);

        const_index_buffer[const_count] = -1;
        for(kid=cLISTOPo->op_first->op_sibling; kid; kid=kid->op_sibling){
            if( kid->op_type == OP_CONST || kid->op_type == OP_UNDEF )
                const_index_buffer[p++] = q;
            ++q;
        }
        const_index_buffer[p] = -1;
    }
}

static void prepare_anonlist_node(pTHX_ OP * o){
#ifdef DEBUG
    printf("prepare anonlist node\n");
#endif
    prepare_anonlisthash_node(aTHX_ o);
    o->op_ppaddr = my_pp_anonlist;
}

static void prepare_anonhash_node(pTHX_ OP * o){
#ifdef DEBUG
    printf("prepare anonhash node\n");
#endif
    prepare_anonlisthash_node(aTHX_ o);
    o->op_ppaddr = my_pp_anonhash;
}

static void prepare_arg_head(pTHX_ OP * o){
#ifdef DEBUG
    printf("prepare arg head %s (%d: %s) %u\n", OP_NAME(o), (int)o->op_type, OP_DESC(o), o->op_private);
#endif

    switch( o->op_type ){
        case OP_ANONLIST:
            prepare_anonlist_node(aTHX_ o);
            break;
        case OP_ANONHASH:
            prepare_anonhash_node(aTHX_ o);
            break;
        case OP_PADSV:
        case OP_PADAV:
        case OP_PADHV:
            return;
        default:
            croak("DestructAssign: Unrecognized pattern");
            break;
    }
}

static unsigned int traverse_args(pTHX_ unsigned int found_index, OP * o){
    if( o->op_type == OP_NULL ){
        if( o->op_flags & OPf_KIDS ){
            OP *kid;
            for(kid=cUNOPo->op_first; kid; kid=kid->op_sibling)
                found_index = traverse_args(aTHX_ found_index, kid);
        }
        return found_index;
    }

    // use the second kid (the first arg)
    if( found_index==1 ){
        switch( o->op_type ){
           case OP_ANONLIST:
                prepare_anonlist_node(aTHX_ o);
                break;
           case OP_ANONHASH:
                prepare_anonhash_node(aTHX_ o);
                break;
            default:
                croak("des arg must be exactly an anonymous list or anonymous hash");
        }
    }
    else if( found_index==3 ){
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

static OP* p_check(pTHX_ OP* o, GV *namegv, SV *ckobj){
    if( o->op_flags & OPf_KIDS ){
        OP *kid;
        unsigned int found_index = 0;
        for(kid=cUNOPo->op_first; kid; kid=kid->op_sibling)
            found_index = traverse_args(aTHX_ found_index, kid);
        o->op_ppaddr = my_pp_entersub;
    }
    return o;
}

MODULE = DestructAssign		PACKAGE = DestructAssign		

INCLUDE: const-xs.inc

BOOT:
    cv_set_call_checker(get_cv("DestructAssign::des", TRUE), p_check, &PL_sv_undef);
    cv_set_call_checker(get_cv("DestructAssign::des_my", TRUE), p_check, &PL_sv_undef);
    cv_set_call_checker(get_cv("DestructAssign::des_alias", TRUE), p_check, &PL_sv_undef);
    cv_set_call_checker(get_cv("DestructAssign::des_my_alias", TRUE), p_check, &PL_sv_undef);

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

/* stuff that should probably be in ppport.h, but isn't */

/* OK, so this is wrong, but it's what 5.6 did. */
#ifndef U_32
#define U_32(nv) ( (U32) I_32(nv) )
#endif

/* blead (5.9) stores these somewhere else, with access macros */
#ifndef COP_SEQ_RANGE_LOW
#define COP_SEQ_RANGE_LOW(sv)  (U_32(SvNVX(sv)))
#define COP_SEQ_RANGE_HIGH(sv) ((U32) SvIVX(sv))
#endif

#ifndef CvISXSUB
#define CvISXSUB(cv) CvXSUB(cv)
#endif

#ifndef CVf_WEAKOUTSIDE
#define CVf_WEAKOUTSIDE 0
#endif

#ifndef CvCONST
#define CvCONST(cv) (0)
#endif

#ifndef AvREIFY_only
#define AvREIFY_only(av) (AvFLAGS(av) = AVf_REIFY)
#endif

#ifndef newSV_type
static SV *
newSV_type(svtype type)
{
    SV *sv;

    sv = newSV(0);
    sv_upgrade(sv, type);
    return sv;
}
#endif

#ifdef DEBUG_CLONE
#define TRACEME(a) warn a;
#else
#define TRACEME(a)
#endif

#define TRACE_SV(action, name, sv) \
    TRACEME(("%s (%s) = 0x%x(%d)\n", action, name, sv, SvREFCNT(sv)))

#define CLONE_KEY(x) ((char *) x) 

#define CLONE_STORE(x,y)						\
do {									\
    if (!hv_store(SEEN, CLONE_KEY(x), PTRSIZE, SvREFCNT_inc(y), 0)) {	\
	SvREFCNT_dec(y); /* Restore the refcount */			\
	croak("Can't store clone in seen hash (HSEEN)");		\
    }									\
    else {	\
  TRACE_SV("ref", "SEEN", x);                           \
  TRACE_SV("clone", "SEEN", y);                         \
    }									\
} while (0)

#define CLONE_FETCH(x) (hv_fetch(SEEN, CLONE_KEY(x), PTRSIZE, 0))

static void hv_clone        (HV *SEEN, HV *ref, HV *clone);
static void av_clone        (HV *SEEN, AV *ref, AV *clone);
static SV  *sv_clone        (HV *SEEN, SV *ref);
static CV  *CC_cv_clone     (CV *ref);
static void pad_clone       (HV *SEEN, CV *ref, CV *clone);
static CV  *pad_findscope   (CV *start, SV *ref);

static void
hv_clone(HV *SEEN, HV *ref, HV *clone)
{
    HE *next = NULL;

    TRACE_SV("ref", "HV", ref);

    hv_iterinit(ref);
    while (next = hv_iternext(ref)) {
        SV *key = hv_iterkeysv(next);
        hv_store_ent(clone, key, 
            sv_clone(SEEN, hv_iterval(ref, next)), 0);
    }

    TRACE_SV("clone", "HV", clone);
}

static void
av_clone(HV *SEEN, AV *ref, AV *clone)
{
  SV **svp;
  SV *val = NULL;
  I32 arrlen = 0;
  int i = 0;

  TRACE_SV("ref", "AV", ref);

  if (SvREFCNT(ref) > 1)
    CLONE_STORE(ref, (SV *)clone);

  arrlen = av_len(ref);
  av_extend(clone, arrlen);

  for (i = 0; i <= arrlen; i++) {
      svp = av_fetch(ref, i, 0);
      if (svp)
	av_store(clone, i, sv_clone(SEEN, *svp));
  }

  TRACE_SV("clone", "AV", clone);
}

/* largely taken from pad.c:cv_clone (in op.c in 5.6) */
static CV *
CC_cv_clone(CV *ref)
{
    AV *const rpadlist = CvPADLIST(ref);
    AV *const rname    = (AV *)*av_fetch(rpadlist, 0, FALSE);
    U32       rdepth   = CvDEPTH(ref);
    AV *const rpad     = (AV *)*av_fetch(rpadlist, rdepth, FALSE);
    const I32 fname    = AvFILLp(rname);
    const I32 fpad     = AvFILLp(rpad);
    SV **     prname   = AvARRAY(rname);
    AV *      cpadlist;
    AV *      cname;
    AV *      cpad;
    AV *      a0;
    CV       *clone, *outside;
    I32       ix;

    TRACE_SV("ref", "CV", ref);

    /* CvCONST is only set on a clone if the sub is actually constant */
    if (!CvCLONED(ref) || CvCONST(ref)) {
        /* we shouldn't be cloning a closure prototype */
        assert(!CvCLONE(ref));

        SvREFCNT_inc(ref);
        TRACE_SV("copy", "CV", ref);
        return ref;
    }

    assert(!CvUNIQUE(ref));

    outside = CvOUTSIDE(ref);
    /* we should be cloning an instantiated closure, so CvOUTSIDE
     * shouldn't be a closure prototype */
    assert(!(outside && CvCLONE(outside) && !CvCLONED(outside)));
    assert(CvPADLIST(outside));

    clone = (CV *)newSV_type(SvTYPE(ref));
    CvFLAGS(clone) = CvFLAGS(ref) & ~(CVf_CLONE|CVf_WEAKOUTSIDE);
    CvCLONED_on(clone);

#ifdef USE_ITHREADS
    CvFILE(clone)           = CvISXSUB(ref) ? CvFILE(ref)
                                            : savepv(CvFILE(ref));
#else
    CvFILE(clone)           = CvFILE(ref);
#endif
    CvGV(clone)             = CvGV(ref);
    CvSTASH(clone)          = CvSTASH(ref);
    OP_REFCNT_LOCK;
    CvROOT(clone)           = OpREFCNT_inc(CvROOT(ref));
    OP_REFCNT_UNLOCK;
    CvSTART(clone)          = CvSTART(ref);
    CvOUTSIDE(clone)        = (CV *)SvREFCNT_inc(outside);
#ifdef CvOUTSIDE_SEQ
    CvOUTSIDE_SEQ(clone)    = CvOUTSIDE_SEQ(ref);
#endif

    if (SvPOK(ref))
        sv_setpvn((SV *)clone, SvPVX_const(ref), SvCUR(ref));

    /* create a new padlist, and initial pad */
    cpadlist    = newAV();
    cname       = newAV();
    cpad        = newAV();

    /* create @_ */
    a0 = newAV();
    av_extend(a0, 0);
    av_store(cpad, 0, (SV *)a0);
    AvREIFY_only(a0);

    AvREAL_off(cpadlist);
    av_store(cpadlist, 0, (SV *)cname);
    av_store(cpadlist, 1, (SV *)cpad);

    /* fill in the names of the lexicals */
    av_fill(cpad, fpad);
    for (ix = fname; ix >= 0; ix--)
        av_store(cname, ix, SvREFCNT_inc(prname[ix]));

    CvPADLIST(clone) = cpadlist;

    /* the pad is filled in later, by pad_clone */

    TRACE_SV("clone", "CV", clone);

    return clone;
}

/* mostly stolen from PadWalker */

static void
pad_clone(HV *SEEN, CV *ref, CV *clone)
{
    U32 vdepth = CvDEPTH(clone) ? CvDEPTH(clone) : 1;
    U32 rdepth = CvDEPTH(ref)   ? CvDEPTH(ref)   : 1;
    AV *padn   = (AV *) *av_fetch(CvPADLIST(clone), 0,      FALSE);
    AV *padv   = (AV *) *av_fetch(CvPADLIST(clone), vdepth, FALSE);
    AV *padr   = (AV *) *av_fetch(CvPADLIST(ref),   rdepth, FALSE);
    I32 i;

    TRACE_SV("ref", "pad", ref);

    for (i = av_len(padn); i >= 0; --i) {
        SV  **name_p, *name_sv, **val_p, *val_sv;
        SV  **old_p, *old_sv, *new_sv;
        const char *name;
        CV *lexscope;

        name_p = av_fetch(padn, i, 0);

        if (!name_p || !SvPOKp(*name_p))
            continue;

        name_sv = *name_p;
        name    = SvPVX_const(name_sv);

        if (SvFLAGS(name_sv) & SVpad_OUR)
            continue;

        val_p    = av_fetch(padr, i, 0);
        val_sv   = val_p ? *val_p : &PL_sv_undef;

        TRACE_SV("ref", name, val_sv);

        /* start with the scope that declared the lexical... */
        lexscope = SvFAKE(name_sv) 
            ? pad_findscope(clone, name_sv)
            : clone;

        /* ...and see if there are any outside which aren't UNIQUE */
        while ( lexscope && CvUNIQUE(lexscope) ) {
            lexscope = CvOUTSIDE(lexscope);
        }

        TRACEME(("lexscope: 0x%x%s\n", lexscope, 
            (lexscope && !CvUNIQUE(lexscope) ? "" : " UNIQUE")));

        /* if this lexical was defined in a scope that may run more than
         * once, it needs cloning; otherwise, it doesn't. */
        if ( lexscope && !CvUNIQUE(lexscope) ) {
            new_sv  = sv_clone(SEEN, val_sv);
            
            TRACE_SV("ref, again", name, val_sv);
            TRACE_SV("clone", name, new_sv);
        }
        else {
            new_sv = SvREFCNT_inc(val_sv);
            CLONE_STORE(val_sv, new_sv);

            TRACE_SV("ref, again", name, val_sv);
            TRACE_SV("copy", name, new_sv);
        }

        old_p    = av_fetch(padv, i, 0);
        old_sv   = old_p ? *old_p : &PL_sv_undef;

        /* can't use av_store as the refcounts get wrong */
        (AvARRAY(padv))[i] = new_sv;
        /*av_store(padv, i, SvREFCNT_inc(new_sv));*/

        if ( SvREFCNT(old_sv) > 1 )
            SvREFCNT_dec(old_sv);
        TRACE_SV("drop", name, old_sv);
    }

    TRACE_SV("clone", "pad", target);
}

/* locate the scope in which a lexical was declared */
/* mostly stolen from pad.c:pad_findlex */

static CV *
pad_findscope(CV *scope, SV *name_sv)
{
    const char  *name = SvPVX_const(name_sv);
    U32          seq;
    CV          *last_fake = scope;

    TRACEME(("searching for %s\n", name));

#define SUB(cv) TRACEME(("scope 0x%x:%s%s\n", cv, \
    SvFAKE(cv) ? " FAKE" : "", \
    CvUNIQUE(cv) ? " UNIQUE" : ""))

#ifdef CvOUTSIDE_SEQ
#define MOVE_OUT(scp, sq) sq = CvOUTSIDE_SEQ(scp), scp = CvOUTSIDE(scp)
#else
    seq = SvIVX(name_sv);
#define MOVE_OUT(scp, sq) scp = CvOUTSIDE(scp)
#endif

    SUB(scope);

    for ( MOVE_OUT(scope, seq); scope; MOVE_OUT(scope, seq) ) {
        SV **svp, *sv;
        AV  *padlist, *padn;
        I32  off;

        SUB(scope);

        padlist = CvPADLIST(scope);
        if (!padlist) /* an undef CV */
            continue;

        svp = av_fetch(padlist, 0, FALSE);
        if (!svp || *svp == &PL_sv_undef)
            continue;

        padn = (AV *)*svp;
        svp  = AvARRAY(padn);

        for (off = AvFILLp(padn); off > 0; off--) {

            sv = svp[off];
            if (
                !sv || sv == &PL_sv_undef
                || !strEQ(SvPVX_const(sv), name)
            ) {
                continue;
            }

            if (SvFAKE(sv)) {
                last_fake = scope;
                continue;
            }
        
            if (
                seq > COP_SEQ_RANGE_LOW(sv)
                && seq <= COP_SEQ_RANGE_HIGH(sv)
            )
            {
                return scope;
            }
            else {
                TRACEME(("found %s but %x not in [%x, %x]\n",
                    name, seq, COP_SEQ_RANGE_LOW(sv),
                    COP_SEQ_RANGE_HIGH(sv)));
            }
        }
    }

    TRACEME(("no scope found; returning last_fake = 0x%x\n",
        last_fake));
    return last_fake;
}

static SV *
sv_clone(HV *SEEN, SV *ref)
{
    dTHX;
    SV *clone = ref;
    SV **seen = NULL;
    UV visible = (SvREFCNT(ref) > 1);
    int magic_ref = 0;

    TRACE_SV("ref", "SV", ref);

    if ( visible && (seen = CLONE_FETCH(ref)) ) {
        SvREFCNT_inc(*seen);
        TRACE_SV("fetch", "SV", *seen);
        return *seen;
    }

    TRACEME(("switch: (0x%x)\n", ref));
    switch (SvTYPE (ref)) {
        case SVt_NULL:	/* 0 */
            TRACEME(("  NULL\n"));
            clone = newSVsv(ref);
            break;

        case SVt_IV:		/* 1 */
            TRACEME(("  IV\n"));
            /* fall through */

        case SVt_NV:		/* 2 */
            TRACEME(("  NV\n"));
            clone = newSVsv(ref);
            break;

        case SVt_RV:		/* 3 */
            TRACEME(("  RV\n"));
            clone = NEWSV(1002, 0);
            sv_upgrade(clone, SVt_RV);
            break;

        case SVt_PV:		/* 4 */
            TRACEME(("  PV\n"));
            clone = newSVsv(ref);
            break;

        case SVt_PVIV:		/* 5 */
            TRACEME(("  PVIV\n"));
            /* fall through */

        case SVt_PVNV:		/* 6 */
            TRACEME(("  PVNV\n"));
            clone = newSVsv(ref);
            break;

        case SVt_PVMG:	/* 7 */
            TRACEME(("  PVMG\n"));
            clone = newSVsv(ref);
            break;

        case SVt_PVAV:	/* 10 */
            TRACEME(("  AV\n"));
            clone = (SV *)newAV();
            break;

        case SVt_PVHV:	/* 11 */
            TRACEME(("  HV\n"));
            clone = (SV *)newHV();
            break;

        case SVt_PVCV:	/* 12 */
            TRACEME(("  CV\n"));
            clone = (SV *)CC_cv_clone ((CV *) ref);
            break;

#if PERL_VERSION <= 8
        case SVt_PVBM:	/* 8 */
#endif
        case SVt_PVLV:	/* 9 */
        case SVt_PVGV:	/* 13 */
        case SVt_PVFM:	/* 14 */
        case SVt_PVIO:	/* 15 */
            TRACEME(("  default: 0x%x\n", SvTYPE (ref)));
            clone = SvREFCNT_inc(ref);  /* just return the ref */
            break;

        default:
            croak("unknown type of scalar: 0x%x", SvTYPE(ref));
    }

    /**
    * It is *vital* that this is performed *before* recursion,
    * to properly handle circular references. cb 2001-02-06
    */

    if (visible)
        CLONE_STORE(ref,clone);

    /*
     * We'll assume (in the absence of evidence to the contrary) that A) a
     * tied hash/array doesn't store its elements in the usual way (i.e.
     * the mg->mg_object(s) take full responsibility for them) and B) that
     * references aren't tied.
     *
     * If theses assumptions hold, the three options below are mutually
     * exclusive.
     *
     * More precisely: 1 & 2 are probably mutually exclusive; 2 & 3 are 
     * definitely mutually exclusive; we have to test 1 before giving 2
     * a chance; and we'll assume that 1 & 3 are mutually exclusive unless
     * and until we can be test-cased out of our delusion.
     *
     * chocolateboy: 2001-05-29
     */
     
    /* 1: TIED */
    if (SvMAGICAL(ref)) {
        MAGIC* mg;
        MGVTBL *vtable = 0;

        for (mg = SvMAGIC(ref); mg; mg = mg->mg_moremagic) {
            SV *obj = (SV *) NULL;
            /* we don't want to clone a qr (regexp) object */
            /* there are probably other types as well ...  */
            TRACEME(("magic type: %c\n", mg->mg_type));

            /* Some mg_obj's can be null, don't bother cloning */
            if ( mg->mg_obj != NULL ) {
                switch (mg->mg_type) {
                    case 'r':	/* PERL_MAGIC_qr  */
                        obj = mg->mg_obj; 
                        break;

                    case 't':	/* PERL_MAGIC_taint */
                    case '<':	/* PERL_MAGIC_backref */
                        continue;
                        break;

                    default:
                        obj = sv_clone(SEEN, mg->mg_obj); 
                }
            }
            else {
                TRACEME(("magic object for type %c in NULL\n", mg->mg_type));
            }

            magic_ref++;

            /* this is plain old magic, so do the same thing */
            sv_magic(clone, 
                 obj,
                 mg->mg_type, 
                 mg->mg_ptr, 
                 mg->mg_len);
        }

        /* major kludge - why does the vtable for a qr type need to be null? */
        if ( mg = mg_find(clone, 'r') )
            mg->mg_virtual = (MGVTBL *) NULL;
    }

    /* 2: HASH/ARRAY  - (with 'internal' elements) */
    if ( magic_ref ) {
        ;;
    }
    else if ( SvTYPE(ref) == SVt_PVHV ) {
        hv_clone(SEEN, (HV *)ref, (HV *)clone);
    }
    else if ( SvTYPE(ref) == SVt_PVAV ) {
        av_clone(SEEN, (AV *)ref, (AV *)clone);
    }
    else if ( SvTYPE(ref) == SVt_PVCV ) {
        pad_clone(SEEN, (CV *)ref, (CV *)clone);
    }
    /* 3: REFERENCE (inlined for speed) */
    else if (SvROK(ref)) {
        SvROK_on(clone);
        SvRV(clone) = sv_clone(SEEN, SvRV(ref));

        if (sv_isobject(ref)) {
            sv_bless(clone, SvSTASH(SvRV(ref)));
        }
    }

    TRACE_SV("clone", "SV", clone);
    return clone;
}

MODULE = Clone::Closure		PACKAGE = Clone::Closure

PROTOTYPES: ENABLE

void
_clone(ref)
	SV *ref
    PREINIT:
	SV *clone;
        HV *SEEN;
    PPCODE:
        TRACE_SV("ref", "_clone", ref);
        SEEN = get_hv("Clone::Closure::SEEN", 0);
	clone = sv_clone(SEEN, ref);
        TRACE_SV("clone", "_clone", clone);
	EXTEND(SP,1);
	PUSHs(sv_2mortal(clone));

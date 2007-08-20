#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

#ifndef SvPVX_const
#define SvPVX_const(sv) ((const char *) (0 + SvPVX(sv)))
#endif

/* OK, so this is wrong, but it's what 5.6 did. */
#ifndef U_32
#define U_32(nv) ( (U32) I_32(nv) )
#endif

/* blead (5.9) stores these somewhere else, with access macros */
#ifndef COP_SEQ_RANGE_LOW
#define COP_SEQ_RANGE_LOW(sv)  (U_32(SvNVX(sv)))
#define COP_SEQ_RANGE_HIGH(sv) ((U32) SvIVX(sv))
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
    if (!hv_store(HSEEN, CLONE_KEY(x), PTRSIZE, SvREFCNT_inc(y), 0)) {	\
	SvREFCNT_dec(y); /* Restore the refcount */			\
	croak("Can't store clone in seen hash (HSEEN)");		\
    }									\
    else {	\
  TRACE_SV("ref", "SEEN", x);                           \
  TRACE_SV("clone", "SEEN", y);                         \
    }									\
} while (0)

#define CLONE_FETCH(x) (hv_fetch(HSEEN, CLONE_KEY(x), PTRSIZE, 0))

static SV *hv_clone (SV *, SV *, int);
static SV *av_clone (SV *, SV *, int);
static SV *sv_clone (SV *, int);
static SV *rv_clone (SV *, int);
static void pad_clone (SV *, SV *, int);
static CV *pad_findscope(CV *, const char *);

static HV *HSEEN;

static SV *
hv_clone (SV * ref, SV * target, int depth)
{
  HV *clone = (HV *) target;
  HV *self = (HV *) ref;
  HE *next = NULL;
  int recur = depth ? depth - 1 : 0;

  TRACE_SV("ref", "HV", ref);

  hv_iterinit (self);
  while (next = hv_iternext (self)) {
      SV *key = hv_iterkeysv (next);
      hv_store_ent (clone, key, 
                sv_clone (hv_iterval (self, next), recur), 0);
  }

  TRACE_SV("clone", "HV", clone);

  return (SV *) clone;
}

static SV *
av_clone (SV * ref, SV * target, int depth)
{
  AV *clone = (AV *) target;
  AV *self = (AV *) ref;
  SV **svp;
  SV *val = NULL;
  I32 arrlen = 0;
  int i = 0;
  int recur = depth ? depth - 1 : 0;

  TRACE_SV("ref", "AV", ref);

  if (SvREFCNT(ref) > 1)
    CLONE_STORE(ref, (SV *)clone);

  arrlen = av_len (self);
  av_extend (clone, arrlen);

  for (i = 0; i <= arrlen; i++) {
      svp = av_fetch (self, i, 0);
      if (svp)
	av_store (clone, i, sv_clone (*svp, recur));
  }

  TRACE_SV("clone", "AV", clone);
  return (SV *) clone;
}

static SV *
rv_clone (SV * ref, int depth)
{
  SV *clone = NULL;
  SV *rv = NULL;
  UV visible = (SvREFCNT(ref) > 1);

  TRACE_SV("ref", "RV", ref);

  if (!SvROK (ref))
    return NULL;

  if (sv_isobject (ref)) {
      clone = newRV_noinc(sv_clone (SvRV(ref), depth));
      sv_2mortal (sv_bless (clone, SvSTASH (SvRV (ref))));
  }
  else {
      clone = newRV_inc(sv_clone (SvRV(ref), depth));
  }
    
  TRACE_SV("clone", "RV", clone);
  return clone;
}

/* mostly stolen from PadWalker */

static void
pad_clone (SV *ref, SV * target, int depth)
{
    CV *cv     = (CV *)target;
    CV *rcv    = (CV *)ref;
    U32 vdepth = CvDEPTH(cv)  ? CvDEPTH(cv)  : 1;
    U32 rdepth = CvDEPTH(rcv) ? CvDEPTH(rcv) : 1;
    AV *padn   = (AV *) *av_fetch(CvPADLIST(cv),  0,      FALSE);
    AV *padv   = (AV *) *av_fetch(CvPADLIST(cv),  vdepth, FALSE);
    AV *padr   = (AV *) *av_fetch(CvPADLIST(rcv), rdepth, FALSE);
    I32 i;
    int recur = depth ? depth - 1 : 0;

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
        lexscope = SvFAKE(name_sv) ? pad_findscope(cv, name) : cv;

        /* ...and see if there are any outside which aren't UNIQUE */
        while ( lexscope && CvUNIQUE(lexscope) ) {
            lexscope = CvOUTSIDE(lexscope);
        }

        TRACEME(("lexscope: 0x%x%s\n", lexscope, 
            (lexscope && !CvUNIQUE(lexscope) ? "" : " UNIQUE")));

        /* if this lexical was defined in a scope that may run more than
         * once, it needs cloning; otherwise, it doesn't. */
        if ( lexscope && !CvUNIQUE(lexscope) ) {
            new_sv  = sv_clone(val_sv, recur);
            
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
}

/* locate the scope in which a lexical was declared */
/* mostly stolen from pad.c:pad_findlex */

static CV *
pad_findscope(CV *scope, const char *name)
{
    U32  seq;
    CV  *last_fake = scope;

    TRACEME(("searching for %s\n", name));

#define SUB(cv) TRACEME(("scope 0x%x:%s%s\n", cv, \
    SvFAKE(cv) ? " FAKE" : "", \
    CvUNIQUE(cv) ? " UNIQUE" : ""))

#ifdef CvOUTSIDE_SEQ
#define MOVE_OUT(scp, sq) sq = CvOUTSIDE_SEQ(scp), scp = CvOUTSIDE(scp)
#else
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
        
#ifdef CvOUTSIDE_SEQ
            if (
                seq > COP_SEQ_RANGE_LOW(sv)
                && seq <= COP_SEQ_RANGE_HIGH(sv)
            )
#endif
            {
                return scope;
            }
        }
    }

    TRACEME(("no scope found; returning last_fake = 0x%x\n",
        last_fake));
    return last_fake;
}

static SV *
sv_clone (SV * ref, int depth)
{
  dTHX;
  SV *clone = ref;
  SV **seen = NULL;
  UV visible = (SvREFCNT(ref) > 1);
  int magic_ref = 0;

  TRACE_SV("ref", "SV", ref);

  if (depth == 0)
    return SvREFCNT_inc(ref);

  if ( visible && (seen = CLONE_FETCH(ref)) ) {
      SvREFCNT_inc(*seen);
      TRACE_SV("fetch", "SV", *seen);
      return *seen;
  }

  TRACEME(("switch: (0x%x)\n", ref));
  switch (SvTYPE (ref)) {

      case SVt_NULL:	/* 0 */
        TRACEME(("  NULL\n"));
        clone = newSVsv (ref);
        break;

      case SVt_IV:		/* 1 */
        TRACEME(("  IV\n"));
        /* fall through */

      case SVt_NV:		/* 2 */
        TRACEME(("  NV\n"));
        clone = newSVsv (ref);
        break;

      case SVt_RV:		/* 3 */
        TRACEME(("  RV\n"));
        clone = NEWSV(1002, 0);
        sv_upgrade(clone, SVt_RV);
	/* move the following to SvROK section below */
        /* SvROK_on(clone); */
        break;

      case SVt_PV:		/* 4 */
        TRACEME(("  PV\n"));
        clone = newSVsv (ref);
        break;

      case SVt_PVIV:		/* 5 */
        TRACEME (("  PVIV\n"));
        /* fall through */

      case SVt_PVNV:		/* 6 */
        TRACEME (("  PVNV\n"));
        clone = newSVsv (ref);
        break;

      case SVt_PVMG:	/* 7 */
        TRACEME(("  PVMG\n"));
        clone = newSVsv (ref);
        break;

      case SVt_PVAV:	/* 10 */
        TRACEME(("  AV\n"));
        clone = (SV *) newAV();
        break;

      case SVt_PVHV:	/* 11 */
        TRACEME(("  HV\n"));
        clone = (SV *) newHV();
        break;

      case SVt_PVCV:	/* 12 */
        TRACEME(("  CV\n"));
        clone = (SV *) Perl_cv_clone (aTHX_ (CV *) ref);
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

  if ( visible )
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
  if (SvMAGICAL(ref) ) {
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
              obj = sv_clone(mg->mg_obj, -1); 
          }
        } else {
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
    clone = hv_clone (ref, clone, depth);
  }
  else if ( SvTYPE(ref) == SVt_PVAV ) {
    clone = av_clone (ref, clone, depth);
  }
  else if ( SvTYPE(ref) == SVt_PVCV ) {
    pad_clone (ref, clone, depth);
  }
  /* 3: REFERENCE (inlined for speed) */
  else if (SvROK (ref)) {
      SvROK_on(clone);  /* only set if ROK is set if ref */
      SvRV(clone) = sv_clone (SvRV(ref), depth); /* Clone the referent */

      if (sv_isobject (ref)) {
          sv_bless (clone, SvSTASH (SvRV (ref)));
      }
  }

  TRACE_SV("clone", "SV", clone);
  return clone;
}

MODULE = Clone::Closure		PACKAGE = Clone::Closure

PROTOTYPES: ENABLE

BOOT:
/* Initialize HSEEN */
HSEEN = newHV(); if (!HSEEN) croak ("Can't initialize seen hash (HSEEN)");

void
clone(self, depth=-1)
	SV *self
	int depth
	PREINIT:
	SV *    clone = &PL_sv_undef;
	PPCODE:
	clone = sv_clone(self, depth);
        TRACEME(("Done clone, about to clear HSEEN\n"));
	hv_clear(HSEEN);  /* Free HV */
        TRACEME(("Cleared HSEEN\n"));
	EXTEND(SP,1);
	PUSHs(sv_2mortal(clone));

   /*******************************************************/
   /*      "C" Language Integrated Production System      */
   /*                                                     */
   /*            CLIPS Version 6.40  07/30/16             */
   /*                                                     */
   /*                USER FUNCTIONS MODULE                */
   /*******************************************************/

/*************************************************************/
/* Purpose:                                                  */
/*                                                           */
/* Principal Programmer(s):                                  */
/*      Gary D. Riley                                        */
/*                                                           */
/* Contributing Programmer(s):                               */
/*                                                           */
/* Revision History:                                         */
/*                                                           */
/*      6.24: Created file to seperate UserFunctions and     */
/*            EnvUserFunctions from main.c.                  */
/*                                                           */
/*      6.30: Removed conditional code for unsupported       */
/*            compilers/operating systems (IBM_MCW,          */
/*            MAC_MCW, and IBM_TBC).                         */
/*                                                           */
/*            Removed use of void pointers for specific      */
/*            data structures.                               */
/*                                                           */
/*************************************************************/

/***************************************************************************/
/*                                                                         */
/* Permission is hereby granted, free of charge, to any person obtaining   */
/* a copy of this software and associated documentation files (the         */
/* "Software"), to deal in the Software without restriction, including     */
/* without limitation the rights to use, copy, modify, merge, publish,     */
/* distribute, and/or sell copies of the Software, and to permit persons   */
/* to whom the Software is furnished to do so.                             */
/*                                                                         */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS */
/* OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF              */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT   */
/* OF THIRD PARTY RIGHTS. IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY  */
/* CLAIM, OR ANY SPECIAL INDIRECT OR CONSEQUENTIAL DAMAGES, OR ANY DAMAGES */
/* WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN   */
/* ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF */
/* OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.          */
/*                                                                         */
/***************************************************************************/

#include "clips.h"
#include "libpq-fe.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void UserFunctions(Environment *);

/***************************************************************************/
/*                                                                         */
/* Which libpq this is.                                                    */
/*                                                                         */
/* PostgreSQL 14 is the oldest release this binds: it is where pipeline    */
/* mode arrives, and everything older is out of support. What 16, 17 and   */
/* 18 added is bound too, and compiled out when the libpq being built      */
/* against does not have it, so one source builds against any of them.     */
/*                                                                         */
/* The makefile passes the version it pinned, or the one pg_config         */
/* reports. Without it -- someone compiling this file by hand -- the       */
/* feature macros libpq publishes about itself are the next best thing;    */
/* they cannot tell 16 from 15, so that case is read as the older of the   */
/* two and one function goes unbound rather than unresolved.               */
/*                                                                         */
/***************************************************************************/

#ifndef CLIPSPG_PG_VERSION_NUM
#  if defined(LIBPQ_HAS_FULL_PROTOCOL_VERSION)
#    define CLIPSPG_PG_VERSION_NUM 180000
#  elif defined(LIBPQ_HAS_ASYNC_CANCEL)
#    define CLIPSPG_PG_VERSION_NUM 170000
#  elif defined(LIBPQ_HAS_SSL_LIBRARY_DETECTION)
#    define CLIPSPG_PG_VERSION_NUM 150000
#  else
#    define CLIPSPG_PG_VERSION_NUM 140000
#  endif
#endif

#define CLIPSPG_HAVE_16 (CLIPSPG_PG_VERSION_NUM >= 160000)
#define CLIPSPG_HAVE_17 (CLIPSPG_PG_VERSION_NUM >= 170000)
#define CLIPSPG_HAVE_18 (CLIPSPG_PG_VERSION_NUM >= 180000)

#if CLIPSPG_PG_VERSION_NUM < 140000
#error "this libpq is too old for CLIPSPostgreSQL: PostgreSQL 14 or later is needed. Build the vendored libpq with 'make', or point PG_CONFIG at a newer installation."
#endif

#if !defined(LIBPQ_HAS_PIPELINING)
#error "this libpq-fe.h has no pipeline mode, so it predates PostgreSQL 14 whatever the build was told."
#endif

/* A version number that disagrees with the header would compile calls to
   functions the library does not have, and the error would arrive at link
   time naming a symbol rather than a version. These say it here instead. */
#if CLIPSPG_HAVE_17 && !defined(LIBPQ_HAS_ASYNC_CANCEL)
#error "the build says PostgreSQL 17 or later, but this libpq-fe.h is older than that."
#endif

#if CLIPSPG_HAVE_18 && !defined(LIBPQ_HAS_FULL_PROTOCOL_VERSION)
#error "the build says PostgreSQL 18 or later, but this libpq-fe.h is older than that."
#endif

/***************************************************************************/
/*                                                                         */
/* Type OIDs.                                                              */
/*                                                                         */
/* The row mappers decide what a column becomes on the CLIPS side from the */
/* column's type OID. The OIDs of the built-in types are part of           */
/* PostgreSQL's on-the-wire contract and never change, but the header that */
/* names them, catalog/pg_type_d.h, belongs to the server headers and is   */
/* not installed with libpq. The handful that matter here are written out. */
/*                                                                         */
/***************************************************************************/

#define PQ_OID_BOOL        16
#define PQ_OID_INT8        20
#define PQ_OID_INT2        21
#define PQ_OID_INT4        23
#define PQ_OID_OID         26
#define PQ_OID_FLOAT4     700
#define PQ_OID_FLOAT8     701
#define PQ_OID_NUMERIC   1700

/***************************************************************************/
/*                                                                         */
/* Reporting.                                                              */
/*                                                                         */
/* Every wrapper that refuses says so the same way: the CLIPS name of the  */
/* function, the reason, and FALSE to the caller. Nothing here raises a    */
/* CLIPS error -- a refused call is a value the caller can test, which is  */
/* what makes (if (bind ?r (pq-...)) then ...) the idiom throughout.       */
/*                                                                         */
/***************************************************************************/

static void PqFail(
  Environment *theEnv,
  UDFValue *returnValue,
  const char *fname,
  const char *msg)
{
	WriteString(theEnv, STDERR, fname);
	WriteString(theEnv, STDERR, ": ");
	WriteString(theEnv, STDERR, msg);
	WriteString(theEnv, STDERR, "\n");
	returnValue->lexemeValue = FalseSymbol(theEnv);
}

/* The same, with libpq's own account of the failure appended. */
static void PqFailConn(
  Environment *theEnv,
  UDFValue *returnValue,
  const char *fname,
  PGconn *conn)
{
	const char *msg = (conn == NULL) ? NULL : PQerrorMessage(conn);

	WriteString(theEnv, STDERR, fname);
	WriteString(theEnv, STDERR, ": ");
	if (msg == NULL || msg[0] == '\0')
	{
		WriteString(theEnv, STDERR, "the call failed and libpq reports no message\n");
	}
	else
	{
		/* PQerrorMessage already ends in a newline. */
		WriteString(theEnv, STDERR, msg);
		if (msg[strlen(msg) - 1] != '\n')
		{
			WriteString(theEnv, STDERR, "\n");
		}
	}
	returnValue->lexemeValue = FalseSymbol(theEnv);
}

/***************************************************************************/
/*                                                                         */
/* Arguments.                                                              */
/*                                                                         */
/* CLIPS screens literal arguments against the restriction string AddUDF   */
/* is given, but a value that reaches a wrapper through a variable has not */
/* been screened at all: every one of these is checked here as well. The   */
/* helpers hand back NULL, or false, having already written the message    */
/* and set the return value, so a wrapper's guard is one line per          */
/* argument.                                                               */
/*                                                                         */
/***************************************************************************/

/* An external address that is not NULL. The UDFValue is handed back so the
   wrappers that close a handle can clear it in place. */
static void *PqPointerArgument(
  Environment *theEnv,
  UDFContext *context,
  UDFValue *returnValue,
  const char *fname,
  const char *what,
  UDFValue *theArg)
{
	char msg[128];

	if (!UDFNextArgument(context, EXTERNAL_ADDRESS_BIT, theArg) ||
	    theArg->header->type != EXTERNAL_ADDRESS_TYPE)
	{
		snprintf(msg, sizeof msg, "expected a %s pointer", what);
		PqFail(theEnv, returnValue, fname, msg);
		return NULL;
	}

	if (theArg->externalAddressValue->contents == NULL)
	{
		snprintf(msg, sizeof msg, "the %s pointer is NULL", what);
		PqFail(theEnv, returnValue, fname, msg);
		return NULL;
	}

	return theArg->externalAddressValue->contents;
}

static PGconn *PqConnArgument(
  Environment *theEnv,
  UDFContext *context,
  UDFValue *returnValue,
  const char *fname,
  UDFValue *theArg)
{
	return (PGconn *) PqPointerArgument(theEnv, context, returnValue, fname, "connection", theArg);
}

static PGresult *PqResultArgument(
  Environment *theEnv,
  UDFContext *context,
  UDFValue *returnValue,
  const char *fname,
  UDFValue *theArg)
{
	return (PGresult *) PqPointerArgument(theEnv, context, returnValue, fname, "result", theArg);
}

#if CLIPSPG_HAVE_17
static PGcancelConn *PqCancelArgument(
  Environment *theEnv,
  UDFContext *context,
  UDFValue *returnValue,
  const char *fname,
  UDFValue *theArg)
{
	return (PGcancelConn *) PqPointerArgument(theEnv, context, returnValue, fname, "cancel connection", theArg);
}
#endif

/* A symbol or a string. The symbol nil is the way a CLIPS program spells a
   missing value, so where libpq takes a NULL pointer it is accepted here and
   NULL comes back with no error. */
static bool PqTextArgument(
  Environment *theEnv,
  UDFContext *context,
  UDFValue *returnValue,
  const char *fname,
  const char *what,
  bool nilIsNull,
  const char **out)
{
	UDFValue theArg;
	char msg[128];

	if (!UDFNextArgument(context, LEXEME_BITS, &theArg) ||
	    (theArg.header->type != SYMBOL_TYPE && theArg.header->type != STRING_TYPE))
	{
		snprintf(msg, sizeof msg, "expected a symbol or a string for %s", what);
		PqFail(theEnv, returnValue, fname, msg);
		return false;
	}

	if (nilIsNull &&
	    theArg.header->type == SYMBOL_TYPE &&
	    (theArg.lexemeValue == FalseSymbol(theEnv) ||
	     strcmp(theArg.lexemeValue->contents, "nil") == 0))
	{
		*out = NULL;
		return true;
	}

	*out = theArg.lexemeValue->contents;
	return true;
}

static bool PqIntegerArgument(
  Environment *theEnv,
  UDFContext *context,
  UDFValue *returnValue,
  const char *fname,
  const char *what,
  long long *out)
{
	UDFValue theArg;
	char msg[128];

	if (!UDFNextArgument(context, INTEGER_BIT, &theArg) ||
	    theArg.header->type != INTEGER_TYPE)
	{
		snprintf(msg, sizeof msg, "expected an integer for %s", what);
		PqFail(theEnv, returnValue, fname, msg);
		return false;
	}

	*out = theArg.integerValue->contents;
	return true;
}

static bool PqBooleanArgument(
  Environment *theEnv,
  UDFContext *context,
  UDFValue *returnValue,
  const char *fname,
  const char *what,
  bool *out)
{
	UDFValue theArg;
	char msg[128];

	if (!UDFNextArgument(context, LEXEME_BITS, &theArg) ||
	    theArg.header->type != SYMBOL_TYPE ||
	    (theArg.lexemeValue != TrueSymbol(theEnv) &&
	     theArg.lexemeValue != FalseSymbol(theEnv)))
	{
		snprintf(msg, sizeof msg, "expected TRUE or FALSE for %s", what);
		PqFail(theEnv, returnValue, fname, msg);
		return false;
	}

	*out = (theArg.lexemeValue == TrueSymbol(theEnv));
	return true;
}

static bool PqMultifieldArgument(
  Environment *theEnv,
  UDFContext *context,
  UDFValue *returnValue,
  const char *fname,
  const char *what,
  UDFValue *theArg)
{
	char msg[128];

	if (!UDFNextArgument(context, MULTIFIELD_BIT, theArg) ||
	    theArg->header->type != MULTIFIELD_TYPE)
	{
		snprintf(msg, sizeof msg, "expected a multifield for %s", what);
		PqFail(theEnv, returnValue, fname, msg);
		return false;
	}

	return true;
}

/* A row or column index, checked against the result it indexes. libpq itself
   answers out-of-range indices with NULL or -1 rather than refusing, which
   would turn a typo into a silently empty value. */
static bool PqRowArgument(
  Environment *theEnv,
  UDFContext *context,
  UDFValue *returnValue,
  const char *fname,
  PGresult *result,
  int *out)
{
	long long row;
	char msg[128];

	if (!PqIntegerArgument(theEnv, context, returnValue, fname, "a row number", &row))
	{
		return false;
	}

	if (row < 0 || row >= PQntuples(result))
	{
		snprintf(msg, sizeof msg, "row %lld is out of range: the result has %d",
		         row, PQntuples(result));
		PqFail(theEnv, returnValue, fname, msg);
		return false;
	}

	*out = (int) row;
	return true;
}

static bool PqColumnArgument(
  Environment *theEnv,
  UDFContext *context,
  UDFValue *returnValue,
  const char *fname,
  PGresult *result,
  int *out)
{
	long long column;
	char msg[128];

	if (!PqIntegerArgument(theEnv, context, returnValue, fname, "a column number", &column))
	{
		return false;
	}

	if (column < 0 || column >= PQnfields(result))
	{
		snprintf(msg, sizeof msg, "column %lld is out of range: the result has %d",
		         column, PQnfields(result));
		PqFail(theEnv, returnValue, fname, msg);
		return false;
	}

	*out = (int) column;
	return true;
}

/***************************************************************************/
/*                                                                         */
/* Enumerations.                                                           */
/*                                                                         */
/* Every enumeration libpq returns crosses into CLIPS as the symbol C      */
/* spells it with, and every one it takes is accepted either as that       */
/* symbol or as the integer behind it. The tables are the whole mapping:   */
/* a name that is not in one of them is a name this libpq does not have.   */
/*                                                                         */
/***************************************************************************/

struct PqEnumEntry
{
	const char *name;
	int value;
};

static const struct PqEnumEntry PqConnStatusNames[] = {
	{ "CONNECTION_OK",                CONNECTION_OK },
	{ "CONNECTION_BAD",               CONNECTION_BAD },
	{ "CONNECTION_STARTED",           CONNECTION_STARTED },
	{ "CONNECTION_MADE",              CONNECTION_MADE },
	{ "CONNECTION_AWAITING_RESPONSE", CONNECTION_AWAITING_RESPONSE },
	{ "CONNECTION_AUTH_OK",           CONNECTION_AUTH_OK },
	{ "CONNECTION_SETENV",            CONNECTION_SETENV },
	{ "CONNECTION_SSL_STARTUP",       CONNECTION_SSL_STARTUP },
	{ "CONNECTION_NEEDED",            CONNECTION_NEEDED },
	{ "CONNECTION_CHECK_WRITABLE",    CONNECTION_CHECK_WRITABLE },
	{ "CONNECTION_CONSUME",           CONNECTION_CONSUME },
	{ "CONNECTION_GSS_STARTUP",       CONNECTION_GSS_STARTUP },
	{ "CONNECTION_CHECK_TARGET",      CONNECTION_CHECK_TARGET },
	{ "CONNECTION_CHECK_STANDBY",     CONNECTION_CHECK_STANDBY },
#if CLIPSPG_HAVE_17
	{ "CONNECTION_ALLOCATED",         CONNECTION_ALLOCATED },
#endif
#if CLIPSPG_HAVE_18
	{ "CONNECTION_AUTHENTICATING",    CONNECTION_AUTHENTICATING },
#endif
	{ NULL, 0 }
};

static const struct PqEnumEntry PqPollingStatusNames[] = {
	{ "PGRES_POLLING_FAILED",  PGRES_POLLING_FAILED },
	{ "PGRES_POLLING_READING", PGRES_POLLING_READING },
	{ "PGRES_POLLING_WRITING", PGRES_POLLING_WRITING },
	{ "PGRES_POLLING_OK",      PGRES_POLLING_OK },
	{ "PGRES_POLLING_ACTIVE",  PGRES_POLLING_ACTIVE },
	{ NULL, 0 }
};

static const struct PqEnumEntry PqExecStatusNames[] = {
	{ "PGRES_EMPTY_QUERY",      PGRES_EMPTY_QUERY },
	{ "PGRES_COMMAND_OK",       PGRES_COMMAND_OK },
	{ "PGRES_TUPLES_OK",        PGRES_TUPLES_OK },
	{ "PGRES_COPY_OUT",         PGRES_COPY_OUT },
	{ "PGRES_COPY_IN",          PGRES_COPY_IN },
	{ "PGRES_BAD_RESPONSE",     PGRES_BAD_RESPONSE },
	{ "PGRES_NONFATAL_ERROR",   PGRES_NONFATAL_ERROR },
	{ "PGRES_FATAL_ERROR",      PGRES_FATAL_ERROR },
	{ "PGRES_COPY_BOTH",        PGRES_COPY_BOTH },
	{ "PGRES_SINGLE_TUPLE",     PGRES_SINGLE_TUPLE },
	{ "PGRES_PIPELINE_SYNC",    PGRES_PIPELINE_SYNC },
	{ "PGRES_PIPELINE_ABORTED", PGRES_PIPELINE_ABORTED },
#if CLIPSPG_HAVE_17
	{ "PGRES_TUPLES_CHUNK",     PGRES_TUPLES_CHUNK },
#endif
	{ NULL, 0 }
};

static const struct PqEnumEntry PqTransactionStatusNames[] = {
	{ "PQTRANS_IDLE",    PQTRANS_IDLE },
	{ "PQTRANS_ACTIVE",  PQTRANS_ACTIVE },
	{ "PQTRANS_INTRANS", PQTRANS_INTRANS },
	{ "PQTRANS_INERROR", PQTRANS_INERROR },
	{ "PQTRANS_UNKNOWN", PQTRANS_UNKNOWN },
	{ NULL, 0 }
};

static const struct PqEnumEntry PqPingNames[] = {
	{ "PQPING_OK",          PQPING_OK },
	{ "PQPING_REJECT",      PQPING_REJECT },
	{ "PQPING_NO_RESPONSE", PQPING_NO_RESPONSE },
	{ "PQPING_NO_ATTEMPT",  PQPING_NO_ATTEMPT },
	{ NULL, 0 }
};

static const struct PqEnumEntry PqPipelineStatusNames[] = {
	{ "PQ_PIPELINE_OFF",     PQ_PIPELINE_OFF },
	{ "PQ_PIPELINE_ON",      PQ_PIPELINE_ON },
	{ "PQ_PIPELINE_ABORTED", PQ_PIPELINE_ABORTED },
	{ NULL, 0 }
};

static const struct PqEnumEntry PqErrorVerbosityNames[] = {
	{ "PQERRORS_TERSE",    PQERRORS_TERSE },
	{ "PQERRORS_DEFAULT",  PQERRORS_DEFAULT },
	{ "PQERRORS_VERBOSE",  PQERRORS_VERBOSE },
	{ "PQERRORS_SQLSTATE", PQERRORS_SQLSTATE },
	{ NULL, 0 }
};

static const struct PqEnumEntry PqContextVisibilityNames[] = {
	{ "PQSHOW_CONTEXT_NEVER",  PQSHOW_CONTEXT_NEVER },
	{ "PQSHOW_CONTEXT_ERRORS", PQSHOW_CONTEXT_ERRORS },
	{ "PQSHOW_CONTEXT_ALWAYS", PQSHOW_CONTEXT_ALWAYS },
	{ NULL, 0 }
};

/* The error fields PQresultErrorField reads, whose C values are the single
   characters the backend tags them with. */
static const struct PqEnumEntry PqDiagNames[] = {
	{ "PG_DIAG_SEVERITY",           PG_DIAG_SEVERITY },
	{ "PG_DIAG_SEVERITY_NONLOCALIZED", PG_DIAG_SEVERITY_NONLOCALIZED },
	{ "PG_DIAG_SQLSTATE",           PG_DIAG_SQLSTATE },
	{ "PG_DIAG_MESSAGE_PRIMARY",    PG_DIAG_MESSAGE_PRIMARY },
	{ "PG_DIAG_MESSAGE_DETAIL",     PG_DIAG_MESSAGE_DETAIL },
	{ "PG_DIAG_MESSAGE_HINT",       PG_DIAG_MESSAGE_HINT },
	{ "PG_DIAG_STATEMENT_POSITION", PG_DIAG_STATEMENT_POSITION },
	{ "PG_DIAG_INTERNAL_POSITION",  PG_DIAG_INTERNAL_POSITION },
	{ "PG_DIAG_INTERNAL_QUERY",     PG_DIAG_INTERNAL_QUERY },
	{ "PG_DIAG_CONTEXT",            PG_DIAG_CONTEXT },
	{ "PG_DIAG_SCHEMA_NAME",        PG_DIAG_SCHEMA_NAME },
	{ "PG_DIAG_TABLE_NAME",         PG_DIAG_TABLE_NAME },
	{ "PG_DIAG_COLUMN_NAME",        PG_DIAG_COLUMN_NAME },
	{ "PG_DIAG_DATATYPE_NAME",      PG_DIAG_DATATYPE_NAME },
	{ "PG_DIAG_CONSTRAINT_NAME",    PG_DIAG_CONSTRAINT_NAME },
	{ "PG_DIAG_SOURCE_FILE",        PG_DIAG_SOURCE_FILE },
	{ "PG_DIAG_SOURCE_LINE",        PG_DIAG_SOURCE_LINE },
	{ "PG_DIAG_SOURCE_FUNCTION",    PG_DIAG_SOURCE_FUNCTION },
	{ NULL, 0 }
};

/* The name C gives a value, or "<unknown>" for one this libpq has grown
   since these tables were written. */
static const char *PqEnumName(
  const struct PqEnumEntry *table,
  int value)
{
	int i;

	for (i = 0; table[i].name != NULL; i++)
	{
		if (table[i].value == value)
		{
			return table[i].name;
		}
	}

	return "<unknown>";
}

/* The value behind a name, which the caller may also have written as the
   integer itself. */
static bool PqEnumArgument(
  Environment *theEnv,
  UDFContext *context,
  UDFValue *returnValue,
  const char *fname,
  const char *what,
  const struct PqEnumEntry *table,
  int *out)
{
	UDFValue theArg;
	char msg[160];
	int i;

	if (!UDFNextArgument(context, INTEGER_BIT | LEXEME_BITS, &theArg))
	{
		snprintf(msg, sizeof msg, "expected a symbol or an integer for %s", what);
		PqFail(theEnv, returnValue, fname, msg);
		return false;
	}

	if (theArg.header->type == INTEGER_TYPE)
	{
		*out = (int) theArg.integerValue->contents;
		return true;
	}

	if (theArg.header->type != SYMBOL_TYPE && theArg.header->type != STRING_TYPE)
	{
		snprintf(msg, sizeof msg, "expected a symbol or an integer for %s", what);
		PqFail(theEnv, returnValue, fname, msg);
		return false;
	}

	for (i = 0; table[i].name != NULL; i++)
	{
		if (strcmp(table[i].name, theArg.lexemeValue->contents) == 0)
		{
			*out = table[i].value;
			return true;
		}
	}

	snprintf(msg, sizeof msg, "%s is not %s this libpq knows",
	         theArg.lexemeValue->contents, what);
	PqFail(theEnv, returnValue, fname, msg);
	return false;
}

/***************************************************************************/
/*                                                                         */
/* Multifields of text.                                                    */
/*                                                                         */
/* libpq takes its keyword lists, its value lists and its query parameters */
/* as NULL-terminated arrays of C strings. On the CLIPS side all three are */
/* multifields, and every field in one is converted the same way: the      */
/* symbol nil becomes a NULL pointer, which is what libpq reads as SQL     */
/* NULL and as "this keyword is unset", and everything else becomes its    */
/* printed form.                                                           */
/*                                                                         */
/***************************************************************************/

static void PqFreeTextArray(
  char **array,
  size_t count)
{
	size_t i;

	if (array == NULL) { return; }

	for (i = 0; i < count; i++)
	{
		free(array[i]);
	}
	free(array);
}

static char **PqTextArray(
  Environment *theEnv,
  Multifield *mf,
  int *badIndex)
{
	char **array;
	size_t count = mf->length;
	size_t i;
	char buffer[64];
	const char *text;

	*badIndex = -1;

	array = (char **) calloc(count + 1, sizeof(char *));
	if (array == NULL) { return NULL; }

	for (i = 0; i < count; i++)
	{
		CLIPSValue *field = &mf->contents[i];

		switch (field->header->type)
		{
			case SYMBOL_TYPE:
				if (field->lexemeValue == FalseSymbol(theEnv) ||
				    strcmp(field->lexemeValue->contents, "nil") == 0)
				{
					array[i] = NULL;
					continue;
				}
				if (field->lexemeValue == TrueSymbol(theEnv))
				{
					text = "true";
					break;
				}
				text = field->lexemeValue->contents;
				break;

			case STRING_TYPE:
				text = field->lexemeValue->contents;
				break;

			case INTEGER_TYPE:
				snprintf(buffer, sizeof buffer, "%lld", field->integerValue->contents);
				text = buffer;
				break;

			case FLOAT_TYPE:
				snprintf(buffer, sizeof buffer, "%.17g", field->floatValue->contents);
				text = buffer;
				break;

			default:
				*badIndex = (int) i;
				PqFreeTextArray(array, i);
				return NULL;
		}

		array[i] = (char *) malloc(strlen(text) + 1);
		if (array[i] == NULL)
		{
			PqFreeTextArray(array, i);
			return NULL;
		}
		strcpy(array[i], text);
	}

	return array;
}

/* The keyword/value pairs of a PQconninfoOption array, flattened into one
   multifield: the keyword as a symbol, then its value as a string, or the
   symbol nil where the option is unset. */
static Multifield *PqConninfoMultifield(
  Environment *theEnv,
  PQconninfoOption *options)
{
	MultifieldBuilder *mb;
	Multifield *result;
	PQconninfoOption *option;

	mb = CreateMultifieldBuilder(theEnv, 0);

	for (option = options; option != NULL && option->keyword != NULL; option++)
	{
		MBAppendSymbol(mb, option->keyword);
		if (option->val == NULL)
		{
			MBAppendSymbol(mb, "nil");
		}
		else
		{
			MBAppendString(mb, option->val);
		}
	}

	result = MBCreate(mb);
	MBDispose(mb);
	return result;
}

/***************************************************************************/
/*                                                                         */
/* Database Connection Control Functions                                   */
/*                                                                         */
/***************************************************************************/

void PqConnectdbFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	const char *conninfo = "";
	PGconn *conn;

	if (UDFHasNextArgument(context) &&
	    !PqTextArgument(theEnv, context, returnValue, "pq-connectdb", "the connection string", false, &conninfo))
	{
		return;
	}

	conn = PQconnectdb(conninfo);
	if (conn == NULL)
	{
		PqFail(theEnv, returnValue, "pq-connectdb", "libpq could not allocate a connection");
		return;
	}

	returnValue->externalAddressValue = CreateCExternalAddress(theEnv, (void *) conn);
}

/* The shared body of the four functions that take two multifields of
   keywords and values: PQconnectdbParams, PQconnectStartParams and
   PQpingParams, which differ only in what they do with the arrays. */
static bool PqParamsArguments(
  Environment *theEnv,
  UDFContext *context,
  UDFValue *returnValue,
  const char *fname,
  char ***keywords,
  char ***values,
  size_t *count,
  bool *expandDbname)
{
	UDFValue keywordArg, valueArg;
	int bad;
	char msg[128];

	*keywords = NULL;
	*values = NULL;
	*count = 0;
	*expandDbname = true;

	if (!PqMultifieldArgument(theEnv, context, returnValue, fname, "the keywords", &keywordArg))
	{
		return false;
	}

	if (!PqMultifieldArgument(theEnv, context, returnValue, fname, "the values", &valueArg))
	{
		return false;
	}

	if (keywordArg.multifieldValue->length != valueArg.multifieldValue->length)
	{
		snprintf(msg, sizeof msg,
		         "%lu keywords and %lu values: the two multifields must be the same length",
		         (unsigned long) keywordArg.multifieldValue->length,
		         (unsigned long) valueArg.multifieldValue->length);
		PqFail(theEnv, returnValue, fname, msg);
		return false;
	}

	if (UDFHasNextArgument(context) &&
	    !PqBooleanArgument(theEnv, context, returnValue, fname, "expand-dbname", expandDbname))
	{
		return false;
	}

	*count = keywordArg.multifieldValue->length;

	*keywords = PqTextArray(theEnv, keywordArg.multifieldValue, &bad);
	if (*keywords == NULL)
	{
		PqFail(theEnv, returnValue, fname,
		       bad >= 0 ? "a keyword is neither a symbol, a string nor a number"
		                : "out of memory building the keyword array");
		return false;
	}

	*values = PqTextArray(theEnv, valueArg.multifieldValue, &bad);
	if (*values == NULL)
	{
		PqFreeTextArray(*keywords, *count);
		*keywords = NULL;
		PqFail(theEnv, returnValue, fname,
		       bad >= 0 ? "a value is neither a symbol, a string nor a number"
		                : "out of memory building the value array");
		return false;
	}

	return true;
}

void PqConnectdbParamsFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	char **keywords, **values;
	size_t count;
	bool expandDbname;
	PGconn *conn;

	if (!PqParamsArguments(theEnv, context, returnValue, "pq-connectdb-params",
	                       &keywords, &values, &count, &expandDbname))
	{
		return;
	}

	conn = PQconnectdbParams((const char *const *) keywords,
	                         (const char *const *) values,
	                         expandDbname ? 1 : 0);

	PqFreeTextArray(keywords, count);
	PqFreeTextArray(values, count);

	if (conn == NULL)
	{
		PqFail(theEnv, returnValue, "pq-connectdb-params", "libpq could not allocate a connection");
		return;
	}

	returnValue->externalAddressValue = CreateCExternalAddress(theEnv, (void *) conn);
}

void PqSetdbLoginFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	const char *host, *port, *options, *tty, *dbName, *login, *pwd;
	PGconn *conn;

	if (!PqTextArgument(theEnv, context, returnValue, "pq-setdb-login", "the host", true, &host) ||
	    !PqTextArgument(theEnv, context, returnValue, "pq-setdb-login", "the port", true, &port) ||
	    !PqTextArgument(theEnv, context, returnValue, "pq-setdb-login", "the options", true, &options) ||
	    !PqTextArgument(theEnv, context, returnValue, "pq-setdb-login", "the tty", true, &tty) ||
	    !PqTextArgument(theEnv, context, returnValue, "pq-setdb-login", "the database name", true, &dbName) ||
	    !PqTextArgument(theEnv, context, returnValue, "pq-setdb-login", "the login", true, &login) ||
	    !PqTextArgument(theEnv, context, returnValue, "pq-setdb-login", "the password", true, &pwd))
	{
		return;
	}

	conn = PQsetdbLogin(host, port, options, tty, dbName, login, pwd);
	if (conn == NULL)
	{
		PqFail(theEnv, returnValue, "pq-setdb-login", "libpq could not allocate a connection");
		return;
	}

	returnValue->externalAddressValue = CreateCExternalAddress(theEnv, (void *) conn);
}

void PqConnectStartFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	const char *conninfo = "";
	PGconn *conn;

	if (UDFHasNextArgument(context) &&
	    !PqTextArgument(theEnv, context, returnValue, "pq-connect-start", "the connection string", false, &conninfo))
	{
		return;
	}

	conn = PQconnectStart(conninfo);
	if (conn == NULL)
	{
		PqFail(theEnv, returnValue, "pq-connect-start", "libpq could not allocate a connection");
		return;
	}

	returnValue->externalAddressValue = CreateCExternalAddress(theEnv, (void *) conn);
}

void PqConnectStartParamsFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	char **keywords, **values;
	size_t count;
	bool expandDbname;
	PGconn *conn;

	if (!PqParamsArguments(theEnv, context, returnValue, "pq-connect-start-params",
	                       &keywords, &values, &count, &expandDbname))
	{
		return;
	}

	conn = PQconnectStartParams((const char *const *) keywords,
	                            (const char *const *) values,
	                            expandDbname ? 1 : 0);

	PqFreeTextArray(keywords, count);
	PqFreeTextArray(values, count);

	if (conn == NULL)
	{
		PqFail(theEnv, returnValue, "pq-connect-start-params", "libpq could not allocate a connection");
		return;
	}

	returnValue->externalAddressValue = CreateCExternalAddress(theEnv, (void *) conn);
}

void PqConnectPollFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGconn *conn;

	if ((conn = PqConnArgument(theEnv, context, returnValue, "pq-connect-poll", &theArg)) == NULL)
	{
		return;
	}

	returnValue->lexemeValue = CreateSymbol(theEnv, PqEnumName(PqPollingStatusNames, PQconnectPoll(conn)));
}

void PqFinishFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGconn *conn;

	if ((conn = PqConnArgument(theEnv, context, returnValue, "pq-finish", &theArg)) == NULL)
	{
		return;
	}

	PQfinish(conn);

	/* The handle the caller holds now points at freed memory: emptying it
	   here is what makes a second (pq-finish ?c) a refusal rather than a
	   double free. */
	theArg.externalAddressValue->contents = NULL;

	returnValue->lexemeValue = TrueSymbol(theEnv);
}

void PqResetFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGconn *conn;

	if ((conn = PqConnArgument(theEnv, context, returnValue, "pq-reset", &theArg)) == NULL)
	{
		return;
	}

	PQreset(conn);

	returnValue->lexemeValue = TrueSymbol(theEnv);
}

void PqResetStartFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGconn *conn;

	if ((conn = PqConnArgument(theEnv, context, returnValue, "pq-reset-start", &theArg)) == NULL)
	{
		return;
	}

	if (PQresetStart(conn) == 0)
	{
		PqFailConn(theEnv, returnValue, "pq-reset-start", conn);
		return;
	}

	returnValue->lexemeValue = TrueSymbol(theEnv);
}

void PqResetPollFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGconn *conn;

	if ((conn = PqConnArgument(theEnv, context, returnValue, "pq-reset-poll", &theArg)) == NULL)
	{
		return;
	}

	returnValue->lexemeValue = CreateSymbol(theEnv, PqEnumName(PqPollingStatusNames, PQresetPoll(conn)));
}

void PqPingFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	const char *conninfo = "";

	if (UDFHasNextArgument(context) &&
	    !PqTextArgument(theEnv, context, returnValue, "pq-ping", "the connection string", false, &conninfo))
	{
		return;
	}

	returnValue->lexemeValue = CreateSymbol(theEnv, PqEnumName(PqPingNames, PQping(conninfo)));
}

void PqPingParamsFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	char **keywords, **values;
	size_t count;
	bool expandDbname;
	PGPing ping;

	if (!PqParamsArguments(theEnv, context, returnValue, "pq-ping-params",
	                       &keywords, &values, &count, &expandDbname))
	{
		return;
	}

	ping = PQpingParams((const char *const *) keywords,
	                    (const char *const *) values,
	                    expandDbname ? 1 : 0);

	PqFreeTextArray(keywords, count);
	PqFreeTextArray(values, count);

	returnValue->lexemeValue = CreateSymbol(theEnv, PqEnumName(PqPingNames, ping));
}

void PqConndefaultsFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PQconninfoOption *options;

	options = PQconndefaults();
	if (options == NULL)
	{
		PqFail(theEnv, returnValue, "pq-conndefaults", "libpq could not allocate the option array");
		return;
	}

	returnValue->multifieldValue = PqConninfoMultifield(theEnv, options);
	PQconninfoFree(options);
}

void PqConninfoFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGconn *conn;
	PQconninfoOption *options;

	if ((conn = PqConnArgument(theEnv, context, returnValue, "pq-conninfo", &theArg)) == NULL)
	{
		return;
	}

	options = PQconninfo(conn);
	if (options == NULL)
	{
		PqFail(theEnv, returnValue, "pq-conninfo", "libpq could not allocate the option array");
		return;
	}

	returnValue->multifieldValue = PqConninfoMultifield(theEnv, options);
	PQconninfoFree(options);
}

void PqConninfoParseFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	const char *conninfo;
	char *errmsg = NULL;
	PQconninfoOption *options;

	if (!PqTextArgument(theEnv, context, returnValue, "pq-conninfo-parse", "the connection string", false, &conninfo))
	{
		return;
	}

	options = PQconninfoParse(conninfo, &errmsg);
	if (options == NULL)
	{
		PqFail(theEnv, returnValue, "pq-conninfo-parse",
		       errmsg != NULL ? errmsg : "the connection string could not be parsed");
		PQfreemem(errmsg);
		return;
	}

	returnValue->multifieldValue = PqConninfoMultifield(theEnv, options);
	PQconninfoFree(options);
	PQfreemem(errmsg);
}

/***************************************************************************/
/*                                                                         */
/* Connection Status Functions                                             */
/*                                                                         */
/* The accessors that answer with a string share one body: what differs    */
/* between PQdb and PQhost here is only which libpq function is asked.     */
/* NULL comes back as FALSE, which for these means the connection is not   */
/* in a state that has an answer rather than that the call was refused.    */
/*                                                                         */
/***************************************************************************/

static void PqConnString(
  Environment *theEnv,
  UDFContext *context,
  UDFValue *returnValue,
  const char *fname,
  char *(*accessor)(const PGconn *))
{
	UDFValue theArg;
	PGconn *conn;
	char *value;

	if ((conn = PqConnArgument(theEnv, context, returnValue, fname, &theArg)) == NULL)
	{
		return;
	}

	value = accessor(conn);
	if (value == NULL)
	{
		returnValue->lexemeValue = FalseSymbol(theEnv);
		return;
	}

	returnValue->lexemeValue = CreateString(theEnv, value);
}

static void PqConnInteger(
  Environment *theEnv,
  UDFContext *context,
  UDFValue *returnValue,
  const char *fname,
  int (*accessor)(const PGconn *))
{
	UDFValue theArg;
	PGconn *conn;

	if ((conn = PqConnArgument(theEnv, context, returnValue, fname, &theArg)) == NULL)
	{
		return;
	}

	returnValue->integerValue = CreateInteger(theEnv, accessor(conn));
}

static void PqConnBoolean(
  Environment *theEnv,
  UDFContext *context,
  UDFValue *returnValue,
  const char *fname,
  int (*accessor)(const PGconn *))
{
	UDFValue theArg;
	PGconn *conn;

	if ((conn = PqConnArgument(theEnv, context, returnValue, fname, &theArg)) == NULL)
	{
		return;
	}

	returnValue->lexemeValue = accessor(conn) ? TrueSymbol(theEnv) : FalseSymbol(theEnv);
}

void PqDbFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PqConnString(theEnv, context, returnValue, "pq-db", PQdb);
}

void PqUserFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PqConnString(theEnv, context, returnValue, "pq-user", PQuser);
}

void PqPassFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PqConnString(theEnv, context, returnValue, "pq-pass", PQpass);
}

void PqHostFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PqConnString(theEnv, context, returnValue, "pq-host", PQhost);
}

void PqHostaddrFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PqConnString(theEnv, context, returnValue, "pq-hostaddr", PQhostaddr);
}

void PqPortFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PqConnString(theEnv, context, returnValue, "pq-port", PQport);
}

void PqOptionsFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PqConnString(theEnv, context, returnValue, "pq-options", PQoptions);
}

void PqErrorMessageFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PqConnString(theEnv, context, returnValue, "pq-error-message", PQerrorMessage);
}

void PqStatusFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGconn *conn;

	if ((conn = PqConnArgument(theEnv, context, returnValue, "pq-status", &theArg)) == NULL)
	{
		return;
	}

	returnValue->lexemeValue = CreateSymbol(theEnv, PqEnumName(PqConnStatusNames, PQstatus(conn)));
}

void PqTransactionStatusFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGconn *conn;

	if ((conn = PqConnArgument(theEnv, context, returnValue, "pq-transaction-status", &theArg)) == NULL)
	{
		return;
	}

	returnValue->lexemeValue = CreateSymbol(theEnv, PqEnumName(PqTransactionStatusNames, PQtransactionStatus(conn)));
}

void PqParameterStatusFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGconn *conn;
	const char *name, *value;

	if ((conn = PqConnArgument(theEnv, context, returnValue, "pq-parameter-status", &theArg)) == NULL)
	{
		return;
	}

	if (!PqTextArgument(theEnv, context, returnValue, "pq-parameter-status", "the parameter name", false, &name))
	{
		return;
	}

	value = PQparameterStatus(conn, name);
	if (value == NULL)
	{
		returnValue->lexemeValue = FalseSymbol(theEnv);
		return;
	}

	returnValue->lexemeValue = CreateString(theEnv, value);
}

void PqProtocolVersionFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PqConnInteger(theEnv, context, returnValue, "pq-protocol-version", PQprotocolVersion);
}

#if CLIPSPG_HAVE_18
void PqFullProtocolVersionFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PqConnInteger(theEnv, context, returnValue, "pq-full-protocol-version", PQfullProtocolVersion);
}
#endif

void PqServerVersionFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PqConnInteger(theEnv, context, returnValue, "pq-server-version", PQserverVersion);
}

void PqSocketFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGconn *conn;
	int fd;

	if ((conn = PqConnArgument(theEnv, context, returnValue, "pq-socket", &theArg)) == NULL)
	{
		return;
	}

	fd = PQsocket(conn);
	if (fd < 0)
	{
		PqFail(theEnv, returnValue, "pq-socket", "the connection has no open socket");
		return;
	}

	returnValue->integerValue = CreateInteger(theEnv, fd);
}

void PqBackendPidFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PqConnInteger(theEnv, context, returnValue, "pq-backend-pid", PQbackendPID);
}

void PqConnectionNeedsPasswordFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PqConnBoolean(theEnv, context, returnValue, "pq-connection-needs-password", PQconnectionNeedsPassword);
}

void PqConnectionUsedPasswordFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PqConnBoolean(theEnv, context, returnValue, "pq-connection-used-password", PQconnectionUsedPassword);
}

#if CLIPSPG_HAVE_16
void PqConnectionUsedGssapiFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PqConnBoolean(theEnv, context, returnValue, "pq-connection-used-gssapi", PQconnectionUsedGSSAPI);
}
#endif

void PqSslInUseFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGconn *conn;

	if ((conn = PqConnArgument(theEnv, context, returnValue, "pq-ssl-in-use", &theArg)) == NULL)
	{
		return;
	}

	returnValue->lexemeValue = PQsslInUse(conn) ? TrueSymbol(theEnv) : FalseSymbol(theEnv);
}

void PqGssEncInUseFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGconn *conn;

	if ((conn = PqConnArgument(theEnv, context, returnValue, "pq-gss-enc-in-use", &theArg)) == NULL)
	{
		return;
	}

	returnValue->lexemeValue = PQgssEncInUse(conn) ? TrueSymbol(theEnv) : FalseSymbol(theEnv);
}

void PqSslAttributeFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGconn *conn;
	const char *name, *value;

	if ((conn = PqConnArgument(theEnv, context, returnValue, "pq-ssl-attribute", &theArg)) == NULL)
	{
		return;
	}

	if (!PqTextArgument(theEnv, context, returnValue, "pq-ssl-attribute", "the attribute name", false, &name))
	{
		return;
	}

	value = PQsslAttribute(conn, name);
	if (value == NULL)
	{
		returnValue->lexemeValue = FalseSymbol(theEnv);
		return;
	}

	returnValue->lexemeValue = CreateString(theEnv, value);
}

void PqSslAttributeNamesFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGconn *conn;
	const char *const *names;
	MultifieldBuilder *mb;
	int i;

	if ((conn = PqConnArgument(theEnv, context, returnValue, "pq-ssl-attribute-names", &theArg)) == NULL)
	{
		return;
	}

	names = PQsslAttributeNames(conn);

	mb = CreateMultifieldBuilder(theEnv, 0);
	for (i = 0; names != NULL && names[i] != NULL; i++)
	{
		MBAppendSymbol(mb, names[i]);
	}

	returnValue->multifieldValue = MBCreate(mb);
	MBDispose(mb);
}

void PqClientEncodingFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PqConnInteger(theEnv, context, returnValue, "pq-client-encoding", PQclientEncoding);
}

/***************************************************************************/
/*                                                                         */
/* Command Execution Functions                                             */
/*                                                                         */
/* Everything that runs a command answers with a result handle whenever    */
/* libpq produced one, whatever the result says: a query the server        */
/* rejected is a result whose status is PGRES_FATAL_ERROR and whose        */
/* pq-result-error-message says why, not a refusal. FALSE is kept for the  */
/* case libpq itself has no result to give -- the connection is gone, or   */
/* the memory for one could not be had -- because that is the case where   */
/* there is nothing to clear and nothing to ask.                           */
/*                                                                         */
/***************************************************************************/

static void PqReturnResult(
  Environment *theEnv,
  UDFValue *returnValue,
  const char *fname,
  PGconn *conn,
  PGresult *result)
{
	if (result == NULL)
	{
		PqFailConn(theEnv, returnValue, fname, conn);
		return;
	}

	returnValue->externalAddressValue = CreateCExternalAddress(theEnv, (void *) result);
}

/* PQexec, PQdescribePrepared, PQdescribePortal, PQclosePrepared and
   PQclosePortal are all a connection and one string. */
static void PqConnNameResult(
  Environment *theEnv,
  UDFContext *context,
  UDFValue *returnValue,
  const char *fname,
  const char *what,
  PGresult *(*command)(PGconn *, const char *))
{
	UDFValue theArg;
	PGconn *conn;
	const char *name;

	if ((conn = PqConnArgument(theEnv, context, returnValue, fname, &theArg)) == NULL)
	{
		return;
	}

	if (!PqTextArgument(theEnv, context, returnValue, fname, what, false, &name))
	{
		return;
	}

	PqReturnResult(theEnv, returnValue, fname, conn, command(conn, name));
}

/* The multifield of parameter values the *Params and *Prepared functions
   take. Every parameter is sent in text format and typed by the server,
   which is what makes (pq-exec-params ?c "SELECT $1::int + 1" (create$ 41))
   work without the caller naming an OID. */
static bool PqParamValues(
  Environment *theEnv,
  UDFContext *context,
  UDFValue *returnValue,
  const char *fname,
  char ***values,
  size_t *count)
{
	UDFValue theArg;
	int bad;

	*values = NULL;
	*count = 0;

	if (!UDFHasNextArgument(context))
	{
		return true;
	}

	if (!PqMultifieldArgument(theEnv, context, returnValue, fname, "the parameters", &theArg))
	{
		return false;
	}

	*count = theArg.multifieldValue->length;
	if (*count == 0)
	{
		return true;
	}

	*values = PqTextArray(theEnv, theArg.multifieldValue, &bad);
	if (*values == NULL)
	{
		PqFail(theEnv, returnValue, fname,
		       bad >= 0 ? "a parameter is neither a symbol, a string nor a number"
		                : "out of memory building the parameter array");
		return false;
	}

	return true;
}

void PqExecFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PqConnNameResult(theEnv, context, returnValue, "pq-exec", "the command", PQexec);
}

void PqExecParamsFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGconn *conn;
	const char *command;
	char **values;
	size_t count;
	PGresult *result;

	if ((conn = PqConnArgument(theEnv, context, returnValue, "pq-exec-params", &theArg)) == NULL)
	{
		return;
	}

	if (!PqTextArgument(theEnv, context, returnValue, "pq-exec-params", "the command", false, &command))
	{
		return;
	}

	if (!PqParamValues(theEnv, context, returnValue, "pq-exec-params", &values, &count))
	{
		return;
	}

	result = PQexecParams(conn, command, (int) count, NULL,
	                      (const char *const *) values, NULL, NULL, 0);

	PqFreeTextArray(values, count);
	PqReturnResult(theEnv, returnValue, "pq-exec-params", conn, result);
}

void PqPrepareFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGconn *conn;
	const char *name, *query;

	if ((conn = PqConnArgument(theEnv, context, returnValue, "pq-prepare", &theArg)) == NULL)
	{
		return;
	}

	if (!PqTextArgument(theEnv, context, returnValue, "pq-prepare", "the statement name", false, &name) ||
	    !PqTextArgument(theEnv, context, returnValue, "pq-prepare", "the query", false, &query))
	{
		return;
	}

	PqReturnResult(theEnv, returnValue, "pq-prepare", conn,
	               PQprepare(conn, name, query, 0, NULL));
}

void PqExecPreparedFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGconn *conn;
	const char *name;
	char **values;
	size_t count;
	PGresult *result;

	if ((conn = PqConnArgument(theEnv, context, returnValue, "pq-exec-prepared", &theArg)) == NULL)
	{
		return;
	}

	if (!PqTextArgument(theEnv, context, returnValue, "pq-exec-prepared", "the statement name", false, &name))
	{
		return;
	}

	if (!PqParamValues(theEnv, context, returnValue, "pq-exec-prepared", &values, &count))
	{
		return;
	}

	result = PQexecPrepared(conn, name, (int) count,
	                        (const char *const *) values, NULL, NULL, 0);

	PqFreeTextArray(values, count);
	PqReturnResult(theEnv, returnValue, "pq-exec-prepared", conn, result);
}

void PqDescribePreparedFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PqConnNameResult(theEnv, context, returnValue, "pq-describe-prepared",
	                 "the statement name", PQdescribePrepared);
}

void PqDescribePortalFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PqConnNameResult(theEnv, context, returnValue, "pq-describe-portal",
	                 "the portal name", PQdescribePortal);
}

#if CLIPSPG_HAVE_17
void PqClosePreparedFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PqConnNameResult(theEnv, context, returnValue, "pq-close-prepared",
	                 "the statement name", PQclosePrepared);
}

void PqClosePortalFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PqConnNameResult(theEnv, context, returnValue, "pq-close-portal",
	                 "the portal name", PQclosePortal);
}
#endif

void PqMakeEmptyPgresultFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGconn *conn;
	int status;
	PGresult *result;

	if ((conn = PqConnArgument(theEnv, context, returnValue, "pq-make-empty-pgresult", &theArg)) == NULL)
	{
		return;
	}

	if (!PqEnumArgument(theEnv, context, returnValue, "pq-make-empty-pgresult", "a result status",
	                    PqExecStatusNames, &status))
	{
		return;
	}

	result = PQmakeEmptyPGresult(conn, (ExecStatusType) status);
	PqReturnResult(theEnv, returnValue, "pq-make-empty-pgresult", conn, result);
}

void PqClearFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGresult *result;

	if ((result = PqResultArgument(theEnv, context, returnValue, "pq-clear", &theArg)) == NULL)
	{
		return;
	}

	PQclear(result);

	/* As with pq-finish: the handle is emptied so a second clear is caught
	   here rather than in the allocator. */
	theArg.externalAddressValue->contents = NULL;

	returnValue->lexemeValue = TrueSymbol(theEnv);
}

/***************************************************************************/
/*                                                                         */
/* Retrieving Query Result Information                                     */
/*                                                                         */
/***************************************************************************/

static void PqResultInteger(
  Environment *theEnv,
  UDFContext *context,
  UDFValue *returnValue,
  const char *fname,
  int (*accessor)(const PGresult *))
{
	UDFValue theArg;
	PGresult *result;

	if ((result = PqResultArgument(theEnv, context, returnValue, fname, &theArg)) == NULL)
	{
		return;
	}

	returnValue->integerValue = CreateInteger(theEnv, accessor(result));
}

/* PQfname, PQftype and the rest of the per-column accessors: a result and a
   column number, which is checked against the result before libpq sees it. */
static bool PqResultColumn(
  Environment *theEnv,
  UDFContext *context,
  UDFValue *returnValue,
  const char *fname,
  PGresult **result,
  int *column)
{
	UDFValue theArg;

	if ((*result = PqResultArgument(theEnv, context, returnValue, fname, &theArg)) == NULL)
	{
		return false;
	}

	return PqColumnArgument(theEnv, context, returnValue, fname, *result, column);
}

void PqResultStatusFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGresult *result;

	if ((result = PqResultArgument(theEnv, context, returnValue, "pq-result-status", &theArg)) == NULL)
	{
		return;
	}

	returnValue->lexemeValue = CreateSymbol(theEnv, PqEnumName(PqExecStatusNames, PQresultStatus(result)));
}

void PqResStatusFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	int status;

	if (!PqEnumArgument(theEnv, context, returnValue, "pq-res-status", "a result status",
	                    PqExecStatusNames, &status))
	{
		return;
	}

	returnValue->lexemeValue = CreateString(theEnv, PQresStatus((ExecStatusType) status));
}

void PqResultErrorMessageFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGresult *result;
	const char *message;

	if ((result = PqResultArgument(theEnv, context, returnValue, "pq-result-error-message", &theArg)) == NULL)
	{
		return;
	}

	message = PQresultErrorMessage(result);
	if (message == NULL || message[0] == '\0')
	{
		returnValue->lexemeValue = FalseSymbol(theEnv);
		return;
	}

	returnValue->lexemeValue = CreateString(theEnv, message);
}

void PqResultVerboseErrorMessageFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGresult *result;
	int verbosity, visibility;
	char *message;

	if ((result = PqResultArgument(theEnv, context, returnValue, "pq-result-verbose-error-message", &theArg)) == NULL)
	{
		return;
	}

	if (!PqEnumArgument(theEnv, context, returnValue, "pq-result-verbose-error-message", "an error verbosity",
	                    PqErrorVerbosityNames, &verbosity) ||
	    !PqEnumArgument(theEnv, context, returnValue, "pq-result-verbose-error-message", "a context visibility",
	                    PqContextVisibilityNames, &visibility))
	{
		return;
	}

	message = PQresultVerboseErrorMessage(result, (PGVerbosity) verbosity,
	                                      (PGContextVisibility) visibility);
	if (message == NULL)
	{
		PqFail(theEnv, returnValue, "pq-result-verbose-error-message",
		       "libpq could not build the message");
		return;
	}

	returnValue->lexemeValue = CreateString(theEnv, message);
	PQfreemem(message);
}

void PqResultErrorFieldFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGresult *result;
	int field;
	const char *value;

	if ((result = PqResultArgument(theEnv, context, returnValue, "pq-result-error-field", &theArg)) == NULL)
	{
		return;
	}

	if (!PqEnumArgument(theEnv, context, returnValue, "pq-result-error-field", "an error field",
	                    PqDiagNames, &field))
	{
		return;
	}

	value = PQresultErrorField(result, field);
	if (value == NULL)
	{
		returnValue->lexemeValue = FalseSymbol(theEnv);
		return;
	}

	returnValue->lexemeValue = CreateString(theEnv, value);
}

void PqNtuplesFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PqResultInteger(theEnv, context, returnValue, "pq-ntuples", PQntuples);
}

void PqNfieldsFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PqResultInteger(theEnv, context, returnValue, "pq-nfields", PQnfields);
}

void PqNparamsFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PqResultInteger(theEnv, context, returnValue, "pq-nparams", PQnparams);
}

void PqBinaryTuplesFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGresult *result;

	if ((result = PqResultArgument(theEnv, context, returnValue, "pq-binary-tuples", &theArg)) == NULL)
	{
		return;
	}

	returnValue->lexemeValue = PQbinaryTuples(result) ? TrueSymbol(theEnv) : FalseSymbol(theEnv);
}

void PqFnameFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PGresult *result;
	int column;
	char *name;

	if (!PqResultColumn(theEnv, context, returnValue, "pq-fname", &result, &column))
	{
		return;
	}

	name = PQfname(result, column);
	if (name == NULL)
	{
		returnValue->lexemeValue = FalseSymbol(theEnv);
		return;
	}

	returnValue->lexemeValue = CreateString(theEnv, name);
}

void PqFnumberFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGresult *result;
	const char *name;

	if ((result = PqResultArgument(theEnv, context, returnValue, "pq-fnumber", &theArg)) == NULL)
	{
		return;
	}

	if (!PqTextArgument(theEnv, context, returnValue, "pq-fnumber", "the column name", false, &name))
	{
		return;
	}

	returnValue->integerValue = CreateInteger(theEnv, PQfnumber(result, name));
}

void PqFtableFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PGresult *result;
	int column;
	Oid table;

	if (!PqResultColumn(theEnv, context, returnValue, "pq-ftable", &result, &column))
	{
		return;
	}

	/* A computed column belongs to no table, which libpq says with
	   InvalidOid: FALSE, as everywhere else here that means there is
	   nothing to report rather than that the call was refused. */
	table = PQftable(result, column);
	if (table == InvalidOid)
	{
		returnValue->lexemeValue = FalseSymbol(theEnv);
		return;
	}

	returnValue->integerValue = CreateInteger(theEnv, (long long) table);
}

void PqFtablecolFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PGresult *result;
	int column;
	int tableColumn;

	if (!PqResultColumn(theEnv, context, returnValue, "pq-ftablecol", &result, &column))
	{
		return;
	}

	/* Table columns are numbered from one, so zero is libpq saying this
	   column is not one of them. */
	tableColumn = PQftablecol(result, column);
	if (tableColumn == 0)
	{
		returnValue->lexemeValue = FalseSymbol(theEnv);
		return;
	}

	returnValue->integerValue = CreateInteger(theEnv, tableColumn);
}

void PqFformatFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PGresult *result;
	int column;

	if (!PqResultColumn(theEnv, context, returnValue, "pq-fformat", &result, &column))
	{
		return;
	}

	returnValue->integerValue = CreateInteger(theEnv, PQfformat(result, column));
}

void PqFtypeFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PGresult *result;
	int column;

	if (!PqResultColumn(theEnv, context, returnValue, "pq-ftype", &result, &column))
	{
		return;
	}

	returnValue->integerValue = CreateInteger(theEnv, (long long) PQftype(result, column));
}

void PqFmodFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PGresult *result;
	int column;

	if (!PqResultColumn(theEnv, context, returnValue, "pq-fmod", &result, &column))
	{
		return;
	}

	returnValue->integerValue = CreateInteger(theEnv, PQfmod(result, column));
}

void PqFsizeFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PGresult *result;
	int column;

	if (!PqResultColumn(theEnv, context, returnValue, "pq-fsize", &result, &column))
	{
		return;
	}

	returnValue->integerValue = CreateInteger(theEnv, PQfsize(result, column));
}

void PqParamtypeFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGresult *result;
	long long index;
	char msg[128];

	if ((result = PqResultArgument(theEnv, context, returnValue, "pq-paramtype", &theArg)) == NULL)
	{
		return;
	}

	if (!PqIntegerArgument(theEnv, context, returnValue, "pq-paramtype", "a parameter number", &index))
	{
		return;
	}

	if (index < 0 || index >= PQnparams(result))
	{
		snprintf(msg, sizeof msg, "parameter %lld is out of range: the statement has %d",
		         index, PQnparams(result));
		PqFail(theEnv, returnValue, "pq-paramtype", msg);
		return;
	}

	returnValue->integerValue = CreateInteger(theEnv, (long long) PQparamtype(result, (int) index));
}

void PqGetvalueFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGresult *result;
	int row, column;

	if ((result = PqResultArgument(theEnv, context, returnValue, "pq-getvalue", &theArg)) == NULL)
	{
		return;
	}

	if (!PqRowArgument(theEnv, context, returnValue, "pq-getvalue", result, &row) ||
	    !PqColumnArgument(theEnv, context, returnValue, "pq-getvalue", result, &column))
	{
		return;
	}

	/* libpq answers an SQL NULL with an empty string, which a CLIPS program
	   cannot tell from a column that really is empty. The symbol nil is the
	   answer instead, and pq-getisnull is still there for a caller that
	   would rather ask. */
	if (PQgetisnull(result, row, column))
	{
		returnValue->lexemeValue = CreateSymbol(theEnv, "nil");
		return;
	}

	returnValue->lexemeValue = CreateString(theEnv, PQgetvalue(result, row, column));
}

void PqGetisnullFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGresult *result;
	int row, column;

	if ((result = PqResultArgument(theEnv, context, returnValue, "pq-getisnull", &theArg)) == NULL)
	{
		return;
	}

	if (!PqRowArgument(theEnv, context, returnValue, "pq-getisnull", result, &row) ||
	    !PqColumnArgument(theEnv, context, returnValue, "pq-getisnull", result, &column))
	{
		return;
	}

	returnValue->lexemeValue = PQgetisnull(result, row, column) ? TrueSymbol(theEnv) : FalseSymbol(theEnv);
}

void PqGetlengthFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGresult *result;
	int row, column;

	if ((result = PqResultArgument(theEnv, context, returnValue, "pq-getlength", &theArg)) == NULL)
	{
		return;
	}

	if (!PqRowArgument(theEnv, context, returnValue, "pq-getlength", result, &row) ||
	    !PqColumnArgument(theEnv, context, returnValue, "pq-getlength", result, &column))
	{
		return;
	}

	returnValue->integerValue = CreateInteger(theEnv, PQgetlength(result, row, column));
}

void PqCmdStatusFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGresult *result;
	char *status;

	if ((result = PqResultArgument(theEnv, context, returnValue, "pq-cmd-status", &theArg)) == NULL)
	{
		return;
	}

	status = PQcmdStatus(result);
	if (status == NULL)
	{
		returnValue->lexemeValue = FalseSymbol(theEnv);
		return;
	}

	returnValue->lexemeValue = CreateString(theEnv, status);
}

void PqCmdTuplesFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGresult *result;
	char *tuples;

	if ((result = PqResultArgument(theEnv, context, returnValue, "pq-cmd-tuples", &theArg)) == NULL)
	{
		return;
	}

	tuples = PQcmdTuples(result);

	/* An empty string is what libpq says for a command that does not count
	   rows; the integer is the useful shape for the ones that do. */
	if (tuples == NULL || tuples[0] == '\0')
	{
		returnValue->lexemeValue = FalseSymbol(theEnv);
		return;
	}

	returnValue->integerValue = CreateInteger(theEnv, strtoll(tuples, NULL, 10));
}

void PqOidValueFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGresult *result;
	Oid oid;

	if ((result = PqResultArgument(theEnv, context, returnValue, "pq-oid-value", &theArg)) == NULL)
	{
		return;
	}

	oid = PQoidValue(result);
	if (oid == InvalidOid)
	{
		returnValue->lexemeValue = FalseSymbol(theEnv);
		return;
	}

	returnValue->integerValue = CreateInteger(theEnv, (long long) oid);
}

void PqResultMemorySizeFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGresult *result;

	if ((result = PqResultArgument(theEnv, context, returnValue, "pq-result-memory-size", &theArg)) == NULL)
	{
		return;
	}

	returnValue->integerValue = CreateInteger(theEnv, (long long) PQresultMemorySize(result));
}

/***************************************************************************/
/*                                                                         */
/* Rows as CLIPS data                                                      */
/*                                                                         */
/* libpq hands every value over as text and says what type it was with an  */
/* OID. These three functions are the only ones here with no counterpart   */
/* in the C API: they turn one row of a result into a multifield, a fact   */
/* or an instance, converting each column by its type OID rather than      */
/* leaving every value a string.                                           */
/*                                                                         */
/* The types that have a CLIPS equivalent get it -- the integers, the      */
/* floating-point types, boolean -- and everything else stays the text     */
/* PostgreSQL produced, which is the only lossless thing to do with a      */
/* type CLIPS has no shape for. NUMERIC is the exception worth knowing     */
/* about: it becomes a float, and a value too precise for a double loses   */
/* that precision here. Read it with pq-getvalue to keep it exact.         */
/*                                                                         */
/***************************************************************************/

enum PqFieldKind
{
	PQ_FIELD_NULL,
	PQ_FIELD_INTEGER,
	PQ_FIELD_FLOAT,
	PQ_FIELD_BOOLEAN,
	PQ_FIELD_STRING
};

static enum PqFieldKind PqFieldValue(
  PGresult *result,
  int row,
  int column,
  long long *integerValue,
  double *floatValue,
  bool *booleanValue,
  const char **stringValue)
{
	const char *text;

	if (PQgetisnull(result, row, column))
	{
		return PQ_FIELD_NULL;
	}

	text = PQgetvalue(result, row, column);
	*stringValue = text;

	/* A column sent in binary format is bytes, not a printed value: nothing
	   here can be read out of it, so it stays a string. */
	if (PQfformat(result, column) != 0)
	{
		return PQ_FIELD_STRING;
	}

	switch (PQftype(result, column))
	{
		case PQ_OID_INT2:
		case PQ_OID_INT4:
		case PQ_OID_INT8:
		case PQ_OID_OID:
			*integerValue = strtoll(text, NULL, 10);
			return PQ_FIELD_INTEGER;

		case PQ_OID_FLOAT4:
		case PQ_OID_FLOAT8:
		case PQ_OID_NUMERIC:
			*floatValue = strtod(text, NULL);
			return PQ_FIELD_FLOAT;

		case PQ_OID_BOOL:
			*booleanValue = (text[0] == 't');
			return PQ_FIELD_BOOLEAN;

		default:
			return PQ_FIELD_STRING;
	}
}

/* A slot that would not take the column's value. The two cases worth
   telling apart are a shape that has no such slot at all and a slot whose
   declared type the value does not fit; both mean the row cannot be
   represented by the shape the caller named. */
static void PqFailSlot(
  Environment *theEnv,
  UDFValue *returnValue,
  const char *fname,
  const char *shape,
  const char *slot,
  PutSlotError slotError)
{
	char msg[256];

	switch (slotError)
	{
		case PSE_SLOT_NOT_FOUND_ERROR:
			snprintf(msg, sizeof msg,
			         "the column \"%s\" has no slot to go in: the %s needs one named for it",
			         slot, shape);
			break;
		case PSE_TYPE_ERROR:
		case PSE_ALLOWED_VALUES_ERROR:
		case PSE_ALLOWED_CLASSES_ERROR:
		case PSE_RANGE_ERROR:
		case PSE_CARDINALITY_ERROR:
			snprintf(msg, sizeof msg,
			         "the value of column \"%s\" is not one the %s slot allows",
			         slot, shape);
			break;
		default:
			snprintf(msg, sizeof msg,
			         "the value of column \"%s\" could not be put in its slot",
			         slot);
			break;
	}

	PqFail(theEnv, returnValue, fname, msg);
}

/* The result and row number every mapper starts with. */
static bool PqResultRow(
  Environment *theEnv,
  UDFContext *context,
  UDFValue *returnValue,
  const char *fname,
  PGresult **result,
  int *row)
{
	UDFValue theArg;

	if ((*result = PqResultArgument(theEnv, context, returnValue, fname, &theArg)) == NULL)
	{
		return false;
	}

	return PqRowArgument(theEnv, context, returnValue, fname, *result, row);
}

void PqRowToMultifieldFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PGresult *result;
	int row, column;
	MultifieldBuilder *mb;
	long long integerValue = 0;
	double floatValue = 0.0;
	bool booleanValue = false;
	const char *stringValue = NULL;

	if (!PqResultRow(theEnv, context, returnValue, "pq-row-to-multifield", &result, &row))
	{
		return;
	}

	mb = CreateMultifieldBuilder(theEnv, 0);

	for (column = 0; column < PQnfields(result); column++)
	{
		switch (PqFieldValue(result, row, column, &integerValue, &floatValue, &booleanValue, &stringValue))
		{
			case PQ_FIELD_NULL:    MBAppendSymbol(mb, "nil"); break;
			case PQ_FIELD_INTEGER: MBAppendInteger(mb, integerValue); break;
			case PQ_FIELD_FLOAT:   MBAppendFloat(mb, floatValue); break;
			case PQ_FIELD_BOOLEAN: MBAppendSymbol(mb, booleanValue ? "TRUE" : "FALSE"); break;
			case PQ_FIELD_STRING:  MBAppendString(mb, stringValue); break;
		}
	}

	returnValue->multifieldValue = MBCreate(mb);
	MBDispose(mb);
}

void PqRowToFactFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGresult *result;
	int row, column;
	FactBuilder *fb;
	Fact *fact;
	long long integerValue = 0;
	double floatValue = 0.0;
	bool booleanValue = false;
	const char *stringValue = NULL;

	if (!PqResultRow(theEnv, context, returnValue, "pq-row-to-fact", &result, &row))
	{
		return;
	}

	if (!UDFNextArgument(context, SYMBOL_BIT, &theArg) ||
	    theArg.header->type != SYMBOL_TYPE)
	{
		PqFail(theEnv, returnValue, "pq-row-to-fact", "expected a symbol for the deftemplate name");
		return;
	}

	fb = CreateFactBuilder(theEnv, theArg.lexemeValue->contents);
	switch (FBError(theEnv))
	{
		case FBE_NO_ERROR:
			break;
		case FBE_DEFTEMPLATE_NOT_FOUND_ERROR:
			PqFail(theEnv, returnValue, "pq-row-to-fact", "there is no deftemplate by that name");
			FBDispose(fb);
			return;
		case FBE_IMPLIED_DEFTEMPLATE_ERROR:
			PqFail(theEnv, returnValue, "pq-row-to-fact", "the implied deftemplate has no slots to fill");
			FBDispose(fb);
			return;
		default:
			PqFail(theEnv, returnValue, "pq-row-to-fact", "the FactBuilder could not be created");
			FBDispose(fb);
			return;
	}

	for (column = 0; column < PQnfields(result); column++)
	{
		const char *slot = PQfname(result, column);
		PutSlotError slotError = PSE_NO_ERROR;

		switch (PqFieldValue(result, row, column, &integerValue, &floatValue, &booleanValue, &stringValue))
		{
			case PQ_FIELD_NULL:    slotError = FBPutSlotSymbol(fb, slot, "nil"); break;
			case PQ_FIELD_INTEGER: slotError = FBPutSlotInteger(fb, slot, integerValue); break;
			case PQ_FIELD_FLOAT:   slotError = FBPutSlotFloat(fb, slot, floatValue); break;
			case PQ_FIELD_BOOLEAN: slotError = FBPutSlotSymbol(fb, slot, booleanValue ? "TRUE" : "FALSE"); break;
			case PQ_FIELD_STRING:  slotError = FBPutSlotString(fb, slot, stringValue); break;
		}

		/* A column with nowhere to go is the whole row silently losing a
		   value, so it ends the call instead. */
		if (slotError != PSE_NO_ERROR)
		{
			PqFailSlot(theEnv, returnValue, "pq-row-to-fact", "deftemplate", slot, slotError);
			FBDispose(fb);
			return;
		}
	}

	fact = FBAssert(fb);
	if (fact == NULL)
	{
		switch (FBError(theEnv))
		{
			case FBE_COULD_NOT_ASSERT_ERROR:
				PqFail(theEnv, returnValue, "pq-row-to-fact",
				       "the fact could not be asserted: a column has no slot to go in, or the fact already exists");
				break;
			case FBE_RULE_NETWORK_ERROR:
				PqFail(theEnv, returnValue, "pq-row-to-fact",
				       "an error was raised while the assertion was processed by the rule network");
				break;
			case FBE_NULL_POINTER_ERROR:
				PqFail(theEnv, returnValue, "pq-row-to-fact",
				       "the FactBuilder has no deftemplate");
				break;
			default:
				PqFail(theEnv, returnValue, "pq-row-to-fact",
				       "the fact was not asserted and the FactBuilder reports no error");
				break;
		}
		FBDispose(fb);
		return;
	}

	returnValue->factValue = fact;
	FBDispose(fb);
}

void PqRowToInstanceFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGresult *result;
	int row, column;
	InstanceBuilder *ib;
	Instance *instance;
	const char *defclassName, *instanceName = NULL, *nameSlotReplacement = "_name";
	long long integerValue = 0;
	double floatValue = 0.0;
	bool booleanValue = false;
	const char *stringValue = NULL;

	if (!PqResultRow(theEnv, context, returnValue, "pq-row-to-instance", &result, &row))
	{
		return;
	}

	if (!UDFNextArgument(context, SYMBOL_BIT, &theArg) ||
	    theArg.header->type != SYMBOL_TYPE)
	{
		PqFail(theEnv, returnValue, "pq-row-to-instance", "expected a symbol for the defclass name");
		return;
	}
	defclassName = theArg.lexemeValue->contents;

	/* The instance name. nil asks for the one CLIPS makes up, which is what
	   a row-per-instance loop wants. */
	if (UDFHasNextArgument(context))
	{
		if (!UDFNextArgument(context, SYMBOL_BIT, &theArg) ||
		    theArg.header->type != SYMBOL_TYPE)
		{
			PqFail(theEnv, returnValue, "pq-row-to-instance", "expected a symbol for the instance name");
			return;
		}
		if (strcmp("nil", theArg.lexemeValue->contents) != 0)
		{
			instanceName = theArg.lexemeValue->contents;
		}
	}

	/* An instance's name is not a slot, so a column called "name" has
	   nowhere to go. It is written to _name instead, or to whatever slot
	   the caller names here. */
	if (UDFHasNextArgument(context))
	{
		if (!UDFNextArgument(context, SYMBOL_BIT, &theArg) ||
		    theArg.header->type != SYMBOL_TYPE)
		{
			PqFail(theEnv, returnValue, "pq-row-to-instance", "expected a symbol for the name slot replacement");
			return;
		}
		nameSlotReplacement = theArg.lexemeValue->contents;
	}

	ib = CreateInstanceBuilder(theEnv, defclassName);
	switch (IBError(theEnv))
	{
		case IBE_NO_ERROR:
			break;
		case IBE_DEFCLASS_NOT_FOUND_ERROR:
			PqFail(theEnv, returnValue, "pq-row-to-instance", "there is no defclass by that name");
			IBDispose(ib);
			return;
		default:
			PqFail(theEnv, returnValue, "pq-row-to-instance", "the InstanceBuilder could not be created");
			IBDispose(ib);
			return;
	}

	for (column = 0; column < PQnfields(result); column++)
	{
		const char *slot = PQfname(result, column);

		if (strcmp("name", slot) == 0)
		{
			slot = nameSlotReplacement;
		}

		PutSlotError slotError = PSE_NO_ERROR;

		switch (PqFieldValue(result, row, column, &integerValue, &floatValue, &booleanValue, &stringValue))
		{
			case PQ_FIELD_NULL:    slotError = IBPutSlotSymbol(ib, slot, "nil"); break;
			case PQ_FIELD_INTEGER: slotError = IBPutSlotInteger(ib, slot, integerValue); break;
			case PQ_FIELD_FLOAT:   slotError = IBPutSlotFloat(ib, slot, floatValue); break;
			case PQ_FIELD_BOOLEAN: slotError = IBPutSlotSymbol(ib, slot, booleanValue ? "TRUE" : "FALSE"); break;
			case PQ_FIELD_STRING:  slotError = IBPutSlotString(ib, slot, stringValue); break;
		}

		if (slotError != PSE_NO_ERROR)
		{
			PqFailSlot(theEnv, returnValue, "pq-row-to-instance", "defclass", slot, slotError);
			IBDispose(ib);
			return;
		}
	}

	instance = IBMake(ib, instanceName);
	if (instance == NULL)
	{
		switch (IBError(theEnv))
		{
			case IBE_COULD_NOT_CREATE_ERROR:
				PqFail(theEnv, returnValue, "pq-row-to-instance",
				       "the instance could not be made: a column has no slot to go in");
				break;
			case IBE_RULE_NETWORK_ERROR:
				PqFail(theEnv, returnValue, "pq-row-to-instance",
				       "an error was raised while the instance was processed by the rule network");
				break;
			case IBE_NULL_POINTER_ERROR:
				PqFail(theEnv, returnValue, "pq-row-to-instance",
				       "the InstanceBuilder has no defclass");
				break;
			default:
				PqFail(theEnv, returnValue, "pq-row-to-instance",
				       "the instance was not made and the InstanceBuilder reports no error");
				break;
		}
		IBDispose(ib);
		return;
	}

	returnValue->instanceValue = instance;
	IBDispose(ib);
}

/***************************************************************************/
/*                                                                         */
/* Whole results as CLIPS data                                             */
/*                                                                         */
/* The row mappers above take one row and refuse a column with nowhere to  */
/* go. These six take every row of a result at once, and they take the     */
/* other side of that bargain: the query decides what it selects and the   */
/* deftemplate or defclass decides what it holds, so a column with no slot */
/* is passed over and a row a slot refuses is skipped and reported, while  */
/* the rows around it still land. The answer is the record of what was     */
/* made, in row order.                                                     */
/*                                                                         */
/* The three pq-exec-to-* forms run the command first, and can infer the   */
/* deftemplate or defclass from the one table the result's columns come    */
/* from, which is what PQftable is for; a result on its own carries no     */
/* connection to ask, so the pq-result-to-* forms are told the name.       */
/*                                                                         */
/***************************************************************************/

/* A message about a call that still answers something: the rows it lost,
   not the whole result, so the return value is left alone. */
static void PqReportOnce(
  Environment *theEnv,
  const char *fname,
  const char *msg,
  bool *reported)
{
	if (*reported)
	{
		return;
	}
	*reported = true;

	WriteString(theEnv, STDERR, fname);
	WriteString(theEnv, STDERR, ": ");
	WriteString(theEnv, STDERR, msg);
	WriteString(theEnv, STDERR, "\n");
}

static const char *PqShapeNoun(unsigned short kind)
{
	return (kind == FACT_ADDRESS_TYPE) ? "deftemplate" : "defclass";
}

/* The instance names a caller asked for, in row order. */
struct PqInstanceNames
{
	CLIPSLexeme **items;   /* NULL when none were given */
	size_t count;
};

/* The name for one row, or NULL to leave CLIPS to make one up. */
static const char *PqInstanceNameForRow(
  const struct PqInstanceNames *names,
  int row)
{
	if (names == NULL || row < 0 || (size_t) row >= names->count)
	{
		return NULL;
	}

	return names->items[row]->contents;
}

static void PqFreeInstanceNames(
  Environment *theEnv,
  struct PqInstanceNames *names)
{
	if (names->items == NULL)
	{
		return;
	}

	genfree(theEnv, names->items, names->count * sizeof(CLIPSLexeme *));
	names->items = NULL;
	names->count = 0;
}

static bool PqIsInstanceNameLexeme(unsigned short type)
{
	return type == SYMBOL_TYPE || type == STRING_TYPE || type == INSTANCE_NAME_TYPE;
}

/* The optional instance-names argument the two instance forms take, already
   read: one lexeme names the first row, a multifield names the rows it has
   entries for. */
static bool PqInstanceNamesFromValue(
  Environment *theEnv,
  UDFValue *returnValue,
  const char *fname,
  UDFValue *theArg,
  struct PqInstanceNames *names)
{
	Multifield *mf;
	size_t i;
	char msg[128];

	if (theArg->header->type != MULTIFIELD_TYPE)
	{
		if (!PqIsInstanceNameLexeme(theArg->header->type))
		{
			PqFail(theEnv, returnValue, fname,
			       "expected a multifield, or one symbol, string or instance name, for the instance names");
			return false;
		}

		names->items = (CLIPSLexeme **) genalloc(theEnv, sizeof(CLIPSLexeme *));
		names->items[0] = theArg->lexemeValue;
		names->count = 1;
		return true;
	}

	/* begin and range rather than the whole multifield: a $?rest bound on a
	   rule's LHS arrives as a window onto a longer one, and reading it from
	   field zero would name the rows after values the caller never passed. */
	mf = theArg->multifieldValue;
	if (theArg->range == 0)
	{
		return true;   /* an empty list names nothing */
	}

	names->items = (CLIPSLexeme **) genalloc(theEnv, theArg->range * sizeof(CLIPSLexeme *));
	names->count = theArg->range;

	for (i = 0; i < names->count; i++)
	{
		CLIPSValue *field = &mf->contents[theArg->begin + i];

		if (!PqIsInstanceNameLexeme(field->header->type))
		{
			snprintf(msg, sizeof msg,
			         "field %zu of the instance names is not a symbol, string or instance name",
			         i + 1);
			PqFail(theEnv, returnValue, fname, msg);
			PqFreeInstanceNames(theEnv, names);
			return false;
		}
		names->items[i] = field->lexemeValue;
	}

	return true;
}

/* The optional instance-names argument, read from the context. */
static bool PqInstanceNamesArgument(
  Environment *theEnv,
  UDFContext *context,
  UDFValue *returnValue,
  const char *fname,
  struct PqInstanceNames *names)
{
	UDFValue theArg;

	if (!UDFNextArgument(context, MULTIFIELD_BIT | LEXEME_BITS | INSTANCE_NAME_BIT, &theArg))
	{
		PqFail(theEnv, returnValue, fname,
		       "expected a multifield, or one symbol, string or instance name, for the instance names");
		return false;
	}

	return PqInstanceNamesFromValue(theEnv, returnValue, fname, &theArg, names);
}

/* One field of one row as a CLIPS value, by the same mapping the row
   mappers use. */
static void PqFieldCLIPSValue(
  Environment *theEnv,
  PGresult *result,
  int row,
  int column,
  CLIPSValue *out)
{
	long long integerValue = 0;
	double floatValue = 0.0;
	bool booleanValue = false;
	const char *stringValue = NULL;

	switch (PqFieldValue(result, row, column, &integerValue, &floatValue, &booleanValue, &stringValue))
	{
		case PQ_FIELD_NULL:    out->lexemeValue = CreateSymbol(theEnv, "nil"); break;
		case PQ_FIELD_INTEGER: out->integerValue = CreateInteger(theEnv, integerValue); break;
		case PQ_FIELD_FLOAT:   out->floatValue = CreateFloat(theEnv, floatValue); break;
		case PQ_FIELD_BOOLEAN: out->lexemeValue = booleanValue ? TrueSymbol(theEnv) : FalseSymbol(theEnv); break;
		case PQ_FIELD_STRING:  out->lexemeValue = CreateString(theEnv, stringValue); break;
	}
}

/* Walks every row of a result, making one fact or instance per row, or
   appending every row to one multifield, and answers what it made in row
   order. */
static void PqResultToWorkingMemory(
  Environment *theEnv,
  UDFValue *returnValue,
  const char *fname,
  PGresult *result,
  unsigned short kind,
  const char *name,
  const struct PqInstanceNames *names,
  bool headers)
{
	int rows = PQntuples(result);
	int columns = PQnfields(result);
	Deftemplate *tmpl = NULL;
	Defclass *cls = NULL;
	FactBuilder *fb = NULL;
	InstanceBuilder *ib = NULL;
	MultifieldBuilder *mb;
	const char **slots;
	bool reported = false;
	/* CLIPS reports a build it refused by setting the evaluation error, and
	   that also halts execution -- after which the next row is refused too,
	   and one lost row would quietly take the rest of the result with it.
	   The rows are independent, so the flags are put back to what this call
	   found them as and the row after gets its own attempt. Only the build
	   can do this; a slot value a constraint refuses does not halt. */
	bool haltWas = GetHaltExecution(theEnv);
	bool errorWas = GetEvaluationError(theEnv);
	int row, column;
	char msg[256];

	if (kind == FACT_ADDRESS_TYPE)
	{
		if ((tmpl = FindDeftemplate(theEnv, name)) == NULL)
		{
			snprintf(msg, sizeof msg, "there is no deftemplate named %s", name);
			PqFail(theEnv, returnValue, fname, msg);
			return;
		}

		fb = CreateFactBuilder(theEnv, name);
		if (FBError(theEnv) != FBE_NO_ERROR)
		{
			PqFail(theEnv, returnValue, fname,
			       (FBError(theEnv) == FBE_IMPLIED_DEFTEMPLATE_ERROR)
			         ? "the implied deftemplate has no slots to fill"
			         : "the FactBuilder could not be created");
			FBDispose(fb);
			return;
		}
	}
	else if (kind == INSTANCE_ADDRESS_TYPE)
	{
		if ((cls = FindDefclass(theEnv, name)) == NULL)
		{
			snprintf(msg, sizeof msg, "there is no defclass named %s", name);
			PqFail(theEnv, returnValue, fname, msg);
			return;
		}

		ib = CreateInstanceBuilder(theEnv, name);
		if (IBError(theEnv) != IBE_NO_ERROR)
		{
			PqFail(theEnv, returnValue, fname, "the InstanceBuilder could not be created");
			IBDispose(ib);
			return;
		}
	}

	/* Which column goes to which slot is decided once, before the first
	   row: a column with no slot is NULL here and passed over below. An
	   instance's name is not a slot, so a column called "name" goes to
	   _name, as it does for pq-row-to-instance. */
	slots = (const char **) genalloc(theEnv, (size_t) (columns + 1) * sizeof(const char *));
	for (column = 0; column < columns; column++)
	{
		const char *slot = PQfname(result, column);

		if (kind == INSTANCE_ADDRESS_TYPE && strcmp("name", slot) == 0)
		{
			slot = "_name";
		}

		if ((kind == FACT_ADDRESS_TYPE && !DeftemplateSlotExistP(tmpl, slot)) ||
		    (kind == INSTANCE_ADDRESS_TYPE && !SlotExistP(cls, slot, true)))
		{
			slot = NULL;
		}

		slots[column] = slot;
	}

	mb = CreateMultifieldBuilder(theEnv, (size_t) (kind == MULTIFIELD_TYPE ? rows * columns : rows));

	if (kind == MULTIFIELD_TYPE && headers)
	{
		for (column = 0; column < columns; column++)
		{
			MBAppendString(mb, PQfname(result, column));
		}
	}

	for (row = 0; row < rows; row++)
	{
		bool rowOk = true;

		for (column = 0; column < columns; column++)
		{
			CLIPSValue cv;
			PutSlotError slotError;

			if (slots[column] == NULL)
			{
				continue;
			}

			PqFieldCLIPSValue(theEnv, result, row, column, &cv);

			if (kind == MULTIFIELD_TYPE)
			{
				MBAppend(mb, &cv);
				continue;
			}

			slotError = (fb != NULL) ? FBPutSlot(fb, slots[column], &cv)
			                         : IBPutSlot(ib, slots[column], &cv);
			if (slotError == PSE_NO_ERROR)
			{
				continue;
			}

			rowOk = false;
			snprintf(msg, sizeof msg,
			         "slot %s of %s would not take the value in column \"%s\"; those rows are skipped",
			         slots[column], name, PQfname(result, column));
			PqReportOnce(theEnv, fname, msg, &reported);
			break;
		}

		if (fb != NULL)
		{
			Fact *fact;

			if (!rowOk)
			{
				FBAbort(fb);
				continue;
			}

			if ((fact = FBAssert(fb)) != NULL)
			{
				MBAppendFact(mb, fact);
			}
			else
			{
				snprintf(msg, sizeof msg,
				         "no fact of %s could be made for a row; those rows are skipped", name);
				PqReportOnce(theEnv, fname, msg, &reported);
			}
		}
		else if (ib != NULL)
		{
			Instance *instance;

			if (!rowOk)
			{
				IBAbort(ib);
				continue;
			}

			if ((instance = IBMake(ib, PqInstanceNameForRow(names, row))) != NULL)
			{
				MBAppendInstance(mb, instance);
			}
			else
			{
				IBAbort(ib);
				snprintf(msg, sizeof msg,
				         "no instance of %s could be made for a row; those rows are skipped", name);
				PqReportOnce(theEnv, fname, msg, &reported);
				SetEvaluationError(theEnv, errorWas);
				SetHaltExecution(theEnv, haltWas);
			}
		}
	}

	if (fb != NULL) { FBDispose(fb); }
	if (ib != NULL) { IBDispose(ib); }
	genfree(theEnv, slots, (size_t) (columns + 1) * sizeof(const char *));

	returnValue->multifieldValue = MBCreate(mb);
	MBDispose(mb);
}

/* The name of the one table the result's columns come from, uppercased for
   a defclass. The string is the caller's to free, and NULL means the reason
   has already been written. */
static char *PqInferConstructName(
  Environment *theEnv,
  UDFValue *returnValue,
  const char *fname,
  PGconn *conn,
  PGresult *result,
  unsigned short kind)
{
	Oid table = InvalidOid;
	int tables = 0;
	int column;
	char oidText[32];
	const char *values[1];
	PGresult *lookup;
	const char *relname;
	size_t len;
	char *copy;
	char msg[256];

	/* Every column that is a plain reference to a table column says which
	   table; a computed column says nothing and is not counted. */
	for (column = 0; column < PQnfields(result); column++)
	{
		Oid candidate = PQftable(result, column);

		if (candidate == InvalidOid || candidate == table)
		{
			continue;
		}
		if (table != InvalidOid)
		{
			/* A third table is still "more than one". */
			tables = 2;
			break;
		}
		table = candidate;
		tables = 1;
	}

	if (tables == 0)
	{
		snprintf(msg, sizeof msg,
		         "no column of the result comes from a table, so there is no %s name to infer; name one",
		         PqShapeNoun(kind));
		PqFail(theEnv, returnValue, fname, msg);
		return NULL;
	}
	if (tables > 1)
	{
		snprintf(msg, sizeof msg,
		         "the columns come from more than one table, so there is no single name to infer; name the %s",
		         PqShapeNoun(kind));
		PqFail(theEnv, returnValue, fname, msg);
		return NULL;
	}

	snprintf(oidText, sizeof oidText, "%u", (unsigned) table);
	values[0] = oidText;
	lookup = PQexecParams(conn, "SELECT relname FROM pg_catalog.pg_class WHERE oid = $1::oid",
	                      1, NULL, values, NULL, NULL, 0);
	if (lookup == NULL ||
	    PQresultStatus(lookup) != PGRES_TUPLES_OK ||
	    PQntuples(lookup) != 1)
	{
		const char *why = (lookup == NULL) ? PQerrorMessage(conn) : PQresultErrorMessage(lookup);

		snprintf(msg, sizeof msg,
		         "the table's name could not be read, so there is no %s name to infer; name one%s%s",
		         PqShapeNoun(kind),
		         (why != NULL && why[0] != '\0') ? ": " : "",
		         (why != NULL) ? why : "");
		len = strlen(msg);
		if (len > 0 && msg[len - 1] == '\n')
		{
			msg[len - 1] = '\0';
		}
		PqFail(theEnv, returnValue, fname, msg);
		PQclear(lookup);
		return NULL;
	}

	relname = PQgetvalue(lookup, 0, 0);
	len = strlen(relname);
	copy = (char *) genalloc(theEnv, len + 1);
	memcpy(copy, relname, len + 1);
	PQclear(lookup);

	/* The default class names of this library are spelled in capitals, so
	   the class inferred for a table is too. ASCII only: a table name that
	   needs more is one to spell out. */
	if (kind == INSTANCE_ADDRESS_TYPE)
	{
		char *s;

		for (s = copy; *s != '\0'; s++)
		{
			if (*s >= 'a' && *s <= 'z')
			{
				*s = (char) (*s - 'a' + 'A');
			}
		}
	}

	return copy;
}

/* pq-result-to-multifields, pq-result-to-facts and pq-result-to-instances:
   a result, then what to make of it. */
static void PqResultToShape(
  Environment *theEnv,
  UDFContext *context,
  UDFValue *returnValue,
  const char *fname,
  unsigned short kind)
{
	UDFValue theArg;
	PGresult *result;
	const char *name = NULL;
	struct PqInstanceNames names = { NULL, 0 };
	bool headers = false;

	if ((result = PqResultArgument(theEnv, context, returnValue, fname, &theArg)) == NULL)
	{
		return;
	}

	if (kind == MULTIFIELD_TYPE)
	{
		if (UDFHasNextArgument(context) &&
		    !PqBooleanArgument(theEnv, context, returnValue, fname, "the headers flag", &headers))
		{
			return;
		}

		PqResultToWorkingMemory(theEnv, returnValue, fname, result, kind, NULL, NULL, headers);
		return;
	}

	if (!PqTextArgument(theEnv, context, returnValue, fname,
	                    (kind == FACT_ADDRESS_TYPE) ? "the deftemplate name" : "the defclass name",
	                    false, &name))
	{
		return;
	}

	if (kind == INSTANCE_ADDRESS_TYPE && UDFHasNextArgument(context) &&
	    !PqInstanceNamesArgument(theEnv, context, returnValue, fname, &names))
	{
		return;
	}

	PqResultToWorkingMemory(theEnv, returnValue, fname, result, kind, name, &names, headers);
	PqFreeInstanceNames(theEnv, &names);
}

/* pq-exec-to-multifields, pq-exec-to-facts and pq-exec-to-instances: a
   connection and a command, then what to make of the rows. */
static void PqExecToShape(
  Environment *theEnv,
  UDFContext *context,
  UDFValue *returnValue,
  const char *fname,
  unsigned short kind)
{
	UDFValue theArg;
	PGconn *conn;
	const char *command;
	const char *given = NULL;
	char *inferred = NULL;
	struct PqInstanceNames names = { NULL, 0 };
	bool namesGiven = false;
	bool headers = false;
	PGresult *result;
	ExecStatusType status;
	char msg[256];

	if ((conn = PqConnArgument(theEnv, context, returnValue, fname, &theArg)) == NULL)
	{
		return;
	}

	if (!PqTextArgument(theEnv, context, returnValue, fname, "the command", false, &command))
	{
		return;
	}

	if (kind == MULTIFIELD_TYPE)
	{
		if (UDFHasNextArgument(context) &&
		    !PqBooleanArgument(theEnv, context, returnValue, fname, "the headers flag", &headers))
		{
			return;
		}
	}
	else if (UDFHasNextArgument(context))
	{
		/* The deftemplate or defclass, which is optional. For instances, a
		   multifield here is the instance names instead, and the class is
		   inferred: a class is one lexeme and a list of names is a
		   multifield, so the two cannot be confused. */
		if (!UDFNextArgument(context,
		                     (kind == INSTANCE_ADDRESS_TYPE) ? (MULTIFIELD_BIT | LEXEME_BITS)
		                                                     : LEXEME_BITS,
		                     &theArg))
		{
			snprintf(msg, sizeof msg, "expected a symbol or a string for the %s name", PqShapeNoun(kind));
			PqFail(theEnv, returnValue, fname, msg);
			return;
		}

		if (theArg.header->type == MULTIFIELD_TYPE)
		{
			if (!PqInstanceNamesFromValue(theEnv, returnValue, fname, &theArg, &names))
			{
				return;
			}
			namesGiven = true;
		}
		else
		{
			given = theArg.lexemeValue->contents;
		}
	}

	if (kind == INSTANCE_ADDRESS_TYPE && UDFHasNextArgument(context))
	{
		if (namesGiven)
		{
			PqFail(theEnv, returnValue, fname,
			       "the instance names were given twice: the multifield third argument is already them");
			PqFreeInstanceNames(theEnv, &names);
			return;
		}

		if (!PqInstanceNamesArgument(theEnv, context, returnValue, fname, &names))
		{
			return;
		}
	}

	if ((result = PQexec(conn, command)) == NULL)
	{
		PqFailConn(theEnv, returnValue, fname, conn);
		PqFreeInstanceNames(theEnv, &names);
		return;
	}

	/* A command the server refused is a result whose status says so, and
	   there is nothing in it to convert: unlike pq-exec, this answers FALSE
	   for it, with the server's message. */
	status = PQresultStatus(result);
	if (status != PGRES_TUPLES_OK && status != PGRES_COMMAND_OK && status != PGRES_EMPTY_QUERY)
	{
		const char *why = PQresultErrorMessage(result);
		size_t len;

		snprintf(msg, sizeof msg, "the command produced no rows: %s%s%s",
		         PqEnumName(PqExecStatusNames, status),
		         (why != NULL && why[0] != '\0') ? ": " : "",
		         (why != NULL) ? why : "");
		len = strlen(msg);
		if (len > 0 && msg[len - 1] == '\n')
		{
			msg[len - 1] = '\0';
		}
		PqFail(theEnv, returnValue, fname, msg);
		PQclear(result);
		PqFreeInstanceNames(theEnv, &names);
		return;
	}

	if (kind != MULTIFIELD_TYPE && given == NULL)
	{
		if ((inferred = PqInferConstructName(theEnv, returnValue, fname, conn, result, kind)) == NULL)
		{
			PQclear(result);
			PqFreeInstanceNames(theEnv, &names);
			return;
		}
		given = inferred;
	}

	PqResultToWorkingMemory(theEnv, returnValue, fname, result, kind, given, &names, headers);

	if (inferred != NULL)
	{
		genfree(theEnv, inferred, strlen(inferred) + 1);
	}
	PqFreeInstanceNames(theEnv, &names);
	PQclear(result);
}

void PqResultToMultifieldsFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PqResultToShape(theEnv, context, returnValue, "pq-result-to-multifields", MULTIFIELD_TYPE);
}

void PqResultToFactsFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PqResultToShape(theEnv, context, returnValue, "pq-result-to-facts", FACT_ADDRESS_TYPE);
}

void PqResultToInstancesFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PqResultToShape(theEnv, context, returnValue, "pq-result-to-instances", INSTANCE_ADDRESS_TYPE);
}

void PqExecToMultifieldsFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PqExecToShape(theEnv, context, returnValue, "pq-exec-to-multifields", MULTIFIELD_TYPE);
}

void PqExecToFactsFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PqExecToShape(theEnv, context, returnValue, "pq-exec-to-facts", FACT_ADDRESS_TYPE);
}

void PqExecToInstancesFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PqExecToShape(theEnv, context, returnValue, "pq-exec-to-instances", INSTANCE_ADDRESS_TYPE);
}

/***************************************************************************/
/*                                                                         */
/* Escaping Strings for Inclusion in SQL Commands                          */
/*                                                                         */
/***************************************************************************/

/* PQescapeLiteral and PQescapeIdentifier: same shape, same ownership -- the
   string libpq returns is ours to free once it has been copied into CLIPS. */
static void PqEscapeWithConn(
  Environment *theEnv,
  UDFContext *context,
  UDFValue *returnValue,
  const char *fname,
  char *(*escape)(PGconn *, const char *, size_t))
{
	UDFValue theArg;
	PGconn *conn;
	const char *text;
	char *escaped;

	if ((conn = PqConnArgument(theEnv, context, returnValue, fname, &theArg)) == NULL)
	{
		return;
	}

	if (!PqTextArgument(theEnv, context, returnValue, fname, "the text to escape", false, &text))
	{
		return;
	}

	escaped = escape(conn, text, strlen(text));
	if (escaped == NULL)
	{
		PqFailConn(theEnv, returnValue, fname, conn);
		return;
	}

	returnValue->lexemeValue = CreateString(theEnv, escaped);
	PQfreemem(escaped);
}

void PqEscapeLiteralFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PqEscapeWithConn(theEnv, context, returnValue, "pq-escape-literal", PQescapeLiteral);
}

void PqEscapeIdentifierFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PqEscapeWithConn(theEnv, context, returnValue, "pq-escape-identifier", PQescapeIdentifier);
}

void PqEscapeStringConnFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGconn *conn;
	const char *text;
	char *escaped;
	size_t length;
	int error = 0;

	if ((conn = PqConnArgument(theEnv, context, returnValue, "pq-escape-string-conn", &theArg)) == NULL)
	{
		return;
	}

	if (!PqTextArgument(theEnv, context, returnValue, "pq-escape-string-conn", "the text to escape", false, &text))
	{
		return;
	}

	length = strlen(text);

	/* The size libpq documents for the output buffer: two bytes per input
	   byte, plus the terminator. */
	escaped = (char *) malloc(2 * length + 1);
	if (escaped == NULL)
	{
		PqFail(theEnv, returnValue, "pq-escape-string-conn", "out of memory");
		return;
	}

	PQescapeStringConn(conn, escaped, text, length, &error);
	if (error != 0)
	{
		free(escaped);
		PqFailConn(theEnv, returnValue, "pq-escape-string-conn", conn);
		return;
	}

	returnValue->lexemeValue = CreateString(theEnv, escaped);
	free(escaped);
}

/* Binary data crosses as a multifield of byte values, so that a NUL in the
   middle of it is a field like any other rather than the end of a string.
   A string is accepted too, for the common case of text going into a bytea. */
static unsigned char *PqBinaryArgument(
  Environment *theEnv,
  UDFContext *context,
  UDFValue *returnValue,
  const char *fname,
  size_t *length)
{
	UDFValue theArg;
	unsigned char *bytes;
	size_t i;
	char msg[128];

	if (!UDFNextArgument(context, LEXEME_BITS | MULTIFIELD_BIT, &theArg))
	{
		PqFail(theEnv, returnValue, fname, "expected a string or a multifield of byte values");
		return NULL;
	}

	if (theArg.header->type == STRING_TYPE || theArg.header->type == SYMBOL_TYPE)
	{
		*length = strlen(theArg.lexemeValue->contents);
		bytes = (unsigned char *) malloc(*length + 1);
		if (bytes == NULL)
		{
			PqFail(theEnv, returnValue, fname, "out of memory");
			return NULL;
		}
		memcpy(bytes, theArg.lexemeValue->contents, *length + 1);
		return bytes;
	}

	if (theArg.header->type != MULTIFIELD_TYPE)
	{
		PqFail(theEnv, returnValue, fname, "expected a string or a multifield of byte values");
		return NULL;
	}

	*length = theArg.multifieldValue->length;
	bytes = (unsigned char *) malloc(*length + 1);
	if (bytes == NULL)
	{
		PqFail(theEnv, returnValue, fname, "out of memory");
		return NULL;
	}

	for (i = 0; i < *length; i++)
	{
		CLIPSValue *field = &theArg.multifieldValue->contents[i];

		if (field->header->type != INTEGER_TYPE ||
		    field->integerValue->contents < 0 ||
		    field->integerValue->contents > 255)
		{
			snprintf(msg, sizeof msg,
			         "field %lu is not a byte value: every field must be an integer from 0 to 255",
			         (unsigned long) (i + 1));
			PqFail(theEnv, returnValue, fname, msg);
			free(bytes);
			return NULL;
		}

		bytes[i] = (unsigned char) field->integerValue->contents;
	}

	bytes[*length] = '\0';
	return bytes;
}

void PqEscapeByteaConnFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGconn *conn;
	unsigned char *bytes, *escaped;
	size_t length, escapedLength;

	if ((conn = PqConnArgument(theEnv, context, returnValue, "pq-escape-bytea-conn", &theArg)) == NULL)
	{
		return;
	}

	bytes = PqBinaryArgument(theEnv, context, returnValue, "pq-escape-bytea-conn", &length);
	if (bytes == NULL)
	{
		return;
	}

	escaped = PQescapeByteaConn(conn, bytes, length, &escapedLength);
	free(bytes);

	if (escaped == NULL)
	{
		PqFailConn(theEnv, returnValue, "pq-escape-bytea-conn", conn);
		return;
	}

	returnValue->lexemeValue = CreateString(theEnv, (const char *) escaped);
	PQfreemem(escaped);
}

void PqUnescapeByteaFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	const char *text;
	unsigned char *bytes;
	size_t length, i;
	MultifieldBuilder *mb;

	if (!PqTextArgument(theEnv, context, returnValue, "pq-unescape-bytea", "the escaped text", false, &text))
	{
		return;
	}

	bytes = PQunescapeBytea((const unsigned char *) text, &length);
	if (bytes == NULL)
	{
		PqFail(theEnv, returnValue, "pq-unescape-bytea",
		       "the text is not a bytea in the format the server sends, or there was no memory for the result");
		return;
	}

	mb = CreateMultifieldBuilder(theEnv, length);
	for (i = 0; i < length; i++)
	{
		MBAppendInteger(mb, bytes[i]);
	}

	returnValue->multifieldValue = MBCreate(mb);
	MBDispose(mb);
	PQfreemem(bytes);
}

/***************************************************************************/
/*                                                                         */
/* Asynchronous Command Processing                                         */
/*                                                                         */
/***************************************************************************/

/* PQsendQuery, and the send-side calls that are a connection and a string:
   1 for sent, 0 for not, and libpq's message for why not. */
static void PqSendConnName(
  Environment *theEnv,
  UDFContext *context,
  UDFValue *returnValue,
  const char *fname,
  const char *what,
  int (*command)(PGconn *, const char *))
{
	UDFValue theArg;
	PGconn *conn;
	const char *name;

	if ((conn = PqConnArgument(theEnv, context, returnValue, fname, &theArg)) == NULL)
	{
		return;
	}

	if (!PqTextArgument(theEnv, context, returnValue, fname, what, false, &name))
	{
		return;
	}

	if (command(conn, name) == 0)
	{
		PqFailConn(theEnv, returnValue, fname, conn);
		return;
	}

	returnValue->lexemeValue = TrueSymbol(theEnv);
}

/* The calls that are a connection and nothing else, and answer 1 or 0. */
static void PqConnCommand(
  Environment *theEnv,
  UDFContext *context,
  UDFValue *returnValue,
  const char *fname,
  int (*command)(PGconn *))
{
	UDFValue theArg;
	PGconn *conn;

	if ((conn = PqConnArgument(theEnv, context, returnValue, fname, &theArg)) == NULL)
	{
		return;
	}

	if (command(conn) == 0)
	{
		PqFailConn(theEnv, returnValue, fname, conn);
		return;
	}

	returnValue->lexemeValue = TrueSymbol(theEnv);
}

void PqSendQueryFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PqSendConnName(theEnv, context, returnValue, "pq-send-query", "the command", PQsendQuery);
}

void PqSendQueryParamsFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGconn *conn;
	const char *command;
	char **values;
	size_t count;
	int sent;

	if ((conn = PqConnArgument(theEnv, context, returnValue, "pq-send-query-params", &theArg)) == NULL)
	{
		return;
	}

	if (!PqTextArgument(theEnv, context, returnValue, "pq-send-query-params", "the command", false, &command))
	{
		return;
	}

	if (!PqParamValues(theEnv, context, returnValue, "pq-send-query-params", &values, &count))
	{
		return;
	}

	sent = PQsendQueryParams(conn, command, (int) count, NULL,
	                         (const char *const *) values, NULL, NULL, 0);

	PqFreeTextArray(values, count);

	if (sent == 0)
	{
		PqFailConn(theEnv, returnValue, "pq-send-query-params", conn);
		return;
	}

	returnValue->lexemeValue = TrueSymbol(theEnv);
}

void PqSendPrepareFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGconn *conn;
	const char *name, *query;

	if ((conn = PqConnArgument(theEnv, context, returnValue, "pq-send-prepare", &theArg)) == NULL)
	{
		return;
	}

	if (!PqTextArgument(theEnv, context, returnValue, "pq-send-prepare", "the statement name", false, &name) ||
	    !PqTextArgument(theEnv, context, returnValue, "pq-send-prepare", "the query", false, &query))
	{
		return;
	}

	if (PQsendPrepare(conn, name, query, 0, NULL) == 0)
	{
		PqFailConn(theEnv, returnValue, "pq-send-prepare", conn);
		return;
	}

	returnValue->lexemeValue = TrueSymbol(theEnv);
}

void PqSendQueryPreparedFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGconn *conn;
	const char *name;
	char **values;
	size_t count;
	int sent;

	if ((conn = PqConnArgument(theEnv, context, returnValue, "pq-send-query-prepared", &theArg)) == NULL)
	{
		return;
	}

	if (!PqTextArgument(theEnv, context, returnValue, "pq-send-query-prepared", "the statement name", false, &name))
	{
		return;
	}

	if (!PqParamValues(theEnv, context, returnValue, "pq-send-query-prepared", &values, &count))
	{
		return;
	}

	sent = PQsendQueryPrepared(conn, name, (int) count,
	                           (const char *const *) values, NULL, NULL, 0);

	PqFreeTextArray(values, count);

	if (sent == 0)
	{
		PqFailConn(theEnv, returnValue, "pq-send-query-prepared", conn);
		return;
	}

	returnValue->lexemeValue = TrueSymbol(theEnv);
}

void PqSendDescribePreparedFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PqSendConnName(theEnv, context, returnValue, "pq-send-describe-prepared",
	               "the statement name", PQsendDescribePrepared);
}

void PqSendDescribePortalFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PqSendConnName(theEnv, context, returnValue, "pq-send-describe-portal",
	               "the portal name", PQsendDescribePortal);
}

#if CLIPSPG_HAVE_17
void PqSendClosePreparedFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PqSendConnName(theEnv, context, returnValue, "pq-send-close-prepared",
	               "the statement name", PQsendClosePrepared);
}

void PqSendClosePortalFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PqSendConnName(theEnv, context, returnValue, "pq-send-close-portal",
	               "the portal name", PQsendClosePortal);
}
#endif

void PqGetResultFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGconn *conn;
	PGresult *result;

	if ((conn = PqConnArgument(theEnv, context, returnValue, "pq-get-result", &theArg)) == NULL)
	{
		return;
	}

	result = PQgetResult(conn);

	/* NULL is how libpq says the command is finished, not that anything went
	   wrong, so this FALSE is the loop's exit and writes no message. */
	if (result == NULL)
	{
		returnValue->lexemeValue = FalseSymbol(theEnv);
		return;
	}

	returnValue->externalAddressValue = CreateCExternalAddress(theEnv, (void *) result);
}

void PqConsumeInputFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PqConnCommand(theEnv, context, returnValue, "pq-consume-input", PQconsumeInput);
}

void PqIsBusyFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGconn *conn;

	if ((conn = PqConnArgument(theEnv, context, returnValue, "pq-is-busy", &theArg)) == NULL)
	{
		return;
	}

	returnValue->lexemeValue = PQisBusy(conn) ? TrueSymbol(theEnv) : FalseSymbol(theEnv);
}

void PqSetnonblockingFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGconn *conn;
	bool nonblocking;

	if ((conn = PqConnArgument(theEnv, context, returnValue, "pq-setnonblocking", &theArg)) == NULL)
	{
		return;
	}

	if (!PqBooleanArgument(theEnv, context, returnValue, "pq-setnonblocking", "the blocking state", &nonblocking))
	{
		return;
	}

	if (PQsetnonblocking(conn, nonblocking ? 1 : 0) != 0)
	{
		PqFailConn(theEnv, returnValue, "pq-setnonblocking", conn);
		return;
	}

	returnValue->lexemeValue = TrueSymbol(theEnv);
}

void PqIsnonblockingFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGconn *conn;

	if ((conn = PqConnArgument(theEnv, context, returnValue, "pq-isnonblocking", &theArg)) == NULL)
	{
		return;
	}

	returnValue->lexemeValue = PQisnonblocking(conn) ? TrueSymbol(theEnv) : FalseSymbol(theEnv);
}

void PqFlushFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGconn *conn;
	int state;

	if ((conn = PqConnArgument(theEnv, context, returnValue, "pq-flush", &theArg)) == NULL)
	{
		return;
	}

	state = PQflush(conn);
	if (state < 0)
	{
		PqFailConn(theEnv, returnValue, "pq-flush", conn);
		return;
	}

	/* 1 means the socket would have blocked and some of the data is still
	   queued: not a failure, and not done either. */
	if (state > 0)
	{
		returnValue->lexemeValue = CreateSymbol(theEnv, "busy");
		return;
	}

	returnValue->lexemeValue = TrueSymbol(theEnv);
}

void PqSetSingleRowModeFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PqConnCommand(theEnv, context, returnValue, "pq-set-single-row-mode", PQsetSingleRowMode);
}

#if CLIPSPG_HAVE_17
void PqSetChunkedRowsModeFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGconn *conn;
	long long rows;

	if ((conn = PqConnArgument(theEnv, context, returnValue, "pq-set-chunked-rows-mode", &theArg)) == NULL)
	{
		return;
	}

	if (!PqIntegerArgument(theEnv, context, returnValue, "pq-set-chunked-rows-mode", "the chunk size", &rows))
	{
		return;
	}

	if (rows <= 0)
	{
		PqFail(theEnv, returnValue, "pq-set-chunked-rows-mode", "the chunk size must be greater than zero");
		return;
	}

	if (PQsetChunkedRowsMode(conn, (int) rows) == 0)
	{
		PqFailConn(theEnv, returnValue, "pq-set-chunked-rows-mode", conn);
		return;
	}

	returnValue->lexemeValue = TrueSymbol(theEnv);
}

void PqSocketPollFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	long long socket, endTime;
	bool forRead, forWrite;
	int ready;

	if (!PqIntegerArgument(theEnv, context, returnValue, "pq-socket-poll", "the socket", &socket) ||
	    !PqBooleanArgument(theEnv, context, returnValue, "pq-socket-poll", "for-read", &forRead) ||
	    !PqBooleanArgument(theEnv, context, returnValue, "pq-socket-poll", "for-write", &forWrite) ||
	    !PqIntegerArgument(theEnv, context, returnValue, "pq-socket-poll", "the end time", &endTime))
	{
		return;
	}

	ready = PQsocketPoll((int) socket, forRead ? 1 : 0, forWrite ? 1 : 0,
	                     (pg_usec_time_t) endTime);
	if (ready < 0)
	{
		PqFail(theEnv, returnValue, "pq-socket-poll", "the socket could not be polled");
		return;
	}

	returnValue->integerValue = CreateInteger(theEnv, ready);
}

void PqGetCurrentTimeUsecFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	returnValue->integerValue = CreateInteger(theEnv, (long long) PQgetCurrentTimeUSec());
}
#endif

/***************************************************************************/
/*                                                                         */
/* Pipeline Mode                                                           */
/*                                                                         */
/***************************************************************************/

void PqPipelineStatusFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGconn *conn;

	if ((conn = PqConnArgument(theEnv, context, returnValue, "pq-pipeline-status", &theArg)) == NULL)
	{
		return;
	}

	returnValue->lexemeValue = CreateSymbol(theEnv, PqEnumName(PqPipelineStatusNames, PQpipelineStatus(conn)));
}

void PqEnterPipelineModeFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PqConnCommand(theEnv, context, returnValue, "pq-enter-pipeline-mode", PQenterPipelineMode);
}

void PqExitPipelineModeFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PqConnCommand(theEnv, context, returnValue, "pq-exit-pipeline-mode", PQexitPipelineMode);
}

void PqPipelineSyncFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PqConnCommand(theEnv, context, returnValue, "pq-pipeline-sync", PQpipelineSync);
}

#if CLIPSPG_HAVE_17
void PqSendPipelineSyncFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PqConnCommand(theEnv, context, returnValue, "pq-send-pipeline-sync", PQsendPipelineSync);
}
#endif

void PqSendFlushRequestFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	PqConnCommand(theEnv, context, returnValue, "pq-send-flush-request", PQsendFlushRequest);
}

/***************************************************************************/
/*                                                                         */
/* Canceling Queries in Progress                                           */
/*                                                                         */
/* The PGcancelConn interface, which is the one PostgreSQL 17 and later    */
/* document. The older PQgetCancel/PQcancel pair is not bound here.        */
/*                                                                         */
/***************************************************************************/

#if CLIPSPG_HAVE_17
void PqCancelCreateFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGconn *conn;
	PGcancelConn *cancelConn;

	if ((conn = PqConnArgument(theEnv, context, returnValue, "pq-cancel-create", &theArg)) == NULL)
	{
		return;
	}

	cancelConn = PQcancelCreate(conn);
	if (cancelConn == NULL)
	{
		PqFail(theEnv, returnValue, "pq-cancel-create", "libpq could not allocate a cancel connection");
		return;
	}

	returnValue->externalAddressValue = CreateCExternalAddress(theEnv, (void *) cancelConn);
}

void PqCancelBlockingFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGcancelConn *cancelConn;

	if ((cancelConn = PqCancelArgument(theEnv, context, returnValue, "pq-cancel-blocking", &theArg)) == NULL)
	{
		return;
	}

	if (PQcancelBlocking(cancelConn) == 0)
	{
		PqFail(theEnv, returnValue, "pq-cancel-blocking", PQcancelErrorMessage(cancelConn));
		return;
	}

	returnValue->lexemeValue = TrueSymbol(theEnv);
}

void PqCancelStartFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGcancelConn *cancelConn;

	if ((cancelConn = PqCancelArgument(theEnv, context, returnValue, "pq-cancel-start", &theArg)) == NULL)
	{
		return;
	}

	if (PQcancelStart(cancelConn) == 0)
	{
		PqFail(theEnv, returnValue, "pq-cancel-start", PQcancelErrorMessage(cancelConn));
		return;
	}

	returnValue->lexemeValue = TrueSymbol(theEnv);
}

void PqCancelPollFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGcancelConn *cancelConn;

	if ((cancelConn = PqCancelArgument(theEnv, context, returnValue, "pq-cancel-poll", &theArg)) == NULL)
	{
		return;
	}

	returnValue->lexemeValue = CreateSymbol(theEnv, PqEnumName(PqPollingStatusNames, PQcancelPoll(cancelConn)));
}

void PqCancelStatusFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGcancelConn *cancelConn;

	if ((cancelConn = PqCancelArgument(theEnv, context, returnValue, "pq-cancel-status", &theArg)) == NULL)
	{
		return;
	}

	returnValue->lexemeValue = CreateSymbol(theEnv, PqEnumName(PqConnStatusNames, PQcancelStatus(cancelConn)));
}

void PqCancelSocketFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGcancelConn *cancelConn;
	int fd;

	if ((cancelConn = PqCancelArgument(theEnv, context, returnValue, "pq-cancel-socket", &theArg)) == NULL)
	{
		return;
	}

	fd = PQcancelSocket(cancelConn);
	if (fd < 0)
	{
		PqFail(theEnv, returnValue, "pq-cancel-socket", "the cancel connection has no open socket");
		return;
	}

	returnValue->integerValue = CreateInteger(theEnv, fd);
}

void PqCancelErrorMessageFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGcancelConn *cancelConn;
	const char *message;

	if ((cancelConn = PqCancelArgument(theEnv, context, returnValue, "pq-cancel-error-message", &theArg)) == NULL)
	{
		return;
	}

	message = PQcancelErrorMessage(cancelConn);
	if (message == NULL || message[0] == '\0')
	{
		returnValue->lexemeValue = FalseSymbol(theEnv);
		return;
	}

	returnValue->lexemeValue = CreateString(theEnv, message);
}

void PqCancelResetFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGcancelConn *cancelConn;

	if ((cancelConn = PqCancelArgument(theEnv, context, returnValue, "pq-cancel-reset", &theArg)) == NULL)
	{
		return;
	}

	PQcancelReset(cancelConn);
	returnValue->lexemeValue = TrueSymbol(theEnv);
}

void PqCancelFinishFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGcancelConn *cancelConn;

	if ((cancelConn = PqCancelArgument(theEnv, context, returnValue, "pq-cancel-finish", &theArg)) == NULL)
	{
		return;
	}

	PQcancelFinish(cancelConn);
	theArg.externalAddressValue->contents = NULL;

	returnValue->lexemeValue = TrueSymbol(theEnv);
}
#endif

/***************************************************************************/
/*                                                                         */
/* Asynchronous Notification                                               */
/*                                                                         */
/***************************************************************************/

void PqNotifiesFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGconn *conn;
	PGnotify *notify;
	MultifieldBuilder *mb;

	if ((conn = PqConnArgument(theEnv, context, returnValue, "pq-notifies", &theArg)) == NULL)
	{
		return;
	}

	notify = PQnotifies(conn);

	/* No notification waiting is the ordinary answer, not a failure. */
	if (notify == NULL)
	{
		returnValue->lexemeValue = FalseSymbol(theEnv);
		return;
	}

	mb = CreateMultifieldBuilder(theEnv, 3);
	MBAppendSymbol(mb, notify->relname);
	MBAppendInteger(mb, notify->be_pid);
	MBAppendString(mb, notify->extra);

	returnValue->multifieldValue = MBCreate(mb);
	MBDispose(mb);
	PQfreemem(notify);
}

/***************************************************************************/
/*                                                                         */
/* Functions Associated with the COPY Command                              */
/*                                                                         */
/***************************************************************************/

void PqPutCopyDataFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGconn *conn;
	unsigned char *bytes;
	size_t length;
	int sent;

	if ((conn = PqConnArgument(theEnv, context, returnValue, "pq-put-copy-data", &theArg)) == NULL)
	{
		return;
	}

	bytes = PqBinaryArgument(theEnv, context, returnValue, "pq-put-copy-data", &length);
	if (bytes == NULL)
	{
		return;
	}

	sent = PQputCopyData(conn, (const char *) bytes, (int) length);
	free(bytes);

	if (sent < 0)
	{
		PqFailConn(theEnv, returnValue, "pq-put-copy-data", conn);
		return;
	}

	/* Zero is the non-blocking connection's "the buffer is full, try the
	   same data again", which is a state and not an error. */
	if (sent == 0)
	{
		returnValue->lexemeValue = CreateSymbol(theEnv, "busy");
		return;
	}

	returnValue->lexemeValue = TrueSymbol(theEnv);
}

void PqPutCopyEndFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGconn *conn;
	const char *errormsg = NULL;
	int sent;

	if ((conn = PqConnArgument(theEnv, context, returnValue, "pq-put-copy-end", &theArg)) == NULL)
	{
		return;
	}

	if (UDFHasNextArgument(context) &&
	    !PqTextArgument(theEnv, context, returnValue, "pq-put-copy-end", "the error message", true, &errormsg))
	{
		return;
	}

	sent = PQputCopyEnd(conn, errormsg);
	if (sent < 0)
	{
		PqFailConn(theEnv, returnValue, "pq-put-copy-end", conn);
		return;
	}

	if (sent == 0)
	{
		returnValue->lexemeValue = CreateSymbol(theEnv, "busy");
		return;
	}

	returnValue->lexemeValue = TrueSymbol(theEnv);
}

void PqGetCopyDataFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGconn *conn;
	bool async = false;
	char *buffer = NULL;
	int length;

	if ((conn = PqConnArgument(theEnv, context, returnValue, "pq-get-copy-data", &theArg)) == NULL)
	{
		return;
	}

	if (UDFHasNextArgument(context) &&
	    !PqBooleanArgument(theEnv, context, returnValue, "pq-get-copy-data", "async", &async))
	{
		return;
	}

	length = PQgetCopyData(conn, &buffer, async ? 1 : 0);

	if (length == -2)
	{
		PQfreemem(buffer);
		PqFailConn(theEnv, returnValue, "pq-get-copy-data", conn);
		return;
	}

	/* -1 is the end of the copy and 0 is "nothing yet, ask again": two
	   symbols, so that neither can be mistaken for a row of data. */
	if (length == -1)
	{
		PQfreemem(buffer);
		returnValue->lexemeValue = CreateSymbol(theEnv, "done");
		return;
	}

	if (length == 0)
	{
		PQfreemem(buffer);
		returnValue->lexemeValue = CreateSymbol(theEnv, "busy");
		return;
	}

	returnValue->lexemeValue = CreateString(theEnv, buffer);
	PQfreemem(buffer);
}

/***************************************************************************/
/*                                                                         */
/* Control Functions                                                       */
/*                                                                         */
/***************************************************************************/

void PqSetClientEncodingFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGconn *conn;
	const char *encoding;

	if ((conn = PqConnArgument(theEnv, context, returnValue, "pq-set-client-encoding", &theArg)) == NULL)
	{
		return;
	}

	if (!PqTextArgument(theEnv, context, returnValue, "pq-set-client-encoding", "the encoding name", false, &encoding))
	{
		return;
	}

	if (PQsetClientEncoding(conn, encoding) != 0)
	{
		PqFailConn(theEnv, returnValue, "pq-set-client-encoding", conn);
		return;
	}

	returnValue->lexemeValue = TrueSymbol(theEnv);
}

void PqSetErrorVerbosityFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGconn *conn;
	int verbosity;

	if ((conn = PqConnArgument(theEnv, context, returnValue, "pq-set-error-verbosity", &theArg)) == NULL)
	{
		return;
	}

	if (!PqEnumArgument(theEnv, context, returnValue, "pq-set-error-verbosity", "an error verbosity",
	                    PqErrorVerbosityNames, &verbosity))
	{
		return;
	}

	returnValue->lexemeValue = CreateSymbol(theEnv,
	    PqEnumName(PqErrorVerbosityNames, PQsetErrorVerbosity(conn, (PGVerbosity) verbosity)));
}

void PqSetErrorContextVisibilityFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGconn *conn;
	int visibility;

	if ((conn = PqConnArgument(theEnv, context, returnValue, "pq-set-error-context-visibility", &theArg)) == NULL)
	{
		return;
	}

	if (!PqEnumArgument(theEnv, context, returnValue, "pq-set-error-context-visibility", "a context visibility",
	                    PqContextVisibilityNames, &visibility))
	{
		return;
	}

	returnValue->lexemeValue = CreateSymbol(theEnv,
	    PqEnumName(PqContextVisibilityNames,
	               PQsetErrorContextVisibility(conn, (PGContextVisibility) visibility)));
}

/***************************************************************************/
/*                                                                         */
/* Miscellaneous Functions                                                 */
/*                                                                         */
/***************************************************************************/

void PqLibVersionFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	returnValue->integerValue = CreateInteger(theEnv, PQlibVersion());
}

/* Which libpq this binding was compiled against, which is what decides
   which functions exist at all. CLIPS gives a program no way to ask whether
   a function is defined, so without this there would be no way to write
   something that uses the newer ones where they are there. */
void PqBuiltVersionFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	returnValue->integerValue = CreateInteger(theEnv, CLIPSPG_PG_VERSION_NUM);
}

void PqIsthreadsafeFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	returnValue->lexemeValue = PQisthreadsafe() ? TrueSymbol(theEnv) : FalseSymbol(theEnv);
}

void PqEncryptPasswordConnFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGconn *conn;
	const char *passwd, *user, *algorithm = NULL;
	char *encrypted;

	if ((conn = PqConnArgument(theEnv, context, returnValue, "pq-encrypt-password-conn", &theArg)) == NULL)
	{
		return;
	}

	if (!PqTextArgument(theEnv, context, returnValue, "pq-encrypt-password-conn", "the password", false, &passwd) ||
	    !PqTextArgument(theEnv, context, returnValue, "pq-encrypt-password-conn", "the user name", false, &user))
	{
		return;
	}

	if (UDFHasNextArgument(context) &&
	    !PqTextArgument(theEnv, context, returnValue, "pq-encrypt-password-conn", "the algorithm", true, &algorithm))
	{
		return;
	}

	encrypted = PQencryptPasswordConn(conn, passwd, user, algorithm);
	if (encrypted == NULL)
	{
		PqFailConn(theEnv, returnValue, "pq-encrypt-password-conn", conn);
		return;
	}

	returnValue->lexemeValue = CreateString(theEnv, encrypted);
	PQfreemem(encrypted);
}

#if CLIPSPG_HAVE_17
void PqChangePasswordFunction(Environment *theEnv, UDFContext *context, UDFValue *returnValue)
{
	UDFValue theArg;
	PGconn *conn;
	const char *user, *passwd;

	if ((conn = PqConnArgument(theEnv, context, returnValue, "pq-change-password", &theArg)) == NULL)
	{
		return;
	}

	if (!PqTextArgument(theEnv, context, returnValue, "pq-change-password", "the user name", false, &user) ||
	    !PqTextArgument(theEnv, context, returnValue, "pq-change-password", "the password", false, &passwd))
	{
		return;
	}

	PqReturnResult(theEnv, returnValue, "pq-change-password", conn,
	               PQchangePassword(conn, user, passwd));
}
#endif

/*******************************************************/
/* UserFunctions: Informs the expert system environment */
/*   of any user defined functions.                     */
/*                                                      */
/* Each registration carries the annotation API.md is   */
/* generated from. A doc-group comment opens a section  */
/* of the reference; the doc comment trailing a         */
/* registration names that function's arguments in call */
/* order, with "?" marking an optional one, and the     */
/* kind of value it answers with.                       */
/*                                                      */
/* docs/gen-api-docs.sh reads them, takes the prose for */
/* each function from the PostgreSQL documentation for  */
/* the libpq being built against, and refuses to write  */
/* a reference in which a registration here has no      */
/* annotation.                                          */
/*******************************************************/

void UserFunctions(
  Environment *env)
{
	/* doc-group: Database Connection Control Functions */
	AddUDF(env,"pq-connectdb","be",0,1,";sy",PqConnectdbFunction,"PqConnectdbFunction",NULL);  /* doc: conninfo? -> handle */
	AddUDF(env,"pq-connectdb-params","be",2,3,";m;m;b",PqConnectdbParamsFunction,"PqConnectdbParamsFunction",NULL);  /* doc: keywords values expand-dbname? -> handle */
	AddUDF(env,"pq-setdb-login","be",7,7,";sy;sy;sy;sy;sy;sy;sy",PqSetdbLoginFunction,"PqSetdbLoginFunction",NULL);  /* doc: pghost pgport pgoptions pgtty dbname login pwd -> handle */
	AddUDF(env,"pq-connect-start","be",0,1,";sy",PqConnectStartFunction,"PqConnectStartFunction",NULL);  /* doc: conninfo? -> handle */
	AddUDF(env,"pq-connect-start-params","be",2,3,";m;m;b",PqConnectStartParamsFunction,"PqConnectStartParamsFunction",NULL);  /* doc: keywords values expand-dbname? -> handle */
	AddUDF(env,"pq-connect-poll","by",1,1,";e",PqConnectPollFunction,"PqConnectPollFunction",NULL);  /* doc: conn -> symbol */
	AddUDF(env,"pq-finish","b",1,1,";e",PqFinishFunction,"PqFinishFunction",NULL);  /* doc: conn -> boolean */
	AddUDF(env,"pq-reset","b",1,1,";e",PqResetFunction,"PqResetFunction",NULL);  /* doc: conn -> boolean */
	AddUDF(env,"pq-reset-start","b",1,1,";e",PqResetStartFunction,"PqResetStartFunction",NULL);  /* doc: conn -> boolean */
	AddUDF(env,"pq-reset-poll","by",1,1,";e",PqResetPollFunction,"PqResetPollFunction",NULL);  /* doc: conn -> symbol */
	AddUDF(env,"pq-ping","by",0,1,";sy",PqPingFunction,"PqPingFunction",NULL);  /* doc: conninfo? -> symbol */
	AddUDF(env,"pq-ping-params","by",2,3,";m;m;b",PqPingParamsFunction,"PqPingParamsFunction",NULL);  /* doc: keywords values expand-dbname? -> symbol */
	AddUDF(env,"pq-conndefaults","bm",0,0,NULL,PqConndefaultsFunction,"PqConndefaultsFunction",NULL);  /* doc: -> multifield */
	AddUDF(env,"pq-conninfo","bm",1,1,";e",PqConninfoFunction,"PqConninfoFunction",NULL);  /* doc: conn -> multifield */
	AddUDF(env,"pq-conninfo-parse","bm",1,1,";sy",PqConninfoParseFunction,"PqConninfoParseFunction",NULL);  /* doc: conninfo -> multifield */

	/* doc-group: Connection Status Functions */
	AddUDF(env,"pq-db","bs",1,1,";e",PqDbFunction,"PqDbFunction",NULL);  /* doc: conn -> string */
	AddUDF(env,"pq-user","bs",1,1,";e",PqUserFunction,"PqUserFunction",NULL);  /* doc: conn -> string */
	AddUDF(env,"pq-pass","bs",1,1,";e",PqPassFunction,"PqPassFunction",NULL);  /* doc: conn -> string */
	AddUDF(env,"pq-host","bs",1,1,";e",PqHostFunction,"PqHostFunction",NULL);  /* doc: conn -> string */
	AddUDF(env,"pq-hostaddr","bs",1,1,";e",PqHostaddrFunction,"PqHostaddrFunction",NULL);  /* doc: conn -> string */
	AddUDF(env,"pq-port","bs",1,1,";e",PqPortFunction,"PqPortFunction",NULL);  /* doc: conn -> string */
	AddUDF(env,"pq-options","bs",1,1,";e",PqOptionsFunction,"PqOptionsFunction",NULL);  /* doc: conn -> string */
	AddUDF(env,"pq-status","by",1,1,";e",PqStatusFunction,"PqStatusFunction",NULL);  /* doc: conn -> symbol */
	AddUDF(env,"pq-transaction-status","by",1,1,";e",PqTransactionStatusFunction,"PqTransactionStatusFunction",NULL);  /* doc: conn -> symbol */
	AddUDF(env,"pq-parameter-status","bs",2,2,";e;sy",PqParameterStatusFunction,"PqParameterStatusFunction",NULL);  /* doc: conn param-name -> string */
	AddUDF(env,"pq-protocol-version","bl",1,1,";e",PqProtocolVersionFunction,"PqProtocolVersionFunction",NULL);  /* doc: conn -> integer */
#if CLIPSPG_HAVE_18
	AddUDF(env,"pq-full-protocol-version","bl",1,1,";e",PqFullProtocolVersionFunction,"PqFullProtocolVersionFunction",NULL);  /* doc: conn -> integer */
#endif
	AddUDF(env,"pq-server-version","bl",1,1,";e",PqServerVersionFunction,"PqServerVersionFunction",NULL);  /* doc: conn -> integer */
	AddUDF(env,"pq-error-message","bs",1,1,";e",PqErrorMessageFunction,"PqErrorMessageFunction",NULL);  /* doc: conn -> string */
	AddUDF(env,"pq-socket","bl",1,1,";e",PqSocketFunction,"PqSocketFunction",NULL);  /* doc: conn -> integer */
	AddUDF(env,"pq-backend-pid","bl",1,1,";e",PqBackendPidFunction,"PqBackendPidFunction",NULL);  /* doc: conn -> integer */
	AddUDF(env,"pq-connection-needs-password","b",1,1,";e",PqConnectionNeedsPasswordFunction,"PqConnectionNeedsPasswordFunction",NULL);  /* doc: conn -> boolean */
	AddUDF(env,"pq-connection-used-password","b",1,1,";e",PqConnectionUsedPasswordFunction,"PqConnectionUsedPasswordFunction",NULL);  /* doc: conn -> boolean */
#if CLIPSPG_HAVE_16
	AddUDF(env,"pq-connection-used-gssapi","b",1,1,";e",PqConnectionUsedGssapiFunction,"PqConnectionUsedGssapiFunction",NULL);  /* doc: conn -> boolean */
#endif
	AddUDF(env,"pq-ssl-in-use","b",1,1,";e",PqSslInUseFunction,"PqSslInUseFunction",NULL);  /* doc: conn -> boolean */
	AddUDF(env,"pq-gss-enc-in-use","b",1,1,";e",PqGssEncInUseFunction,"PqGssEncInUseFunction",NULL);  /* doc: conn -> boolean */
	AddUDF(env,"pq-ssl-attribute","bs",2,2,";e;sy",PqSslAttributeFunction,"PqSslAttributeFunction",NULL);  /* doc: conn attribute-name -> string */
	AddUDF(env,"pq-ssl-attribute-names","bm",1,1,";e",PqSslAttributeNamesFunction,"PqSslAttributeNamesFunction",NULL);  /* doc: conn -> multifield */
	AddUDF(env,"pq-client-encoding","bl",1,1,";e",PqClientEncodingFunction,"PqClientEncodingFunction",NULL);  /* doc: conn -> integer */

	/* doc-group: Command Execution Functions */
	AddUDF(env,"pq-exec","be",2,2,";e;sy",PqExecFunction,"PqExecFunction",NULL);  /* doc: conn command -> handle */
	AddUDF(env,"pq-exec-params","be",2,3,";e;sy;m",PqExecParamsFunction,"PqExecParamsFunction",NULL);  /* doc: conn command params? -> handle */
	AddUDF(env,"pq-prepare","be",3,3,";e;sy;sy",PqPrepareFunction,"PqPrepareFunction",NULL);  /* doc: conn statement-name query -> handle */
	AddUDF(env,"pq-exec-prepared","be",2,3,";e;sy;m",PqExecPreparedFunction,"PqExecPreparedFunction",NULL);  /* doc: conn statement-name params? -> handle */
	AddUDF(env,"pq-describe-prepared","be",2,2,";e;sy",PqDescribePreparedFunction,"PqDescribePreparedFunction",NULL);  /* doc: conn statement-name -> handle */
	AddUDF(env,"pq-describe-portal","be",2,2,";e;sy",PqDescribePortalFunction,"PqDescribePortalFunction",NULL);  /* doc: conn portal-name -> handle */
#if CLIPSPG_HAVE_17
	AddUDF(env,"pq-close-prepared","be",2,2,";e;sy",PqClosePreparedFunction,"PqClosePreparedFunction",NULL);  /* doc: conn statement-name -> handle */
	AddUDF(env,"pq-close-portal","be",2,2,";e;sy",PqClosePortalFunction,"PqClosePortalFunction",NULL);  /* doc: conn portal-name -> handle */
#endif
	AddUDF(env,"pq-make-empty-pgresult","be",2,2,";e;lsy",PqMakeEmptyPgresultFunction,"PqMakeEmptyPgresultFunction",NULL);  /* doc: conn status -> handle */
	AddUDF(env,"pq-clear","b",1,1,";e",PqClearFunction,"PqClearFunction",NULL);  /* doc: res -> boolean */

	/* doc-group: Retrieving Query Result Information */
	AddUDF(env,"pq-result-status","by",1,1,";e",PqResultStatusFunction,"PqResultStatusFunction",NULL);  /* doc: res -> symbol */
	AddUDF(env,"pq-res-status","bs",1,1,";lsy",PqResStatusFunction,"PqResStatusFunction",NULL);  /* doc: status -> string */
	AddUDF(env,"pq-result-error-message","bs",1,1,";e",PqResultErrorMessageFunction,"PqResultErrorMessageFunction",NULL);  /* doc: res -> string */
	AddUDF(env,"pq-result-verbose-error-message","bs",3,3,";e;lsy;lsy",PqResultVerboseErrorMessageFunction,"PqResultVerboseErrorMessageFunction",NULL);  /* doc: res verbosity show-context -> string */
	AddUDF(env,"pq-result-error-field","bs",2,2,";e;lsy",PqResultErrorFieldFunction,"PqResultErrorFieldFunction",NULL);  /* doc: res fieldcode -> string */
	AddUDF(env,"pq-ntuples","bl",1,1,";e",PqNtuplesFunction,"PqNtuplesFunction",NULL);  /* doc: res -> integer */
	AddUDF(env,"pq-nfields","bl",1,1,";e",PqNfieldsFunction,"PqNfieldsFunction",NULL);  /* doc: res -> integer */
	AddUDF(env,"pq-fname","bs",2,2,";e;l",PqFnameFunction,"PqFnameFunction",NULL);  /* doc: res column-number -> string */
	AddUDF(env,"pq-fnumber","bl",2,2,";e;sy",PqFnumberFunction,"PqFnumberFunction",NULL);  /* doc: res column-name -> integer */
	AddUDF(env,"pq-ftable","bl",2,2,";e;l",PqFtableFunction,"PqFtableFunction",NULL);  /* doc: res column-number -> integer */
	AddUDF(env,"pq-ftablecol","bl",2,2,";e;l",PqFtablecolFunction,"PqFtablecolFunction",NULL);  /* doc: res column-number -> integer */
	AddUDF(env,"pq-fformat","bl",2,2,";e;l",PqFformatFunction,"PqFformatFunction",NULL);  /* doc: res column-number -> integer */
	AddUDF(env,"pq-ftype","bl",2,2,";e;l",PqFtypeFunction,"PqFtypeFunction",NULL);  /* doc: res column-number -> integer */
	AddUDF(env,"pq-fmod","bl",2,2,";e;l",PqFmodFunction,"PqFmodFunction",NULL);  /* doc: res column-number -> integer */
	AddUDF(env,"pq-fsize","bl",2,2,";e;l",PqFsizeFunction,"PqFsizeFunction",NULL);  /* doc: res column-number -> integer */
	AddUDF(env,"pq-binary-tuples","b",1,1,";e",PqBinaryTuplesFunction,"PqBinaryTuplesFunction",NULL);  /* doc: res -> boolean */
	AddUDF(env,"pq-getvalue","bsy",3,3,";e;l;l",PqGetvalueFunction,"PqGetvalueFunction",NULL);  /* doc: res row-number column-number -> string */
	AddUDF(env,"pq-getisnull","b",3,3,";e;l;l",PqGetisnullFunction,"PqGetisnullFunction",NULL);  /* doc: res row-number column-number -> boolean */
	AddUDF(env,"pq-getlength","bl",3,3,";e;l;l",PqGetlengthFunction,"PqGetlengthFunction",NULL);  /* doc: res row-number column-number -> integer */
	AddUDF(env,"pq-nparams","bl",1,1,";e",PqNparamsFunction,"PqNparamsFunction",NULL);  /* doc: res -> integer */
	AddUDF(env,"pq-paramtype","bl",2,2,";e;l",PqParamtypeFunction,"PqParamtypeFunction",NULL);  /* doc: res param-number -> integer */

	/* doc-group: Retrieving Other Result Information */
	AddUDF(env,"pq-cmd-status","bs",1,1,";e",PqCmdStatusFunction,"PqCmdStatusFunction",NULL);  /* doc: res -> string */
	AddUDF(env,"pq-cmd-tuples","bl",1,1,";e",PqCmdTuplesFunction,"PqCmdTuplesFunction",NULL);  /* doc: res -> integer */
	AddUDF(env,"pq-oid-value","bl",1,1,";e",PqOidValueFunction,"PqOidValueFunction",NULL);  /* doc: res -> integer */
	AddUDF(env,"pq-result-memory-size","bl",1,1,";e",PqResultMemorySizeFunction,"PqResultMemorySizeFunction",NULL);  /* doc: res -> integer */

	/* doc-group: Escaping Strings for Inclusion in SQL Commands */
	AddUDF(env,"pq-escape-literal","bs",2,2,";e;sy",PqEscapeLiteralFunction,"PqEscapeLiteralFunction",NULL);  /* doc: conn str -> string */
	AddUDF(env,"pq-escape-identifier","bs",2,2,";e;sy",PqEscapeIdentifierFunction,"PqEscapeIdentifierFunction",NULL);  /* doc: conn str -> string */
	AddUDF(env,"pq-escape-string-conn","bs",2,2,";e;sy",PqEscapeStringConnFunction,"PqEscapeStringConnFunction",NULL);  /* doc: conn from -> string */
	AddUDF(env,"pq-escape-bytea-conn","bs",2,2,";e;smy",PqEscapeByteaConnFunction,"PqEscapeByteaConnFunction",NULL);  /* doc: conn from -> string */
	AddUDF(env,"pq-unescape-bytea","bm",1,1,";sy",PqUnescapeByteaFunction,"PqUnescapeByteaFunction",NULL);  /* doc: from -> multifield */

	/* doc-group: Rows as CLIPS Data */
	AddUDF(env,"pq-row-to-multifield","bm",2,2,";e;l",PqRowToMultifieldFunction,"PqRowToMultifieldFunction",NULL);  /* doc: res row-number -> multifield */
	AddUDF(env,"pq-row-to-fact","bf",3,3,";e;l;y",PqRowToFactFunction,"PqRowToFactFunction",NULL);  /* doc: res row-number deftemplate -> fact */
	AddUDF(env,"pq-row-to-instance","bi",3,5,";e;l;y;y;y",PqRowToInstanceFunction,"PqRowToInstanceFunction",NULL);  /* doc: res row-number defclass instance-name? name-slot? -> instance */
	AddUDF(env,"pq-result-to-multifields","bm",1,2,";e;b",PqResultToMultifieldsFunction,"PqResultToMultifieldsFunction",NULL);  /* doc: res headers? -> multifield */
	AddUDF(env,"pq-result-to-facts","bm",2,2,";e;sy",PqResultToFactsFunction,"PqResultToFactsFunction",NULL);  /* doc: res deftemplate -> multifield */
	AddUDF(env,"pq-result-to-instances","bm",2,3,";e;sy;mnsy",PqResultToInstancesFunction,"PqResultToInstancesFunction",NULL);  /* doc: res defclass instance-names? -> multifield */
	AddUDF(env,"pq-exec-to-multifields","bm",2,3,";e;sy;b",PqExecToMultifieldsFunction,"PqExecToMultifieldsFunction",NULL);  /* doc: conn command headers? -> multifield */
	AddUDF(env,"pq-exec-to-facts","bm",2,3,";e;sy;sy",PqExecToFactsFunction,"PqExecToFactsFunction",NULL);  /* doc: conn command deftemplate? -> multifield */
	AddUDF(env,"pq-exec-to-instances","bm",2,4,";e;sy;mnsy;mnsy",PqExecToInstancesFunction,"PqExecToInstancesFunction",NULL);  /* doc: conn command defclass? instance-names? -> multifield */

	/* doc-group: Asynchronous Command Processing */
	AddUDF(env,"pq-send-query","b",2,2,";e;sy",PqSendQueryFunction,"PqSendQueryFunction",NULL);  /* doc: conn command -> boolean */
	AddUDF(env,"pq-send-query-params","b",2,3,";e;sy;m",PqSendQueryParamsFunction,"PqSendQueryParamsFunction",NULL);  /* doc: conn command params? -> boolean */
	AddUDF(env,"pq-send-prepare","b",3,3,";e;sy;sy",PqSendPrepareFunction,"PqSendPrepareFunction",NULL);  /* doc: conn statement-name query -> boolean */
	AddUDF(env,"pq-send-query-prepared","b",2,3,";e;sy;m",PqSendQueryPreparedFunction,"PqSendQueryPreparedFunction",NULL);  /* doc: conn statement-name params? -> boolean */
	AddUDF(env,"pq-send-describe-prepared","b",2,2,";e;sy",PqSendDescribePreparedFunction,"PqSendDescribePreparedFunction",NULL);  /* doc: conn statement-name -> boolean */
	AddUDF(env,"pq-send-describe-portal","b",2,2,";e;sy",PqSendDescribePortalFunction,"PqSendDescribePortalFunction",NULL);  /* doc: conn portal-name -> boolean */
#if CLIPSPG_HAVE_17
	AddUDF(env,"pq-send-close-prepared","b",2,2,";e;sy",PqSendClosePreparedFunction,"PqSendClosePreparedFunction",NULL);  /* doc: conn statement-name -> boolean */
	AddUDF(env,"pq-send-close-portal","b",2,2,";e;sy",PqSendClosePortalFunction,"PqSendClosePortalFunction",NULL);  /* doc: conn portal-name -> boolean */
#endif
	AddUDF(env,"pq-get-result","be",1,1,";e",PqGetResultFunction,"PqGetResultFunction",NULL);  /* doc: conn -> handle */
	AddUDF(env,"pq-consume-input","b",1,1,";e",PqConsumeInputFunction,"PqConsumeInputFunction",NULL);  /* doc: conn -> boolean */
	AddUDF(env,"pq-is-busy","b",1,1,";e",PqIsBusyFunction,"PqIsBusyFunction",NULL);  /* doc: conn -> boolean */
	AddUDF(env,"pq-setnonblocking","b",2,2,";e;b",PqSetnonblockingFunction,"PqSetnonblockingFunction",NULL);  /* doc: conn arg -> boolean */
	AddUDF(env,"pq-isnonblocking","b",1,1,";e",PqIsnonblockingFunction,"PqIsnonblockingFunction",NULL);  /* doc: conn -> boolean */
	AddUDF(env,"pq-flush","by",1,1,";e",PqFlushFunction,"PqFlushFunction",NULL);  /* doc: conn -> symbol */
	AddUDF(env,"pq-set-single-row-mode","b",1,1,";e",PqSetSingleRowModeFunction,"PqSetSingleRowModeFunction",NULL);  /* doc: conn -> boolean */
#if CLIPSPG_HAVE_17
	AddUDF(env,"pq-set-chunked-rows-mode","b",2,2,";e;l",PqSetChunkedRowsModeFunction,"PqSetChunkedRowsModeFunction",NULL);  /* doc: conn chunk-size -> boolean */
	AddUDF(env,"pq-socket-poll","bl",4,4,";l;b;b;l",PqSocketPollFunction,"PqSocketPollFunction",NULL);  /* doc: sock for-read for-write end-time -> integer */
	AddUDF(env,"pq-get-current-time-usec","l",0,0,NULL,PqGetCurrentTimeUsecFunction,"PqGetCurrentTimeUsecFunction",NULL);  /* doc: -> integer */
#endif

	/* doc-group: Pipeline Mode */
	AddUDF(env,"pq-pipeline-status","by",1,1,";e",PqPipelineStatusFunction,"PqPipelineStatusFunction",NULL);  /* doc: conn -> symbol */
	AddUDF(env,"pq-enter-pipeline-mode","b",1,1,";e",PqEnterPipelineModeFunction,"PqEnterPipelineModeFunction",NULL);  /* doc: conn -> boolean */
	AddUDF(env,"pq-exit-pipeline-mode","b",1,1,";e",PqExitPipelineModeFunction,"PqExitPipelineModeFunction",NULL);  /* doc: conn -> boolean */
	AddUDF(env,"pq-pipeline-sync","b",1,1,";e",PqPipelineSyncFunction,"PqPipelineSyncFunction",NULL);  /* doc: conn -> boolean */
#if CLIPSPG_HAVE_17
	AddUDF(env,"pq-send-pipeline-sync","b",1,1,";e",PqSendPipelineSyncFunction,"PqSendPipelineSyncFunction",NULL);  /* doc: conn -> boolean */
#endif
	AddUDF(env,"pq-send-flush-request","b",1,1,";e",PqSendFlushRequestFunction,"PqSendFlushRequestFunction",NULL);  /* doc: conn -> boolean */

	/* doc-group: Canceling Queries in Progress */
#if CLIPSPG_HAVE_17
	AddUDF(env,"pq-cancel-create","be",1,1,";e",PqCancelCreateFunction,"PqCancelCreateFunction",NULL);  /* doc: conn -> handle */
	AddUDF(env,"pq-cancel-blocking","b",1,1,";e",PqCancelBlockingFunction,"PqCancelBlockingFunction",NULL);  /* doc: cancel-conn -> boolean */
	AddUDF(env,"pq-cancel-start","b",1,1,";e",PqCancelStartFunction,"PqCancelStartFunction",NULL);  /* doc: cancel-conn -> boolean */
	AddUDF(env,"pq-cancel-poll","by",1,1,";e",PqCancelPollFunction,"PqCancelPollFunction",NULL);  /* doc: cancel-conn -> symbol */
	AddUDF(env,"pq-cancel-status","by",1,1,";e",PqCancelStatusFunction,"PqCancelStatusFunction",NULL);  /* doc: cancel-conn -> symbol */
	AddUDF(env,"pq-cancel-socket","bl",1,1,";e",PqCancelSocketFunction,"PqCancelSocketFunction",NULL);  /* doc: cancel-conn -> integer */
	AddUDF(env,"pq-cancel-error-message","bs",1,1,";e",PqCancelErrorMessageFunction,"PqCancelErrorMessageFunction",NULL);  /* doc: cancel-conn -> string */
	AddUDF(env,"pq-cancel-reset","b",1,1,";e",PqCancelResetFunction,"PqCancelResetFunction",NULL);  /* doc: cancel-conn -> boolean */
	AddUDF(env,"pq-cancel-finish","b",1,1,";e",PqCancelFinishFunction,"PqCancelFinishFunction",NULL);  /* doc: cancel-conn -> boolean */
#endif

	/* doc-group: Asynchronous Notification */
	AddUDF(env,"pq-notifies","bm",1,1,";e",PqNotifiesFunction,"PqNotifiesFunction",NULL);  /* doc: conn -> multifield */

	/* doc-group: Functions Associated with the COPY Command */
	AddUDF(env,"pq-put-copy-data","by",2,2,";e;smy",PqPutCopyDataFunction,"PqPutCopyDataFunction",NULL);  /* doc: conn buffer -> symbol */
	AddUDF(env,"pq-put-copy-end","by",1,2,";e;sy",PqPutCopyEndFunction,"PqPutCopyEndFunction",NULL);  /* doc: conn errormsg? -> symbol */
	AddUDF(env,"pq-get-copy-data","bsy",1,2,";e;b",PqGetCopyDataFunction,"PqGetCopyDataFunction",NULL);  /* doc: conn async? -> string */

	/* doc-group: Control Functions */
	AddUDF(env,"pq-set-client-encoding","b",2,2,";e;sy",PqSetClientEncodingFunction,"PqSetClientEncodingFunction",NULL);  /* doc: conn encoding -> boolean */
	AddUDF(env,"pq-set-error-verbosity","by",2,2,";e;lsy",PqSetErrorVerbosityFunction,"PqSetErrorVerbosityFunction",NULL);  /* doc: conn verbosity -> symbol */
	AddUDF(env,"pq-set-error-context-visibility","by",2,2,";e;lsy",PqSetErrorContextVisibilityFunction,"PqSetErrorContextVisibilityFunction",NULL);  /* doc: conn show-context -> symbol */

	/* doc-group: Miscellaneous Functions */
	AddUDF(env,"pq-lib-version","l",0,0,NULL,PqLibVersionFunction,"PqLibVersionFunction",NULL);  /* doc: -> integer */
	AddUDF(env,"pq-built-version","l",0,0,NULL,PqBuiltVersionFunction,"PqBuiltVersionFunction",NULL);  /* doc: -> integer */
	AddUDF(env,"pq-isthreadsafe","b",0,0,NULL,PqIsthreadsafeFunction,"PqIsthreadsafeFunction",NULL);  /* doc: -> boolean */
	AddUDF(env,"pq-encrypt-password-conn","bs",3,4,";e;sy;sy;sy",PqEncryptPasswordConnFunction,"PqEncryptPasswordConnFunction",NULL);  /* doc: conn passwd user algorithm? -> string */
#if CLIPSPG_HAVE_17
	AddUDF(env,"pq-change-password","be",3,3,";e;sy;sy",PqChangePasswordFunction,"PqChangePasswordFunction",NULL);  /* doc: conn user passwd -> handle */
#endif
}

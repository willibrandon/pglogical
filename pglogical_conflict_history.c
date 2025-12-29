/*-------------------------------------------------------------------------
 *
 * pglogical_conflict_history.c
 *		pglogical conflict history persistence
 *
 * This module provides functionality to record replication conflicts
 * to a queryable table (pglogical.conflict_history) for monitoring
 * and analysis purposes.
 *
 * Copyright (c) 2015, PostgreSQL Global Development Group
 *
 * IDENTIFICATION
 *		pglogical_conflict_history.c
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "access/htup_details.h"
#include "access/xact.h"
#include "catalog/namespace.h"
#include "catalog/pg_type.h"
#include "executor/spi.h"
#include "replication/origin.h"
#include "utils/builtins.h"
#include "utils/jsonb.h"
#include "utils/lsyscache.h"
#include "utils/rel.h"
#include "utils/syscache.h"

#include "pglogical.h"
#include "pglogical_worker.h"
#include "pglogical_conflict_history.h"

/* GUC variables */
bool	pglogical_conflict_history_enabled = false;
bool	pglogical_conflict_history_store_tuples = true;
int		pglogical_conflict_history_max_tuple_size = 1024;

/* Internal function prototypes */
static Datum tuple_to_jsonb(TupleDesc tupdesc, HeapTuple tuple, int max_size);
static const char *conflict_type_to_string(PGLogicalConflictType type);
static const char *resolution_to_string(PGLogicalConflictResolution res);
static void ensure_partition_exists(void);

/*
 * Convert a conflict type enum to its string representation for storage.
 */
static const char *
conflict_type_to_string(PGLogicalConflictType type)
{
	switch (type)
	{
		case CONFLICT_INSERT_INSERT:
			return "insert_insert";
		case CONFLICT_UPDATE_UPDATE:
			return "update_update";
		case CONFLICT_UPDATE_DELETE:
			return "update_delete";
		case CONFLICT_DELETE_DELETE:
			return "delete_delete";
		default:
			return "unknown";
	}
}

/*
 * Convert a resolution enum to its string representation for storage.
 */
static const char *
resolution_to_string(PGLogicalConflictResolution res)
{
	switch (res)
	{
		case PGLogicalResolution_ApplyRemote:
			return "apply_remote";
		case PGLogicalResolution_KeepLocal:
			return "keep_local";
		case PGLogicalResolution_Skip:
			return "skip";
		default:
			return "unknown";
	}
}

/*
 * Convert a HeapTuple to a JSONB datum for storage.
 *
 * This function iterates through all user columns, converts their values
 * to strings, and constructs a JSONB object. It handles:
 * - NULL values (stored as JSON null)
 * - Dropped columns (skipped)
 * - System columns (skipped)
 * - External TOAST values (stored as "(unchanged-toast-datum)")
 * - Value truncation for large fields
 *
 * Returns (Datum) 0 if the tuple is NULL.
 */
static Datum
tuple_to_jsonb(TupleDesc tupdesc, HeapTuple tuple, int max_size)
{
	JsonbParseState *state = NULL;
	JsonbValue *result;
	int			natt;

	if (tuple == NULL)
		return (Datum) 0;

	pushJsonbValue(&state, WJB_BEGIN_OBJECT, NULL);

	for (natt = 0; natt < tupdesc->natts; natt++)
	{
		Form_pg_attribute attr = TupleDescAttr(tupdesc, natt);
		Oid			typid;
		Oid			typoutput;
		bool		typisvarlena;
		Datum		origval;
		bool		isnull;
		JsonbValue	key;
		JsonbValue	val;

		/* Skip dropped columns */
		if (attr->attisdropped)
			continue;

		/* Skip system columns */
		if (attr->attnum < 0)
			continue;

		typid = attr->atttypid;

		/* Add column name as key */
		key.type = jbvString;
		key.val.string.len = strlen(NameStr(attr->attname));
		key.val.string.val = pstrdup(NameStr(attr->attname));
		pushJsonbValue(&state, WJB_KEY, &key);

		/* Get the value */
		origval = heap_getattr(tuple, natt + 1, tupdesc, &isnull);

		if (isnull)
		{
			/* NULL SQL value becomes JSON null */
			val.type = jbvNull;
			pushJsonbValue(&state, WJB_VALUE, &val);
		}
		else
		{
			char *outputstr = NULL;

			/* Check for external TOAST datum */
			getTypeOutputInfo(typid, &typoutput, &typisvarlena);

			if (typisvarlena && VARATT_IS_EXTERNAL_ONDISK(origval))
			{
				outputstr = "(unchanged-toast-datum)";
			}
			else
			{
				Datum detoasted;

				if (typisvarlena)
					detoasted = PointerGetDatum(PG_DETOAST_DATUM(origval));
				else
					detoasted = origval;

				outputstr = OidOutputFunctionCall(typoutput, detoasted);

				/* Truncate if necessary */
				if (strlen(outputstr) > (size_t) max_size)
				{
					outputstr[max_size] = '\0';
				}
			}

			val.type = jbvString;
			val.val.string.len = strlen(outputstr);
			val.val.string.val = pstrdup(outputstr);
			pushJsonbValue(&state, WJB_VALUE, &val);
		}
	}

	result = pushJsonbValue(&state, WJB_END_OBJECT, NULL);

	return JsonbPGetDatum(JsonbValueToJsonb(result));
}

/*
 * Ensure that a partition exists for the current date.
 *
 * This calls the SQL function pglogical.conflict_history_ensure_partition()
 * which handles creating the partition if it doesn't exist.
 */
static void
ensure_partition_exists(void)
{
	int			ret;

	ret = SPI_execute("SELECT pglogical.conflict_history_ensure_partition(CURRENT_DATE)", false, 0);

	if (ret != SPI_OK_SELECT)
	{
		elog(WARNING, "conflict_history: failed to ensure partition exists: %d", ret);
	}
}

/*
 * Record a conflict to the pglogical.conflict_history table.
 *
 * This function is called from pglogical_report_conflict() after the
 * conflict has been resolved. It stores the conflict information for
 * later querying and analysis.
 *
 * The function uses PG_TRY/PG_CATCH to ensure that any failures in
 * recording do not abort the apply worker transaction. This is critical
 * because recording is purely observational and should never interfere
 * with replication.
 */
void
pglogical_record_conflict(PGLogicalConflictType conflict_type,
						  PGLogicalRelation *rel,
						  HeapTuple localtuple,
						  HeapTuple remotetuple,
						  PGLogicalConflictResolution resolution,
						  TransactionId local_tuple_xid,
						  bool found_local_origin,
						  RepOriginId local_tuple_origin,
						  TimestampTz local_tuple_commit_ts,
						  Oid conflict_idx_oid,
						  bool has_before_triggers)
{
	static const char *insert_sql =
		"INSERT INTO pglogical.conflict_history ("
		"sub_id, sub_name, conflict_type, resolution, "
		"schema_name, table_name, index_name, "
		"local_tuple, local_xid, local_origin, local_commit_ts, "
		"remote_tuple, remote_origin, remote_commit_ts, remote_commit_lsn, "
		"has_before_triggers"
		") VALUES ("
		"$1, $2, $3, $4, "
		"$5, $6, $7, "
		"$8, $9, $10, $11, "
		"$12, $13, $14, $15, "
		"$16"
		")";

	Oid			argtypes[16];
	Datum		values[16];
	char		nulls[16];
	int			ret;
	TupleDesc	tupdesc;
	const char *idxname = NULL;
	char		lsn_str[32];
	bool		spi_connected = false;

	/* Early exit if feature is disabled */
	if (!pglogical_conflict_history_enabled)
		return;

	/* Early exit if no subscription context */
	if (MySubscription == NULL)
		return;

	/* Connect to SPI first - if this fails, just return */
	ret = SPI_connect();
	if (ret != SPI_OK_CONNECT)
	{
		elog(WARNING, "conflict_history: SPI_connect failed: %d", ret);
		return;
	}
	spi_connected = true;

	/* Wrap the actual work in PG_TRY to prevent errors from aborting apply */
	PG_TRY();
	{
		/* Ensure partition exists for current date */
		ensure_partition_exists();

		/* Get tuple descriptor for JSONB conversion */
		tupdesc = RelationGetDescr(rel->rel);

		/* Get index name if available */
		if (OidIsValid(conflict_idx_oid))
			idxname = get_rel_name(conflict_idx_oid);

		/* Format LSN as string for PG_LSN type */
		snprintf(lsn_str, sizeof(lsn_str), "%X/%X",
				 (uint32)(replorigin_session_origin_lsn >> 32),
				 (uint32)replorigin_session_origin_lsn);

		/* Initialize nulls array */
		memset(nulls, ' ', sizeof(nulls));

		/* Parameter 1: sub_id (OID) */
		argtypes[0] = OIDOID;
		values[0] = ObjectIdGetDatum(MySubscription->id);

		/* Parameter 2: sub_name (NAME) */
		argtypes[1] = NAMEOID;
		values[1] = DirectFunctionCall1(namein, CStringGetDatum(MySubscription->name));

		/* Parameter 3: conflict_type (TEXT) */
		argtypes[2] = TEXTOID;
		values[2] = CStringGetTextDatum(conflict_type_to_string(conflict_type));

		/* Parameter 4: resolution (TEXT) */
		argtypes[3] = TEXTOID;
		values[3] = CStringGetTextDatum(resolution_to_string(resolution));

		/* Parameter 5: schema_name (NAME) */
		argtypes[4] = NAMEOID;
		values[4] = DirectFunctionCall1(namein,
			CStringGetDatum(get_namespace_name(RelationGetNamespace(rel->rel))));

		/* Parameter 6: table_name (NAME) */
		argtypes[5] = NAMEOID;
		values[5] = DirectFunctionCall1(namein,
			CStringGetDatum(RelationGetRelationName(rel->rel)));

		/* Parameter 7: index_name (NAME, nullable) */
		argtypes[6] = NAMEOID;
		if (idxname != NULL)
			values[6] = DirectFunctionCall1(namein, CStringGetDatum(idxname));
		else
			nulls[6] = 'n';

		/* Parameter 8: local_tuple (JSONB, nullable) */
		argtypes[7] = JSONBOID;
		if (localtuple != NULL && pglogical_conflict_history_store_tuples)
		{
			Datum jsonb_datum = tuple_to_jsonb(tupdesc, localtuple,
											   pglogical_conflict_history_max_tuple_size);
			if (jsonb_datum != (Datum) 0)
				values[7] = jsonb_datum;
			else
				nulls[7] = 'n';
		}
		else
		{
			nulls[7] = 'n';
		}

		/* Parameter 9: local_xid (XID, nullable) */
		argtypes[8] = XIDOID;
		if (TransactionIdIsValid(local_tuple_xid))
			values[8] = TransactionIdGetDatum(local_tuple_xid);
		else
			nulls[8] = 'n';

		/* Parameter 10: local_origin (INTEGER, nullable) */
		argtypes[9] = INT4OID;
		if (found_local_origin)
			values[9] = Int32GetDatum((int32) local_tuple_origin);
		else
			nulls[9] = 'n';

		/* Parameter 11: local_commit_ts (TIMESTAMPTZ, nullable) */
		argtypes[10] = TIMESTAMPTZOID;
		if (found_local_origin)
			values[10] = TimestampTzGetDatum(local_tuple_commit_ts);
		else
			nulls[10] = 'n';

		/* Parameter 12: remote_tuple (JSONB, nullable) */
		argtypes[11] = JSONBOID;
		if (remotetuple != NULL && pglogical_conflict_history_store_tuples)
		{
			Datum jsonb_datum = tuple_to_jsonb(tupdesc, remotetuple,
											   pglogical_conflict_history_max_tuple_size);
			if (jsonb_datum != (Datum) 0)
				values[11] = jsonb_datum;
			else
				nulls[11] = 'n';
		}
		else
		{
			nulls[11] = 'n';
		}

		/* Parameter 13: remote_origin (INTEGER) */
		argtypes[12] = INT4OID;
		values[12] = Int32GetDatum((int32) replorigin_session_origin);

		/* Parameter 14: remote_commit_ts (TIMESTAMPTZ) */
		argtypes[13] = TIMESTAMPTZOID;
		values[13] = TimestampTzGetDatum(replorigin_session_origin_timestamp);

		/* Parameter 15: remote_commit_lsn (PG_LSN) */
		argtypes[14] = LSNOID;
		values[14] = DirectFunctionCall1(pg_lsn_in, CStringGetDatum(lsn_str));

		/* Parameter 16: has_before_triggers (BOOLEAN) */
		argtypes[15] = BOOLOID;
		values[15] = BoolGetDatum(has_before_triggers);

		/* Execute the INSERT */
		ret = SPI_execute_with_args(insert_sql, 16, argtypes, values, nulls, false, 0);

		if (ret != SPI_OK_INSERT)
		{
			elog(WARNING, "conflict_history: INSERT failed with code %d", ret);
		}

		SPI_finish();
		spi_connected = false;
	}
	PG_CATCH();
	{
		/* Clean up SPI connection if it was established */
		if (spi_connected)
			SPI_finish();

		/* Log the error and continue - don't abort the apply transaction */
		FlushErrorState();
		elog(WARNING, "conflict_history: recording failed, continuing without recording");
	}
	PG_END_TRY();
}

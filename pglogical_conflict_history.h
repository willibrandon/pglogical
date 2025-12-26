/*-------------------------------------------------------------------------
 *
 * pglogical_conflict_history.h
 *		pglogical conflict history persistence
 *
 * Copyright (c) 2015, PostgreSQL Global Development Group
 *
 * IDENTIFICATION
 *		pglogical_conflict_history.h
 *
 *-------------------------------------------------------------------------
 */
#ifndef PGLOGICAL_CONFLICT_HISTORY_H
#define PGLOGICAL_CONFLICT_HISTORY_H

#include "pglogical_conflict.h"
#include "pglogical_relcache.h"

/* GUC variables */
extern bool pglogical_conflict_history_enabled;
extern bool pglogical_conflict_history_store_tuples;
extern int  pglogical_conflict_history_max_tuple_size;

/* Main API */
extern void pglogical_record_conflict(
	PGLogicalConflictType conflict_type,
	PGLogicalRelation *rel,
	HeapTuple localtuple,
	HeapTuple remotetuple,
	PGLogicalConflictResolution resolution,
	TransactionId local_tuple_xid,
	bool found_local_origin,
	RepOriginId local_tuple_origin,
	TimestampTz local_tuple_commit_ts,
	Oid conflict_idx_oid,
	bool has_before_triggers);

#endif /* PGLOGICAL_CONFLICT_HISTORY_H */

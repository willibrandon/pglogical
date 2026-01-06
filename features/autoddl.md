# Feature: Automatic DDL Replication

## Overview

This feature adds automatic DDL (Data Definition Language) replication to pglogical. When enabled, DDL statements executed on the provider are automatically captured via the ProcessUtility hook and queued for replication to subscribers.

## Current State

pglogical already has:
- `pglogical.replicate_ddl_command(command text, replication_sets text[])` - Manual DDL replication function
- ProcessUtility hook infrastructure in `pglogical_executor.c`
- Object access hook for dependency tracking
- Queue mechanism for replication messages (`queue_message()`)

What's missing:
- Automatic interception and queuing of DDL statements
- GUC settings to enable/disable automatic DDL replication
- Automatic table addition to replication sets on CREATE TABLE
- Filtering logic for unsafe/unsupported DDL

## Design

### GUC Settings

| GUC | Type | Default | Description |
|-----|------|---------|-------------|
| `pglogical.enable_ddl_replication` | bool | false | Enable automatic DDL statement replication |
| `pglogical.include_ddl_repset` | bool | false | Auto-add tables to replication sets on CREATE |
| `pglogical.allow_ddl_from_functions` | bool | false | Replicate DDL from within functions |

### Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         DDL Statement                                │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    ProcessUtility Hook                               │
│                  pglogical_ProcessUtility()                         │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                    ┌─────────────┴─────────────┐
                    ▼                           ▼
          ┌─────────────────┐         ┌─────────────────┐
          │ Execute DDL     │         │ Check AutoDDL   │
          │ (standard path) │         │ Conditions      │
          └─────────────────┘         └─────────────────┘
                                              │
                                              ▼
                                    ┌─────────────────┐
                                    │ autoddl_can_    │
                                    │ proceed()       │
                                    └─────────────────┘
                                              │
                              ┌───────────────┴───────────────┐
                              │                               │
                              ▼                               ▼
                    ┌─────────────────┐             ┌─────────────────┐
                    │ Skip DDL        │             │ pglogical_auto_ │
                    │ (filtered out)  │             │ replicate_ddl() │
                    └─────────────────┘             └─────────────────┘
                                                          │
                                                          ▼
                                                ┌─────────────────┐
                                                │ queue_message() │
                                                │ (JSON encoded)  │
                                                └─────────────────┘
                                                          │
                                                          ▼
                                                ┌─────────────────┐
                                                │ add_ddl_to_     │
                                                │ repset()        │
                                                └─────────────────┘
```

### DDL Filtering Rules

**Skipped DDL (never replicated):**
- `CREATE DATABASE` / `DROP DATABASE` / `ALTER DATABASE`
- `CREATE TABLESPACE` / `DROP TABLESPACE`
- `CREATE SUBSCRIPTION` / `DROP SUBSCRIPTION` / `ALTER SUBSCRIPTION`
- `VACUUM`
- `LISTEN` / `NOTIFY` / `UNLISTEN`
- `FETCH`
- Temporary tables/sequences/views
- `CREATE INDEX CONCURRENTLY` / `REINDEX CONCURRENTLY` / `DROP INDEX CONCURRENTLY`
- `ALTER TABLE ... DETACH PARTITION CONCURRENTLY`
- `CLUSTER` on partitioned tables

**Warned DDL (replicated with warning):**
- `CREATE TABLE AS` - Data may not be replicated correctly

**Standard DDL (replicated normally):**
- `CREATE TABLE` / `DROP TABLE` / `ALTER TABLE`
- `CREATE INDEX` / `DROP INDEX`
- `CREATE SEQUENCE` / `ALTER SEQUENCE` / `DROP SEQUENCE`
- `CREATE VIEW` / `DROP VIEW`
- `CREATE FUNCTION` / `DROP FUNCTION`
- `CREATE TRIGGER` / `DROP TRIGGER`
- `GRANT` / `REVOKE`
- etc.

## Implementation

### File Structure

```
pglogical/
├── pglogical_autoddl.c      # New file - AutoDDL logic
├── pglogical_autoddl.h      # New file - AutoDDL header
├── pglogical_executor.c     # Modified - Add autoddl call
├── pglogical.c              # Modified - Add GUC definitions
├── pglogical.h              # Modified - Add extern declarations
└── pglogical_functions.c    # Modified - Add auto_replicate_ddl
```

### Header File: pglogical_autoddl.h

```c
/*-------------------------------------------------------------------------
 *
 * pglogical_autoddl.h
 *      pglogical automatic DDL replication support
 *
 * Copyright (c) 2015-2025, PostgreSQL Global Development Group
 *
 *-------------------------------------------------------------------------
 */
#ifndef PGLOGICAL_AUTODDL_H
#define PGLOGICAL_AUTODDL_H

#include "postgres.h"
#include "nodes/parsenodes.h"
#include "tcop/utility.h"

/*
 * Central entry from ProcessUtility on origin.
 * Decides if/how to replicate and performs enqueue via existing API.
 */
extern void pglogical_autoddl_process(PlannedStmt *pstmt,
                                      const char *queryString,
                                      ProcessUtilityContext context,
                                      NodeTag toplevel_stmt);

/*
 * Add newly created table to appropriate replication set.
 */
extern void pglogical_add_ddl_to_repset(Node *parsetree);

#endif /* PGLOGICAL_AUTODDL_H */
```

### Source File: pglogical_autoddl.c

```c
/*-------------------------------------------------------------------------
 *
 * pglogical_autoddl.c
 *      pglogical automatic DDL replication support
 *
 * Copyright (c) 2015-2025, PostgreSQL Global Development Group
 *
 *-------------------------------------------------------------------------
 */
#include "postgres.h"

#include "access/relation.h"
#include "access/table.h"
#include "catalog/index.h"
#include "catalog/namespace.h"
#include "catalog/pg_authid_d.h"
#include "catalog/pg_inherits.h"
#include "commands/defrem.h"
#include "commands/extension.h"
#include "miscadmin.h"
#include "tcop/utility.h"
#include "utils/builtins.h"
#include "utils/lsyscache.h"
#include "utils/rel.h"
#include "utils/snapmgr.h"

#include "pglogical_autoddl.h"
#include "pglogical_executor.h"
#include "pglogical_queue.h"
#include "pglogical_relcache.h"
#include "pglogical_repset.h"
#include "pglogical_node.h"
#include "pglogical.h"

static void remove_table_from_repsets(Oid nodeid, Oid reloid, bool only_for_update);
static bool autoddl_can_proceed(Node *parsetree, ProcessUtilityContext context,
                                NodeTag toplevel_stmt);

/*
 * pglogical_autoddl_process
 *
 * Central entrypoint for AutoDDL. Called from the ProcessUtility hook
 * after the DDL has been executed. Filters, validates, and queues
 * qualifying DDL for replication.
 */
void
pglogical_autoddl_process(PlannedStmt *pstmt,
                          const char *queryString,
                          ProcessUtilityContext context,
                          NodeTag toplevel_stmt)
{
    Oid         save_userid = 0;
    int         save_sec_context = 0;
    const char *curr_qry;
    int         loc = pstmt->stmt_location;
    int         len = pstmt->stmt_len;
    Node       *parsetree = pstmt->utilityStmt;
    bool        needTx = false;
    bool        needSnapshot = false;

    /* Fast path: check if we should proceed */
    if (!autoddl_can_proceed(parsetree, context, toplevel_stmt))
        return;

    /* Ensure we have a transaction context */
    needTx = !IsTransactionState();
    if (needTx)
        StartTransactionCommand();

    needSnapshot = !HaveRegisteredOrActiveSnapshot();
    if (needSnapshot)
        PushActiveSnapshot(GetTransactionSnapshot());

    /*
     * Elevate access rights: Utility hook is called under the session user,
     * who may not have access to pglogical extension objects.
     */
    GetUserIdAndSecContext(&save_userid, &save_sec_context);
    SetUserIdAndSecContext(BOOTSTRAP_SUPERUSERID,
                           save_sec_context | SECURITY_LOCAL_USERID_CHANGE);

    /* Not a pglogical node, do nothing */
    if (get_local_node(false, true) == NULL)
        goto end;

    /* Extract the query text */
    queryString = CleanQuerytext(queryString, &loc, &len);
    curr_qry = pnstrdup(queryString, len);

    /* Queue the DDL for replication */
    pglogical_auto_replicate_ddl(curr_qry,
                                 list_make1(DEFAULT_INSONLY_REPSET_NAME),
                                 GetUserId(),
                                 parsetree);

    /* Add tables to replication set if configured */
    pglogical_add_ddl_to_repset(parsetree);

end:
    /* Restore previous session privileges */
    SetUserIdAndSecContext(save_userid, save_sec_context);

    if (needSnapshot)
        PopActiveSnapshot();
    if (needTx)
        CommitTransactionCommand();
}

/*
 * pglogical_add_ddl_to_repset
 *
 * Check if the DDL statement created a table that should be added to a
 * replication set. Tables with PKs go to 'default', others to
 * 'default_insert_only'.
 */
void
pglogical_add_ddl_to_repset(Node *parsetree)
{
    Relation        targetrel;
    PGLogicalRepSet *repset;
    PGLogicalLocalNode *node;
    Oid             reloid = InvalidOid;
    RangeVar       *relation = NULL;
    List           *reloids = NIL;
    ListCell       *lc;
    bool            missing_ok = false;

    /* No need to proceed if pglogical_include_ddl_repset is off */
    if (!pglogical_include_ddl_repset)
        return;

    /* Handle different statement types */
    if (nodeTag(parsetree) == T_AlterTableStmt)
    {
        AlterTableStmt *atstmt = castNode(AlterTableStmt, parsetree);

        if (atstmt->objtype == OBJECT_TABLE)
            relation = atstmt->relation;
        else if (atstmt->objtype == OBJECT_INDEX)
        {
            ListCell *cell;

            foreach(cell, atstmt->cmds)
            {
                AlterTableCmd *cmd = (AlterTableCmd *) lfirst(cell);

                if (cmd->subtype == AT_AttachPartition)
                {
                    Relation indrel;

                    indrel = relation_openrv(atstmt->relation, AccessShareLock);
                    reloid = IndexGetRelation(RelationGetRelid(indrel), false);
                    table_close(indrel, NoLock);
                }
            }

            if (!OidIsValid(reloid))
                return;
        }
        else
            return;

        missing_ok = atstmt->missing_ok;
    }
    else if (nodeTag(parsetree) == T_CreateStmt)
        relation = castNode(CreateStmt, parsetree)->relation;
    else if (nodeTag(parsetree) == T_CreateTableAsStmt &&
             castNode(CreateTableAsStmt, parsetree)->objtype == OBJECT_TABLE)
        relation = castNode(CreateTableAsStmt, parsetree)->into->rel;
    else if (nodeTag(parsetree) == T_CreateSchemaStmt)
    {
        ListCell *cell;
        CreateSchemaStmt *cstmt = (CreateSchemaStmt *) parsetree;

        foreach(cell, cstmt->schemaElts)
        {
            if (nodeTag(lfirst(cell)) == T_CreateStmt)
                pglogical_add_ddl_to_repset(lfirst(cell));
        }
        return;
    }
    else
        return;

    node = get_local_node(false, true);
    if (!node)
        return;

    if (OidIsValid(reloid))
        targetrel = RelationIdGetRelation(reloid);
    else
    {
        targetrel = table_openrv_extended(relation, AccessShareLock, missing_ok);
        if (targetrel == NULL)
            return;
    }

    reloid = RelationGetRelid(targetrel);

    /* Handle partitioned tables */
    if (targetrel->rd_rel->relkind == RELKIND_PARTITIONED_TABLE)
        reloids = find_all_inheritors(reloid, NoLock, NULL);
    else
        reloids = lappend_oid(reloids, reloid);

    table_close(targetrel, NoLock);

    foreach(lc, reloids)
    {
        reloid = lfirst_oid(lc);
        targetrel = RelationIdGetRelation(reloid);

        /* UNLOGGED and TEMP relations cannot be replicated */
        if (!RelationNeedsWAL(targetrel))
        {
            remove_table_from_repsets(node->node->id, reloid, false);
            table_close(targetrel, NoLock);
            return;
        }

        if (targetrel->rd_indexvalid == 0)
            RelationGetIndexList(targetrel);

        /*
         * Choose replication set based on whether table has PK or
         * replica identity.
         */
        if (OidIsValid(targetrel->rd_pkindex) ||
            OidIsValid(targetrel->rd_replidindex))
        {
            repset = get_replication_set_by_name(node->node->id,
                                                 DEFAULT_REPSET_NAME, false);
            remove_table_from_repsets(node->node->id, reloid, false);
        }
        else
        {
            repset = get_replication_set_by_name(node->node->id,
                                                 DEFAULT_INSONLY_REPSET_NAME, false);
            remove_table_from_repsets(node->node->id, reloid, true);
        }

        /* Skip if no valid replica identity for update/delete repsets */
        if (!OidIsValid(targetrel->rd_replidindex) &&
            (repset->replicate_update || repset->replicate_delete) &&
            !OidIsValid(get_replication_identity(targetrel)))
        {
            table_close(targetrel, NoLock);
            return;
        }

        table_close(targetrel, NoLock);

        /* Add if not already present */
        if (get_table_replication_row(repset->id, reloid, NULL, NULL) == NULL)
        {
            replication_set_add_table(repset->id, reloid, NIL, NULL);
            elog(LOG, "table '%s' was added to '%s' replication set.",
                 get_rel_name(reloid), repset->name);
        }
    }
}

/*
 * remove_table_from_repsets
 *
 * Remove a table from replication sets. If only_for_update is true,
 * only remove from sets that replicate UPDATE/DELETE.
 */
static void
remove_table_from_repsets(Oid nodeid, Oid reloid, bool only_for_update)
{
    ListCell   *lc;
    List       *repsets;

    repsets = get_table_replication_sets(nodeid, reloid);
    foreach(lc, repsets)
    {
        PGLogicalRepSet *rs = (PGLogicalRepSet *) lfirst(lc);

        if (only_for_update)
        {
            if (rs->replicate_update || rs->replicate_delete)
                replication_set_remove_table(rs->id, reloid, true);
        }
        else
            replication_set_remove_table(rs->id, reloid, true);
    }
}

/*
 * autoddl_can_proceed
 *
 * Quick precheck to determine if auto-DDL replication should proceed.
 * This is called before acquiring any locks or transactions.
 */
static bool
autoddl_can_proceed(Node *parsetree, ProcessUtilityContext context,
                    NodeTag toplevel_stmt)
{
    /* Skip if in repair mode */
    if (pglogical_replication_repair_mode)
        return false;

    /* Only process DDL statements */
    if (GetCommandLogLevel(parsetree) != LOGSTMT_DDL)
        return false;

    /* If DDL replication is disabled, do nothing */
    if (!pglogical_enable_ddl_replication)
        return false;

    /* If already processing a queued DDL, do nothing */
    if (in_pglogical_queue_ddl_command || in_pglogical_replicate_ddl_command)
        return false;

    /* Allow all toplevel statements */
    if (context == PROCESS_UTILITY_TOPLEVEL)
        return true;

    /* Guard against CREATE EXTENSION subcommands */
    if (creating_extension)
        return false;

    /* Subcommands are handled by their top-level query */
    if (context == PROCESS_UTILITY_SUBCOMMAND)
        return false;

    /* Allow DDL from functions if configured */
    if (context == PROCESS_UTILITY_QUERY && pglogical_allow_ddl_from_functions)
    {
        if (toplevel_stmt != T_CreateExtensionStmt &&
            toplevel_stmt != T_CreateSchemaStmt &&
            !(toplevel_stmt == T_DropStmt &&
              castNode(DropStmt, parsetree)->removeType == OBJECT_EXTENSION))
            return true;

        return false;
    }

    return false;
}

/*
 * CleanQuerytext
 *
 * Extract the actual query text from a potentially larger query string.
 * Adjusts location and length pointers.
 */
const char *
CleanQuerytext(const char *queryString, int *loc, int *len)
{
    if (*loc >= 0)
        queryString = queryString + *loc;

    if (*len <= 0)
        *len = strlen(queryString);

    /* Trim trailing whitespace and semicolons */
    while (*len > 0 &&
           (queryString[*len - 1] == ';' ||
            queryString[*len - 1] == ' ' ||
            queryString[*len - 1] == '\n' ||
            queryString[*len - 1] == '\t'))
        (*len)--;

    return queryString;
}
```

### Modifications to pglogical.c (GUC definitions)

Add to the GUC variable declarations section:

```c
/* AutoDDL GUC variables */
bool pglogical_enable_ddl_replication = false;
bool pglogical_include_ddl_repset = false;
bool pglogical_allow_ddl_from_functions = false;
```

Add to `pglogical_init()` or equivalent GUC registration function:

```c
/* AutoDDL: Enable automatic DDL replication */
DefineCustomBoolVariable("pglogical.enable_ddl_replication",
                         "Enable automatic replication of DDL statements.",
                         NULL,
                         &pglogical_enable_ddl_replication,
                         false,
                         PGC_SUSET,
                         0,
                         NULL, NULL, NULL);

/* AutoDDL: Auto-add tables to replication sets */
DefineCustomBoolVariable("pglogical.include_ddl_repset",
                         "Automatically add tables to replication sets on CREATE.",
                         NULL,
                         &pglogical_include_ddl_repset,
                         false,
                         PGC_SUSET,
                         0,
                         NULL, NULL, NULL);

/* AutoDDL: Allow DDL from functions */
DefineCustomBoolVariable("pglogical.allow_ddl_from_functions",
                         "Replicate DDL statements executed from within functions.",
                         NULL,
                         &pglogical_allow_ddl_from_functions,
                         false,
                         PGC_SUSET,
                         0,
                         NULL, NULL, NULL);
```

### Modifications to pglogical.h

Add extern declarations:

```c
/* AutoDDL GUC variables */
extern bool pglogical_enable_ddl_replication;
extern bool pglogical_include_ddl_repset;
extern bool pglogical_allow_ddl_from_functions;

/* AutoDDL state flags */
extern bool in_pglogical_queue_ddl_command;

/* AutoDDL function */
extern void pglogical_auto_replicate_ddl(const char *query, List *replication_sets,
                                         Oid roleoid, Node *stmt);
```

### Modifications to pglogical_executor.c

Add include at top:

```c
#include "pglogical_autoddl.h"
```

Modify `pglogical_ProcessUtility()` to call autoddl after execution:

```c
static void
pglogical_ProcessUtility(PlannedStmt *pstmt,
                         const char *queryString,
                         bool readOnlyTree,
                         ProcessUtilityContext context,
                         ParamListInfo params,
                         QueryEnvironment *queryEnv,
                         DestReceiver *dest,
                         QueryCompletion *qc)
{
    Node       *parsetree = pstmt->utilityStmt;
    NodeTag     toplevel_stmt = nodeTag(parsetree);

    dropping_pglogical_obj = false;

    if (nodeTag(parsetree) == T_TruncateStmt)
        pglogical_start_truncate();

    if (nodeTag(parsetree) == T_DropStmt)
    {
        /*
         * Allow dropping replication tables without CASCADE when
         * auto DDL replication is enabled.
         */
        if (pglogical_enable_ddl_replication || in_pglogical_queue_ddl_command)
            pglogical_lastDropBehavior = DROP_CASCADE;
        else
            pglogical_lastDropBehavior = ((DropStmt *) parsetree)->behavior;
    }

    /* There's no reason we should be in a long lived context here */
    Assert(CurrentMemoryContext != TopMemoryContext
           && CurrentMemoryContext != CacheMemoryContext);

    if (next_ProcessUtility_hook)
        PGLnext_ProcessUtility_hook(pstmt, queryString, readOnlyTree, context,
                                    params, queryEnv, dest, qc);
    else
        PGLstandard_ProcessUtility(pstmt, queryString, readOnlyTree, context,
                                   params, queryEnv, dest, qc);

    if (nodeTag(parsetree) == T_TruncateStmt)
        pglogical_finish_truncate();

    /* Check for AutoDDL - process after DDL execution */
    pglogical_autoddl_process(pstmt, queryString, context, toplevel_stmt);
}
```

### Modifications to pglogical_functions.c

Add the `pglogical_auto_replicate_ddl()` function:

```c
/* Flag to track if we're in a queued DDL command */
bool in_pglogical_queue_ddl_command = false;

/*
 * pglogical_auto_replicate_ddl
 *
 * Add the DDL statement to the pglogical.queue table for replication.
 * Includes the current search_path with the query.
 */
void
pglogical_auto_replicate_ddl(const char *query, List *replication_sets,
                             Oid roleoid, Node *stmt)
{
    ListCell       *lc;
    PGLogicalLocalNode *node;
    StringInfoData  cmd;
    StringInfoData  q;
    char           *search_path;
    bool            add_search_path = true;
    bool            warn = false;

    node = check_local_node(false);

    /* Validate replication sets */
    foreach(lc, replication_sets)
    {
        char *setname = lfirst(lc);
        (void) get_replication_set_by_name(node->node->id, setname, false);
    }

    /*
     * Filter local commands and decide on search path setting.
     */
    switch (nodeTag(stmt))
    {
        /* Purely local commands - skip entirely */
        case T_FetchStmt:
        case T_NotifyStmt:
        case T_ListenStmt:
        case T_UnlistenStmt:
            goto skip_ddl;

        /* Commands that run outside transactions */
        case T_CreateTableSpaceStmt:
        case T_DropTableSpaceStmt:
        case T_VacuumStmt:
            goto skip_ddl;

        /* Database-level commands */
        case T_CreatedbStmt:
        case T_DropdbStmt:
        case T_AlterDatabaseStmt:
#if PG_VERSION_NUM >= 150000
        case T_AlterDatabaseRefreshCollStmt:
#endif
        case T_AlterDatabaseSetStmt:
        case T_AlterSystemStmt:
        case T_CreateSubscriptionStmt:
        case T_DropSubscriptionStmt:
        case T_AlterSubscriptionStmt:
            add_search_path = false;
            goto skip_ddl;

        case T_AlterOwnerStmt:
            if (castNode(AlterOwnerStmt, stmt)->objectType == OBJECT_DATABASE ||
                castNode(AlterOwnerStmt, stmt)->objectType == OBJECT_SUBSCRIPTION)
                goto skip_ddl;
            if (castNode(AlterOwnerStmt, stmt)->objectType == OBJECT_TABLESPACE)
                add_search_path = false;
            break;

        case T_RenameStmt:
            if (castNode(RenameStmt, stmt)->renameType == OBJECT_DATABASE ||
                castNode(RenameStmt, stmt)->renameType == OBJECT_SUBSCRIPTION)
                goto skip_ddl;
            if (castNode(RenameStmt, stmt)->renameType == OBJECT_TABLESPACE)
                add_search_path = false;
            break;

        case T_CreateTableAsStmt:
            {
                CreateTableAsStmt *ctas = castNode(CreateTableAsStmt, stmt);

                if (ctas->into->rel->relpersistence == RELPERSISTENCE_TEMP)
                    goto skip_ddl;
                if (castNode(Query, ctas->query)->commandType == CMD_UTILITY &&
                    IsA(castNode(Query, ctas->query)->utilityStmt, ExecuteStmt))
                    goto skip_ddl;
                warn = true;
            }
            break;

        case T_CreateStmt:
            if (castNode(CreateStmt, stmt)->relation->relpersistence == RELPERSISTENCE_TEMP)
                goto skip_ddl;
            break;

        case T_CreateSeqStmt:
            if (castNode(CreateSeqStmt, stmt)->sequence->relpersistence == RELPERSISTENCE_TEMP)
                goto skip_ddl;
            break;

        case T_ViewStmt:
            if (castNode(ViewStmt, stmt)->view->relpersistence == RELPERSISTENCE_TEMP)
                goto skip_ddl;
            break;

        case T_ClusterStmt:
            {
                ClusterStmt *cstmt = (ClusterStmt *) stmt;
                bool skip_cluster = true;

                if (cstmt->relation != NULL)
                {
                    Relation    rel;
                    Oid         tableOid;

                    tableOid = RangeVarGetRelidExtended(cstmt->relation,
                                                       AccessShareLock, 0,
                                                       NULL, NULL);
                    rel = table_open(tableOid, NoLock);
                    skip_cluster = (rel->rd_rel->relkind == RELKIND_PARTITIONED_TABLE);
                    table_close(rel, AccessShareLock);
                }

                if (skip_cluster)
                    goto skip_ddl;

                add_search_path = false;
            }
            break;

        case T_AlterTableSpaceOptionsStmt:
            add_search_path = false;
            break;

        case T_AlterTableStmt:
            {
                ListCell *cell;
                AlterTableStmt *atstmt = (AlterTableStmt *) stmt;

                foreach(cell, atstmt->cmds)
                {
                    AlterTableCmd *cmd = (AlterTableCmd *) lfirst(cell);

                    if (cmd->subtype == AT_DetachPartition &&
                        ((PartitionCmd *) cmd->def)->concurrent)
                        goto skip_ddl;
                }
            }
            break;

        case T_IndexStmt:
            if (castNode(IndexStmt, stmt)->concurrent)
                goto skip_ddl;
            break;

        case T_ReindexStmt:
            {
                ReindexStmt *rstmt = (ReindexStmt *) stmt;
                bool concurrently = false;

                foreach(lc, rstmt->params)
                {
                    DefElem *opt = (DefElem *) lfirst(lc);

                    if (strcmp(opt->defname, "concurrently") != 0)
                        continue;
                    concurrently = defGetBoolean(opt);
                }

                if (concurrently)
                    goto skip_ddl;
            }
            break;

        case T_DropStmt:
            if (castNode(DropStmt, stmt)->removeType == OBJECT_INDEX &&
                castNode(DropStmt, stmt)->concurrent)
                goto skip_ddl;
            break;

        default:
            add_search_path = true;
            break;
    }

    /* Report replication status */
    if (warn)
        elog(WARNING, "DDL statement replicated, but could be unsafe.");
    else
        elog(INFO, "DDL statement replicated.");

    /* Build the query with search path */
    initStringInfo(&q);
    if (add_search_path)
    {
        search_path = GetConfigOptionByName("search_path", NULL, false);
        if (strlen(search_path) > 0)
            appendStringInfo(&q, "SET search_path TO %s; ", search_path);
        else
            appendStringInfo(&q, "SET search_path TO ''; ");
    }
    appendStringInfoString(&q, query);

    /* Convert the query to JSON string */
    initStringInfo(&cmd);
    escape_json(&cmd, q.data);

    /* Queue the DDL for replication */
    queue_message(replication_sets, roleoid, QUEUE_COMMAND_TYPE_SQL, cmd.data);

    pfree(cmd.data);
    pfree(q.data);
    return;

skip_ddl:
    elog(DEBUG1, "DDL statement will not be replicated.");
}
```

### Modifications to Makefile

Add `pglogical_autoddl.o` to the object files list:

```makefile
OBJS = pglogical_apply.o pglogical_conflict.o pglogical_manager.o \
       pglogical_node.o pglogical_relcache.o pglogical_repset.o \
       pglogical_rpc.o pglogical_functions.o pglogical_queue.o \
       pglogical_fe.o pglogical.o pglogical_sync.o pglogical_worker.o \
       pglogical_output.o pglogical_executor.o pglogical_dependency.o \
       pglogical_apply_heap.o pglogical_apply_spi.o pglogical_output_config.o \
       pglogical_output_plugin.o pglogical_output_proto.o \
       pglogical_proto_json.o pglogical_proto_native.o \
       pglogical_monitoring.o pglogical_sequences.o \
       pglogical_conflict_history.o pglogical_autoddl.o
```

### CMakeLists.txt Modifications

Add to the source files list:

```cmake
set(PGLOGICAL_SOURCES
    # ... existing sources ...
    pglogical_autoddl.c
)
```

## SQL Interface

Add documentation-only function (the actual work is done via GUC settings):

```sql
-- Document the GUC settings in extension comments
COMMENT ON EXTENSION pglogical IS
'PostgreSQL Logical Replication

GUC Settings for Automatic DDL Replication:
  pglogical.enable_ddl_replication = on/off
    Enable automatic replication of DDL statements.

  pglogical.include_ddl_repset = on/off
    Automatically add tables to replication sets when created.
    Tables with PKs go to ''default'', others to ''default_insert_only''.

  pglogical.allow_ddl_from_functions = on/off
    Also replicate DDL statements executed from within functions.
';
```

## Usage

### Enable Automatic DDL Replication

```sql
-- In postgresql.conf or via ALTER SYSTEM
ALTER SYSTEM SET pglogical.enable_ddl_replication = on;
ALTER SYSTEM SET pglogical.include_ddl_repset = on;
SELECT pg_reload_conf();

-- Or per-session
SET pglogical.enable_ddl_replication = on;
SET pglogical.include_ddl_repset = on;
```

### Example Workflow

```sql
-- On provider node with auto DDL enabled
CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    customer_id INT NOT NULL,
    total DECIMAL(10,2),
    created_at TIMESTAMPTZ DEFAULT NOW()
);
-- INFO: DDL statement replicated.
-- LOG: table 'orders' was added to 'default' replication set.

ALTER TABLE orders ADD COLUMN status VARCHAR(20) DEFAULT 'pending';
-- INFO: DDL statement replicated.

CREATE INDEX idx_orders_customer ON orders(customer_id);
-- INFO: DDL statement replicated.

-- Table is automatically replicated to subscribers
```

### Verify Replication

```sql
-- Check if table is in replication set
SELECT * FROM pglogical.tables WHERE relname = 'orders';

-- View queued DDL commands
SELECT * FROM pglogical.queue WHERE message_type = 'S';
```

## Testing

### Regression Test: sql/autoddl.sql

```sql
-- Test automatic DDL replication
\set VERBOSITY terse
SELECT pglogical.create_node('test_provider', 'dbname=' || current_database());

-- Enable auto DDL
SET pglogical.enable_ddl_replication = on;
SET pglogical.include_ddl_repset = on;

-- Test table creation (should replicate)
CREATE TABLE autoddl_test1 (
    id SERIAL PRIMARY KEY,
    name TEXT
);

-- Verify table was added to replication set
SELECT COUNT(*) FROM pglogical.replication_set_table
WHERE set_name = 'default'
  AND set_reloid = 'autoddl_test1'::regclass;

-- Test table without PK (should go to insert_only)
CREATE TABLE autoddl_test2 (
    data TEXT
);

SELECT COUNT(*) FROM pglogical.replication_set_table
WHERE set_name = 'default_insert_only'
  AND set_reloid = 'autoddl_test2'::regclass;

-- Test ALTER TABLE
ALTER TABLE autoddl_test1 ADD COLUMN created_at TIMESTAMPTZ;

-- Test skipped DDL (temp table)
CREATE TEMP TABLE autoddl_temp (id INT);

-- Test skipped DDL (concurrent index)
CREATE INDEX CONCURRENTLY idx_autoddl ON autoddl_test1(name);

-- Cleanup
DROP TABLE IF EXISTS autoddl_test1, autoddl_test2;
SELECT pglogical.drop_node('test_provider');
RESET pglogical.enable_ddl_replication;
RESET pglogical.include_ddl_repset;
```

## Migration Notes

### Upgrading from Manual DDL Replication

If you were previously using `pglogical.replicate_ddl_command()` manually:

1. You can continue using manual DDL replication alongside automatic
2. The automatic replication will skip DDL that's already being processed via the manual function (using the `in_pglogical_replicate_ddl_command` flag)
3. Consider enabling `pglogical.enable_ddl_replication` only after ensuring schema is identical across all nodes

### Configuration Recommendations

```ini
# postgresql.conf

# Enable after initial sync is complete
pglogical.enable_ddl_replication = on

# Enable to auto-add new tables
pglogical.include_ddl_repset = on

# Usually leave disabled unless you have DDL-generating functions
pglogical.allow_ddl_from_functions = off
```

## Limitations

1. **Concurrent operations** - DDL using `CONCURRENTLY` cannot be replicated (runs outside transaction)
2. **Database-level DDL** - `CREATE DATABASE`, `DROP DATABASE` not replicated
3. **Tablespace DDL** - Tablespace operations not replicated
4. **CREATE TABLE AS** - Data may not sync correctly (warning issued)
5. **Temp objects** - Temporary tables/sequences/views not replicated
6. **Subscriptions** - Native PostgreSQL subscription DDL not replicated

## References

- PostgreSQL ProcessUtility hook documentation
- pglogical existing `replicate_ddl_command` function

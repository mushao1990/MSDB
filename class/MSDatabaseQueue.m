//  MSDatabaseQueue.m
//  MSDatabase
//
//  Created by muser on 2023/5/15.
//  Copyright © 2023 Mac. All rights reserved.
//

#import "MSDatabaseQueue.h"
#import "MSDatabase.h"

/*
 
 Note: we call [self retain]; before using dispatch_sync, just incase 
 MSDatabaseQueue is released on another thread and we're in the middle of doing
 something in dispatch_sync
 
 */

/*
 * A key used to associate the MSDatabaseQueue object with the dispatch_queue_t it uses.
 * This in turn is used for deadlock detection by seeing if inDatabase: is called on
 * the queue's dispatch queue, which should not happen and causes a deadlock.
 */
static const void * const kDispatchQueueSpecificKey = &kDispatchQueueSpecificKey;
 
@implementation MSDatabaseQueue

@synthesize path = _path;
@synthesize openFlags = _openFlags;

+ (instancetype)databaseQueueWithPath:(NSString*)aPath {
    
    MSDatabaseQueue *q = [[self alloc] initWithPath:aPath];
    
    MSDBAutorelease(q);
    
    return q;
}

+ (instancetype)databaseQueueWithPath:(NSString*)aPath flags:(int)openFlags {
    
    MSDatabaseQueue *q = [[self alloc] initWithPath:aPath flags:openFlags];
    
    MSDBAutorelease(q);
    
    return q;
}

+ (Class)databaseClass {
    return [MSDatabase class];
}

- (instancetype)initWithPath:(NSString*)aPath flags:(int)openFlags {
    
    self = [super init];
    
    if (self != nil) {
        
        _db = [[[self class] databaseClass] databaseWithPath:aPath];
        MSDBRetain(_db);
        
#if SQLITE_VERSION_NUMBER >= 3005000
        BOOL success = [_db openWithFlags:openFlags];
#else
        BOOL success = [_db open];
#endif
        if (!success) {
            NSLog(@"Could not create database queue for path %@", aPath);
            MSDBRelease(self);
            return 0x00;
        }
        
        _path = MSDBReturnRetained(aPath);
        
        _queue = dispatch_queue_create([[NSString stringWithFormat:@"MSDB.%@", self] UTF8String], NULL);
        dispatch_queue_set_specific(_queue, kDispatchQueueSpecificKey, (__bridge void *)self, NULL);
        _openFlags = openFlags;
    }
    
    return self;
}

- (instancetype)initWithPath:(NSString*)aPath {
    
    // default flags for sqlite3_open
    return [self initWithPath:aPath flags:SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE];
}

- (instancetype)init {
    return [self initWithPath:nil];
}

    
- (void)dealloc {
    
    MSDBRelease(_db);
    MSDBRelease(_path);
    
    if (_queue) {
        MSDBDispatchQueueRelease(_queue);
        _queue = 0x00;
    }
#if ! __has_feature(objc_arc)
    [super dealloc];
#endif
}

- (void)close {
    MSDBRetain(self);
    dispatch_sync(_queue, ^() {
        [self->_db close];
        MSDBRelease(_db);
        self->_db = 0x00;
    });
    MSDBRelease(self);
}

- (MSDatabase*)database {
    if (!_db) {
        _db = MSDBReturnRetained([MSDatabase databaseWithPath:_path]);
        
#if SQLITE_VERSION_NUMBER >= 3005000
        BOOL success = [_db openWithFlags:_openFlags];
#else
        BOOL success = [_db open];
#endif
        if (!success) {
            NSLog(@"MSDatabaseQueue could not reopen database for path %@", _path);
            MSDBRelease(_db);
            _db  = 0x00;
            return 0x00;
        }
    }
    
    return _db;
}

- (void)inDatabase:(void (^)(MSDatabase *db))block {
    /* Get the currently executing queue (which should probably be nil, but in theory could be another DB queue
     * and then check it against self to make sure we're not about to deadlock. */
    MSDatabaseQueue *currentSyncQueue = (__bridge id)dispatch_get_specific(kDispatchQueueSpecificKey);
    assert(currentSyncQueue != self && "inDatabase: was called reentrantly on the same queue, which would lead to a deadlock");
    
    MSDBRetain(self);
    
    dispatch_sync(_queue, ^() {
        
        MSDatabase *db = [self database];
        block(db);
        
        if ([db hasOpenResultSets]) {
            NSLog(@"Warning: there is at least one open result set around after performing [MSDatabaseQueue inDatabase:]");
            
#if defined(DEBUG) && DEBUG
            NSSet *openSetCopy = MSDBReturnAutoreleased([[db valueForKey:@"_openResultSets"] copy]);
            for (NSValue *rsInWrappedInATastyValueMeal in openSetCopy) {
                MSResultSet *rs = (MSResultSet *)[rsInWrappedInATastyValueMeal pointerValue];
                NSLog(@"query: '%@'", [rs query]);
            }
#endif
        }
    });
    
    MSDBRelease(self);
}


- (void)beginTransaction:(BOOL)useDeferred withBlock:(void (^)(MSDatabase *db, BOOL *rollback))block {
    MSDBRetain(self);
    dispatch_sync(_queue, ^() { 
        
        BOOL shouldRollback = NO;
        
        if (useDeferred) {
            [[self database] beginDeferredTransaction];
        }
        else {
            [[self database] beginTransaction];
        }
        
        block([self database], &shouldRollback);
        
        if (shouldRollback) {
            [[self database] rollback];
        }
        else {
            [[self database] commit];
        }
    });
    
    MSDBRelease(self);
}

- (void)inDeferredTransaction:(void (^)(MSDatabase *db, BOOL *rollback))block {
    [self beginTransaction:YES withBlock:block];
}

- (void)inTransaction:(void (^)(MSDatabase *db, BOOL *rollback))block {
    [self beginTransaction:NO withBlock:block];
}

#if SQLITE_VERSION_NUMBER >= 3007000
- (NSError*)inSavePoint:(void (^)(MSDatabase *db, BOOL *rollback))block {
    
    static unsigned long savePointIdx = 0;
    __block NSError *err = 0x00;
    MSDBRetain(self);
    dispatch_sync(_queue, ^() { 
        
        NSString *name = [NSString stringWithFormat:@"savePoint%ld", savePointIdx++];
        
        BOOL shouldRollback = NO;
        
        if ([[self database] startSavePointWithName:name error:&err]) {
            
            block([self database], &shouldRollback);
            
            if (shouldRollback) {
                // We need to rollback and release this savepoint to remove it
                [[self database] rollbackToSavePointWithName:name error:&err];
            }
            [[self database] releaseSavePointWithName:name error:&err];
            
        }
    });
    MSDBRelease(self);
    return err;
}
#endif

@end

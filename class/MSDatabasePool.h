//  MSDatabasePool.h
//  MSDatabase
//
//  Created by muser on 2023/5/15.
//  Copyright © 2023 Mac. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "sqlite3.h"

@class MSDatabase;

/** Pool of `<MSDatabase>` objects.

 ### See also
 
 - `<MSDatabaseQueue>`
 - `<MSDatabase>`

 @warning Before using `MSDatabasePool`, please consider using `<MSDatabaseQueue>` instead.

 If you really really really know what you're doing and `MSDatabasePool` is what
 you really really need (ie, you're using a read only database), OK you can use
 it.  But just be careful not to deadlock!

 For an example on deadlocking, search for:
 `ONLY_USE_THE_POOL_IF_YOU_ARE_DOING_READS_OTHERWISE_YOULL_DEADLOCK_USE_MSDataBASEQUEUE_INSTEAD`
 in the main.m file.
 */

@interface MSDatabasePool : NSObject {
    NSString            *_path;
    
    dispatch_queue_t    _lockQueue;
    
    NSMutableArray      *_databaseInPool;
    NSMutableArray      *_databaseOutPool;
    
    __unsafe_unretained id _delegate;
    
    NSUInteger          _maximumNumberOfDatabasesToCreate;
    int                 _openFlags;
}

/** Database path */

@property (atomic, retain) NSString *path;

/** Delegate object */

@property (atomic, assign) id delegate;

/** Maximum number of databases to create */

@property (atomic, assign) NSUInteger maximumNumberOfDatabasesToCreate;

/** Open flags */

@property (atomic, readonly) int openFlags;


///---------------------
/// @name Initialization
///---------------------

/** Create pool using path.

 @param aPath The file path of the database.

 @return The `MSDatabasePool` object. `nil` on error.
 */

+ (instancetype)databasePoolWithPath:(NSString*)aPath;

/** Create pool using path and specified flags

 @param aPath The file path of the database.
 @param openFlags Flags passed to the openWithFlags method of the database

 @return The `MSDatabasePool` object. `nil` on error.
 */

+ (instancetype)databasePoolWithPath:(NSString*)aPath flags:(int)openFlags;

/** Create pool using path.

 @param aPath The file path of the database.

 @return The `MSDatabasePool` object. `nil` on error.
 */

- (instancetype)initWithPath:(NSString*)aPath;

/** Create pool using path and specified flags.

 @param aPath The file path of the database.
 @param openFlags Flags passed to the openWithFlags method of the database

 @return The `MSDatabasePool` object. `nil` on error.
 */

- (instancetype)initWithPath:(NSString*)aPath flags:(int)openFlags;

///------------------------------------------------
/// @name Keeping track of checked in/out databases
///------------------------------------------------

/** Number of checked-in databases in pool
 
 @returns Number of databases
 */

- (NSUInteger)countOfCheckedInDatabases;

/** Number of checked-out databases in pool

 @returns Number of databases
 */

- (NSUInteger)countOfCheckedOutDatabases;

/** Total number of databases in pool

 @returns Number of databases
 */

- (NSUInteger)countOfOpenDatabases;

/** Release all databases in pool */

- (void)releaseAllDatabases;

///------------------------------------------
/// @name Perform database operations in pool
///------------------------------------------

/** Synchronously perform database operations in pool.

 @param block The code to be run on the `MSDatabasePool` pool.
 */

- (void)inDatabase:(void (^)(MSDatabase *db))block;

/** Synchronously perform database operations in pool using transaction.

 @param block The code to be run on the `MSDatabasePool` pool.
 */

- (void)inTransaction:(void (^)(MSDatabase *db, BOOL *rollback))block;

/** Synchronously perform database operations in pool using deferred transaction.

 @param block The code to be run on the `MSDatabasePool` pool.
 */

- (void)inDeferredTransaction:(void (^)(MSDatabase *db, BOOL *rollback))block;

#if SQLITE_VERSION_NUMBER >= 3007000

/** Synchronously perform database operations in pool using save point.

 @param block The code to be run on the `MSDatabasePool` pool.
 
 @return `NSError` object if error; `nil` if successful.

 @warning You can not nest these, since calling it will pull another database out of the pool and you'll get a deadlock. If you need to nest, use `<[MSDatabase startSavePointWithName:error:]>` instead.
*/

- (NSError*)inSavePoint:(void (^)(MSDatabase *db, BOOL *rollback))block;
#endif

@end


/** MSDatabasePool delegate category
 
 This is a category that defines the protocol for the MSDatabasePool delegate
 */

@interface NSObject (MSDatabasePoolDelegate)

/** Asks the delegate whether database should be added to the pool. 
 
 @param pool     The `MSDatabasePool` object.
 @param database The `MSDatabase` object.
 
 @return `YES` if it should add database to pool; `NO` if not.
 
 */

- (BOOL)databasePool:(MSDatabasePool*)pool shouldAddDatabaseToPool:(MSDatabase*)database;

/** Tells the delegate that database was added to the pool.
 
 @param pool     The `MSDatabasePool` object.
 @param database The `MSDatabase` object.

 */

- (void)databasePool:(MSDatabasePool*)pool didAddDatabase:(MSDatabase*)database;

@end


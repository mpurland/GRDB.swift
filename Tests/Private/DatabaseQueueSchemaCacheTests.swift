import XCTest
@testable import GRDB

class DatabaseQueueSchemaCacheTests : GRDBTestCase {
    
    func testCache() {
        assertNoError {
            try dbQueue.inDatabase { db in
                try db.execute("CREATE TABLE items (id INTEGER PRIMARY KEY)")
            }
            
            dbQueue.inDatabase { db in
                // Assert that cache is empty
                XCTAssertTrue(db.schemaCache.primaryKey(tableName: "items") == nil)
            }
            
            try dbQueue.inDatabase { db in
                // Warm cache
                let primaryKey = try db.primaryKey("items")
                switch primaryKey {
                case .RowID(let columnName):
                    XCTAssertEqual(columnName, "id")
                default:
                    XCTFail()
                }
                
                // Assert that cache is warmed
                XCTAssertTrue(db.schemaCache.primaryKey(tableName: "items") != nil)
            }
            
            try dbQueue.inDatabase { db in
                // Empty cache after schema change
                try db.execute("DROP TABLE items")
                
                // Assert that cache is empty
                XCTAssertTrue(db.schemaCache.primaryKey(tableName: "items") == nil)
            }
            
            try dbQueue.inDatabase { db in
                do {
                    // Assert that cache is used: we expect an error now that
                    // the cache is empty.
                    _ = try db.primaryKey("items")
                    XCTFail()
                } catch let error as DatabaseError {
                    XCTAssertEqual(error.code, 1) // SQLITE_ERROR
                    XCTAssertEqual(error.message!, "no such table: items")
                    XCTAssertEqual(error.description, "SQLite error 1: no such table: items")
                }
            }
        }
    }
}

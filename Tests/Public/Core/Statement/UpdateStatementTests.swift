import XCTest
import GRDB

class UpdateStatementTests : GRDBTestCase {
    
    override func setUp() {
        super.setUp()
        
        var migrator = DatabaseMigrator()
        
        migrator.registerMigration("createPersons") { db in
            try db.execute(
                "CREATE TABLE persons (" +
                    "id INTEGER PRIMARY KEY, " +
                    "creationDate TEXT, " +
                    "name TEXT NOT NULL, " +
                    "age INT" +
                ")")
        }
        
        assertNoError {
            try migrator.migrate(dbQueue)
        }
    }
    
    func testTrailingSemicolonAndWhiteSpaceIsAcceptedAndOptional() {
        assertNoError {
            try dbQueue.inTransaction { db in
                try db.updateStatement("INSERT INTO persons (name) VALUES ('Arthur');").execute()
                try db.updateStatement("INSERT INTO persons (name) VALUES ('Barbara')\n \t").execute()
                try db.updateStatement("INSERT INTO persons (name) VALUES ('Craig');").execute()
                try db.updateStatement("INSERT INTO persons (name) VALUES ('Daniel');\n \t").execute()
                return .Commit
            }
        }
        
        dbQueue.inDatabase { db in
            let names = String.fetchAll(db, "SELECT name FROM persons ORDER BY name")
            XCTAssertEqual(names, ["Arthur", "Barbara", "Craig", "Daniel"])
        }
    }
    
    func testArrayStatementArguments() {
        assertNoError {
            
            try dbQueue.inTransaction { db in
                
                let statement = try db.updateStatement("INSERT INTO persons (name, age) VALUES (?, ?)")
                let persons: [[DatabaseValueConvertible?]] = [
                    ["Arthur", 41],
                    ["Barbara", nil],
                ]
                for person in persons {
                    try statement.execute(arguments: StatementArguments(person))
                }
                
                return .Commit
            }
            
            dbQueue.inDatabase { db in
                let rows = Row.fetchAll(db, "SELECT * FROM persons ORDER BY name")
                XCTAssertEqual(rows.count, 2)
                XCTAssertEqual(rows[0].value(named: "name") as String, "Arthur")
                XCTAssertEqual(rows[0].value(named: "age") as Int, 41)
                XCTAssertEqual(rows[1].value(named: "name") as String, "Barbara")
                XCTAssertTrue(rows[1]["age"]!.isNull)
            }
        }
    }
    
    func testStatementArgumentsSetterWithArray() {
        assertNoError {
            
            try dbQueue.inTransaction { db in
                
                let statement = try db.updateStatement("INSERT INTO persons (name, age) VALUES (?, ?)")
                let persons: [[DatabaseValueConvertible?]] = [
                    ["Arthur", 41],
                    ["Barbara", nil],
                ]
                for person in persons {
                    statement.arguments = StatementArguments(person)
                    try statement.execute()
                }
                
                return .Commit
            }
            
            dbQueue.inDatabase { db in
                let rows = Row.fetchAll(db, "SELECT * FROM persons ORDER BY name")
                XCTAssertEqual(rows.count, 2)
                XCTAssertEqual(rows[0].value(named: "name") as String, "Arthur")
                XCTAssertEqual(rows[0].value(named: "age") as Int, 41)
                XCTAssertEqual(rows[1].value(named: "name") as String, "Barbara")
                XCTAssertTrue(rows[1]["age"]!.isNull)
            }
        }
    }
    
    func testDictionaryStatementArguments() {
        assertNoError {
            
            try dbQueue.inTransaction { db in
                
                let statement = try db.updateStatement("INSERT INTO persons (name, age) VALUES (:name, :age)")
                let persons: [[String: DatabaseValueConvertible?]] = [
                    ["name": "Arthur", "age": 41],
                    ["name": "Barbara", "age": nil],
                ]
                for person in persons {
                    try statement.execute(arguments: StatementArguments(person))
                }
                
                return .Commit
            }
            
            dbQueue.inDatabase { db in
                let rows = Row.fetchAll(db, "SELECT * FROM persons ORDER BY name")
                XCTAssertEqual(rows.count, 2)
                XCTAssertEqual(rows[0].value(named: "name") as String, "Arthur")
                XCTAssertEqual(rows[0].value(named: "age") as Int, 41)
                XCTAssertEqual(rows[1].value(named: "name") as String, "Barbara")
                XCTAssertTrue(rows[1]["age"]!.isNull)
            }
        }
    }
    
    func testStatementArgumentsSetterWithDictionary() {
        assertNoError {
            
            try dbQueue.inTransaction { db in
                
                let statement = try db.updateStatement("INSERT INTO persons (name, age) VALUES (:name, :age)")
                let persons: [[String: DatabaseValueConvertible?]] = [
                    ["name": "Arthur", "age": 41],
                    ["name": "Barbara", "age": nil],
                ]
                for person in persons {
                    statement.arguments = StatementArguments(person)
                    try statement.execute()
                }
                
                return .Commit
            }
            
            dbQueue.inDatabase { db in
                let rows = Row.fetchAll(db, "SELECT * FROM persons ORDER BY name")
                XCTAssertEqual(rows.count, 2)
                XCTAssertEqual(rows[0].value(named: "name") as String, "Arthur")
                XCTAssertEqual(rows[0].value(named: "age") as Int, 41)
                XCTAssertEqual(rows[1].value(named: "name") as String, "Barbara")
                XCTAssertTrue(rows[1]["age"]!.isNull)
            }
        }
    }
    
    func testUpdateStatementAcceptsSelectQueries() {
        // This test makes sure we do not introduce any regression for
        // https://github.com/groue/GRDB.swift/issues/15
        assertNoError {
            try dbQueue.inDatabase { db in
                try db.execute("SELECT 1")
            }
        }
    }
    
    func testExecuteMultipleStatement() {
        assertNoError {
            try dbQueue.inDatabase { db in
                try db.execute("CREATE TABLE wines (name TEXT, color INT); CREATE TABLE books (name TEXT, age INT)")
                XCTAssertTrue(db.tableExists("wines"))
                XCTAssertTrue(db.tableExists("books"))
            }
        }
    }
    
    func testExecuteMultipleStatementWithTrailingWhiteSpace() {
        assertNoError {
            try dbQueue.inDatabase { db in
                try db.execute("CREATE TABLE wines (name TEXT, color INT); CREATE TABLE books (name TEXT, age INT)\n \t")
                XCTAssertTrue(db.tableExists("wines"))
                XCTAssertTrue(db.tableExists("books"))
            }
        }
    }
    
    func testExecuteMultipleStatementWithTrailingSemicolonAndWhiteSpace() {
        assertNoError {
            try dbQueue.inDatabase { db in
                try db.execute("CREATE TABLE wines (name TEXT, color INT); CREATE TABLE books (name TEXT, age INT);\n \t")
                XCTAssertTrue(db.tableExists("wines"))
                XCTAssertTrue(db.tableExists("books"))
            }
        }
    }
    
    func testExecuteMultipleStatementWithNamedArguments() {
        assertNoError {
            try dbQueue.inTransaction { db in
                try db.execute(
                    "INSERT INTO persons (name, age) VALUES ('Arthur', :age1);" +
                    "INSERT INTO persons (name, age) VALUES ('Arthur', :age2);",
                    arguments: ["age1": 41, "age2": 32])
                XCTAssertEqual(Int.fetchAll(db, "SELECT age FROM persons ORDER BY age"), [32, 41])
                return .Rollback
            }
            
            try dbQueue.inTransaction { db in
                try db.execute(
                    "INSERT INTO persons (name, age) VALUES ('Arthur', :age1);" +
                    "INSERT INTO persons (name, age) VALUES ('Arthur', :age2);",
                    arguments: [41, 32])
                XCTAssertEqual(Int.fetchAll(db, "SELECT age FROM persons ORDER BY age"), [32, 41])
                return .Rollback
            }
        }
    }
    
    func testExecuteMultipleStatementWithReusedNamedArguments() {
        assertNoError {
            try dbQueue.inTransaction { db in
                try db.execute(
                    "INSERT INTO persons (name, age) VALUES ('Arthur', :age);" +
                    "INSERT INTO persons (name, age) VALUES ('Arthur', :age);",
                    arguments: ["age": 41])
                XCTAssertEqual(Int.fetchAll(db, "SELECT age FROM persons"), [41, 41])
                return .Rollback
            }
            
//            // The test below fails because 41 in consumed by the first statement,
//            // leaving no argument for the second statement.
//            //
//            // TODO? make it work
//            try dbQueue.inTransaction { db in
//                try db.execute(
//                    "INSERT INTO persons (name, age) VALUES ('Arthur', :age);" +
//                    "INSERT INTO persons (name, age) VALUES ('Arthur', :age);",
//                    arguments: [41])
//                XCTAssertEqual(Int.fetchAll(db, "SELECT age FROM persons"), [41, 41])
//                return .Rollback
//            }
        }
    }
    
    func testExecuteMultipleStatementWithPositionalArguments() {
        assertNoError {
            try dbQueue.inTransaction { db in
                try db.execute(
                    "INSERT INTO persons (name, age) VALUES ('Arthur', ?);" +
                    "INSERT INTO persons (name, age) VALUES ('Arthur', ?);",
                    arguments: [41, 32])
                XCTAssertEqual(Int.fetchAll(db, "SELECT age FROM persons ORDER BY age"), [32, 41])
                return .Rollback
            }
        }
    }
    
    func testDatabaseErrorThrownByUpdateStatementContainSQL() {
        dbQueue.inDatabase { db in
            do {
                _ = try db.updateStatement("UPDATE blah SET id = 12")
                XCTFail()
            } catch let error as DatabaseError {
                XCTAssertEqual(error.code, 1)
                XCTAssertEqual(error.message!, "no such table: blah")
                XCTAssertEqual(error.sql!, "UPDATE blah SET id = 12")
                XCTAssertEqual(error.description, "SQLite error 1 with statement `UPDATE blah SET id = 12`: no such table: blah")
            } catch {
                XCTFail("\(error)")
            }
        }
    }
    
    func testMultipleValidStatementsError() {
        assertNoError {
            try dbQueue.inDatabase { db in
                do {
                    _ = try db.updateStatement("UPDATE persons SET age = 1; UPDATE persons SET age = 2;")
                    XCTFail("Expected error")
                } catch let error as DatabaseError {
                    XCTAssertEqual(error.code, 21)  // SQLITE_MISUSE
                    XCTAssertEqual(error.message!, "Multiple statements found. To execute multiple statements, use Database.execute() instead.")
                    XCTAssertEqual(error.sql!, "UPDATE persons SET age = 1; UPDATE persons SET age = 2;")
                    XCTAssertEqual(error.description, "SQLite error 21 with statement `UPDATE persons SET age = 1; UPDATE persons SET age = 2;`: Multiple statements found. To execute multiple statements, use Database.execute() instead.")
                }
            }
        }
    }
    
    func testMultipleStatementsWithSecondOneInvalidError() {
        assertNoError {
            try dbQueue.inDatabase { db in
                do {
                    _ = try db.updateStatement("UPDATE persons SET age = 1;x")
                    XCTFail("Expected error")
                } catch let error as DatabaseError {
                    XCTAssertEqual(error.code, 21)  // SQLITE_MISUSE
                    XCTAssertEqual(error.message!, "Multiple statements found. To execute multiple statements, use Database.execute() instead.")
                    XCTAssertEqual(error.sql!, "UPDATE persons SET age = 1;x")
                    XCTAssertEqual(error.description, "SQLite error 21 with statement `UPDATE persons SET age = 1;x`: Multiple statements found. To execute multiple statements, use Database.execute() instead.")
                }
            }
        }
    }
    
    func testReadOnlyDatabaseCanNotBeModified() {
        assertNoError {
            var configuration = Configuration()
            configuration.readonly = true
            dbQueue = try DatabaseQueue(path: dbQueuePath, configuration: configuration)
            let statement = try dbQueue.inDatabase { db in
                try db.updateStatement("CREATE TABLE items (id INTEGER PRIMARY KEY)")
            }
            do {
                try dbQueue.inDatabase { db in
                    try statement.execute()
                }
                XCTFail()
            } catch let error as DatabaseError {
                XCTAssertEqual(error.code, 8)   // SQLITE_READONLY
                XCTAssertEqual(error.message!, "attempt to write a readonly database")
                XCTAssertEqual(error.sql!, "CREATE TABLE items (id INTEGER PRIMARY KEY)")
                XCTAssertEqual(error.description, "SQLite error 8 with statement `CREATE TABLE items (id INTEGER PRIMARY KEY)`: attempt to write a readonly database")
            }
        }
    }
}

import XCTest
import GRDB

class TransactionObserver : TransactionObserverType {
    var lastCommittedEvents: [DatabaseEvent] = []
    var events: [DatabaseEvent] = []
    var commitError: ErrorType?
    var deinitBlock: (() -> ())?
    
    init(deinitBlock: (() -> ())? = nil) {
        self.deinitBlock = deinitBlock
    }
    
    deinit {
        if let deinitBlock = deinitBlock {
            deinitBlock()
        }
    }
    
    var didChangeCount: Int = 0
    var willCommitCount: Int = 0
    var didCommitCount: Int = 0
    var didRollbackCount: Int = 0
    
    func resetCounts() {
        didChangeCount = 0
        willCommitCount = 0
        didCommitCount = 0
        didRollbackCount = 0
    }
    
    func databaseDidChangeWithEvent(event: DatabaseEvent) {
        didChangeCount += 1
        events.append(event)
    }
    
    func databaseWillCommit() throws {
        willCommitCount += 1
        if let commitError = commitError {
            throw commitError
        }
    }
    
    func databaseDidCommit(db: Database) {
        didCommitCount += 1
        lastCommittedEvents = events
        events = []
    }
    
    func databaseDidRollback(db: Database) {
        didRollbackCount += 1
        lastCommittedEvents = []
        events = []
    }
}

class Artist : Record {
    var id: Int64?
    var name: String?
    
    init(id: Int64? = nil, name: String?) {
        self.id = id
        self.name = name
        super.init()
    }
    
    static func setupInDatabase(db: Database) throws {
        try db.execute(
            "CREATE TABLE artists (" +
                "id INTEGER PRIMARY KEY, " +
                "name TEXT" +
            ")")
    }
    
    // Record
    
    static override func databaseTableName() -> String {
        return "artists"
    }
    
    required init(_ row: Row) {
        id = row.value(named: "id")
        name = row.value(named: "name")
        super.init(row)
    }
    
    override var persistentDictionary: [String: DatabaseValueConvertible?] {
        return ["id": id, "name": name]
    }
    
    override func didInsertWithRowID(rowID: Int64, forColumn column: String?) {
        self.id = rowID
    }
}

class Artwork : Record {
    var id: Int64?
    var artistId: Int64?
    var title: String?
    
    init(id: Int64? = nil, title: String?, artistId: Int64? = nil) {
        self.id = id
        self.title = title
        self.artistId = artistId
        super.init()
    }
    
    static func setupInDatabase(db: Database) throws {
        try db.execute(
            "CREATE TABLE artworks (" +
                "id INTEGER PRIMARY KEY, " +
                "artistId INTEGER NOT NULL REFERENCES artists(id) ON DELETE CASCADE ON UPDATE CASCADE, " +
                "title TEXT" +
            ")")
    }
    
    // Record
    
    static override func databaseTableName() -> String {
        return "artworks"
    }
    
    required init(_ row: Row) {
        id = row.value(named: "id")
        title = row.value(named: "title")
        artistId = row.value(named: "artistId")
        super.init(row)
    }
    
    override var persistentDictionary: [String: DatabaseValueConvertible?] {
        return ["id": id, "artistId": artistId, "title": title]
    }
    
    override func didInsertWithRowID(rowID: Int64, forColumn column: String?) {
        self.id = rowID
    }
}

class TransactionObserverTests: GRDBTestCase {
    var observer: TransactionObserver!
    
    override func setUp() {
        super.setUp()
        
        observer = TransactionObserver()
        
        assertNoError {
            dbQueue.addTransactionObserver(self.observer)
            try dbQueue.inDatabase { db in
                try Artist.setupInDatabase(db)
                try Artwork.setupInDatabase(db)
            }
        }

        self.observer.resetCounts()
    }
    
    func match(event event: DatabaseEvent, kind: DatabaseEvent.Kind, tableName: String, rowId: Int64) -> Bool {
        return (event.tableName == tableName) && (event.rowID == rowId) && (event.kind == kind)
    }
    
    
    // MARK: - Events
    
    func testInsertEvent() {
        assertNoError {
            try dbQueue.inDatabase { db in
                let artist = Artist(name: "Gerhard Richter")
                
                //
                try artist.save(db)
                XCTAssertEqual(self.observer.lastCommittedEvents.count, 1)
                let event = self.observer.lastCommittedEvents.filter { event in
                    self.match(event: event, kind: .Insert, tableName: "artists", rowId: artist.id!)
                    }.first
                XCTAssertTrue(event != nil)
            }
        }
    }
    
    func testUpdateEvent() {
        assertNoError {
            try dbQueue.inDatabase { db in
                let artist = Artist(name: "Gerhard Richter")
                try artist.save(db)
                artist.name = "Vincent Fournier"
                
                //
                try artist.save(db)
                XCTAssertEqual(self.observer.lastCommittedEvents.count, 1)
                let event = self.observer.lastCommittedEvents.filter {
                    self.match(event: $0, kind: .Update, tableName: "artists", rowId: artist.id!)
                    }.first
                XCTAssertTrue(event != nil)
            }
        }
    }
    
    func testDeleteEvent() {
        assertNoError {
            try dbQueue.inDatabase { db in
                let artist = Artist(name: "Gerhard Richter")
                try artist.save(db)
                
                //
                try artist.delete(db)
                XCTAssertEqual(self.observer.lastCommittedEvents.count, 1)
                let event = self.observer.lastCommittedEvents.filter {
                    self.match(event: $0, kind: .Delete, tableName: "artists", rowId: artist.id!)
                    }.first
                XCTAssertTrue(event != nil)
            }
        }
    }
    
    func testCascadingDeleteEvents() {
        assertNoError {
            try dbQueue.inDatabase { db in
                let artist = Artist(name: "Gerhard Richter")
                try artist.save(db)
                let artwork1 = Artwork(title: "Cloud", artistId: artist.id)
                try artwork1.save(db)
                let artwork2 = Artwork(title: "Ema (Nude on a Staircase)", artistId: artist.id)
                try artwork2.save(db)
                
                //
                try artist.delete(db)
                XCTAssertEqual(self.observer.lastCommittedEvents.count, 3)
                let artistEvent = self.observer.lastCommittedEvents.filter {
                    self.match(event: $0, kind: .Delete, tableName: "artists", rowId: artist.id!)
                    }.first
                XCTAssertTrue(artistEvent != nil)
                let artwork1Event = self.observer.lastCommittedEvents.filter {
                    self.match(event: $0, kind: .Delete, tableName: "artworks", rowId: artwork1.id!)
                    }.first
                XCTAssertTrue(artwork1Event != nil)
                let artwork2Event = self.observer.lastCommittedEvents.filter {
                    self.match(event: $0, kind: .Delete, tableName: "artworks", rowId: artwork2.id!)
                    }.first
                XCTAssertTrue(artwork2Event != nil)
            }
        }
    }
    
    
    // MARK: - Commits & Rollback
    
    func testImplicitTransactionCommit() {
        assertNoError {
            let artist = Artist(name: "Gerhard Richter")
            
            try dbQueue.inDatabase { db in
                self.observer.resetCounts()
                try artist.save(db)
                XCTAssertEqual(self.observer.didChangeCount, 1)
                XCTAssertEqual(self.observer.willCommitCount, 1)
                XCTAssertEqual(self.observer.didCommitCount, 1)
                XCTAssertEqual(self.observer.didRollbackCount, 0)
            }
        }
    }
    
    func testCascadeWithImplicitTransactionCommit() {
        assertNoError {
            let artist = Artist(name: "Gerhard Richter")
            let artwork1 = Artwork(title: "Cloud")
            let artwork2 = Artwork(title: "Ema (Nude on a Staircase)")
            
            try dbQueue.inDatabase { db in
                try artist.save(db)
                artwork1.artistId = artist.id
                artwork2.artistId = artist.id
                try artwork1.save(db)
                try artwork2.save(db)
                
                //
                self.observer.resetCounts()
                try artist.delete(db)
                XCTAssertEqual(self.observer.didChangeCount, 3) // 3 deletes
                XCTAssertEqual(self.observer.willCommitCount, 1)
                XCTAssertEqual(self.observer.didCommitCount, 1)
                XCTAssertEqual(self.observer.didRollbackCount, 0)
                
                let artistDeleteEvent = self.observer.lastCommittedEvents.filter {
                    self.match(event: $0, kind: .Delete, tableName: "artists", rowId: artist.id!)
                    }.first
                XCTAssertTrue(artistDeleteEvent != nil)
                
                let artwork1DeleteEvent = self.observer.lastCommittedEvents.filter {
                    self.match(event: $0, kind: .Delete, tableName: "artworks", rowId: artwork1.id!)
                    }.first
                XCTAssertTrue(artwork1DeleteEvent != nil)
                
                let artwork2DeleteEvent = self.observer.lastCommittedEvents.filter {
                    self.match(event: $0, kind: .Delete, tableName: "artworks", rowId: artwork2.id!)
                    }.first
                XCTAssertTrue(artwork2DeleteEvent != nil)
            }
        }
    }
    
    func testExplicitTransactionCommit() {
        assertNoError {
            let artist = Artist(name: "Gerhard Richter")
            let artwork1 = Artwork(title: "Cloud")
            let artwork2 = Artwork(title: "Ema (Nude on a Staircase)")
            
            try dbQueue.inTransaction { db in
                self.observer.resetCounts()
                try artist.save(db)
                XCTAssertEqual(self.observer.didChangeCount, 1)
                XCTAssertEqual(self.observer.willCommitCount, 0)
                XCTAssertEqual(self.observer.didCommitCount, 0)
                XCTAssertEqual(self.observer.didRollbackCount, 0)
                
                artwork1.artistId = artist.id
                artwork2.artistId = artist.id
                
                self.observer.resetCounts()
                try artwork1.save(db)
                XCTAssertEqual(self.observer.didChangeCount, 1)
                XCTAssertEqual(self.observer.willCommitCount, 0)
                XCTAssertEqual(self.observer.didCommitCount, 0)
                XCTAssertEqual(self.observer.didRollbackCount, 0)
                
                self.observer.resetCounts()
                try artwork2.save(db)
                XCTAssertEqual(self.observer.didChangeCount, 1)
                XCTAssertEqual(self.observer.willCommitCount, 0)
                XCTAssertEqual(self.observer.didCommitCount, 0)
                XCTAssertEqual(self.observer.didRollbackCount, 0)
                
                self.observer.resetCounts()
                return .Commit
            }
            XCTAssertEqual(self.observer.didChangeCount, 0)
            XCTAssertEqual(self.observer.willCommitCount, 1)
            XCTAssertEqual(self.observer.didCommitCount, 1)
            XCTAssertEqual(self.observer.didRollbackCount, 0)
            XCTAssertEqual(observer.lastCommittedEvents.count, 3)
            
            let artistEvent = observer.lastCommittedEvents.filter {
                self.match(event: $0, kind: .Insert, tableName: "artists", rowId: artist.id!)
                }.first
            XCTAssertTrue(artistEvent != nil)
            
            let artwork1Event = observer.lastCommittedEvents.filter {
                self.match(event: $0, kind: .Insert, tableName: "artworks", rowId: artwork1.id!)
                }.first
            XCTAssertTrue(artwork1Event != nil)
            
            let artwork2Event = observer.lastCommittedEvents.filter {
                self.match(event: $0, kind: .Insert, tableName: "artworks", rowId: artwork2.id!)
                }.first
            XCTAssertTrue(artwork2Event != nil)
        }
    }
    
    func testCascadeWithExplicitTransactionCommit() {
        assertNoError {
            let artist = Artist(name: "Gerhard Richter")
            let artwork1 = Artwork(title: "Cloud")
            let artwork2 = Artwork(title: "Ema (Nude on a Staircase)")
            
            try dbQueue.inTransaction { db in
                try artist.save(db)
                artwork1.artistId = artist.id
                artwork2.artistId = artist.id
                try artwork1.save(db)
                try artwork2.save(db)
                
                //
                self.observer.resetCounts()
                try artist.delete(db)
                XCTAssertEqual(self.observer.didChangeCount, 3) // 3 deletes
                XCTAssertEqual(self.observer.willCommitCount, 0)
                XCTAssertEqual(self.observer.didCommitCount, 0)
                XCTAssertEqual(self.observer.didRollbackCount, 0)
                
                self.observer.resetCounts()
                return .Commit
            }
            XCTAssertEqual(self.observer.didChangeCount, 0)
            XCTAssertEqual(self.observer.willCommitCount, 1)
            XCTAssertEqual(self.observer.didCommitCount, 1)
            XCTAssertEqual(self.observer.didRollbackCount, 0)
            XCTAssertEqual(self.observer.lastCommittedEvents.count, 6)  // 3 inserts, and 3 deletes
            
            let artistInsertEvent = self.observer.lastCommittedEvents.filter {
                self.match(event: $0, kind: .Insert, tableName: "artists", rowId: artist.id!)
                }.first
            XCTAssertTrue(artistInsertEvent != nil)
            
            let artwork1InsertEvent = self.observer.lastCommittedEvents.filter {
                self.match(event: $0, kind: .Insert, tableName: "artworks", rowId: artwork1.id!)
                }.first
            XCTAssertTrue(artwork1InsertEvent != nil)
            
            let artwork2InsertEvent = self.observer.lastCommittedEvents.filter {
                self.match(event: $0, kind: .Insert, tableName: "artworks", rowId: artwork2.id!)
                }.first
            XCTAssertTrue(artwork2InsertEvent != nil)
            
            let artistDeleteEvent = self.observer.lastCommittedEvents.filter {
                self.match(event: $0, kind: .Delete, tableName: "artists", rowId: artist.id!)
                }.first
            XCTAssertTrue(artistDeleteEvent != nil)
            
            let artwork1DeleteEvent = self.observer.lastCommittedEvents.filter {
                self.match(event: $0, kind: .Delete, tableName: "artworks", rowId: artwork1.id!)
                }.first
            XCTAssertTrue(artwork1DeleteEvent != nil)
            
            let artwork2DeleteEvent = self.observer.lastCommittedEvents.filter {
                self.match(event: $0, kind: .Delete, tableName: "artworks", rowId: artwork2.id!)
                }.first
            XCTAssertTrue(artwork2DeleteEvent != nil)
        }
    }
    
    func testExplicitTransactionRollback() {
        assertNoError {
            let artist = Artist(name: "Gerhard Richter")
            let artwork1 = Artwork(title: "Cloud")
            let artwork2 = Artwork(title: "Ema (Nude on a Staircase)")
            
            try dbQueue.inTransaction { db in
                try artist.save(db)
                artwork1.artistId = artist.id
                artwork2.artistId = artist.id
                try artwork1.save(db)
                try artwork2.save(db)
                
                self.observer.resetCounts()
                return .Rollback
            }
            XCTAssertEqual(self.observer.didChangeCount, 0)
            XCTAssertEqual(self.observer.willCommitCount, 0)
            XCTAssertEqual(self.observer.didCommitCount, 0)
            XCTAssertEqual(self.observer.didRollbackCount, 1)
        }
    }
    
    func testImplicitTransactionRollbackCausedByDatabaseError() {
        assertNoError {
            do {
                try dbQueue.inDatabase { db in
                    do {
                        try Artwork(title: "meh").save(db)
                        XCTFail("Expected Error")
                    } catch let error as DatabaseError {
                        XCTAssertEqual(error.code, 19)
                        XCTAssertEqual(self.observer.didChangeCount, 0)
                        XCTAssertEqual(self.observer.willCommitCount, 0)
                        XCTAssertEqual(self.observer.didCommitCount, 0)
                        XCTAssertEqual(self.observer.didRollbackCount, 0)
                        throw error
                    }
                }
                XCTFail("Expected Error")
            } catch let error as DatabaseError {
                XCTAssertEqual(error.code, 19)
                XCTAssertEqual(self.observer.didChangeCount, 0)
                XCTAssertEqual(self.observer.willCommitCount, 0)
                XCTAssertEqual(self.observer.didCommitCount, 0)
                XCTAssertEqual(self.observer.didRollbackCount, 0)
            }
        }
    }

    func testExplicitTransactionRollbackCausedByDatabaseError() {
        assertNoError {
            do {
                try dbQueue.inTransaction { db in
                    do {
                        try Artwork(title: "meh").save(db)
                        XCTFail("Expected Error")
                    } catch let error as DatabaseError {
                        // Immediate constraint check has failed.
                        XCTAssertEqual(error.code, 19)
                        XCTAssertEqual(self.observer.didChangeCount, 0)
                        XCTAssertEqual(self.observer.willCommitCount, 0)
                        XCTAssertEqual(self.observer.didCommitCount, 0)
                        XCTAssertEqual(self.observer.didRollbackCount, 0)
                        throw error
                    }
                    return .Commit
                }
                XCTFail("Expected Error")
            } catch let error as DatabaseError {
                XCTAssertEqual(error.code, 19)
                XCTAssertEqual(self.observer.didChangeCount, 0)
                XCTAssertEqual(self.observer.willCommitCount, 0)
                XCTAssertEqual(self.observer.didCommitCount, 0)
                XCTAssertEqual(self.observer.didRollbackCount, 1)
            }
        }
    }
    
    func testImplicitTransactionRollbackCausedByTransactionObserver() {
        assertNoError {
            self.observer.commitError = NSError(domain: "foo", code: 0, userInfo: nil)
            dbQueue.inDatabase { db in
                do {
                    try Artist(name: "Gerhard Richter").save(db)
                    XCTFail("Expected Error")
                } catch let error as NSError {
                    XCTAssertEqual(error.domain, "foo")
                    XCTAssertEqual(error.code, 0)
                    XCTAssertEqual(self.observer.didChangeCount, 1)
                    XCTAssertEqual(self.observer.willCommitCount, 1)
                    XCTAssertEqual(self.observer.didCommitCount, 0)
                    XCTAssertEqual(self.observer.didRollbackCount, 1)
                }
            }
        }
    }
    
    func testExplicitTransactionRollbackCausedByTransactionObserver() {
        assertNoError {
            self.observer.commitError = NSError(domain: "foo", code: 0, userInfo: nil)
            do {
                try dbQueue.inTransaction { db in
                    do {
                        try Artist(name: "Gerhard Richter").save(db)
                    } catch {
                        XCTFail("Unexpected Error")
                    }
                    return .Commit
                }
                XCTFail("Expected Error")
            } catch let error as NSError {
                XCTAssertEqual(error.domain, "foo")
                XCTAssertEqual(error.code, 0)
                XCTAssertEqual(self.observer.didChangeCount, 1)
                XCTAssertEqual(self.observer.willCommitCount, 1)
                XCTAssertEqual(self.observer.didCommitCount, 0)
                XCTAssertEqual(self.observer.didRollbackCount, 1)
            }
        }
    }
    
    func testImplicitTransactionRollbackCausedByDatabaseErrorSuperseedTransactionObserver() {
        assertNoError {
            self.observer.commitError = NSError(domain: "foo", code: 0, userInfo: nil)
            do {
                try dbQueue.inDatabase { db in
                    do {
                        try Artwork(title: "meh").save(db)
                        XCTFail("Expected Error")
                    } catch let error as DatabaseError {
                        XCTAssertEqual(error.code, 19)
                        XCTAssertEqual(self.observer.didChangeCount, 0)
                        XCTAssertEqual(self.observer.willCommitCount, 0)
                        XCTAssertEqual(self.observer.didCommitCount, 0)
                        XCTAssertEqual(self.observer.didRollbackCount, 0)
                        throw error
                    }
                }
                XCTFail("Expected Error")
            } catch let error as DatabaseError {
                XCTAssertEqual(error.code, 19)
                XCTAssertEqual(self.observer.didChangeCount, 0)
                XCTAssertEqual(self.observer.willCommitCount, 0)
                XCTAssertEqual(self.observer.didCommitCount, 0)
                XCTAssertEqual(self.observer.didRollbackCount, 0)
            }
        }
    }
    
    func testExplicitTransactionRollbackCausedByDatabaseErrorSuperseedTransactionObserver() {
        assertNoError {
            self.observer.commitError = NSError(domain: "foo", code: 0, userInfo: nil)
            do {
                try dbQueue.inTransaction { db in
                    do {
                        try Artwork(title: "meh").save(db)
                        XCTFail("Expected Error")
                    } catch let error as DatabaseError {
                        // Immediate constraint check has failed.
                        XCTAssertEqual(error.code, 19)
                        XCTAssertEqual(self.observer.didChangeCount, 0)
                        XCTAssertEqual(self.observer.willCommitCount, 0)
                        XCTAssertEqual(self.observer.didCommitCount, 0)
                        XCTAssertEqual(self.observer.didRollbackCount, 0)
                        throw error
                    }
                    return .Commit
                }
                XCTFail("Expected Error")
            } catch let error as DatabaseError {
                XCTAssertEqual(error.code, 19)
                XCTAssertEqual(self.observer.didChangeCount, 0)
                XCTAssertEqual(self.observer.willCommitCount, 0)
                XCTAssertEqual(self.observer.didCommitCount, 0)
                XCTAssertEqual(self.observer.didRollbackCount, 1)
            }
        }
    }
    
    func testMinimalRowIDUpdateObservation() {
        // Here we test that updating a Record made of a single primary key
        // column performs an actual UPDATE statement, even though it is
        // totally useless (UPDATE id = 1 FROM records WHERE id = 1).
        //
        // It is important to update something, so that TransactionObserverType
        // can observe a change.
        //
        // The goal is to be able to write tests with minimal tables,
        // including tables made of a single primary key column. The less we
        // have exceptions, the better it is.
        assertNoError {
            try dbQueue.inDatabase { db in
                try MinimalRowID.setupInDatabase(db)
                
                let record = MinimalRowID()
                try record.save(db)
                
                self.observer.resetCounts()
                try record.update(db)
                XCTAssertEqual(self.observer.didChangeCount, 1)
                XCTAssertEqual(self.observer.willCommitCount, 1)
                XCTAssertEqual(self.observer.didCommitCount, 1)
                XCTAssertEqual(self.observer.didRollbackCount, 0)
            }
        }
    }
    
    
    // MARK: - Multiple observers
    
    func testInsertEventIsNotifiedToAllObservers() {
        assertNoError {
            let observer1 = TransactionObserver()
            let observer2 = TransactionObserver()
            
            dbQueue.addTransactionObserver(observer1)
            dbQueue.addTransactionObserver(observer2)
            
            try dbQueue.inDatabase { db in
                let artist = Artist(name: "Gerhard Richter")
                
                //
                try artist.save(db)
                
                do {
                    XCTAssertEqual(observer1.lastCommittedEvents.count, 1)
                    let event = observer1.lastCommittedEvents.filter { event in
                        self.match(event: event, kind: .Insert, tableName: "artists", rowId: artist.id!)
                        }.first
                    XCTAssertTrue(event != nil)
                }
                do {
                    XCTAssertEqual(observer2.lastCommittedEvents.count, 1)
                    let event = observer2.lastCommittedEvents.filter { event in
                        self.match(event: event, kind: .Insert, tableName: "artists", rowId: artist.id!)
                        }.first
                    XCTAssertTrue(event != nil)
                }
            }
        }
    }
    
    func testExplicitTransactionRollbackCausedBySecondTransactionObserverOutOfThree() {
        assertNoError {
            let observer1 = TransactionObserver()
            let observer2 = TransactionObserver()
            let observer3 = TransactionObserver()
            observer2.commitError = NSError(domain: "foo", code: 0, userInfo: nil)
            
            dbQueue.addTransactionObserver(observer1)
            dbQueue.addTransactionObserver(observer2)
            dbQueue.addTransactionObserver(observer3)
            
            do {
                try dbQueue.inTransaction { db in
                    do {
                        try Artist(name: "Gerhard Richter").save(db)
                    } catch {
                        XCTFail("Unexpected Error")
                    }
                    return .Commit
                }
                XCTFail("Expected Error")
            } catch let error as NSError {
                XCTAssertEqual(error.domain, "foo")
                XCTAssertEqual(error.code, 0)
                
                XCTAssertEqual(observer1.didChangeCount, 1)
                XCTAssertEqual(observer1.willCommitCount, 1)
                XCTAssertEqual(observer1.didCommitCount, 0)
                XCTAssertEqual(observer1.didRollbackCount, 1)

                XCTAssertEqual(observer2.didChangeCount, 1)
                XCTAssertEqual(observer2.willCommitCount, 1)
                XCTAssertEqual(observer2.didCommitCount, 0)
                XCTAssertEqual(observer2.didRollbackCount, 1)
                
                XCTAssertEqual(observer3.didChangeCount, 1)
                XCTAssertEqual(observer3.willCommitCount, 0)
                XCTAssertEqual(observer3.didCommitCount, 0)
                XCTAssertEqual(observer3.didRollbackCount, 1)
            }
        }
    }
    
    func testTransactionObserverIsNotRetained() {
        assertNoError {
            var observerReleased = false
            do {
                let observer = TransactionObserver(deinitBlock: { observerReleased = true })
                withExtendedLifetime(observer) {
                    dbQueue.addTransactionObserver(observer)
                    XCTAssertFalse(observerReleased)
                }
            }
            XCTAssertTrue(observerReleased)
            try dbQueue.inDatabase { db in
                try Artist(name: "Gerhard Richter").save(db)
            }
        }
    }

}

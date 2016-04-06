import Quick
import Nimble
import FutureSwift

class FutureSpec: QuickSpec {
  
  override func spec() {
    describe("Future") {
      
      it("can resolve") {
        var thenCalledWhenResolved = false
        var thenCalledDirectlyWhenAlreadyResolved = false
        var failCalled = false
        
        let future = Future<Void>()
        future.then { thenCalledWhenResolved = true }
        future.fail { _ in failCalled = true }
        future.resolve()
        future.then { thenCalledDirectlyWhenAlreadyResolved = true }
        future.fail { _ in failCalled = true }
        
        // Wait for async call dispatched on main queue
        waitUntil { done in done() }

        expect(future.state) == FutureState.Resolved
        expect(failCalled) == false
        expect(thenCalledWhenResolved) == true
        expect(thenCalledDirectlyWhenAlreadyResolved) == true
      }

      it("can fail") {
        var failCalledWhenRejected = false
        var failCalledDirectlyWhenAlreadyRejected = false
        var thenCalled = false
        
        let future = Future<Void>()
        future.fail { _ in failCalledWhenRejected = true }
        future.then { thenCalled = true }
        future.reject()
        future.then { thenCalled = true }
        future.fail { _ in failCalledDirectlyWhenAlreadyRejected = true }
        
        // Wait for async call dispatched on main queue
        waitUntil { done in done() }
        
        expect(future.state) == FutureState.Rejected
        expect(thenCalled) == false
        expect(failCalledWhenRejected) == true
        expect(failCalledDirectlyWhenAlreadyRejected) == true
      }

      it("always resolve/reject on main queue") {
        var isMainQueueOnResolve = false
        var isMainQueueOnReject = false
        
        let futureResolved = Future<Void>()
        let futureRejected = Future<Void>()
        
        futureResolved.then { isMainQueueOnResolve = NSThread.isMainThread() }
        futureRejected.fail { _ in isMainQueueOnReject = NSThread.isMainThread() }
        
        futureResolved.resolve()
        futureRejected.reject(nil)
        
        // Wait for async call dispatched on main queue
        waitUntil { done in done() }
        
        expect(futureResolved.state) == FutureState.Resolved
        expect(futureRejected.state) == FutureState.Rejected
        expect(isMainQueueOnResolve) == true
        expect(isMainQueueOnReject) == true
      }
      
      it("calls block in FIFO order") {
        var order: [Int] = []
        
        let future = Future<Void>()
        
        for i in (0...2) {
          future.then {
            order.append(i)
          }
        }
        
        future.resolve()
        
        // Wait for async call dispatched on main queue
        waitUntil { done in done() }
        
        expect(order) == [0, 1, 2]
      }
      
      it("can chain futures") {
        var results: [Int] = []
        let future = Future<Int>()
        
        future.then { result -> Int in
          results.append(result)
          return 2
          //return Future<Int>.resolve(2)
        }.then { result in
          results.append(result)
        }
        
        future.resolve(1)
        
        // Wait for async call dispatched on main queue
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 1, false)
        
        expect(results) == [1, 2]
      }
      
      context("when a future fails") {
        future {
        
        }
        
        it("it rejects up to the parent") {
          let future = Future<Int>()
          
          var results: [Int] = []
          
          future.then { x -> Future<Int> in
            results.append(x)
            return Future<Void>.reject(nil)
          }.then { _ in
            results.append(21)
          }.fail { _ in
            results.append(42)
          }
          
          future.resolve(1)
          
          // Wait for async call dispatched on main queue
          CFRunLoopRunInMode(kCFRunLoopDefaultMode, 1, false)
          
          expect(results) == [1, 42]
        }
      }
    }
    
    describe("Future#finally") {
      var future: Future<Void>!
      var thenCalled: Bool = false
      var failedCalled: Bool = false
      var finallyCalled: Bool = false
      
      beforeEach {
        future = Future<Void>()
        thenCalled = false
        failedCalled = false
        finallyCalled = false
      }
      
      it("properly calls finally when future is resolved") {
        future.then {
          thenCalled = true
        }.fail { _ in
          failedCalled = true
        }.finally {
          finallyCalled = true
        }
        
        future.resolve()
        
        waitUntil { done in done() }

        expect(thenCalled) == true
        expect(failedCalled) == false
        expect(finallyCalled) == true
      }

      it("properly calls finally when future is rejected") {
        future.then {
          thenCalled = true
        }.fail { _ in
          failedCalled = true
        }.finally {
          finallyCalled = true
        }
        
        future.reject(nil)
        
        waitUntil { done in done() }

        expect(thenCalled) == false
        expect(failedCalled) == true
        expect(finallyCalled) == true
      }
      
    }

    describe("Future#timeout") {
      it("rejects the future when timeout triggers") {
        var failedCalled = false
        
        let future = Future<Void>()
        future.fail { _ in
          failedCalled = true
        }.timeout(0.5)
        
        future.timeoutTimer?.fire()
        
        waitUntil { done in done() }
        
        expect(failedCalled) == true
      }
    }
    
    describe("Futur#merge") {
      context("when they all resolve") {
        it("resolves with a tuple of values") {
          let future1 = Future<Int>()
          let future2 = Future<String>()
          let future3 = future1.merge(future2)
          
          future1.resolve(42)
          future2.resolve("42")
          
          waitUntil { done in
            future3.then { x, y in
              expect(x) == 42
              expect(y) == "42"
              done()
            }
          }
        }
      }
      
      context("when one fails") {
        it("should fail") {
          let future1 = Future<Int>()
          let future2 = Future<String>()
          let future3 = future1.merge(future2)

          let error = NSError(domain: "", code: 42, userInfo: nil)
          
          future1.resolve(42)
          future2.reject(error)
          
          waitUntil { done in
            future3.fail { error in
              expect(error) == error
              done()
            }
          }
        }
      }
    }
    
    describe("Future.all") {
      
      context("when all futures resolve") {
        let futures: [Future<Int>] = (1...3).map { index in
          return promise { future in
            NSThread.sleepForTimeInterval(0.2)
            future.resolve(index)
          }
        }
        
        var results: [Int]!
        let future = all(futures)
        
        waitUntil { done in
          future.then {
            results = $0
            done()
          }
        }
        
        it ("resolves when all futures are resolved") {
          for future in futures {
            expect(future.state) == FutureState.Resolved
          }
          
          expect(future.state) == FutureState.Resolved
        }
        
        it("resolves with all values") {
          expect(results).toNot(beNil())
          expect(results.count) == 3
          expect(results).to(contain(1))
          expect(results).to(contain(2))
          expect(results).to(contain(3))
        }
      }
      
      context("when at least one future fails") {
        let futures: [Future<Int>] = (1...3).map { index in
          return promise { future in
            NSThread.sleepForTimeInterval(0.2 * Double(index))
            if index == 1 {
              future.reject()
            } else {
              future.resolve(index)
            }
          }
        }

        let future = all(futures)

        waitUntil { done in
          future.fail { _ in
            done()
          }
        }
        
        it ("rejects the promise") {
          expect(future.state) == FutureState.Rejected
        }
      }
      
    }
    
    describe("Future.any") {
      
      context("when at least 1 future resolves") {
        let futures: [Future<Int>] = (0...2).map { index in
          return promise { future in
            if index == 0 {
              future.resolve(index)
            } else {
              future.reject()
            }
          }
        }
        
        var result: Int!
        
        waitUntil { done in
          any(futures).then {
            result = $0
            done()
          }
        }
        
        it("resolves as soon as one future is resolved") {
          expect(futures.map { $0.state }).to(contain(FutureState.Resolved))
        }
        
        it("resolves with the first value resolved") {
          expect(result).toNot(beNil())
          expect(result) == 0
        }
      }
      
    }
    
    describe("...") {
      func request(params: [String: String]) -> Future<[String: String]> {
        return future {
          NSThread.sleepForTimeInterval(0.5)
          return params
        }
      }
      
      func login(u: String, p: String) -> Future<[String: String]> {
        return future {
          try await <- request([u: u, p: p])
        }
      }
      
      func values(user: [String: String]) -> Future<[String]> {
        return future {
          try { Array<String>($0.values).sort() } <- request(user)
        }
      }
      
      it("fukcing works") {
        let posts = try? await <- values <- login("foo", p: "bar")
        expect(posts) == ["bar", "foo"]
      }
    }
    
  }
}

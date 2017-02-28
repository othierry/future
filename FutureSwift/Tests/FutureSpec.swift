import Quick
import Nimble
import Future

func futures_wait(_ f: @escaping (Void) -> [Future<Void>]) {
  waitUntil(timeout: 10) { done in
    let futures = f()
    var x = futures.count
    futures.forEach {
      $0.finally {
        x -= 1
        if x == 0 {
          done()
        }
      }
    }
  }
}

class FutureSpec: QuickSpec {

  override func spec() {
    describe("Future") {

      it("can resolve") {
        var thenCalledWhenResolved = false
        var thenCalledDirectlyWhenAlreadyResolved = false
        var failCalled = false

        let future = Future<Void>()

        futures_wait() {
          let futures = [
            future.then { thenCalledWhenResolved = true },
            future.fail { _ in failCalled = true }
          ]

          future.resolve()

          return futures
        }

        expect(thenCalledWhenResolved) == true
        expect(future.state.isResolved) == true
        expect(failCalled) == false

        futures_wait {
          [
            future.then { thenCalledDirectlyWhenAlreadyResolved = true }
          ]
        }

        expect(thenCalledDirectlyWhenAlreadyResolved) == true
      }

      it("can fail") {
        var failCalledWhenRejected = false
        var failCalledDirectlyWhenAlreadyRejected = false
        var thenCalled = false
        
        let future = Future<Void>()

        futures_wait {
          let futures = [
            future.fail { _ in failCalledWhenRejected = true },
            future.then { thenCalled = true }
          ]

          future.reject()

          return futures
        }

        expect(future.state.isRejected) == true
        expect(thenCalled) == false
        expect(failCalledWhenRejected) == true

        futures_wait {
          [
            future.fail { _ in failCalledDirectlyWhenAlreadyRejected = true }
          ]
        }

        expect(failCalledDirectlyWhenAlreadyRejected) == true
      }

      it("resolves/reject on specified queue") {
        for queue in [DispatchQueue.main, DispatchQueue(label: UUID().uuidString, attributes: DispatchQueue.Attributes.concurrent)] {
          var resolveQueueLabel: String!
          var rejectQueueLabel: String!
          var finallyQueueLabel: String!

          let futureResolved = Future<Void>()
          let futureRejected = Future<Void>()

          futures_wait {
            let futures = [
              futureResolved.then(on: queue) {
                resolveQueueLabel = String(cString: __dispatch_queue_get_label(nil), encoding: .utf8)
              },
              futureRejected.fail(on: queue) { _ in
                rejectQueueLabel = String(cString: __dispatch_queue_get_label(nil), encoding: .utf8)
              },
              futureRejected.finally(on: queue) {
                finallyQueueLabel = String(cString: __dispatch_queue_get_label(nil), encoding: .utf8)
              }
            ]

            futureResolved.resolve()
            futureRejected.reject(nil)

            return futures
          }

          expect(futureResolved.state.isResolved) == true
          expect(futureRejected.state.isRejected) == true
          expect(resolveQueueLabel) == queue.label
          expect(rejectQueueLabel) == queue.label
        }
      }

      it("calls block in FIFO order") {
        var order: [Int] = []
        
        let future = Future<Void>()

        futures_wait {
          let futures = (0...2).map { x in
            future.then {
              order.append(x)
            }
          }

          future.resolve()

          return futures
        }

        expect(order) == [0, 1, 2]
      }
      
      it("can chain futures") {
        var results: [Int] = []
        let future = Future<Int>()

        futures_wait {
          let futures = [
            future.then { result -> Int in
              results.append(result)
              return 2
            }.then { result in
              results.append(result)
            }.wrap()
          ]

          future.resolve(1)

          return futures
        }

        expect(results) == [1, 2]
      }
      
      context("when a future fails") {
        it("it rejects up to the parent") {
          var results: [Int] = []
          let future = Future<Int>()

          futures_wait {
            let futures = [
              future.then { x -> Future<Int> in
                results.append(x)
                return Future<Void>.reject(nil)
              }.then { _ in
                results.append(21)
              }.fail { _ in
                results.append(42)
              }.wrap()
            ]

            future.resolve(1)

            return futures
          }

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
        futures_wait {
          let futures = [
            future.then {
              thenCalled = true
            }.fail { _ in
              failedCalled = true
            }.finally {
              finallyCalled = true
            }
          ]

          future.resolve()

          return futures
        }

        expect(thenCalled) == true
        expect(failedCalled) == false
        expect(finallyCalled) == true
      }

      it("properly calls finally when future is rejected") {
        futures_wait {
          let futures = [
            future.then {
              thenCalled = true
            }.fail { _ in
              failedCalled = true
            }.finally {
              finallyCalled = true
            }
          ]

          future.reject(nil)

          return futures
        }

        expect(thenCalled) == false
        expect(failedCalled) == true
        expect(finallyCalled) == true
      }
      
    }

    describe("Future#timeout") {
      it("rejects the future when timeout triggers") {
        var failedCalled = false
        let future = Future<Void>()

        futures_wait {
          let futures = [
            future.fail { _ in
              failedCalled = true
            }.timeout(after: 0.5)
          ]

          return futures
        }

        expect(failedCalled) == true
      }
    }
    
    describe("Futur#merge") {
      context("when they all resolve") {
        it("resolves with a tuple of values") {
          let future1 = Future<Int>()
          let future2 = Future<String>()
          let future3 = future1.merge(future2)

          var x: Int!
          var y: String!

          futures_wait {
            future1.resolve(42)
            future2.resolve("42")

            return [
              future3.then {
                x = $0
                y = $1
              }.wrap()
            ]
          }

          expect(x) == 42
          expect(y) == "42"
        }
      }
      
      context("when one fails") {
        it("should fail") {
          let future1 = Future<Int>()
          let future2 = Future<String>()
          let future3 = future1.merge(future2)

          let error = NSError(domain: "", code: 42, userInfo: nil)
          var receivedError: NSError!

          futures_wait {
            future1.resolve(42)
            future2.reject(error)

            return [
              future3.fail { error in
                receivedError = error
              }.wrap()
            ]
          }

          expect(receivedError) == error
        }
      }
    }
    
    describe("Future.all") {
      
      context("when all futures resolve") {
        let futures: [Future<Int>] = (1...3).map { index in
          return Promise { promise in
            Thread.sleep(forTimeInterval: 0.2)
            promise.resolve(index)
          }
        }
        
        var results: [Int]!
        let future = futures.all()

        futures_wait {
          [
            future.then {
              results = $0
            }
          ]
        }

        it ("resolves when all futures are resolved") {
          for future in futures {
            expect(future.state.isResolved) == true
          }
          
          expect(future.state.isResolved) == true
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
          return Promise { future in
            Thread.sleep(forTimeInterval: 0.2 * Double(index))
            if index == 1 {
              future.reject()
            } else {
              future.resolve(index)
            }
          }
        }

        let future = futures.all()

        futures_wait {
          [future.wrap()]
        }

        it ("rejects the promise") {
          expect(future.state.isRejected) == true
        }
      }
      
    }
    
    describe("Future.any") {
      
      context("when at least 1 future resolves") {
        Promise<Int> { p in  }

        let futures: [Future<Int>] = (0...2).map { index in
          return Promise { future in
            if index == 0 {
              future.resolve(index)
            } else {
              future.reject()
            }
          }
        }
        
        var result: Int!
        let future = futures.any()

        futures_wait {
          [future.wrap()]
        }

        waitUntil { done in
          futures.any().then {
            result = $0
            done()
          }
        }
        
        it("resolves as soon as one future is resolved") {
          expect(futures.map { $0.state.isResolved }).to(contain(true))
          expect(future.state.isResolved) == true
        }
        
        it("resolves with the first value resolved") {
          expect(result).toNot(beNil())
          expect(result) == 0
        }
      }
      
      
    }
    
    describe("await") {
      func request(_ params: [String: String]) -> Future<[String: String]> {
        return Future {
          Thread.sleep(forTimeInterval: 0.5)
          return params
        }
      }
      
      func login(_ u: String, p: String) -> Future<[String: String]> {
        return Future {
          try await(
            request([u: u, p: p])
          )
        }
      }
      
      func values(_ user: [String: String]) -> Future<[String]> {
        return Future {
          try await(
            request(user) => { Array<String>($0.values).sorted() }
          )
        }
      }
      
      it("properly awaits and resolve values") {
        Future {
          let posts = try? await(
            login("foo", p: "bar") => values
          )

          expect(posts) == ["bar", "foo"]
        }
      }
    }
    
  }
}

//
//  Future.swift
//  Future
//
//  Created by Olivier THIERRY on 06/09/15.
//  Copyright (c) 2015 Olivier THIERRY. All rights reserved.
//

import Foundation

extension DispatchQueue {

  //replacement for dispatch_once(&token)
	private static var _onceTracker = [String]()
  
  /**
   Executes a block of code, associated with a unique token, only once.  The code is thread safe and will
   only execute the code once even in the presence of multithreaded calls.
   
   - parameter token: A unique reverse DNS style name such as com.vectorform.<name> or a GUID
   - parameter block: Block to execute once
   */
  public class func once(token: String, block:@noescape(Void)->Void) {
    objc_sync_enter(self); defer { objc_sync_exit(self) }
    
    if _onceTracker.contains(token) {
      return
    }
    _onceTracker.append(token)
    block()
  }
  
  // replacement for MACRO CURRENT_LABEL
  class var currentLabel: String {
    return String(validatingUTF8: __dispatch_queue_get_label(nil))!
		}
}

let futureQueueConcurrent = DispatchQueue(
  label: "com.future.queue:concurrent",
  attributes: DispatchQueue.Attributes.concurrent)

/**
 States a future can go trought
 
 - `.Pending` : The future is waiting to be resolve or rejected
 - `.Resolve` : The future has been resolved using `future.resolve(_:A)`
 - `.Rejected`: The future has been rejected using `future.reject(_:NSError?)`
 
 Important: A future can only be resolved/rejected ONCE. If a future tries to
 resolve/reject 2 times, an exception will be raised.
 */
public enum FutureState {
  case pending, resolved, rejected
}

public enum FutureErrorCode: Int {
  case timeout = 0
}

open class Future<A>: FutureType {
  public typealias Value = A
  
  open fileprivate(set) var group: DispatchGroup
  
  /// The resolved value `A`
  open var value: A!
  
  /// The error used when the future was rejected
  open var error: Error?
  
  /// Timeout
  open var timeoutTimer: Timer?
  
  /// The current state of the future
  open var state: FutureState = .pending
  
  /// Optionnal. An identifier assigned to the future. This is useful to debug
  /// multiple, concurrent futures.
  open var identifier: String?
  
  /// Fonction chaining to keep track of functions to invoke when
  /// rejecting or resolving a future in FIFO mode.
  ///
  /// Important: When resolved, the fuctture will discard `fail` chain fonctions.
  /// When rejected, the future will discard `then` chain fonctions
  fileprivate var chain: (then: [(A) -> Void], fail: [(Error?) -> Void], finally: [(Void) -> Void]) = ([], [], [])

  /// True if the current running queue is the future queue, false otherwise
  internal var isFutureQueue: Bool {
    
    return DispatchQueue.currentLabel  == futureQueueConcurrent.label
  }

  public init() {
    self.group = DispatchGroup()
    self.group.enter()
  }

  /**
   Designated static initializer for sync futures.
   The method executes the block asynchronously in background queue
   (Future.futureQueueConcurrent)
   
   Parameter: f: The block to execute with the future as parameter.
   
   Returns: The created future object
   */
  public convenience init(_ f: @escaping (Void) throws -> A) {
    self.init()

    let run = {
      autoreleasepool {
        do {
          try self.resolve(f())
        } catch let error {
          self.reject(error)
        }
      }
    }

    // If we are already running on future's queue, they just asynchronously
    // call the function to avoid thread overflow and prevent deadlocking
    // due to future inter dependencies
    if self.isFutureQueue {
      run()
    } else {
      futureQueueConcurrent.async(execute: run)
    }
  }


  deinit {
    self.timeoutTimer?.invalidate()
  }
  
  /**
   Create a resolve future directly. Useful when you need to
   return a future of a value that has already been fetched or
   computed
   
   Parameter value: The value to resolve
   
   Returns: The future
   */
  open static func resolve<A>(_ value: A) -> Future<A> {
    let future = Future<A>()
    future.resolve(value)
    return future
  }
  
  /**
   Create a reject future directly. Useful when you need to
   return a future of a value that you instatanly know that
   can not be resolved and should be rejected
   
   Parameter error: The error to reject
   
   Returns: The future
   */
  open static func reject<A>(_ error: Error?) -> Future<A> {
    let future = Future<A>()
    future.reject(error)
    return future
  }
  
  @objc
  fileprivate func performTimeout() {
    self.reject(
      NSError(
        domain: "com.future",
        code: FutureErrorCode.timeout.rawValue,
        userInfo: nil))
  }
}

public extension Future {
  
  /**
   Add a fonction to fonction `then` chain.
   
   Parameter f: The fonction to execute
   
   Returns: self
   
   Important: `f` is garanteed to be executed on main queue
   */
  public func then(_ f: @escaping (A) -> Void) -> Future<A> {
    return then(queue: DispatchQueue.main, f: f)
  }

  /**
   Add a fonction to fonction `then` chain.

   Parameter queue: The queue on which the block must execute. default is dispatch_get_main_queue()
   Parameter f: The fonction to execute

   Returns: self
   */
  public func then(queue queue: DispatchQueue, f: @escaping (A) -> Void) -> Future<A> {
    appendThen(queue) { value in f(value) }
    return self
  }

  /**
   Add a fonction to fonction `then` chain. This fonction returns
   a new type `B`. A new future of type B is created and
   returned as the result of this fonction
   
   Parameter f: The fonction to execute
   
   Returns: the future
   
   Important: `f` is garanteed to be executed on main queue
   */
  public func then<B>(_ f: @escaping (A) -> B) -> Future<B> {
    return self.then(queue: DispatchQueue.main, f: f)
  }

  /**
   Add a fonction to fonction `then` chain. This fonction returns
   a new type `B`. A new future of type B is created and
   returned as the result of this fonction

   Parameter queue: The queue on which the block must execute. default is dispatch_get_main_queue()
   Parameter f: The fonction to execute

   Returns: the future
   */
  public func then<B>(queue queue: DispatchQueue, f: @escaping (A) -> B) -> Future<B> {
    let future = Future<B>()

    appendThen(queue) { value in
      future.resolve(f(value))
    }

    appendFail(queue) { error in
      future.reject(error)
    }

    return future
  }

  /**
   Add a fonction to fonction `then` chain. This fonction returns
   a new Future of type `B`.
   
   Parameter f: The fonction to execute
   
   Returns: the future
   
   Important: `f` is garanteed to be executed on main queue
   */
  public func then<B>(_ f: @escaping (A) -> Future<B>) -> Future<B> {
    return self.then(queue: DispatchQueue.main, f: f)
  }

  /**
   Add a fonction to fonction `then` chain. This fonction returns
   a new Future of type `B`.

   Parameter queue: The queue on which the block must execute. default is dispatch_get_main_queue()
   Parameter f: The fonction to execute

   Returns: the future
   */
  public func then<B>(queue queue: DispatchQueue, f: @escaping (A) -> Future<B>) -> Future<B> {
    let future = Future<B>()

    appendThen(queue) { value in
      f(value)
        .then(queue:queue) { future.resolve($0) }
        .fail(queue:queue) { future.reject($0) }
    }

    appendFail(queue) { error in
      future.reject(error)
    }

    return future
  }

  /**
   Add a fonction to fonction `fail` chain.

   Parameter f: The fonction to execute

   Returns: self

   Important: `f` is garanteed to be executed on main queue
   */
  public func fail(_ f: @escaping (NSError?) -> Void) -> Future<A> {
    return self.fail(queue: DispatchQueue.main, f: f)
  }

  /**
   Add a fonction to fonction `fail` chain.

   Parameter queue: The queue on which the block must execute. default is dispatch_get_main_queue()
   Parameter f: The fonction to execute

   Returns: self
   */
  public func fail(queue queue: DispatchQueue, f: @escaping (NSError?) -> Void) -> Future<A> {
    appendFail(queue) {
      f($0 as? NSError)
    }
    return self
  }

  /**
   Add a fonction to fonction `fail` chain, with a custom ErrorType

   Parameter f: The fonction to execute

   Returns: self

   Important: `f` is garanteed to be executed on main queue
   */
  public func fail<E: Error>(_ f: @escaping (E) -> Void) -> Future<A> {
    return self.fail(DispatchQueue.main, f: f)
  }

  /**
   Add a fonction to fonction `fail` chain, with a custom ErrorType

   Parameter queue: The queue on which the block must execute. default is dispatch_get_main_queue()
   Parameter f: The fonction to execute

   Returns: self
   */
  public func fail<E: Error>(_ queue: DispatchQueue, f: @escaping (E) -> Void) -> Future<A> {
    appendFail(queue) {
      if let error = $0 as? E {
        f(error)
      }
    }
    return self
  }

  public func timeout(_ seconds: TimeInterval) -> Future<A> {
    // Invalidate current timer if any
    self.timeoutTimer?.invalidate()
    self.timeoutTimer = nil
    
    // Consider 0 as no timeout
    guard seconds > 0 else { return self }
    
    self.timeoutTimer = Timer.scheduledTimer(
      timeInterval: seconds,
      target: self,
      selector: #selector(performTimeout),
      userInfo: nil,
      repeats: false)

    return self
  }

  /**
   Add a fonction to fonction `finally` chain.

   Parameter f: The fonction to execute

   Returns: self

   Important: `f` is garanteed to be executed on main queue
   */
  public func finally(_ f: @escaping (Void) -> Void) -> Future<A> {
    return self.finally(DispatchQueue.main, f: f)
  }

  /**
   Add a fonction to fonction `finally` chain.

   Parameter queue: The queue on which the block must execute. default is dispatch_get_main_queue()
   Parameter f: The fonction to execute

   Returns: self
   */
  public func finally(_ queue: DispatchQueue, f: @escaping (Void) -> Void) -> Future<A> {
    appendFinally(queue, f: f)
    return self
  }
  
  /**
   Append fonction in fonction `then` chain
   
   Important: This fonction locks the future instance
   to do its work. This prevent inconsistent states
   that can pop when multiple threads access the
   same future instance
   */
  fileprivate func appendThen(_ queue: DispatchQueue, f: @escaping (A) -> Void) {
    // Avoid concurrent access, synchronise threads
    objc_sync_enter(self)
    
    self.chain.then.append { value in
      queue.async {
        f(value)
      }
    }
    
    // If future is already resolved, invoke functions chain now
    if state == .resolved {
      resolveAll()
    }
    
    // Release lock
    objc_sync_exit(self)
  }
  
  /**
   Append fonction in fonction `fail` chain
   
   Important: This fonction locks the future instance
   to do its work. This prevent inconsistent states
   that can pop when multiple threads access the
   same future instance
   */
  fileprivate func appendFail(_ queue: DispatchQueue, f: @escaping (Error?) -> Void) {
    // Avoid concurrent access, synchronise threads
    objc_sync_enter(self)
    
    self.chain.fail.append { error in
      queue.async {
        f(error)
      }
    }
    
    // If future is already rejected, invoke functions chain now
    if state == .rejected {
      rejectAll()
    }
    
    // Release lock
    objc_sync_exit(self)
  }
  
  
  /**
   Append fonction in fonction `then` chain
   
   Important: This fonction locks the future instance
   to do its work. This prevent inconsistent states
   that can pop when multiple threads access the
   same future instance
   */
  fileprivate func appendFinally(_ queue: DispatchQueue, f: @escaping (Void) -> Void) {
    // Avoid concurrent access, synchronise threads
    objc_sync_enter(self)
    
    self.chain.finally.append {
      queue.async(execute: f)
    }
    
    // If future is already resolved, invoke functions chain now
    if state != .pending {
      finalizeAll()
    }
    
    // Release lock
    objc_sync_exit(self)
  }
  
}

public extension Future {
  
  /**
   Resolve a future
   
   Parameter value: The value to resolve with
   
   Important: This fonction locks the future instance
   to do its work. This prevent inconsistent states
   that can pop when multiple threads access the
   same future instance
   */
  public func resolve(_ value: A) {
    guard state == .pending else {
      return
    }
    
    // Avoid concurrent access, synchronise threads
    objc_sync_enter(self)
    
    // Invalidate timeout
    self.timeoutTimer?.invalidate()
    self.timeoutTimer = nil
    
    // Store given value
    self.value = value

    // Assign state as .Resolved
    self.state = .resolved

    // Invoke all success fonctions in fonctions chain
    resolveAll()
    finalizeAll()

    // Leave group not future is resolved
    self.group.leave()
    
    // Release lock
    objc_sync_exit(self)
  }
  
  
  /**
   Reject a future
   
   Parameter error: The error to reject with (optional)
   
   Important: This fonction locks the future instance
   to do its work. This prevent inconsistent states
   that can pop when multiple threads access the
   same future instance
   */
  public func reject(_ error: Error? = nil) {
    guard state == .pending else {
      return
    }
    
    // Avoid concurrent access, synchronise threads
    objc_sync_enter(self)
    
    // Store given error
    self.error = error

    // Assign state as .Rejected
    self.state = .rejected

    // Invoke failure functions in fonctions chain
    rejectAll()
    finalizeAll()

    self.group.leave()
    
    // Release lock
    objc_sync_exit(self)
  }
  
  /**
   Invoke all function in `then` function chain
   and empty chain after complete
   */
  fileprivate func resolveAll() {
    for f in self.chain.then {
      f(self.value)
    }
    
    self.chain.then = []
  }
  
  /**
   Invoke all function in `fail` function chain
   and empty chain after complete
   */
  fileprivate func rejectAll() {
    for f in self.chain.fail {
      f(self.error)
    }
    
    self.chain.fail = []
  }
  
  fileprivate func finalizeAll() {
    for f in self.chain.finally {
      f()
    }
    
    self.chain.finally = []
  }
  
}

extension Future {

  /**
   Wrap the result of a future into a new Future<Void>
   
   This is useful when a future actually resolves a value
   with a concrete type but the caller of the future do not
   care about this value and expect Void
   */
  public func wrap() -> Future<Void> {
    return self.then { _ -> Void in }
  }
  
  /**
   Wrap the result of a future into a new Future<C>
   
   This is useful when a future actually resolves a value
   with a concrete type but the caller of the future expect
   another type your value type can be downcasted to.
   */
  public func wrap<B>(_ type: B.Type) -> Future<B> {
    /// TODO: Check error when using as! instead of `unsafeBitCast`
    return self.then { x -> B in
      unsafeBitCast(x, to: B.self)
    }
  }

  /**
   Merge future instance with another Future. The returned future will
   resolve a tuple contained the resolved values of both future.
   If one future fails, the returned future will also fail with the same
   error.
   
   Parameter future: the future object
   Returns: A new future
   */
  public func merge<B>(_ future: Future<B>) -> Future<(A, B)> {
    return self.then { x -> Future<(A, B)> in
      future.then { y in
        (x, y)
      }
    }
  }

  /**
   Block calling thread until future completes
   
   If the future fails, an exception will be thrown with the error
   
   Parameter future: the future object
   
   Returns: the value the future resolved to
   */
  public func await() throws -> A {
    return try _await <- self
  }
}

extension Collection where Iterator.Element: FutureType {

  /**
   Wait until all futures complete and resolve by mapping the values
   of all the futures
   
   If one future fails, the future will be rejected with the same error
   
   Parameter futures: an array of futures to resolve
   
   Returns: future object
   */
  public func all() -> Future<[Iterator.Element.Value]> {
    guard
      let futures = self as? [Future<Iterator.Element.Value>]
      , self.count > 0
      else { return Future<[Iterator.Element.Value]>.resolve([]) }

    var token: String = "0"
    return Promise<[Iterator.Element.Value]> { promise in
      futures.forEach {
        $0.then { _ in
          let pendings = futures.filter { $0.state == .pending }
          if pendings.isEmpty {
            DispatchQueue.once(token: token) {
              let values = futures.flatMap { $0.value }
              promise.resolve(values)
            }
          }
        }.fail { error in
           DispatchQueue.once(token: token){
            promise.reject(error)
          }
        }
      }
    }
  }
  /**
   Wait until one future completes and resolve to its value
   
   If all futures fails, the future will be rejected with a nil error
   
   Parameter futures: an array of futures to resolve
   
   Returns: future object
   */
  public func any() -> Future<Iterator.Element.Value> {
    guard !isEmpty else {
      fatalError("Future.any called with empty futures array.")
    }
    
    return Promise { promise in
      self.forEach {
        if let future = $0 as? Future<Iterator.Element.Value> {
          future.then { x in
            if promise.state != .resolved {
              promise.resolve(x)
            }
          }
        }
      }

      // Await all futures to complete
      let _ = try? await <- self

      // No futures have resolved
      if promise.state != .resolved {
        promise.reject(nil)
      }
    }
  }

  /**
   Works as the normal reduce function for standar library but with futures
   
   If all futures fails, the future will be rejected with the same error
   
   Parameter futures: an array of futures to resolve
   Parameter value: the initial value
   Parameter combine: the reducer closure
   
   Returns: future object
   */
  public func reduce<B>(_ value: B, combine: @escaping (B, Iterator.Element.Value) throws -> B) -> Future<B> {
    return Future {
      let values = try await <- self.all()
      return try values.reduce(value, combine)
    }
  }

}

/**
 Block calling thread until future completes
 
 If the future fails, an exception will be thrown with the error
 
 Parameter future: the future object
 
 Returns: the value the future resolved to
 */
public func await<A>(_ future: A) throws -> A.Value where A: FutureType {
  future.group.wait(timeout: DispatchTime.distantFuture)
  
  switch future.state {
  case .resolved:
    return future.value
  case .rejected:
    throw future.error ?? NSError(
      domain: NSExceptionName.genericException.rawValue,
      code: 42,
      userInfo: nil)
  default:
    fatalError()
  }
}


private func _await<A>(_ future: A) throws -> A.Value where A: FutureType {
  return try await(future)
}

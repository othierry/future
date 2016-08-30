//
//  Future.swift
//  Future
//
//  Created by Olivier THIERRY on 06/09/15.
//  Copyright (c) 2015 Olivier THIERRY. All rights reserved.
//

import Foundation

let futureQueueConcurrent = dispatch_queue_create(
  "com.future.queue:concurrent",
  DISPATCH_QUEUE_CONCURRENT)

/**
 States a future can go trought
 
 - `.Pending` : The future is waiting to be resolve or rejected
 - `.Resolve` : The future has been resolved using `future.resolve(_:A)`
 - `.Rejected`: The future has been rejected using `future.reject(_:NSError?)`
 
 Important: A future can only be resolved/rejected ONCE. If a future tries to
 resolve/reject 2 times, an exception will be raised.
 */
public enum FutureState {
  case Pending, Resolved, Rejected
}

public enum FutureErrorCode: Int {
  case Timeout = 0
}

public class Future<A>: FutureType {
  public typealias Value = A
  
  public private(set) var group: dispatch_group_t
  
  /// The resolved value `A`
  public var value: A!
  
  /// The error used when the future was rejected
  public var error: ErrorType?
  
  /// Timeout
  public var timeoutTimer: NSTimer?
  
  /// The current state of the future
  public var state: FutureState = .Pending
  
  /// Optionnal. An identifier assigned to the future. This is useful to debug
  /// multiple, concurrent futures.
  public var identifier: String?
  
  /// Fonction chaining to keep track of functions to invoke when
  /// rejecting or resolving a future in FIFO mode.
  ///
  /// Important: When resolved, the fuctture will discard `fail` chain fonctions.
  /// When rejected, the future will discard `then` chain fonctions
  private var chain: (then: [A -> Void], fail: [ErrorType? -> Void], finally: [Void -> Void]) = ([], [], [])

  /// True if the current running queue is the future queue, false otherwise
  internal var isFutureQueue: Bool {
    return dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL) == dispatch_queue_get_label(futureQueueConcurrent)
  }

  public init() {
    self.group = dispatch_group_create()
    dispatch_group_enter(self.group)
  }

  /**
   Designated static initializer for sync futures.
   The method executes the block asynchronously in background queue
   (Future.futureQueueConcurrent)
   
   Parameter: f: The block to execute with the future as parameter.
   
   Returns: The created future object
   */
  public convenience init(_ f: Void throws -> A) {
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
      dispatch_async(futureQueueConcurrent, run)
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
  public static func resolve<A>(value: A) -> Future<A> {
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
  public static func reject<A>(error: ErrorType?) -> Future<A> {
    let future = Future<A>()
    future.reject(error)
    return future
  }
  
  @objc
  private func performTimeout() {
    self.reject(
      NSError(
        domain: "com.future",
        code: FutureErrorCode.Timeout.rawValue,
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
  public func then(f: A -> Void) -> Future<A> {
    return then(dispatch_get_main_queue(), f: f)
  }

  /**
   Add a fonction to fonction `then` chain.

   Parameter queue: The queue on which the block must execute. default is dispatch_get_main_queue()
   Parameter f: The fonction to execute

   Returns: self
   */
  public func then(queue: dispatch_queue_t, f: A -> Void) -> Future<A> {
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
  public func then<B>(f: A -> B) -> Future<B> {
    return self.then(dispatch_get_main_queue(), f: f)
  }

  /**
   Add a fonction to fonction `then` chain. This fonction returns
   a new type `B`. A new future of type B is created and
   returned as the result of this fonction

   Parameter queue: The queue on which the block must execute. default is dispatch_get_main_queue()
   Parameter f: The fonction to execute

   Returns: the future
   */
  public func then<B>(queue: dispatch_queue_t, f: A -> B) -> Future<B> {
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
  public func then<B>(f: A -> Future<B>) -> Future<B> {
    return self.then(dispatch_get_main_queue(), f: f)
  }

  /**
   Add a fonction to fonction `then` chain. This fonction returns
   a new Future of type `B`.

   Parameter queue: The queue on which the block must execute. default is dispatch_get_main_queue()
   Parameter f: The fonction to execute

   Returns: the future
   */
  public func then<B>(queue: dispatch_queue_t, f: A -> Future<B>) -> Future<B> {
    let future = Future<B>()

    appendThen(queue) { value in
      f(value)
        .then(queue) { future.resolve($0) }
        .fail(queue) { future.reject($0) }
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
  public func fail(f: NSError? -> Void) -> Future<A> {
    return self.fail(dispatch_get_main_queue(), f: f)
  }

  /**
   Add a fonction to fonction `fail` chain.

   Parameter queue: The queue on which the block must execute. default is dispatch_get_main_queue()
   Parameter f: The fonction to execute

   Returns: self
   */
  public func fail(queue: dispatch_queue_t, f: NSError? -> Void) -> Future<A> {
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
  public func fail<E: ErrorType>(f: E -> Void) -> Future<A> {
    return self.fail(dispatch_get_main_queue(), f: f)
  }

  /**
   Add a fonction to fonction `fail` chain, with a custom ErrorType

   Parameter queue: The queue on which the block must execute. default is dispatch_get_main_queue()
   Parameter f: The fonction to execute

   Returns: self
   */
  public func fail<E: ErrorType>(queue: dispatch_queue_t, f: E -> Void) -> Future<A> {
    appendFail(queue) {
      if let error = $0 as? E {
        f(error)
      }
    }
    return self
  }

  public func timeout(seconds: NSTimeInterval) -> Future<A> {
    // Invalidate current timer if any
    self.timeoutTimer?.invalidate()
    self.timeoutTimer = nil
    
    // Consider 0 as no timeout
    guard seconds > 0 else { return self }
    
    self.timeoutTimer = NSTimer.scheduledTimerWithTimeInterval(
      seconds,
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
  public func finally(f: Void -> Void) -> Future<A> {
    return self.finally(dispatch_get_main_queue(), f: f)
  }

  /**
   Add a fonction to fonction `finally` chain.

   Parameter queue: The queue on which the block must execute. default is dispatch_get_main_queue()
   Parameter f: The fonction to execute

   Returns: self
   */
  public func finally(queue: dispatch_queue_t, f: Void -> Void) -> Future<A> {
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
  private func appendThen(queue: dispatch_queue_t, f: A -> Void) {
    // Avoid concurrent access, synchronise threads
    objc_sync_enter(self)
    
    self.chain.then.append { value in
      dispatch_async(queue) {
        f(value)
      }
    }
    
    // If future is already resolved, invoke functions chain now
    if state == .Resolved {
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
  private func appendFail(queue: dispatch_queue_t, f: ErrorType? -> Void) {
    // Avoid concurrent access, synchronise threads
    objc_sync_enter(self)
    
    self.chain.fail.append { error in
      dispatch_async(queue) {
        f(error)
      }
    }
    
    // If future is already rejected, invoke functions chain now
    if state == .Rejected {
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
  private func appendFinally(queue: dispatch_queue_t, f: Void -> Void) {
    // Avoid concurrent access, synchronise threads
    objc_sync_enter(self)
    
    self.chain.finally.append {
      dispatch_async(queue, f)
    }
    
    // If future is already resolved, invoke functions chain now
    if state != .Pending {
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
  public func resolve(value: A) {
    guard state == .Pending else {
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
    self.state = .Resolved

    // Invoke all success fonctions in fonctions chain
    resolveAll()
    finalizeAll()

    // Leave group not future is resolved
    dispatch_group_leave(self.group)
    
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
  public func reject(error: ErrorType? = nil) {
    guard state == .Pending else {
      return
    }
    
    // Avoid concurrent access, synchronise threads
    objc_sync_enter(self)
    
    // Store given error
    self.error = error

    // Assign state as .Rejected
    self.state = .Rejected

    // Invoke failure functions in fonctions chain
    rejectAll()
    finalizeAll()

    dispatch_group_leave(self.group)
    
    // Release lock
    objc_sync_exit(self)
  }
  
  /**
   Invoke all function in `then` function chain
   and empty chain after complete
   */
  private func resolveAll() {
    for f in self.chain.then {
      f(self.value)
    }
    
    self.chain.then = []
  }
  
  /**
   Invoke all function in `fail` function chain
   and empty chain after complete
   */
  private func rejectAll() {
    for f in self.chain.fail {
      f(self.error)
    }
    
    self.chain.fail = []
  }
  
  private func finalizeAll() {
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
  public func wrap<B>(type: B.Type) -> Future<B> {
    /// TODO: Check error when using as! instead of `unsafeBitCast`
    return self.then { x -> B in
      unsafeBitCast(x, B.self)
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
  public func merge<B>(future: Future<B>) -> Future<(A, B)> {
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

extension CollectionType where Generator.Element: FutureType {

  /**
   Wait until all futures complete and resolve by mapping the values
   of all the futures
   
   If one future fails, the future will be rejected with the same error
   
   Parameter futures: an array of futures to resolve
   
   Returns: future object
   */
  public func all() -> Future<[Generator.Element.Value]> {
    guard
      let futures = self as? [Future<Generator.Element.Value>]
      where self.count > 0
      else { return Future<[Generator.Element.Value]>.resolve([]) }

    var token: dispatch_once_t = 0
    return Promise<[Generator.Element.Value]> { promise in
      futures.forEach {
        $0.then { _ in
          let pendings = futures.filter { $0.state == .Pending }
          if pendings.isEmpty {
            dispatch_once(&token) {
              let values = futures.flatMap { $0.value }
              promise.resolve(values)
            }
          }
        }.fail { error in
          dispatch_once(&token) {
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
  public func any() -> Future<Generator.Element.Value> {
    guard !isEmpty else {
      fatalError("Future.any called with empty futures array.")
    }
    
    return Promise { promise in
      self.forEach {
        if let future = $0 as? Future<Generator.Element.Value> {
          future.then { x in
            if promise.state != .Resolved {
              promise.resolve(x)
            }
          }
        }
      }

      // Await all futures to complete
      let _ = try? await <- self

      // No futures have resolved
      if promise.state != .Resolved {
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
  public func reduce<B>(value: B, combine: (B, Generator.Element.Value) throws -> B) -> Future<B> {
    return Future {
      let values = try await <- self.all()
      return try values.reduce(value, combine: combine)
    }
  }

}

/**
 Block calling thread until future completes
 
 If the future fails, an exception will be thrown with the error
 
 Parameter future: the future object
 
 Returns: the value the future resolved to
 */
public func await<A where A: FutureType>(future: A) throws -> A.Value {
  dispatch_group_wait(
    future.group,
    DISPATCH_TIME_FOREVER)
  
  switch future.state {
  case .Resolved:
    return future.value
  case .Rejected:
    throw future.error ?? NSError(
      domain: NSGenericException,
      code: 42,
      userInfo: nil)
  default:
    fatalError()
  }
}


private func _await<A where A: FutureType>(future: A) throws -> A.Value {
  return try await(future)
}

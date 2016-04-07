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

public class Future<A> {
  
  private var group: dispatch_group_t
  
  /// The resolved value `A`
  public var value: A!
  
  /// The error used when the future was rejected
  public var error: ErrorType?
  
  /// Timeout handking
  public var timeoutTimer: NSTimer?
  public var timeoutInterval: NSTimeInterval = 0 {
    didSet {
      // Invalidate current timer if any
      self.timeoutTimer?.invalidate()
      
      // Consider 0 as no timeout
      guard self.timeoutInterval > 0 else { return }
      
      self.timeoutTimer = NSTimer.scheduledTimerWithTimeInterval(
        self.timeoutInterval,
        target: self,
        selector: #selector(performTimeout),
        userInfo: nil,
        repeats: false)
    }
  }
  
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

    dispatch_async(futureQueueConcurrent) {
      do {
        try self.resolve(f())
      } catch let error {
        self.reject(error)
      }
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
    appendThen { value in f(value) }
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
    let future = Future<B>()
    
    appendThen { value in
      future.resolve(f(value))
    }
    
    appendFail { error in
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
    let future = Future<B>()
    
    appendThen { value in
      f(value)
        .then(future.resolve)
        .fail(future.reject)
      return
    }
    
    appendFail { error in
      future.reject(error)
    }
    
    return future
  }
  
  public func fail(f: NSError? -> Void) -> Future<A> {
    appendFail { f($0 as? NSError) }
    return self
  }
  
  /**
   Add a fonction to fonction `fail` chain.
   
   Parameter f: The fonction to execute
   
   Returns: self
   
   Important: `f` is garanteed to be executed on main queue
   */
  public func fail<E: ErrorType>(f: E! -> Void) -> Future<A> {
    appendFail { f($0 as! E) }
    return self
  }
  
  public func timeout(seconds: NSTimeInterval) -> Future<A> {
    self.timeoutInterval = seconds
    return self
  }
  
  public func finally(f: Void -> Void) -> Future<A> {
    appendFinally(f)
    return self
  }
  
  /**
   Append fonction in fonction `finally` chain
   
   Important: This fonction locks the future instance
   to do its work. This prevent inconsistent states
   that can pop when multiple threads access the
   same future instance
   */
  private func appendThen(f: A -> Void) {
    // Avoid concurrent access, synchronise threads
    objc_sync_enter(self)
    
    self.chain.then.append(f)
    
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
  private func appendFail(f: ErrorType? -> Void) {
    // Avoid concurrent access, synchronise threads
    objc_sync_enter(self)
    
    self.chain.fail.append(f)
    
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
  private func appendFinally(f: Void -> Void) {
    // Avoid concurrent access, synchronise threads
    objc_sync_enter(self)
    
    self.chain.finally.append(f)
    
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
    
    // Invoke all success fonctions in fonctions chain
    resolveAll()
    finalizeAll()
    
    // Assign state as .Resolved
    self.state = .Resolved
    
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
    
    // Invoke failure functions in fonctions chain
    rejectAll()
    finalizeAll()
    
    // Assign state as .Rejected
    self.state = .Rejected
    
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
      dispatch_async(dispatch_get_main_queue()) {
        f(self.value)
      }
    }
    
    self.chain.then = []
  }
  
  /**
   Invoke all function in `fail` function chain
   and empty chain after complete
   */
  private func rejectAll() {
    for f in self.chain.fail {
      dispatch_async(dispatch_get_main_queue()) {
        f(self.error)
      }
    }
    
    self.chain.fail = []
  }
  
  private func finalizeAll() {
    for f in self.chain.finally {
      dispatch_async(dispatch_get_main_queue(), f)
    }
    
    self.chain.finally = []
  }
  
}

public func merge<A, B>(f: Future<A>, _ g: Future<B>) -> Future<(A, B)> {
  return Future {
    let x = try await <- f
    let y = try await <- g
    return (x, y)
  }
}

/**
 Wrap the result of a future into a new Future<Void>
 
 This is useful when a future actually resolves a value
 with a concrete type but the caller of the future do not
 care about this value and expect Void
 */
public func wrap<A>(f: Future<A>) -> Future<Void> {
  return Future {
    try await <- f
  }
}

/**
 Wrap the result of a future into a new Future<C>
 
 This is useful when a future actually resolves a value
 with a concrete type but the caller of the future expect
 another type your value type can be downcasted to.
 */
public func wrap<A, B>(f: Future<A>, to: B.Type) -> Future<B> {
  /// TODO: Check error when using as! instead of `unsafeBitCast`
  /// Why do we need `unsafeBitCast` ?
  return Future {
    let object = try await <- f
    return unsafeBitCast(object, B.self)
  }
}

/**
 Wait until all futures complete and resolve by mapping the values
 of all the futures
 
 If one future fails, the future will be rejected with the same error
 
 Parameter futures: an array of futures to resolve
 
 Returns: future object
 */
public func all<A>(futures: [Future<A>]) -> Future<[A]> {
  return Future {
    try await <- futures
  }
}

/**
 Wait until one future completes and resolve to its value
 
 If all futures fails, the future will be rejected with the same error
 
 Parameter futures: an array of futures to resolve
 
 Returns: future object
 */
public func any<A>(futures: [Future<A>]) -> Future<A> {
  guard !futures.isEmpty else {
    fatalError("Future.any called with empty futures array.")
  }
  
  return Promise<A> { promise in
    do {
      try await <- futures.map { f in
        Future {
          if let value = try? await <- f {
            promise.resolve(value)
          }
        }
      }
    } catch let error {
      promise.reject(error)
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
public func reduce<A, B>(futures: [Future<A>], value: B, combine: (B, A) throws -> B) -> Future<B> {
  return Future {
    let values = try await <- all(futures)
    return try values.reduce(value, combine: combine)
  }
}

/**
 Block calling thread until future completes
 
 If the future fails, an exception will be thrown with the error
 
 Parameter future: the future object
 
 Returns: the value the future resolved to
 */
public func await<A>(future: Future<A>) throws -> A {
  dispatch_group_wait(
    future.group,
    future.timeoutInterval > 0
      ? UInt64(future.timeoutInterval)
      : DISPATCH_TIME_FOREVER)
  
  switch future.state {
  case .Resolved:
    return future.value
  case .Rejected:
    throw future.error ?? NSError(domain: NSGenericException, code: 42, userInfo: nil)
  default:
    throw NSError(domain: NSInternalInconsistencyException, code: -1, userInfo: nil)
  }
}

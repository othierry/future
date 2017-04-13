//
//  Future.swift
//  Future
//
//  Created by Olivier THIERRY on 06/09/15.
//  Copyright (c) 2015 Olivier THIERRY. All rights reserved.
//

import Foundation

let queue = DispatchQueue(
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
public enum FutureState<A> {
  case pending
  case resolved(A!)
  case rejected(Error?)

  public var isPending: Bool {
    if case .pending = self {
      return true
    } else {
      return false
    }
  }

  public var isResolved: Bool {
    if case .resolved(_) = self {
      return true
    } else {
      return false
    }
  }

  public var isRejected: Bool {
    if case .rejected = self {
      return true
    } else {
      return false
    }
  }

}

fileprivate enum FutureCallback<A> {
  case then((A) -> Void)
  case fail((Error?) -> Void)
  case finally((Void) -> Void)
}

public class Future<A>: FutureType {
  /// Optionnal. An identifier assigned to the future. This is useful to debug
  /// multiple, concurrent futures.
  open var identifier: String?

  /// The current state of the future
  open fileprivate(set) var state: FutureState<A> = .pending {
    didSet {
      self.stateDidChange()
    }
  }

  /// Fonction chaining to keep track of closures to invoke when
  /// rejecting or resolving a future in FIFO order.
  ///
  /// Important: When resolved, the fuctture will discard `fail` chain fonctions.
  /// When rejected, the future will discard `then` chain fonctions, etc
  fileprivate var chain: (then: [(A) -> Void], fail: [(Error?) -> Void], finally: [(Void) -> Void]) = ([], [], [])

  // Timer dispatch source used for future with a timeout
  fileprivate var timeoutDispatchSource: DispatchSourceTimer? {
    willSet {
      // Invalidate timeout timer if set
      self.timeoutDispatchSource?.cancel()
    }
  }

  public init() {}

  /**
   Designated static initializer for sync futures.
   The method executes the block asynchronously in background queue

   Parameter: f: The block to execute with the future as parameter.
   
   Returns: The created future object
   */
  @discardableResult
  public convenience init(_ f: @escaping (Void) throws -> A) {
    self.init()

    queue.async {
      autoreleasepool {
        do {
          try self.resolve(f())
        } catch let error {
          self.reject(error)
        }
      }
    }
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

  /**
   Resolve a future

   Parameter value: The value to resolve with

   Important: This fonction locks the future instance
   to do its work. This prevent inconsistent states
   that can pop when multiple threads access the
   same future instance
   */
  public func resolve(_ value: A) {
    guard self.state.isPending else { return }
    self.state = .resolved(value)
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
    guard self.state.isPending else { return }
    self.state = .rejected(error)
  }

}

public extension Future {
  
  /**
   Add a fonction to fonction `then` chain.
   
   Parameter f: The fonction to execute
   
   Returns: self
   
   Important: `f` is garanteed to be executed on main queue
   */
  @discardableResult
  public func then(_ f: @escaping (A) -> Void) -> Self {
    return self.then(on: DispatchQueue.main, f: f)
  }

  /**
   Add a fonction to fonction `then` chain.

   Parameter queue: The queue on which the block must execute. default is dispatch_get_main_queue()
   Parameter f: The fonction to execute

   Returns: self
   */
  @discardableResult
  public func then(on queue: DispatchQueue, f: @escaping (A) -> Void) -> Self {
    self.register(on: queue, .then(f))
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
  @discardableResult
  public func then<B>(_ f: @escaping (A) -> B) -> Future<B> {
    return self.then(on: DispatchQueue.main, f: f)
  }

  /**
   Add a fonction to fonction `then` chain. This fonction returns
   a new type `B`. A new future of type B is created and
   returned as the result of this fonction

   Parameter queue: The queue on which the block must execute. default is dispatch_get_main_queue()
   Parameter f: The fonction to execute

   Returns: the future
   */
  @discardableResult
  public func then<B>(on queue: DispatchQueue, f: @escaping (A) -> B) -> Future<B> {
    let future = Future<B>()

    self.register(on: queue, .then {
      future.resolve(f($0))
    })

    self.register(on: queue, .fail(future.reject))

    return future
  }

  /**
   Add a fonction to fonction `then` chain. This fonction returns
   a new Future of type `B`.
   
   Parameter f: The fonction to execute
   
   Returns: the future
   
   Important: `f` is garanteed to be executed on main queue
   */
  @discardableResult
  public func then<B>(_ f: @escaping (A) -> Future<B>) -> Future<B> {
    return self.then(on: DispatchQueue.main, f: f)
  }

  /**
   Add a fonction to fonction `then` chain. This fonction returns
   a new Future of type `B`.

   Parameter queue: The queue on which the block must execute. default is dispatch_get_main_queue()
   Parameter f: The fonction to execute

   Returns: the future
   */
  @discardableResult
  public func then<B>(on queue: DispatchQueue, f: @escaping (A) -> Future<B>) -> Future<B> {
    let future = Future<B>()

    self.register(on: queue, .then { value in
      f(value)
        .then(on: queue, f: future.resolve)
        .fail(on: queue, f: future.reject)
    })

    return future
  }

  /**
   Add a fonction to fonction `fail` chain.

   Parameter f: The fonction to execute

   Returns: self

   Important: `f` is garanteed to be executed on main queue
   */
  @discardableResult
  public func fail(_ f: @escaping (NSError?) -> Void) -> Self {
    return self.fail(on: DispatchQueue.main, f: f)
  }

  /**
   Add a fonction to fonction `fail` chain.

   Parameter queue: The queue on which the block must execute. default is dispatch_get_main_queue()
   Parameter f: The fonction to execute

   Returns: self
   */
  @discardableResult
  public func fail(on queue: DispatchQueue, f: @escaping (NSError?) -> Void) -> Self {
    self.register(on: queue, .fail {
      f($0 as? NSError)
    })

    return self
  }

  /**
   Add a fonction to fonction `fail` chain, with a custom ErrorType

   Parameter f: The fonction to execute

   Returns: self

   Important: `f` is garanteed to be executed on main queue
   */
  @discardableResult
  public func fail<E: Error>(_ f: @escaping (E) -> Void) -> Self {
    return self.fail(on: DispatchQueue.main, f: f)
  }

  /**
   Add a fonction to fonction `fail` chain, with a custom ErrorType

   Parameter queue: The queue on which the block must execute. default is dispatch_get_main_queue()
   Parameter f: The fonction to execute

   Returns: self
   */
  @discardableResult
  public func fail<E: Error>(on queue: DispatchQueue, f: @escaping (E) -> Void) -> Self {
    self.register(on: queue, .fail {
      if let error = $0 as? E {
        f(error)
      }
    })

    return self
  }

  /**
   Add a fonction to fonction `finally` chain.

   Parameter f: The fonction to execute

   Returns: self

   Important: `f` is garanteed to be executed on main queue
   */
  @discardableResult
  public func finally(_ f: @escaping (Void) -> Void) -> Self {
    return self.finally(on: DispatchQueue.main, f: f)
  }

  /**
   Add a fonction to fonction `finally` chain.

   Parameter queue: The queue on which the block must execute. default is dispatch_get_main_queue()
   Parameter f: The fonction to execute

   Returns: self
   */
  @discardableResult
  public func finally(on queue: DispatchQueue, f: @escaping (Void) -> Void) -> Self {
    self.register(on: queue, .finally(f))
    return self
  }

  /**
   Registers a callback function to the callback function chain.

   Parameter queue: The queue on which the block must execute. default is dispatch_get_main_queue()
   Parameter callback: The callback function wrapped in a FutureCallback<A> type
   */
  fileprivate func register(on queue: DispatchQueue, _ callback: FutureCallback<A>) {
    // Avoid concurrent access, synchronise threads
    objc_sync_enter(self)

    switch callback {
    case .then(let f):
      self.chain.then.append { value in
        queue.async {
          f(value)
        }
      }

      // If future is already resolved, invoke functions chain now
      if case .resolved(let value) = self.state {
        resolveAll(value)
      }
    case .fail(let f):
      self.chain.fail.append { error in
        queue.async {
          f(error)
        }
      }

      // If future is already rejected, invoke functions chain now
      if case .rejected(let error) = self.state {
        rejectAll(error)
      }
    case .finally(let f):
      self.chain.finally.append {
        queue.async {
          f()
        }
      }

      // If future is already resolved/rejected, invoke functions chain now
      if !self.state.isPending {
        finalizeAll()
      }
    }

    // Release lock
    objc_sync_exit(self)
  }


}

public extension Future {

  fileprivate func stateDidChange() {
    // Avoid concurrent access, synchronise threads
    objc_sync_enter(self)

    // Invalidate timeout timer if set
    self.timeoutDispatchSource = nil

    switch self.state {
    case .resolved(let value):
      self.resolveAll(value)
    case .rejected(let error):
      self.rejectAll(error)
    case .pending:
      fatalError("Future's state should never be set to .pending after creation")
    }

    self.finalizeAll()

    // Release lock
    objc_sync_exit(self)
  }
  
  /**
   Invoke all function in `then` function chain
   and empty chain after complete
   */
  fileprivate func resolveAll(_ value: A!) {
    for f in self.chain.then {
      f(value)
    }
    
    self.chain.then = []
  }
  
  /**
   Invoke all function in `fail` function chain
   and empty chain after complete
   */
  fileprivate func rejectAll(_ error: Error?) {
    for f in self.chain.fail {
      f(error)
    }
    
    self.chain.fail = []
  }
  
  /**
   Invoke all function in `finally` function chain
   and empty chain after complete
   */
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
    return self.then { x -> B in
      x as! B
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
    return self.then { a -> Future<(A, B)> in
      future.then { b in
        (a, b)
      }
    }
  }

  public func merge<B, C>(_ future1: Future<B>, _ future2: Future<C>) -> Future<(A, B, C)> {
    return self.then { a in
      future1.then { b in
        future2.then { c in
          (a, b, c)
        }
      }
    }
  }

  public func merge<B, C, D>(_ future1: Future<B>, _ future2: Future<C>, _ future3: Future<D>) -> Future<(A, B, C, D)> {
    return self.then { a in
      future1.then { b in
        future2.then { c in
          future3.then { d in
            (a, b, c, d)
          }
        }
      }
    }
  }

  /**
   Block calling thread until future completes
   
   If the future fails, an exception will be thrown with the error
   
   Parameter future: the future object
   
   Returns: the value the future resolved to
   */
  @discardableResult
  public func await() throws -> A {
    let semaphore = DispatchSemaphore(value: 0)
    self.finally(on: queue) { semaphore.signal() }
    semaphore.wait()

    switch self.state {
    case .resolved(let value):
      return value
    case .rejected(let error):
      // TODO: Default to proper, meaningful error
      throw error ?? NSError(
        domain: NSExceptionName.genericException.rawValue,
        code: 42,
        userInfo: nil
      )
    default:
      fatalError()
    }
  }

  @discardableResult
  public func timeout(after seconds: Double) -> Self {
    // Consider 0 as no timeout
    guard seconds > 0 else {
      self.timeoutDispatchSource = nil
      return self
    }

    let timeoutDispatchSource = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
    timeoutDispatchSource.scheduleOneshot(deadline: .now(), leeway: .milliseconds(Int(seconds * 1000)))
    timeoutDispatchSource.setEventHandler { [weak self] in self?.reject() }
    timeoutDispatchSource.resume()

    self.timeoutDispatchSource = timeoutDispatchSource

    return self
  }

}

@discardableResult
public func await<A>(_ future: Future<A>) throws -> A {
  return try future.await()
}

//
//  FutureType.swift
//  Pods
//
//  Created by Olivier THIERRY on 09/04/16.
//
//

import Foundation

public protocol FutureType {
  associatedtype A
  
  var state: FutureState<A> { get }

  @discardableResult
  func then(_ f: @escaping (A) -> Void) -> Future<A>
  @discardableResult
  func then<B>(_ f: @escaping (A) -> B) -> Future<B>
  @discardableResult
  func then<B>(_ f: @escaping (A) -> Future<B>) -> Future<B>

  @discardableResult
  func fail(_ f: @escaping (NSError?) -> Void) -> Future<A>
  @discardableResult
  func fail<E: Error>(_ f: @escaping (E) -> Void) -> Future<A>

  @discardableResult
  func finally(_ f: @escaping (Void) -> Void) -> Future<A>
  @discardableResult
  func finally(on queue: DispatchQueue, f: @escaping (Void) -> Void) -> Future<A>

  func resolve(_ value: A)
  func reject(_ error: Error?)
}

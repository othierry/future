//
//  Operators.swift
//  Pods
//
//  Created by Olivier THIERRY on 04/04/16.
//
//

import Foundation

precedencegroup FutureBindingPrecedence {
  associativity: left
  higherThan: MultiplicationPrecedence
}

infix operator => : FutureBindingPrecedence

public func =>
  <A, B>
  (x: Future<A>, f: @escaping (A) -> Future<B>) -> Future<B>
{
  return x.then(f)
}

public func =>
  <A, B>
  (x: Future<A>, f: @escaping (A) -> B) -> Future<B>
{
  return x.then(f)
}

public func =>
  <A, B, C>
  (f1: @escaping (A) -> Future<B>, f2: @escaping (B) -> Future<C>) -> (A) -> Future<C>
{
  return { x in f1(x).then(f2) }
}


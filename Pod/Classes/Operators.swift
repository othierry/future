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
  <A>
  (x: Future<A>, f: (Future<A>) throws -> A) rethrows -> A
{
  return try f(x)
}

public func =>
  <A>
  (xs: [Future<A>], f: (Future<A>) throws -> A) rethrows -> [A]
{
  return try xs.map(f)
}

public func =>
  <A, B>
  (x: Future<A>, f: (A) throws -> B) throws -> B
{
  return try f(x => await)
}

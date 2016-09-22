//
//  Operators.swift
//  Pods
//
//  Created by Olivier THIERRY on 04/04/16.
//
//

import Foundation

precedencegroup FuturePrecedence {
  associativity: right
  lowerThan: CastingPrecedence
}

infix operator <- { associativity: right precedence 200}

public func <-
  <A>
  (f: (A) throws -> A.Value, x: A) rethrows -> A.Value where A: FutureType
{
  return try f(x)
}

public func <-
  <A, B>
  (f: (A) throws -> A.Value, xs: B) rethrows -> [A.Value] where A: FutureType, B: Sequence, B.Iterator.Element == A
{
  return try xs.map(f)
}

public func <-
  <A, B>
  (f: (A.Value) -> B, x: A) throws -> B where A: FutureType
{
  return try f(await <- x)
}

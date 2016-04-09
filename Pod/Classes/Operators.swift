//
//  Operators.swift
//  Pods
//
//  Created by Olivier THIERRY on 04/04/16.
//
//

import Foundation

infix operator <- { associativity right }

public func <-
  <A where A: FutureType>
  (f: A throws -> A.Value, x: A) rethrows -> A.Value
{
  return try f(x)
}

public func <-
  <A, B where A: FutureType, B: SequenceType, B.Generator.Element == A>
  (f: A throws -> A.Value, xs: B) rethrows -> [A.Value]
{
  return try xs.map(f)
}

public func <-
  <A, B where A: FutureType>
  (f: A.Value -> B, x: A) throws -> B
{
  return try f(await <- x)
}
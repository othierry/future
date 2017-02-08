//
//  Operators.swift
//  Pods
//
//  Created by Olivier THIERRY on 04/04/16.
//
//

import Foundation

infix operator <- : DefaultPrecedence

public func <-
  <A>
  (f: (Future<A>) throws -> A, x: Future<A>) rethrows -> A
{
  return try f(x)
}

public func <-
  <A>
  (f: (Future<A>) throws -> A, xs: [Future<A>]) rethrows -> [A]
{
  return try xs.map(f)
}

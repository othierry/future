//
//  Operators.swift
//  Pods
//
//  Created by Olivier THIERRY on 04/04/16.
//
//

import Foundation

infix operator <- { associativity right }

public func <-<A>(f: Future<A> throws -> A, x: Future<A>) rethrows -> A {
  return try f(x)
}

public func <-<A>(f: Future<A> throws -> A, xs: [Future<A>]) rethrows -> [A] {
  return try xs.map(f)
}

public func <-<A, B>(f: A -> B, x: Future<A>) throws -> B {
  return f(try await <- x)
}

public func <-<A, B>(f: A -> Future<B>, x: Future<A>) throws -> Future<B> {
  return f(try await <- x)
}

//
//  Sequence.swift
//  Pods
//
//  Created by Olivier THIERRY on 07/02/17.
//
//

import Foundation

extension Sequence where Iterator.Element: FutureType {

  public func any() -> Future<Iterator.Element.A> {
    return Future { promise in
      self.forEach { future in
        future.then(promise.resolve)
        future.fail { error in
          // Guard all future completed before failing
          guard self.filter({ $0.isPending }).isEmpty else { return }
          promise.reject(error)
        }
      }
    }
  }

  public func all() -> Future<[Iterator.Element.A]> {
    return Future { promise -> Void in
      var results: [Iterator.Element.A] = []
      self.forEach { future in
        future
          .then {
            results.append($0)
            // Guard all future completed before resolving
            guard self.filter({ $0.isPending }).isEmpty else { return }
            promise.resolve(results)
          }
          .fail {
            promise.reject($0)
          }
      }
    }
  }

  public func reduce<A>(_ initial: A, reducer: @escaping (A, Iterator.Element.A) throws -> A) -> Future<A> {
    return self.all().then { values -> Future<A> in
      Future {
        try values.reduce(initial, reducer)
      }
    }
  }

}

//
//  Promise.swift
//  Pods
//
//  Created by Olivier THIERRY on 13/02/17.
//
//

import Foundation

public class Promise<A>: Future<A> {

  /**
   Designated static initializer for async futures.
   The method executes the block asynchronously in background queue
   (Future.futureQueueConcurrent). It provide a promise object to
   resolve or reject. This method is useful when the body
   of the async block also calls async code.

   Parameter: f: The block to execute with the future as parameter.

   Returns: The created promise object
   */
  @discardableResult
  public required init(_ f: @escaping (Promise<A>) -> Void) {
    super.init()

    queue.async {
      autoreleasepool {
        f(self)
      }
    }
  }

}

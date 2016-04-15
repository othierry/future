//
//  Promise.swift
//  Pods
//
//  Created by Olivier THIERRY on 07/04/16.
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
  public required init(_ f: Promise<A> -> Void) {
    super.init()

    // If we are already running on future's queue, they just asynchronously
    // call the function to avoid thread overflow and prevent deadlocking
    // due to future inter dependencies
    if self.isFutureQueue {
      f(self)
    } else {
      dispatch_async(futureQueueConcurrent) {
        f(self)
      }
    }
  }
  
}
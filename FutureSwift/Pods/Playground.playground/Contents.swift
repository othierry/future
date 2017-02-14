//: Playground - noun: a place where people can play

import FutureSwift
import PlaygroundSupport

func f(_ x: Int) -> Future<Int> {
  let futures: [Future<Int>] = [
    Future {
      Thread.sleep(forTimeInterval: 2)
      return 42
    },

    Future {
      Thread.sleep(forTimeInterval: 4)
      return 42
    }
  ]

  return futures.any()
}

f(1).then { x in
  print("result: \(x)")
}
PlaygroundPage.current.needsIndefiniteExecution = true
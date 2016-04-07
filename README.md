# FutureSwift

[![Version](https://img.shields.io/cocoapods/v/FutureSwift.svg?style=flat)](http://cocoapods.org/pods/FutureSwift)
[![License](https://img.shields.io/cocoapods/l/FutureSwift.svg?style=flat)](http://cocoapods.org/pods/FutureSwift)
[![Platform](https://img.shields.io/cocoapods/p/FutureSwift.svg?style=flat)](http://cocoapods.org/pods/FutureSwift)

## Installation

FutureSwift is available through [CocoaPods](http://cocoapods.org). To install
it, simply add the following line to your Podfile:

```ruby
pod "FutureSwift"
```

## Usage

### Future

Futures are used to execute blocks of code asynchronously in parallel efficently. They are a placeholder object for a value that may exist in the future.

It is the same thoughts as the Callback pattern with more flexibility and cleaner syntax & code style. Futures are simple objects wrapping success and failure block. They can be chained, one can depend on another, etc... Futures come with a set of methods & functions to provide an efficient control flow to the way they are performed.

### Promise

By design, this library merges Promise and Future patterns. A promise is just a writable (once) container that resolve or reject its contained future. A future is supposed to be read-only. In this library, a future exposes promise's `reject(_:)`/`resolve(_:)` methods the same way a promise would, they must be called only once. If you try to resolve an already resolved/rejected promise, an exception will be thrown.

`promise(_:)` function acts a bit different than `future(_:)` function. Both returns futures but:
- `future(_:)` takes a block taking no argument and returning a value. The block can throw an exception. If an exception is thrown, the future will reject using the catched error, otherwise it will resolve using the returned value.
- `promise(_:)` takes a block taking a `Future` object. You are then responsible for calling `resolve(_:)` or `reject(_:)` on that future with the corresponding value/error.

#### Use case scenarios

- If you need to perform async code within your block (let's say you're using Alamofire that provides only non-blocking API calls) then use `promise(_:)`

```swift
func fetchUser(id: Int) -> Future<User> {
  return promise { promise in
    // Network asynchronous call
    Alamofire.request { user, error in
      if let error = error {
        // Reject
        promise.reject(error)
        return
      }

      // Resolve
      promise.resolve(user)

      // You can continue doing something unrelated
      doSomethingUnrelated()
    }
  }
}

```

- If you need to perform sync code within your block then use `future(_:)`

```swift
func fetchUser(id: Int) -> Future<Bool> {
  return future {
    for i in (0...10000000) {
      // Do something expansive...
    }

    return true
  }
}

```

### Composing futures

*Incoming*

#### Simple future

*Incoming*

#### Chaining Futures

*Incoming*

### Consuming futures

#### Then

You can pass completion blocks to a future using the `then(_:)` method.
The callback can be one of the following:

- `Void -> Void`: Ignores the value resolved by the `Future` and returns nothing.
- `A -> Void`: Takes the value resolved by the future and returns nothing.
- `A -> Future<B>`: Takes the value resolved by the future and returns a new future. the future chain will continue when this future resolves or fails.
- `A -> B`: Takes the value resolved by the future and returns a new value. This value is the new value that will be passed to the rest of the futures chain.

  **NOTE**: This is NOT mutating the future's original value. A future's value is set only once (when resolved).

#### Fail

You can call `fail(_:)` on a future by passing a closure that takes an `ErrorType` as parameter. When one of the future in the chain fails, this block will be called using the given error.

### Await

Await allows you to block the running thread while a future completes. It makes the use of multiple future a lot easier to read and understand.

**NOTE** Do never call `await(_:)` from the main thread. If you try to call `await(_:)` from the main thread, an exception will be raised. As explained in ###, `then(_:)` blocks are scheduled to be run on the main queue. If the main thread is waiting for the future to be completed and the future needs its `then(_:)` blocks to be called in order to complete the future chaining cascade, it will deadlock. `await(_:)` is designed to be called from any thread but the main thread.

**Example:**

Let's take 3 random functions doing work asynchronously:

```
func f1() -> Future<Void> {
  return future {
    NSThread.sleepForTimeInterval(1)
  }
}

func f2() -> Future<Void> {
  return future {
    NSThread.sleepForTimeInterval(2)
  }
}

func f3() -> Future<Void> {
  return future {
    NSThread.sleepForTimeInterval(3)
  }
}
```

You could compose and chain your futures like so (using standard `then(_:)`/`fail(_:)` approach):

```
func doSomethingAsync() -> Future<Void> {
  return f1().then { _ -> Future<Void> in
    f2()
  }.then { _ -> Future<Void> in
    f3()
  }.then {
    // Everthing's done!
  }.fail { error in
    // Something went bad
  }  
}
```

Using await

```
func doSomethingAsync() -> Future<Void> {
  return future {
    try await <- f1()
    try await <- f2()
    try await <- f3()
  }
}
```

Now let's define some other functions that have dependencies to each other.
In the following example, `f2` needs the value resolved by `f1` to run, and `f3` need the value resolved by `f2`.

```
func f1() -> Future<Int> { ... }
func f2(x: Int) -> Future<String> { ... }
func f3(x: String) -> Future<[String]> { ... }
```

Using standard `then(_:)/fail(_:)` approach:

```
f1().then { x -> Future<String> in
  f2(x)
}.then { y -> Future<[String]> in
  f3(y)
}.fail { error in
  // Something went bad
}
```

Using `await(_:)` approach:

```
future {
  let x = try await <- f1()
  let y = try await <- f2(x)
  let z = try await <- f3(y)

  return z
}
```

Or, if you want to be really sex:

```
future {
  try await <- f3 <- f2 <- f1()
}
```

### Operators

*Incoming*

### Control flow

*Incoming*

## Author

Olivier Thierry, olivier.thierry42@gmail.com

## License

FutureSwift is available under the MIT license. See the LICENSE file for more info.

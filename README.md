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

By design, this library merges Promise and Future patterns (`Promise` inherits from `Future`). In this library, `Promise` just defines a new initializer which a closure that takes the `Promise` itself so you have the control when to resolve/reject it.

- `Future`'s initializer takes a block taking no argument and returning a value. The block can throw an exception. If an exception is thrown, the future will reject using the catched error, otherwise it will resolve using the returned value. You use it to do synchronous work.

- `Promise`'s intiailizer takes a block taking a `Promise` object. You are then responsible for calling `resolve(_:)` or `reject(_:)` on that promise with the corresponding value/error. You use it to do asynchronous work.

### Composing futures

- If you need to perform async code within your block (let's say you're using Alamofire that provides only non-blocking API calls) then use `Promise`

```swift
func fetchUser(id: Int) -> Future<User> {
  return Promise { promise in
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

- If you need to perform sync code within your block then use `Future`

```swift
func computeSomething() -> Future<Bool> {
  return Future {
    for i in (0...10000000) {
      // Do something expansive...
    }

    return true
  }
}
```

#### Chaining Futures

Futures & Promises can also be chained.

```Swift
Future {
  return 42
}.then { x in
  return "\(x) - Forty two"
}.then { x -> Future<[String]> in
  Future {
    return [x]
  }
}.then { x in
  print(x) // prints ["Forty two"]
}
```

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

##
## Finally

`finally(_:)` takes a closure that will execute after the future fulfils or fails.

### Await

Await allows you to block the running thread while a future completes. Awaiting is not recommended as it is blocking the calling thread and can cause dead locks when using recursive awaits.

**NOTE** Do not call `await(_:)` from the main thread. `then(_:)` blocks are scheduled to be run on the main queue **by default**. If the main thread is waiting for the future to be completed and the future needs its `then(_:)` blocks to be called in order to complete the future chaining cascade, it will deadlock. `await(_:)` is designed to be called from any thread but the main thread.

**Example:**

Let's take 3 random functions doing work asynchronously:

```swift
func f1() -> Future<Void> {
  return Future {
    NSThread.sleepForTimeInterval(1)
  }
}

func f2() -> Future<Void> {
  return Future {
    NSThread.sleepForTimeInterval(2)
  }
}

func f3() -> Future<Void> {
  return Future {
    NSThread.sleepForTimeInterval(3)
  }
}
```

You could compose and chain your futures like so (using standard `then(_:)`/`fail(_:)` approach):

```swift
func doSomethingAsync() -> Future<Void> {
  return f1().then { _ -> Future<Void> in
    f2()
  }.then { _ -> Future<Void> in
    f3()
  }.then {
    // Everthing's done
  }.fail { error in
    // Something went bad
  }  
}
```

Using await

```swift
func doSomethingAsync() -> Future<Void> {
  return Future {
    try await(f1())
    try await(f2())
    try await(f3())
  }
}
```

Promises can depend on each other.
Here, `f2` needs the value resolved by `f1` to run, and `f3` need the value resolved by `f2`.

```swift
func f1() -> Future<Int> { ... }
func f2(x: Int) -> Future<String> { ... }
func f3(x: String) -> Future<[String]> { ... }
```

Using standard `then(_:)/fail(_:)` approach:

```swift
f1().then { x -> Future<String> in
  f2(x)
}.then { y -> Future<[String]> in
  f3(y)
}.fail { error in
  // Something went bad
}

// or

f1().then(f2).then(f3).fail { error in
  // Something went bad
}
```

Using `await(_:)` approach:

```
Future {
  let x = try await(f1())
  let y = try await(f2())
  let z = try await(f3())

  return z
}
```

You can also use binding operators to chain futures.

```swift
Future {
  try f1() => f2 => f3 => await
  // Equivalent to
  try f1().then(f2).then(f3).await()
}
```

You can compose futures using the same operator

```swift
let f4 = f1 => f2 => f3 // f4 :: (Void) -> Future<[String]>
```

### Operators

`=>` operator can be used as syntactic sugar for composing futures the same way you are composing functions.

Given
```Swift
func f1() -> Future<Int> { ... }
func f2(x: Int) -> Future<String> { ... }
func f3(x: String) -> Future<[String]> { ... }
```

```Swift
let f4 = f1 => f2 => f3              // f4 :: Void -> Future<[String]>
let f4 = f1() => f2 => f3            // f4 :: Future<[String]>
let f4 = try await(f1() => f2 => f3) // f4 :: [String]
```

### Control flow

#### CollectionType extension

This library provides an extension for `Sequence` containing `FutureType` objects. `Future` conforms to `FutureType`.

#### all

`Sequence#all()` method returns a new `Future`. The returned future will resolve when all the futures contained in `self` are resolved and will expose a list of the values returned by the futures. If one of the future fails, the returned future will directly fail with the same error.

**Example**

```swift
let futures: [Future<Int>] = [f1, f2, ...]

futures.all().then { values in
  // All futures completed, values is an Array<Int>
}
```

#### any

`Sequence#any()` method returns a new `Future`. The returned future will resolve as soon as one of the future contained in `self` is resolved and will expose the value. If all the futures fail, the returned future will also fail with a `nil` error.

**Example**

```swift
let futures: [Future<Int>] = [f1, f2, ...]

futures.any().then { value in
  // All futures completed, values is an Int
}
```

#### reduce

`Sequence#reduce()` method is the same as the standard library reduce function but it reduces a list of futures instead of a list of a values.

**Example**

```swift
let futures: [Future<Int>] = [f1, f2, ...]

futures.reduce(0, combine: +).then { value in
  // All futures completed, values is an Int
}
```

#### Future extension

#### merge

`Future#merge(_:)` method takes a future and returns a new `Future` that will resolve to a tuple of 2 values that correspond to the values of `self` and the given future. If one future fails, the returned future will also fail with the same error.

```swift
let f1: Future<Int> = ...
let f2: Future<String> = ...

f1.merge(f2).then { x, y in
  // x is an Int
  // y is a String
}
```

#### wrap

`Future#wrap<A>(_: A.Type)` method takes an arbitrary `Type`. This is useful when a future actually resolves a value with a concrete type but the caller of the future expect another type your value type can be downcasted to. **NOTE: You must make sure that the value can be casted to the given type.**

```swift
let f1: Future<String> = ...
let f2 = f1.wrap(AnyObject) // Is now a Future<AnyObject>
```

`Future#wrap()` returns a new future that resolve to `Void`. This is useful when a future actually resolves a value with a concrete type but the caller of the future do not care about this value and expect Void.

```swift
let f1: Future<Int> = ...
let f2 = f1.wrap() // Is now a Future<Void>
```

## Author

Olivier Thierry, olivier.thierry42@gmail.com

## License

FutureSwift is available under the MIT license. See the LICENSE file for more info.

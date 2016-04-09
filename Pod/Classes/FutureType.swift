//
//  FutureType.swift
//  Pods
//
//  Created by Olivier THIERRY on 09/04/16.
//
//

import Foundation

public protocol FutureType {
  associatedtype Value
  
  var group: dispatch_group_t { get }
  var state: FutureState { get }
  var value: Value! { get }
  var error: ErrorType? { get }
  
  func resolve(value: Value)
  func reject(error: ErrorType?)
}

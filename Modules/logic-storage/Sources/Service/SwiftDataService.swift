/*
 * Copyright (c) 2026 European Commission
 *
 * Licensed under the EUPL, Version 1.2 or - as soon they will be approved by the European
 * Commission - subsequent versions of the EUPL (the "Licence"); You may not use this work
 * except in compliance with the Licence.
 *
 * You may obtain a copy of the Licence at:
 * https://joinup.ec.europa.eu/software/page/eupl
 *
 * Unless required by applicable law or agreed to in writing, software distributed under
 * the Licence is distributed on an "AS IS" basis, WITHOUT WARRANTIES OR CONDITIONS OF
 * ANY KIND, either express or implied. See the Licence for the specific language
 * governing permissions and limitations under the Licence.
 */
import SwiftData
import Foundation

protocol SwiftDataService: Actor {
  func write<T: PersistentModel & IdentifiableObject>(_ object: T) throws
  func writeAll<T: PersistentModel & IdentifiableObject>(_ objects: [T]) throws
  func read<T: PersistentModel & IdentifiableObject, R>(predicate: Predicate<T>, map: (T) -> R) throws -> R?
  func readAll<T: PersistentModel & IdentifiableObject, R>(_ type: T.Type, map: (T) -> R) throws -> [R]
  func delete<T: PersistentModel & IdentifiableObject>(predicate: Predicate<T>) throws
  func deleteAll<T: PersistentModel & IdentifiableObject>(of type: T.Type) throws
}

final actor SwiftDataServiceImpl: SwiftDataService {

  private let container: ModelContainer

  init(storageConfig: StorageConfig) {
    do {
      self.container = try ModelContainer(
        for: storageConfig.schemas,
        configurations: storageConfig.modelConfiguration
      )
    } catch {
      fatalError("ModelContainer init failed: \(error)")
    }
  }

  // A `ModelContext` is not Sendable and must be created and used on the same
  // executor. The previous implementation created the context in `init` (on the
  // caller's thread, typically the main queue) and then used it from this actor's
  // executor, which SwiftData flags ("instantiated on the main queue but is being
  // used off it") and which can crash under Swift 6 / iOS 26. Creating a fresh,
  // cheap context inside each actor-isolated method keeps it bound to this actor.
  private func makeContext() -> ModelContext {
    ModelContext(container)
  }

  func write<T: PersistentModel & IdentifiableObject>(_ object: T) throws {
    let context = makeContext()
    context.insert(object)
    try context.save()
  }

  func writeAll<T: PersistentModel & IdentifiableObject>(_ objects: [T]) throws {
    let context = makeContext()
    for object in objects { context.insert(object) }
    try context.save()
  }

  func read<T: PersistentModel & IdentifiableObject, R>(predicate: Predicate<T>, map: (T) -> R) throws -> R? {
    let context = makeContext()
    var fd = FetchDescriptor<T>(predicate: predicate)
    fd.fetchLimit = 1
    return try context.fetch(fd).first.map(map)
  }

  func readAll<T: PersistentModel & IdentifiableObject, R>(_ type: T.Type, map: (T) -> R) throws -> [R] {
    let context = makeContext()
    return try context.fetch(FetchDescriptor<T>()).map(map)
  }

  func delete<T: PersistentModel & IdentifiableObject>(predicate: Predicate<T>) throws {
    let context = makeContext()
    var fd = FetchDescriptor<T>(predicate: predicate)
    fd.fetchLimit = 1
    if let object = try context.fetch(fd).first {
      context.delete(object)
      try context.save()
    }
  }

  func deleteAll<T: PersistentModel & IdentifiableObject>(of type: T.Type) throws {
    let context = makeContext()
    let results = try context.fetch(FetchDescriptor<T>())
    for result in results { context.delete(result) }
    if !results.isEmpty { try context.save() }
  }
}

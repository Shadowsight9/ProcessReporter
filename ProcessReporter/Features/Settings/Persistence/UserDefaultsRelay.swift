import Foundation

protocol UserDefaultsStorable {
    func toStorable() -> Any?
    static func fromStorable(_ value: Any?) -> Self?
}

final class RelaySubscription {
    private let onDispose: () -> Void
    private var isDisposed = false

    init(onDispose: @escaping () -> Void) {
        self.onDispose = onDispose
    }

    func dispose() {
        guard !isDisposed else { return }
        isDisposed = true
        onDispose()
    }

    deinit {
        dispose()
    }
}

final class BehaviorRelay<Value> {
    private let lock = NSRecursiveLock()
    private var observers: [UUID: (Value) -> Void] = [:]
    private var currentValue: Value
    private let onAccept: (Value) -> Void

    init(value: Value, onAccept: @escaping (Value) -> Void = { _ in }) {
        currentValue = value
        self.onAccept = onAccept
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return currentValue
    }

    func accept(_ value: Value) {
        let callbacks: [(Value) -> Void]
        lock.lock()
        currentValue = value
        callbacks = Array(observers.values)
        lock.unlock()

        onAccept(value)
        callbacks.forEach { $0(value) }
    }

    @discardableResult
    func subscribe(_ handler: @escaping (Value) -> Void) -> RelaySubscription {
        let id = UUID()
        let initialValue: Value

        lock.lock()
        observers[id] = handler
        initialValue = currentValue
        lock.unlock()

        handler(initialValue)

        return RelaySubscription { [weak self] in
            self?.lock.lock()
            self?.observers[id] = nil
            self?.lock.unlock()
        }
    }

    @discardableResult
    func subscribeOnMain(_ handler: @escaping (Value) -> Void) -> RelaySubscription {
        subscribe { value in
            if Thread.isMainThread {
                handler(value)
            } else {
                DispatchQueue.main.async {
                    handler(value)
                }
            }
        }
    }
}

@propertyWrapper
struct UserDefaultsRelay<Value> {
    private let relay: BehaviorRelay<Value>

    init(_ key: String, defaultValue: Value) {
        let savedValue: Value

        if let storable = defaultValue as? any UserDefaultsStorable {
            let valueType = type(of: storable)
            if let storageValue = UserDefaults.standard.object(forKey: key),
               let value = valueType.fromStorable(storageValue) as? Value {
                savedValue = value
            } else {
                savedValue = defaultValue
            }
        } else {
            savedValue = UserDefaults.standard.object(forKey: key) as? Value ?? defaultValue
        }

        relay = BehaviorRelay(value: savedValue) { value in
            if let storable = value as? any UserDefaultsStorable {
                UserDefaults.standard.set(storable.toStorable(), forKey: key)
            } else {
                UserDefaults.standard.set(value, forKey: key)
            }
        }
    }

    var wrappedValue: BehaviorRelay<Value> {
        relay
    }
}

protocol UserDefaultsJSONStorable: UserDefaultsStorable, Codable {}

extension UserDefaultsJSONStorable {
    func toStorable() -> Any? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let jsonData = try? encoder.encode(self) else { return nil }
        return String(data: jsonData, encoding: .utf8)
    }

    static func fromStorable(_ value: Any?) -> Self? {
        guard let value = value as? String,
              let jsonData = value.data(using: .utf8)
        else {
            return nil
        }
        return try? JSONDecoder().decode(Self.self, from: jsonData)
    }
}

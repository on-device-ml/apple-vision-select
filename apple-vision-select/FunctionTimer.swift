import Foundation

class FunctionTimer {
    
    private var startTime: DispatchTime?
    
    func start() {
        startTime = DispatchTime.now()
    }
    
    func stop() -> Double {
        guard let start = startTime else {
            print("Timer was not started.")
            return 0
        }
        
        let end = DispatchTime.now()
        let nanoTime = end.uptimeNanoseconds - start.uptimeNanoseconds
        let timeInterval = Double(nanoTime) / 1_000_000 // in milliseconds
        startTime = nil // reset
        return timeInterval
    }

    /// Measures a closure's execution time in milliseconds.
    static func measure(_ block: () -> Void) -> Double {
        let start = DispatchTime.now()
        block()
        let end = DispatchTime.now()
        let nanoTime = end.uptimeNanoseconds - start.uptimeNanoseconds
        return Double(nanoTime) / 1_000_000 // in milliseconds
    }
}

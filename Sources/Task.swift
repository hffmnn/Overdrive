//
//  Task.swift
//  Overdrive
//
//  Created by Said Sikira on 6/19/16.
//  Copyright © 2016 Said Sikira. All rights reserved.
//

import class Foundation.NSOperation

public class Task<T>: NSOperation {
    
    /**
     Internal result object
     
      - Warning: Should never be set directly, only via `result` property
    */
    private var internalResult: Result<T>?
    
    /**
     Internal task state
     
     - Warning: Setting the state directly using this property will result
     in unexpected behaviour. Use the `state` property to set and retrieve
     current state.
    */
    private var internalState: State = .Initialized
    
    /**
     Internal completion block
     
     - Warning: Accessing this property directly will result in unexpected behavior.
     Use `onCompleteBlock` instead.
    */
    private var internalOnCompleteBlock: ((T) -> Void)?
    
    /**
     Internal error completion block
     
     - Warning: Accessing this property directly will result in unexpected behavior.
     Use `onErrorBlock` instead.
     */
    private var internalOnErrorBlock: ((ErrorType) -> Void)?
    
    /**
     Internal task observers
    */
    private var internalObservers: [TaskObserver] = []
    
    /**
     Internal number of retry counts
    */
    private var internalRetryCount: Int = 0
    
    /**
     Private queue used in task state machine
    */
    let queue = dispatch_queue_create("io.overdrive.task", nil)
    
    //MARK: Class properties
    
    /**
     Task result. Result can contain either value or error.
     
     `Value(T)`: value of type defined by the Task
     
     `Error(ErrorType)`: error that may have occured
     
     This object is not goint to be populated with result until task 
     achieves `Finished` state. You can access the result value directly,
     or setup completion blocks that will execute when task finishes.
    */
    private(set) public var result: Result<T>? {
        get {
            return Dispatch.sync(queue) { return self.internalResult }
        }
        
        set(newResult) {
            Dispatch.sync(queue) {
                self.internalResult = newResult
            }
        }
    }
    
    /// Completion block that will be executed when the task finishes execution
    @available(*, deprecated, message = "use onResult completion instead")
    public override var completionBlock: (() -> Void)? {
        get {
            return nil
        }
        set {
            assert(false, "Use onComplete method to define the behaviour")
        }
    }
    
    var retryCount: Int {
        get {
            return Dispatch.sync(queue) { return self.internalRetryCount }
        }
        
        set(newCount) {
            Dispatch.sync(queue) {
                self.internalRetryCount = newCount
            }
        }
    }
    
    /**
     Completion block that is executed when the task reaches `Finished` state and 
     `.Value` is passed to the `finish:` method. Completion block takes one 
     argument `T`, which is `.Value` component from the task result.
     
     See `Result<T>`.
     
     Block should be set by using `onComplete:` method on `Self`.
     
     - Warning: Setting this property directly may result in unexpected behaviour.
     Always use `onComplete:` method on `Self` to set the block.
    */
    var onCompleteBlock: ((T) -> Void)? {
        get {
            return Dispatch.sync(queue) {
                return self.internalOnCompleteBlock
            }
        }
        
        set(newBlock) {
            if newBlock != nil {
                Dispatch.sync(queue) {
                    self.internalOnCompleteBlock = newBlock
                }
            }
        }
    }
    
    /**
     Completion block that is executed when the task reaches `Finished` state and 
     error is passed to the `finish:` method. Completion block has one argument,
     `ErrorType` and no return type. `ErrorType`.
     
     Block should be set by using `onError:` method on `Self`.
     
     - Warning: Setting this property directly may result in unexpected behaviour.
     Always use `onError:` method on `Self` to set the block.
    */
    var onErrorBlock: ((ErrorType) -> Void)? {
        get {
            return Dispatch.sync(queue) {
                return self.internalOnErrorBlock
            }
        }
        
        set(newBlock) {
            if newBlock != nil {
                Dispatch.sync(queue) {
                    self.internalOnErrorBlock = newBlock
                }
            }
        }
    }
    
    /**
     Use this method to set completion block that will be executed when task
     finishes execution.
     
     - Note: Completion block set will only be executed if the
     task finishes with `.Value` result. 
     
     If the task finishes with `.Error` result, onError completion will be called.
     
     - Warning: This method should only be called before the task state becomes `.Pending`.
     Calling this method after `.Pending` state may result in unexpected behaviour.
     
     - Parameter completion: Completion block that should be executed. Takes only
     one parameter `T` and no return type.
     
     - Returns: `Self`. This method will always return itself, so that it can be used
     in chain with other task methods.
    */
    public final func onComplete(completion: ((T) -> ())) -> Self {
        assert(state < .Executing, "On complete called after task is executed")
        onCompleteBlock = completion
        return self
    }
    
    /**
     Use this method to set completion block that will be executed when task
     finishes with error.
     
     - Note: Completion block set will only be executed if the
     task finishes with `.Error` result.
     
     If the task finishes with `.Value` result, onComplete completion will be called.
     
     - Warning: This method should only be called before the task state becomes `.Pending`.
     Calling this method after `.Pending` state may result in unexpected behaviour.
     
     - Parameter completion: Completion block that should be executed. Takes only
     one parameter `ErrorType` and no return type.
     
     - Returns: `Self`. This method will always return itself, so that it can be used
     in chain with other task methods.
     */
    public final func onError(completion: ((ErrorType) -> ())) -> Self {
        assert(state < .Executing, "On complete called after task is executed")
        onErrorBlock = completion
        return self
    }
    
    private(set) public var observers: [TaskObserver] {
        get {
            return Dispatch.sync(queue) { return self.internalObservers }
        }
        
        set {
            Dispatch.sync(queue) {
                self.internalObservers = newValue
            }
        }
    }
    
    public func retry(times: Int) -> Self {
        retryCount = times
        return self
    }
    
    /**
     Main task state object. Any state change triggers internal `NSOperation` observers.
     
     State can be one of the following:
     
     * `Initialized`
     * `Pending`
     * `Ready`
     * `Executing`
     * `Finished`
     
     - Note:
     You can change state from any thread.
    */
    var state: State {
        get {
            return Dispatch.sync(queue) { return self.internalState }
        }
        
        set(newState) {
            
            // Notify internal `NSOperation` observers that state will be changed
            willChangeValueForKey("state")
            
            Dispatch.sync(queue) {
                assert(self.internalState.canTransitionToState(newState, shouldRetry: self.shouldRetry),
                       "Invalid state transformation")
                self.internalState = newState
            }
            
            // Notifity internal `NSOperation` observers that state is changed
            didChangeValueForKey("state")
        }
    }
    
    /**
     This method changes state of `self` to `Pending`. It is called when task is
     added to the `TaskQueue`
    */
    final func willEnqueue() {
        state = .Pending
    }
    
    public override var asynchronous: Bool {
        return true
    }
    
    public override var ready: Bool {
        switch state {
        case .Initialized:
            return cancelled
        case .Pending:
            guard !cancelled else {
                return true
            }
            
            if super.ready {
                evaluateConditions()
            }
            return false
        case .Ready:
            return super.ready || cancelled
        default:
            return false
        }
    }
    
    public override var executing: Bool {
        return state == .Executing
    }
    
    public override var finished: Bool {
        return state == .Finished
    }
    
    final func evaluateConditions() {
        assert(state == .Pending && !cancelled, "evaluateConditions() was called out-of-order")
        
        state = .Ready
    }
    
    public final func addObserver(observer: TaskObserver) {
        observers.append(observer)
    }
    
    /**
     Finish execution of the task with result. Calling this method will change 
     task state to `Finished` and call neccesary completion blocks. If task finished
     with `Value(T)`, `onCompleteBlock` will be executed. If task finished with 
     `Error(ErrorType)` result, `onErrorBlock` will be executed.
     
     - Parameter result: Task result (`.Value(T)` or `.Error(ErrorType)`)
     
     - Note: 
     Safe to call from any thread.
    */
    public final func finish(result: Result<T>) {
        self.result = result
        moveToFinishedState()
        
        switch result {
        case .Value(let value):
            onCompleteBlock?(value)
        case .Error(let error):
            onErrorBlock?(error)
        }
    }
    
    /**
     Changes task state to `Finished`
    */
    private final func moveToFinishedState() {
        state = .Finished
        
        for observer in observers {
            observer.taskDidFinishExecution(self)
        }
    }
    
    public override final func start() {
        if cancelled {
            moveToFinishedState()
        } else {
            main()
        }
    }
    
    public override final func main() {
        assert(state == .Ready, "Task must be performed on OperationQueue")
        state = .Executing
        
        for observer in observers {
            observer.taskDidStartExecution(self)
        }
        
        if !cancelled {
            run()
        } else {
            moveToFinishedState()
        }
    }
    
    public func run() {
        assertionFailure("run() method should be overrided in \(self.dynamicType)")
    }
    
    public override init() {
        super.init()
    }
    
    //MARK: KVO mechanisms
    
    @objc class func keyPathsForValuesAffectingIsReady() -> Set<NSObject> {
        return ["state"]
    }
    
    @objc class func keyPathsForValuesAffectingIsExecuting() -> Set<NSObject> {
        return ["state"]
    }
    
    @objc class func keyPathsForValuesAffectingIsFinished() -> Set<NSObject> {
        return ["state"]
    }
}

enum RetryCountError: ErrorType {
    case CountIsZero
}


extension Task {
    var shouldRetry: Bool {
        return retryCount > 0
    }
    
    func decreaseRetryCount() throws {
        if retryCount > 0 {
            retryCount = retryCount - 1
        } else {
            throw RetryCountError.CountIsZero
        }
    }
}

//
//  TaskQueue.swift
//  Overdrive
//
//  Created by Said Sikira on 6/19/16.
//  Copyright © 2016 Said Sikira. All rights reserved.
//

import class Foundation.NSOperation
import class Foundation.NSOperationQueue

public class TaskQueue: NSOperationQueue {
    
    public static var main: TaskQueue = TaskQueue(qos: .UserInteractive)
    
    /// TaskQueue delegate object
    weak public var delegate: TaskQueueDelegate?
    
    //MARK: Init methods
    
    /// Creates instance of `TaskQueue`
    public override init() {
        super.init()
    }
    
    /**
     Initilizes TaskQueue with specific `NSQualityOfService` class. Defining
     quality of service class will later determine how tasks are executed.
     */
    public init(qos: NSQualityOfService) {
        super.init()
        self.qualityOfService = qos
    }
    
    //MARK: Task management
    
    /**
     Add task to the TaskQueue and starts execution. Method will call
     delegate method responsible for adding task.
     
     - Parameter task: Task<T> to be added
     */
    public func addTask<T>(task: Task<T>) {
        
        let finishObserver = FinishBlockObserver { [weak self] in
            if let queue = self {
                queue.delegate?.didFinish(task: task, inQueue: queue)
            }
        }
        task.addObserver(finishObserver)
        
        if task.shouldRetry {
            let retryObserver = RetryTaskObserver { [weak self] in
                if let queue = self {
                    queue.retry(task: task)
                }
            }
            task.addObserver(retryObserver)
        }

        addOperation(task)
        delegate?.didAdd(task: task, toQueue: self)
        
        task.willEnqueue()
    }
    
    /**
     Adds array of tasks to the TaskQueue and starts execution. Method will
     call delegate method responsible for adding tasks.
     
     - Parameter tasks: Array of `Task<T>`
     */
    public func addTasks<T>(tasks: [Task<T>]) {
        for task in tasks {
            // Create finish observer and setup completion block
            addTask(task)
        }
    }
}

extension TaskQueue {
    func retry<T>(task task: Task<T>) {
        do {
            try task.decreaseRetryCount()
            task.state = .Initialized
            addTask(task)
            task.willEnqueue()
            delegate?.didRetry(task: task, inQueue: self)
        } catch {
            
        }
    }
}

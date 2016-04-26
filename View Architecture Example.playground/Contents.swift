//: Playground - noun: a place where people can play

import UIKit
import RxSwift

protocol Effect {
    associatedtype Effects
    associatedtype Output
    
    init(transform: Effects -> Observable<Output>, sideEffects: (Effects -> [Disposable])?)
    
    func from<Input>(screen: Input -> Effects) -> Input -> Observable<Output>
}

struct TestEffect<Effects, Output> {
    
    private let transform: Effects -> Observable<Output>
    private let sideEffects: (Effects -> [Disposable])?
    
    init(transform: Effects -> Observable<Output>, sideEffects: (Effects -> [Disposable])? = nil) {
        self.transform = transform
        self.sideEffects = sideEffects
    }
    
    func from<Input>(screen: Input -> Effects) -> Input -> Observable<Output> {
        return { input in
            let effects = screen(input)
            
            return self.sideEffects.map { sideEffect in Observable.using({
                CompositeDisposable(disposables: sideEffect(effects))
                }, observableFactory: { _ in
                    self.transform(effects) })
                } ??  self.transform(effects)
        }
    }
}

struct StoryboardEffect<Effects, Output> {

    private let transform: Effects -> Observable<Output>
    private let sideEffects: (Effects -> [Disposable])?
    
    init(transform: Effects -> Observable<Output>, sideEffects: (Effects -> [Disposable])? = nil) {
        self.transform = transform
        self.sideEffects = sideEffects
    }
    
    func from<Input>(screen: Input -> Effects) -> Input -> Observable<Output> {
        return { input in
            let effects = screen(input)
            
            return self.sideEffects.map { sideEffect in Observable.using({
                CompositeDisposable(disposables: sideEffect(effects))
                }, observableFactory: { _ in
                    self.transform(effects) })
                } ??  self.transform(effects)
        }
    }
}


func start<E>(screen: () -> Observable<E>, ifNotPresent condition: (() -> Observable<E>?)? = nil) -> Observable<E> {
    return Observable<E>.deferred { condition.map { $0() ?? screen() } ?? screen() }
}

extension Observable {
    
    func then<O: ObservableType>(screen: (Element) -> O, ifNotPresent condition: (() -> O?)? = nil) -> Observable<O.E> {
        return flatMap { el throws in condition.map { $0() ?? screen(el) } ?? screen(el) }
    }
    
    func run() {
        debug().subscribe()
    }

}

/*: 
 
 # An Example
 
 Notice how we haven't introduced UIViewControllers at all. That's because it doesn't matter what screens are. They can be actual screens, logical screens, third-party libraries with really weird presentation styles, etc. So I've taken the `Effect` struct that
 
 */
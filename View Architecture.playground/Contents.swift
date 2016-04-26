import UIKit
import RxSwift
import RxBlocking
import RxCocoa
import XCPlayground

XCPlaygroundPage.currentPage.needsIndefiniteExecution = true

/*:

 # Motivation
 
 We want to declare our app as a series of dependent screens. Like:
 
     • 🖥 (present screen) 1 ➡ 👆, 👆, 👆 (interact) ➡ 👍 (ready for next screen)
 
     • Then 🖥 2 ➡ 👆 ➡ 👍
 
     • If ??? then 🖥 3 ➡ 👆, 👆 ➡ 👍

 ## How it is Done
 
 The above diagram makes a screen behave like a function: `(Input) -> Output`. If we use Rx, we might model this as `(Input) -> Observable<Output>`. With this signature, we can easily chain screens together using `flatMap`. 
 
 Let's try an example:
 
 * Screen 1 has no dependencies and completion is determined by calling onNext on a `PublishSubject`
 * Screen 2 is completed automatically after a delay (which is given to screen 2 from screen 1)
 
 */

let screenOneComplete = PublishSubject<Void>()

let screen1: () -> Observable<Double> = { screenOneComplete.map { 1 } }
let screen2: (Double) -> Observable<Void> = { Observable<Int>.timer($0, scheduler: MainScheduler.instance).map { _ in () } }

//The app definition
Observable.deferred(screen1).flatMap(screen2).debug().subscribe()

//Simulate user input on screen 1
screenOneComplete.onNext()
 
/*:
 
 ## Improving readability
 
 To make this more readable, we might want to introduce a few helpers. After introducing these types, we can do the same as above with the following:
 
     start1(screen1).then1(screen2).run()
 
 */

func start1<E>(screen: () -> Observable<E>) -> Observable<E> {
    return Observable<E>.deferred(screen)
}

extension Observable {
    
    func run() {
        debug().subscribe()
    }
    
    func then1<O: ObservableType>(screen: (Element) -> O) -> Observable<O.E> {
        return flatMap(screen)
    }
    
}

/*:
 
 ## Adding conditionality
 
 In many cases, screens are shown conditionally. We should add support for this in our `then` and `start` functions. Below, we introduce an optional parameter that only shows the screen if there is no result from the expression.
 
 With this, we should be able to do: 
 
     func cachedDataScreen2WillSet() -> Observable<Void>? {
         return Observable.just()
     }
 
     start(screen1).then(screen2, ifNotPresent: cachedDataScreen2WillSet).run()
 
 */

func start<E>(screen: () -> Observable<E>, ifNotPresent condition: (() -> Observable<E>?)? = nil) -> Observable<E> {
    return Observable<E>.deferred { condition.map { $0() ?? screen() } ?? screen() }
}

extension Observable {
    
    func then<O: ObservableType>(screen: (Element) -> O, ifNotPresent condition: (() -> O?)? = nil) -> Observable<O.E> {
        return flatMap { el throws in condition.map { $0() ?? screen(el) } ?? screen(el) }
    }
    
}

/*:
 
 ## Handling multiple interactions
 
 Screens don't usually have just a single variable that changes. They can have a complex arrangment of any number of interactable components. That is, a screen generally is more of a function like `(Input) -> (Observable<T>, Observable<U>, Observable<V>, ...)` than it is `(Input) -> Observable<A>`. But `flatMap` can't use multivariate return types. For a screen, we need to transform this collection of Observables to just one. Following the model of applicatives, we define an effect and apply it to a screen.
 
     let screen3: (Void) -> (Observable<String>, Observable<Int>) = ...
 
     start(screen1).then(screen2).then(Effect1{ $0.0 }.from(screen3)).run()
 
 */

struct Effect1<Effects, O: ObservableType> {
    
    private let transform: Effects -> O
    
    init(transform: Effects -> O) {
        self.transform = transform
    }
    
    func from<Input>(screen: Input -> Effects) -> Input -> O {
        return { input in self.transform(screen(input)) }
    }
}

/*:
 
 ## Side Effects
 
 Screens also have side effects. This gets a bit tricky. We'll make side effects optional for convenience and tie subscription resources to the lifetime of the Screen's effect.
 
 An example of what this will enable us to do:
 
     let screen3: (Void) -> (Observable<String>, Observable<Int>) = ...
 
     let screen3Effects = Effect<(Observable<String>, Observable<Int>), String>(
         transform: { $0.0 },
         sideEffects: { [
             $0.1.debug().subscribe()
         ] })
     
     start(screen1)
         .then(screen2)
         .then(screen3Effects.from(screen3)).run()
 
 */

struct Effect<Effects, Output> {
    
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

let screen3: (Void) -> (Observable<String>, Observable<Int>) = { (Observable.empty(), Observable.empty()) }

let screen3Effects = Effect<(Observable<String>, Observable<Int>), String>(
    transform: { $0.0 },
    sideEffects: { [
        $0.1.debug().subscribe()
        ] })


start(screen1)
    .then(screen2)
    .then(screen3Effects.from(screen3)).run()

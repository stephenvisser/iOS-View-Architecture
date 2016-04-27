import UIKit
import RxSwift
import RxBlocking
import RxCocoa
import XCPlayground

XCPlaygroundPage.currentPage.needsIndefiniteExecution = true
/*:

 # Screens as Functions
 
 We want to declare our app as a series of dependent screens. Like:
 
     • 🖥 (present screen) 1 ➡ 👆, 👆, 👆 (interact) ➡ 👍 (ready for next screen)
 
     • Then 🖥 2 ➡ 👆 ➡ 👍
 
     • If ??? then 🖥 3 ➡ 👆, 👆 ➡ 👍

 ## First Attempts
 
 The above diagram makes a screen behave like a function: `(Input) -> Output`. If we use Rx, we might model this as `(Input) -> Observable<Output>`. With this signature, we can easily chain screens together using `flatMap`. 
 
 Let's try an example:
 
 * Screen 1 has no dependencies and completion is determined by calling onNext on a `PublishSubject`
 * Screen 2 is completed automatically after a delay (the number of seconds is passed to screen 2 from screen 1 as an argument)
 
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
 
     func cachedDataScreen2IsResponsibleFor() -> Observable<Void>? {
         return Observable.just()
     }
 
     start(screen1).then(screen2, ifNotPresent: cachedDataScreen2IsResponsibleFor).run()
 
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
 
 Screens also have side effects. In order to explicitly manage these side-effects, we'll extend the `Effect` struct to also take an optional side effect. Callers can completely specify the effect of the screen and also be in control of the side-effects. One particular advantage is that we can tie subscription resources to the lifetime of the Screen's effect.
 
 An example of what this will enable us to do:
 
     start(screen1)
         .then(screen2)
         .then(Effect(
             transform: { $0.0 },
             sideEffects:
                 { [
                     $0.1.debug().subscribe()
                 ] })
             .from(screen3))
         .run()
 
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
/*:
 
 ## Function-izing part 1
 
 Screens in iOS aren't really functions. They are UIViewControllers — objects. We need to introduce a protocol that UIViewControllers can conform to. It's pretty simple.
 
 */
protocol ScreenType {
    associatedtype Input
    associatedtype Output
    
    mutating func setUp(input: Input)
    
    var sideEffects: Output { get }
}
//: An example implementation
struct ViewModel { } // Some data model

class AController: UIViewController, ScreenType {
    let click = PublishSubject<Void>()
    let textBox = PublishSubject<String>()
    
    func setUp(input: ViewModel) {
        //Any setup
    }
    
    var sideEffects: (Observable<Void>, Observable<String>) { return (click, textBox) }
}
/*:
 
 ## Function-izing part 2
 
 We need a conversion mechanism from a `ScreenType` to function. In the world of screens, the screen must be initialized (manually or from storyboard) and presented when the function is called. In other words, we know what a screen needs (`Input`) and what its effects are (`Output`), but we need an environment that can manage this initialization and presentation
 
 Note that the presenter is useful as a utility to create functions from screens. It is not broadly useful since it has type information that is difficult (impossible?) to abstract away. It would be useful like this:
 
     class AViewController: UIViewController, ScreenType { ... }

     let presenter = Presenter { ... load from storyboard ... }
     let screen1 = presenter.present(AViewController.self., { ... present using navigation controller ... })
 
 */

struct Presenter {
    let initialization: (String) -> UIViewController
    
    func present<S: UIViewController where S: ScreenType>(identifier: S.Type, navigation: (S) -> Void) -> S.Input -> S.Output {
        
        return { input in
            
            var vc: S = self.initialization(String(S)) as! S
            vc.setUp(input)
            navigation(vc)
            return vc.sideEffects
            
        }
            
    }
    
}

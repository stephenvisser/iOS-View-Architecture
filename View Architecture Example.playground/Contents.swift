//: Playground - noun: a place where people can play

import UIKit
import RxSwift
import RxCocoa
import XCPlayground

XCPlaygroundPage.currentPage.needsIndefiniteExecution = true

/*:
 
 ## Setup
 
 We'll reuse a few things from the introduction
 
 */
func start<E>(screen: () -> Observable<E>, ifNotPresent condition: (() -> Observable<E>?)? = nil) -> Observable<E> {
    return Observable<E>.deferred { condition.map { $0() ?? screen() } ?? screen() }
}

extension Observable {
    
    func then<O: ObservableType>(screen: (Element) -> O, ifNotPresent condition: (() -> O?)? = nil) -> Observable<O.E> {
        return flatMap { el throws in condition.map { $0() ?? screen(el) } ?? screen(el) }
    }
    
    func run() {
        subscribe()
    }

}

protocol PresentableType {
    associatedtype Input
    associatedtype Output
    
    mutating func setUp(input: Input)
    
    var sideEffects: Output { get }
}
/*:
 
 ## View Setup
 
 Notice how we haven't introduced UIViewControllers at all. That's because it doesn't matter what screens are. They can be actual screens, logical screens, third-party libraries with really weird presentation styles, etc. As seen in the introduction, all you need is a presenter to instruct how to show something to the user. In this playground example, we will use UIViews in favour of UIViewControllers.
 
 */
class First: UIView, PresentableType {
    
    private var button: UIButton!
    
    func setUp(input: Void) {
        backgroundColor = UIColor.greenColor()
        button = UIButton(frame: bounds)
        button.setTitle("Click Me", forState: .Normal)
        
        addSubview(button)
    }
    
    var sideEffects: Observable<Void> { return button.rx_tap.asObservable() }
}

class Second: UIView, PresentableType {
    
    private var text: UITextField!
    
    func setUp(input: Void) {
        backgroundColor = UIColor.whiteColor()
        text = UITextField(frame: bounds)
        
        addSubview(text)
    }
    
    var sideEffects: Observable<String> { return text.rx_text.asObservable() }
}


func present<S: UIView where S: PresentableType>(type: S.Type) -> S.Input -> S.Output {
    
    return { input in
        
        var vc: S
        if type == First.self {
            vc = First(frame: CGRect(x: 0, y: 0, width: 300, height: 100)) as! S
        } else {
            vc = Second(frame: CGRect(x: 0, y: 0, width: 300, height: 100)) as! S
        }

        vc.setUp(input)
        XCPlaygroundPage.currentPage.liveView = vc
        return vc.sideEffects
        
    }
    
}
/*:
 
 ## App Definition
 
 Once we've set everything up, defining the app is pretty easy
 
 */
let first = present(First.self)
let second = present(Second.self)

start(first).then(second).debug().run()

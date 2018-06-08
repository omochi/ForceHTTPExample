//
//  ViewController.swift
//  ForthHTTPExample
//
//  Created by omochimetaru on 2018/06/08.
//  Copyright © 2018年 omochimetaru.com. All rights reserved.
//

import UIKit
import ForceHTTP

public class ViewController: UIViewController {
   
    private let url = URL(string: "http://swift-playground.kishikawakatsumi.com")!
    
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
    }

    @IBAction public func onATSButton() {
        let session = URLSession(configuration: URLSessionConfiguration.ephemeral,
                                 delegate: nil,
                                 delegateQueue: OperationQueue.main)
        let task = session.dataTask(with: url) { (data, response, error) in
            if let error = error {
                self.showAlert("\(error)")
                return
            }
        }
        task.resume()
    }

    @IBAction public func onFHTTP() {
        let request = FHTTPRequest(url: url)
        let session = request.session()
        session.start { (response, error) in
            if let error = error {
                self.showAlert("\(error)")
                return
            }
            
            let html = String(data: response!.data, encoding: .utf8)!
            print("response:\n\(response!.header)\n\(html)")
        }
    }
    
    private func showAlert(_ message: String) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: UIAlertController.Style.alert)
        a.addAction(UIAlertAction(title: "OK", style: UIAlertAction.Style.default, handler: nil))
        self.present(a, animated: true, completion: nil)
    }
}


//
//  Intro5ViewController.swift
//  GordianSigner
//
//  Created by Peter on 12/17/20.
//  Copyright © 2020 Blockchain Commons. All rights reserved.
//

import UIKit

class Intro5ViewController: UIViewController {

    @IBOutlet weak var button: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        button.layer.cornerRadius = 8
    }
    
    @IBAction func dismissAction(_ sender: Any) {
        DispatchQueue.main.async { [weak self] in
            self?.navigationController?.popToRootViewController(animated: true)
        }
    }
    
    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

}